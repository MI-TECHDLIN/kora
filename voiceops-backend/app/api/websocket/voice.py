"""
WS /ws/voice/{shift_id}: the real-time voice relay (docs/contracts/interface.md §1).

    Flutter ⇄ this socket ⇄ AssemblyAI Voice Agent API (STT + LLM + tool calling + TTS)

Driver audio goes upstream as `input.audio`; the co-rider's voice comes back as binary
frames. Every `tool.call` runs here as soon as it arrives (several calls in one turn run
concurrently and are gathered with `asyncio.gather` on `reply.done`, when AssemblyAI expects
the `tool.result`s). While tools run, the relay mirrors them to the app as UI events:
`agent_state`, `task_step`, `screen_navigate`, `map_route`, `call_started` / `call_ended`,
and `summary_chunk`.

The co-rider also speaks unprompted: when the order dispatcher offers this driver a new order,
the relay sends `order_offer` to the app and asks AssemblyAI for a reply now (`reply.create`
with one-shot instructions), once the conversation is quiet. That reply is an ordinary LLM
turn, so the driver can answer it and the agent calls `accept_order` / `decline_order`. The
app's offer card can answer too (`accept_order` / `decline_order` client events): the relay runs
that tool handler itself, with no LLM turn.
"""
import asyncio
import base64
import json
import logging
import time
from typing import Any, Dict, List, Optional, Set, Tuple

import websockets
from fastapi import APIRouter, HTTPException, WebSocket
from jose import jwt as jose_jwt

from app.config import settings
from app.dependencies import authenticate_bearer
from app.agents.agent_config import get_session_config
from app.agents.orchestrator import ToolOrchestrator
from app.agents.tools.navigation import (
    get_best_route,
    start_navigation,
    accept_reroute,
    stop_from_delivery,
    resolve_stop,
    route_fields,
    fastest_route,
    routes_to_stop,
)
from app.api.websocket import events
from app.api.websocket import reasoning
from app.dispatch.order_dispatch import get_order_dispatcher
from app.db.queries import (
    create_voice_session,
    get_driver_by_id,
    get_latest_location,
    get_next_pending_delivery,
    get_shift_by_id,
    log_tool_execution,
    update_voice_session,
)
from app.integrations.twilio_client import get_call_status, hang_up_call
from app.services.voice_readiness import NOT_CONFIGURED_MESSAGE, classify_upstream_failure, connect_upstream

logger = logging.getLogger(__name__)

router = APIRouter()

UPSTREAM_READY_TIMEOUT = 10.0  # connect + session.update → session.ready
DB_TIMEOUT = 3.0               # any Supabase lookup made from the voice loop
TOOL_TIMEOUT = 10.0            # one tool call, end to end
CALL_POLL_INTERVAL = 3.0       # provider status polling for an active customer call
CALL_WATCH_LIMIT = 15 * 60
REPLY_GRACE = 5.0              # after the driver's turn or a tool.result, a reply is due this soon
ANNOUNCE_POLL = 0.2            # how often a queued announcement checks for a quiet moment
TURN_STATE_STALE = 30.0        # a reply / speech flag with no upstream event for this long is stale
TERMINAL_CALL_STATUSES = {"completed", "busy", "failed", "no-answer", "canceled"}
DEMO_SIMULATED_CALL_SECONDS = 1.5  # timer for simulated customer call demo

# Tools whose origin is the driver's position: refresh it from the latest GPS ping first
ROUTING_TOOLS = {"get_next_delivery", "get_best_route", "start_navigation"}
ORDER_RESPONSE_TOOLS = {"accept_order", "decline_order"}

CLOSE_NORMAL = 1000
CLOSE_POLICY_VIOLATION = 1008  # auth_failed, session_expired
CLOSE_INTERNAL_ERROR = 1011    # upstream and internal failures

# Open sessions per shift, so work started over REST (post-shift summary) can reach the app
_sessions: Dict[str, Set["VoiceSession"]] = {}

# AssemblyAI starts a fresh upstream session on every reconnect. Remember which
# driver/shift pair already heard its opening so drops and voice swaps reconnect silently.
# This process-local state naturally resets on deployment; shift ids keep entries isolated.
_greeted_shifts: Set[Tuple[str, str]] = set()


def _claim_shift_greeting(driver_id: str, shift_id: str) -> bool:
    key = (driver_id, shift_id)
    if key in _greeted_shifts:
        return False
    _greeted_shifts.add(key)
    return True


class UpstreamError(Exception):
    def __init__(self, code: str, message: str, reason: Optional[str] = None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.reason = reason  # value-free token for the log, never sent to the app


async def _db(query, *args):
    """Run a Supabase query (sync client under an async def) off the event loop, with a timeout."""
    return await asyncio.wait_for(asyncio.to_thread(lambda: asyncio.run(query(*args))), DB_TIMEOUT)


async def _try_db(query, *args):
    """`_db`, returning None instead of raising: for context that is nice to have."""
    try:
        return await _db(query, *args)
    except Exception as e:
        logger.warning(f"[VoiceWS] {query.__name__} failed: {e!r}")
        return None


async def _open_upstream():
    """Open the AssemblyAI Voice Agent WebSocket (failures are classified in `_start_upstream`)."""
    return await connect_upstream()


def _token_expiry(authorization: str) -> Optional[float]:
    """`exp` of the (already Supabase-validated) bearer token, for the mid-session expiry timer."""
    try:
        exp = jose_jwt.get_unverified_claims(authorization[7:]).get("exp")
        return float(exp) if exp is not None else None
    except Exception:
        return None


def _upstream_error_code(data: dict) -> str:
    return "upstream_timeout" if data.get("code") == "agent_timeout" else "upstream_unavailable"


def _upstream_reason(prefix: str, data: dict) -> str:
    """Log token for an upstream error event: its `code` (AssemblyAI's vocabulary), never its text."""
    code = data.get("code")
    return f"{prefix}_{code}" if isinstance(code, str) and 0 < len(code) <= 40 else prefix


def _is_mock_call(call_id: str) -> bool:
    return call_id.startswith("mock-") or call_id.startswith("demo-")


def live_shifts() -> Dict[str, str]:
    """shift_id → driver_id for every shift with an open voice socket (order dispatch candidates)."""
    return {shift_id: next(iter(sessions)).driver_id for shift_id, sessions in _sessions.items() if sessions}


async def present_offer(shift_id: str, offer: dict) -> int:
    """Show and speak an order offer on every socket open on `shift_id`. Returns how many got it."""
    sessions = list(_sessions.get(shift_id, ()))
    for session in sessions:
        await session.present_offer(offer)
    return len(sessions)


async def close_offer(shift_id: str, order_id: str, outcome: str) -> None:
    for session in list(_sessions.get(shift_id, ())):
        await session.close_offer(order_id, outcome)


async def broadcast_queue_update(shift_id: str, snapshot: dict) -> int:
    """Push one already-built snapshot to every live socket for the shift."""
    sessions = list(_sessions.get(shift_id, ()))
    payload = events.queue_updated(snapshot)
    for session in sessions:
        await session.emit(payload)
    return len(sessions)


async def announce_target_reached(driver_id: str, shift_id: str, target: int) -> int:
    """Queue one warm milestone acknowledgement on the driver's live shift sockets."""
    sessions = [
        session for session in _sessions.get(shift_id, ())
        if session.driver_id == driver_id
    ]
    instructions = (
        f"The driver has just reached today's target of {target} deliveries. "
        "Acknowledge it now in one short, natural, warm sentence. Do not mention remaining counts."
    )
    for session in sessions:
        session._announce(f"target-reached:{target}", instructions)
    return len(sessions)


async def stream_summary(shift_id: str, text: str) -> int:
    """
    Stream a post-shift summary to every voice socket open on `shift_id`
    (`screen_navigate: summary`, then `summary_chunk`s). Returns how many sockets got it.
    """
    sessions = list(_sessions.get(shift_id, ()))
    for session in sessions:
        await session.stream_summary(text)
        await session.emit(events.agent_state("idle"))
    return len(sessions)


async def present_proactive_alert(
    driver_id: str,
    alert_payload: dict,
    spoken_instructions: Optional[str] = None,
    shift_id: Optional[str] = None,
) -> int:
    """
    Push PROACTIVE_ALERT to the driver's active voice session(s) and queue
    an unprompted co-rider voice announcement via reply.create if instructions are provided.
    Returns how many sessions received the alert.
    """
    targets: List["VoiceSession"] = []
    if shift_id and shift_id in _sessions:
        targets = [s for s in _sessions[shift_id] if s.driver_id == driver_id]
    if not targets:
        for s_list in _sessions.values():
            for s in s_list:
                if s.driver_id == driver_id:
                    targets.append(s)

    for session in targets:
        await session.emit(alert_payload)
        if spoken_instructions:
            risk_type = alert_payload.get("risk_type", "alert")
            session._announce(f"risk:{risk_type}", spoken_instructions)

    return len(targets)


class VoiceSession:
    """One app ⇄ AssemblyAI relay for one authenticated driver on one shift."""

    def __init__(self, client: WebSocket, user: dict, shift_id: str, token_exp: Optional[float], voice: Optional[str] = None):
        self.client = client
        self.user = user
        self.driver_id = str(user["id"])
        self.shift_id = shift_id
        self.token_exp = token_exp
        self.voice = voice

        self.upstream = None
        self.context: Dict[str, Any] = {}
        self.voice_session_id: Optional[str] = None

        self.pending_tools: List[Tuple[str, str, asyncio.Task]] = []  # (call_id, name, task)
        self._deferred_upstream: List[dict] = []
        self.active_calls: Dict[str, Optional[asyncio.Task]] = {}  # call_id → status watcher
        self._simulated_call_timer: Optional[asyncio.Task] = None  # timer for simulated customer call demo

        self.driver_turns: List[str] = []
        self.agent_turns: List[str] = []
        self.tool_calls: List[dict] = []
        self.tool_results: List[dict] = []

        self.client_gone = False
        self.close_code = CLOSE_NORMAL
        self._send_lock = asyncio.Lock()

        # Upstream turn state: an unprompted reply.create is sent only when all of these are quiet
        self._reply_active = False
        self._driver_speaking = False
        self._finishing_tools = False
        self._expect_reply_until = 0.0  # monotonic
        self._turn_event_at = 0.0       # monotonic time of the last reply / speech event
        self._announcements: List[Tuple[str, str]] = []  # (key, reply.create instructions)
        self._announce_wake = asyncio.Event()
        self.offers: Dict[str, dict] = {}   # order_id → offer shown to this driver
        self._driver_answered_offers: Set[str] = set()
        self._spoken_offers: Set[str] = set()
        self._background: Set[asyncio.Task] = set()
        self._in_audio_burst = False  # Track if we're in an audio burst for speaking state

    # ------------------------------------------------------------------ app side

    async def emit(self, event: dict) -> None:
        if self.client_gone:
            return
        async with self._send_lock:
            try:
                await self.client.send_text(json.dumps(event))
            except Exception:
                self.client_gone = True

    async def emit_audio(self, audio: bytes) -> None:
        if self.client_gone:
            return
        async with self._send_lock:
            try:
                await self.client.send_bytes(audio)
            except Exception:
                self.client_gone = True

    async def fail(self, code: str, message: str, reason: Optional[str] = None) -> None:
        """Tell the app why the session is ending; the socket closes during cleanup."""
        logger.warning("[VoiceWS] Session failed: code=%s reason=%s shift=%s", code, reason or code, self.shift_id)
        await self.emit(events.error(code, message))
        self.close_code = (CLOSE_POLICY_VIOLATION if code in ("auth_failed", "session_expired")
                           else CLOSE_INTERNAL_ERROR)

    async def present_offer(self, offer: dict) -> None:
        order_id = offer["order_id"]
        self.offers[order_id] = offer
        self._driver_answered_offers.discard(order_id)
        await self.emit(events.order_offer(offer))
        self._drop_announcement(f"offer:{order_id}")
        self._announce(f"offer:{order_id}", self._offer_instructions(offer))

    async def close_offer(self, order_id: str, outcome: str) -> None:
        offer = self.offers.pop(order_id, None)
        self._driver_answered_offers.discard(order_id)
        self._drop_announcement(f"offer:{order_id}")  # never spoken: nothing to take back
        await self.emit(events.order_offer_closed(order_id, outcome))
        if outcome == "expired" and order_id in self._spoken_offers:
            area = (offer or {}).get("area")
            self._announce(f"expired:{order_id}", (
                "Tell the driver in one short sentence that the order offer"
                f"{' on ' + area if area else ''} timed out and went to another driver."))
        self._spoken_offers.discard(order_id)

    @staticmethod
    def _offer_instructions(offer: dict) -> str:
        details = []
        if offer.get("area"):
            details.append(f"drop-off on {offer['area']}")
        if offer.get("distance_km") is not None:
            details.append(f"about {offer['distance_km']:.1f} km from them")
        if offer.get("time_window"):
            details.append(f"delivery window {offer['time_window']}")
        if offer.get("package_count"):
            details.append(f"{offer['package_count']} package(s)")
        return (
            "A new delivery order has just been offered to the driver. They did not ask, so tell "
            f"them now in one or two short sentences: {', '.join(details) or 'a new order'}. "
            "Ask whether they will take it. If they accept, call accept_order. If they decline, "
            f"call decline_order. (order_id {offer['order_id']}.) The offer stays open for about "
            f"{offer.get('window_seconds') or 60} seconds."
        )

    def _announce(self, key: str, instructions: str) -> None:
        self._announcements.append((key, instructions))
        self._announce_wake.set()

    def _drop_announcement(self, key: str) -> None:
        self._announcements = [a for a in self._announcements if a[0] != key]

    def _upstream_idle(self) -> bool:
        """No reply playing or due, the driver isn't talking, and no tool results are outstanding."""
        now = time.monotonic()
        # A missed reply.done or speech.stopped must not silence announcements for the session
        in_turn = (self._reply_active or self._driver_speaking) and now - self._turn_event_at < TURN_STATE_STALE
        return not (in_turn or self._finishing_tools or self.pending_tools or now < self._expect_reply_until)

    async def _announce_loop(self) -> None:
        """Speak queued announcements one at a time, each in the next quiet moment."""
        while True:
            await self._announce_wake.wait()
            self._announce_wake.clear()
            while self._announcements:
                if self._upstream_idle():
                    key, instructions = self._announcements.pop(0)
                    self._expect_reply_until = time.monotonic() + REPLY_GRACE
                    await self.send_upstream({"type": "reply.create", "instructions": instructions})
                    if key.startswith("offer:"):
                        self._spoken_offers.add(key[len("offer:"):])
                await asyncio.sleep(ANNOUNCE_POLL)

    def _spawn(self, coro) -> None:
        task = asyncio.create_task(coro)
        self._background.add(task)
        task.add_done_callback(self._background.discard)

    async def _driver_online(self) -> None:
        try:
            await get_order_dispatcher().driver_available(self.driver_id, self.shift_id)
        except Exception:
            logger.exception("[VoiceWS] Order dispatch on connect failed")

    async def stream_summary(self, text: str) -> None:
        chunks = events.summary_chunks(text)
        if not chunks:
            return
        await self.emit(events.agent_state("summarizing"))
        await self.emit(events.screen_navigate("summary"))
        for chunk in chunks:
            await self.emit(chunk)

    # ------------------------------------------------------------------ upstream side

    async def send_upstream(self, message: dict) -> None:
        try:
            await self.upstream.send(json.dumps(message))
        except websockets.exceptions.ConnectionClosed:
            raise UpstreamError("upstream_unavailable", "Lost connection to the voice service.", "upstream_send_after_close")

    async def recv_upstream(self) -> Optional[dict]:
        """Next JSON event from AssemblyAI, or None once the upstream socket is closed."""
        if self._deferred_upstream:
            return self._deferred_upstream.pop(0)
        while True:
            try:
                raw = await self.upstream.recv()
            except websockets.exceptions.ConnectionClosed:
                return None
            if isinstance(raw, (bytes, bytearray)):
                continue  # the Voice Agent API sends audio as base64 in reply.audio
            try:
                data = json.loads(raw)
            except ValueError:
                logger.warning("[VoiceWS] Dropped a non-JSON upstream frame")
                continue
            if isinstance(data, dict):
                return data

    # ------------------------------------------------------------------ lifecycle

    async def run(self) -> None:
        _sessions.setdefault(self.shift_id, set()).add(self)
        try:
            await self._load_context()
            await self._start_upstream()
            self._spawn(self._driver_online())
            await self._pump()
        except UpstreamError as e:
            await self.fail(e.code, e.message, e.reason)
        except Exception as e:
            logger.exception("[VoiceWS] Session crashed")
            await self.fail("internal", "Something went wrong. Try again.", f"crash_{type(e).__name__}")
        finally:
            await self._close()

    async def _load_context(self) -> None:
        """Driver, current delivery, and last position: the tool context and the agent's facts."""
        driver, delivery, ping = await asyncio.gather(
            _try_db(get_driver_by_id, self.driver_id),
            _try_db(get_next_pending_delivery, self.shift_id, self.driver_id),
            _try_db(get_latest_location, self.shift_id),
        )
        driver = driver or {}
        metadata = self.user.get("user_metadata") or {}
        self.context = {
            "driver_id": self.driver_id,
            "driver_name": driver.get("name") or metadata.get("name") or metadata.get("full_name") or "Driver",
            "vehicle_type": driver.get("vehicle_type"),
            "shift_id": self.shift_id,
            "session_id": None,
            "deliveries": {},
        }
        if delivery:
            self._set_current_delivery(delivery, customer_phone=delivery.get("phone"))
        if ping:
            self._set_location(ping)

        self.voice_session_id = await _try_db(
            create_voice_session, self.shift_id, self.driver_id, delivery.get("id") if delivery else None
        ) or None
        self.context["session_id"] = self.voice_session_id

    def _set_current_delivery(self, delivery: dict, customer_phone: Optional[str] = None) -> None:
        stop = stop_from_delivery(delivery)
        self.context["deliveries"][stop["delivery_id"]] = stop
        self.context["current_delivery"] = {
            "id": stop["delivery_id"],
            "recipient_name": stop["recipient_name"],
            "address": stop["address"],
            "customer_phone": customer_phone,
            "notes": delivery.get("notes"),
            "time_window": delivery.get("time_window"),
            "latitude": stop["latitude"],
            "longitude": stop["longitude"],
            "sequence": stop["sequence"],
        }

    def _set_location(self, ping: dict) -> None:
        try:
            self.context["latitude"] = float(ping["latitude"])
            self.context["longitude"] = float(ping["longitude"])
        except (KeyError, TypeError, ValueError):
            pass

    async def _start_upstream(self) -> None:
        try:
            self.upstream = await _open_upstream()
        except UpstreamError:
            raise
        except Exception as e:
            code, reason, message = classify_upstream_failure(e)
            raise UpstreamError(code, message, reason)

        current = self.context.get("current_delivery") or {}
        next_stop = ""
        if current.get("address"):
            next_stop = f"{current.get('recipient_name') or 'Customer'} at {current['address']}"
            if current.get("time_window"):
                next_stop += f", {current['time_window']}"
        include_greeting = _claim_shift_greeting(self.driver_id, self.shift_id)
        await self.send_upstream(get_session_config(
            driver_id=self.driver_id,
            shift_id=self.shift_id,
            agent_id=settings.assemblyai_agent_id,
            driver_name=self.context["driver_name"],
            vehicle_type=self.context.get("vehicle_type") or "vehicle",
            next_stop_info=next_stop,
            voice=self.voice,
            include_greeting=include_greeting,
        ))

        try:
            while True:
                data = await asyncio.wait_for(self.recv_upstream(), UPSTREAM_READY_TIMEOUT)
                if data is None:
                    raise UpstreamError("upstream_unavailable", "The voice service closed the connection.", "upstream_closed_during_setup")
                msg_type = data.get("type")
                if msg_type in ("session.ready", "session.updated"):
                    if include_greeting:
                        self._expect_reply_until = time.monotonic() + REPLY_GRACE
                    return
                if msg_type in ("session.error", "error"):
                    raise UpstreamError(
                        _upstream_error_code(data), "The voice service rejected the session.",
                        _upstream_reason("session_rejected", data),
                    )
        except asyncio.TimeoutError:
            raise UpstreamError("upstream_timeout", "The voice service did not respond.", "upstream_setup_timeout")

    async def _pump(self) -> None:
        """Relay both directions until either side ends (or the token expires)."""
        tasks = [asyncio.create_task(self._client_loop()), asyncio.create_task(self._upstream_loop()),
                 asyncio.create_task(self._announce_loop())]
        if self.token_exp is not None:
            tasks.append(asyncio.create_task(self._expiry_watch()))
        done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        for task in pending:
            task.cancel()
        await asyncio.gather(*pending, return_exceptions=True)
        for task in done:
            if task.exception() is not None:
                raise task.exception()

    async def _close(self) -> None:
        # Synchronous teardown first, so it happens even if this cleanup is itself cancelled
        sessions = _sessions.get(self.shift_id)
        if sessions is not None:
            sessions.discard(self)
            if not sessions:
                _sessions.pop(self.shift_id, None)
                try:
                    get_order_dispatcher().driver_left(self.driver_id)  # no offer waits on a closed app
                except Exception:
                    logger.exception("[VoiceWS] Moving offers on disconnect failed")
        for _, _, task in self.pending_tools:
            task.cancel()
        for task in self._background:
            task.cancel()
        for watcher in self.active_calls.values():
            if watcher is not None:
                watcher.cancel()

        # Cancel simulated call timer and clean up stored outcome
        if self._simulated_call_timer is not None:
            self._simulated_call_timer.cancel()
            self._simulated_call_timer = None
        self.context.pop("simulated_customer_outcome", None)

        if self.upstream is not None:
            try:
                await self.send_upstream({"type": "session.end"})
            except Exception:
                pass
            try:
                await self.upstream.close()
            except Exception:
                pass

        if not self.client_gone:
            self.client_gone = True
            try:
                await self.client.close(code=self.close_code)
            except Exception:
                pass

        await self._persist()

    async def _persist(self) -> None:
        """Store the turns for post-shift intelligence (driver and agent turns kept separate)."""
        if not self.voice_session_id:
            return
        await _try_db(
            update_voice_session, self.voice_session_id, True,
            "\n".join(self.driver_turns) or None, "\n".join(self.agent_turns) or None,
        )
        if self.tool_calls:
            await _try_db(log_tool_execution, self.voice_session_id, self.tool_calls, self.tool_results)

    async def _expiry_watch(self) -> None:
        await asyncio.sleep(max(0.0, self.token_exp - time.time()))
        await self.fail("session_expired", "Your session expired. Sign in again.", "token_expired_mid_session")

    # ------------------------------------------------------------------ app → upstream

    async def _client_loop(self) -> None:
        while True:
            message = await self.client.receive()
            if message["type"] == "websocket.disconnect":
                self.client_gone = True
                return
            if message.get("bytes") is not None:
                audio = base64.b64encode(message["bytes"]).decode("ascii")
                await self.send_upstream({"type": "input.audio", "audio": audio})
            elif message.get("text") is not None:
                await self._handle_client_text(message["text"])

    async def _handle_client_text(self, text: str) -> None:
        try:
            data = json.loads(text)
        except ValueError:
            data = None
        if not isinstance(data, dict):
            await self.emit(events.error("invalid_message", "Messages must be JSON objects."))
            return

        if data.get("event") == "end_call":
            call_id = data.get("call_id")
            if not isinstance(call_id, str) or not call_id:
                await self.emit(events.error("invalid_message", "end_call needs a call_id."))
                return
            await self._end_call(call_id, hang_up=True)
            return

        if data.get("event") in ("accept_order", "decline_order"):
            await self._handle_tapped_order(data)
            return

        if data.get("event") == "change_voice":
            await self._handle_voice_change(data)
            return

        await self.emit(events.error("invalid_message", "Unsupported message."))

    async def _handle_tapped_order(self, data: dict) -> None:
        """Run a card response through the same tool handler as a voice response."""
        action = data["event"]
        order_id = data.get("order_id")
        if not isinstance(order_id, str) or not order_id:
            await self.emit(events.error("invalid_message", f"{action} needs an order_id."))
            return
        # A tap carries the exact id shown on this socket. Unlike an LLM tool
        # call, never fall back from a stale/unknown id to a different offer.
        if order_id not in self.offers:
            await self.emit(events.error(
                "invalid_message", "That order offer is no longer available."))
            return
        # In the background, so audio keeps flowing to AssemblyAI while the dispatcher answers
        self._spawn(self._run_tapped_order(action, order_id))

    async def _run_tapped_order(self, action: str, order_id: str) -> None:
        spoken = order_id in self._spoken_offers  # close_offer forgets it
        outcome = await self._run_tool(
            action,
            f"tap-{action}-{order_id}",
            {"order_id": order_id},
            driver_confirmed=True,
        )
        result = outcome.get("parsed_result")
        if isinstance(result, dict) and result.get("success"):
            closed_outcome = "accepted" if action == "accept_order" else "declined"
            if order_id in self.offers:
                await self.close_offer(order_id, closed_outcome)
            if spoken:
                # If the offer was already spoken, the co-rider confirms the answer
                where = f" at {result['address']}" if result.get("address") else ""
                self._announce(
                    "order-response",
                    f"The driver {closed_outcome} the order{where} by tapping the card. "
                    "Confirm it in one short sentence.",
                )
            return
        if isinstance(result, dict):
            await self.emit(events.error(
                "internal", result.get("error") or "The order response failed. Try again."))

    async def _handle_voice_change(self, data: dict) -> None:
        """Handle voice change request from client."""
        from app.agents.agent_config import resolve_voice
        
        new_voice = data.get("voice", "").strip()
        resolved_voice = resolve_voice(new_voice)
        
        # Only process if voice actually changed
        if resolved_voice == self.voice:
            logger.info(f"[VoiceWS] Voice unchanged: {resolved_voice}")
            await self.emit(events.voice_unchanged(resolved_voice))
            return
        
        logger.info(f"[VoiceWS] Voice change requested: {self.voice} -> {resolved_voice}")
        
        # Send confirmation to client with instruction to reconnect
        await self.emit(events.voice_change_accepted(resolved_voice))
        
        # Close the current session to force client reconnection with new voice
        # The client will automatically reconnect with the new voice parameter
        await self.client.close(code=CLOSE_NORMAL)
        self.client_gone = True

    # ------------------------------------------------------------------ upstream → app

    async def _upstream_loop(self) -> None:
        while True:
            data = await self.recv_upstream()
            if data is None:
                await self.fail("upstream_unavailable", "Lost connection to the voice service.", "upstream_closed")
                return

            msg_type = data.get("type")
            if msg_type in ("reply.started", "reply.audio", "transcript.agent", "reply.done",
                            "input.speech.started", "input.speech.stopped"):
                self._turn_event_at = time.monotonic()
            if msg_type in ("reply.started", "reply.audio", "transcript.agent"):
                self._reply_active = True
                self._expect_reply_until = 0.0
            if msg_type == "reply.audio":
                raw = data.get("data")
                if raw:
                    # Emit speaking state on first frame of each audio burst
                    if not self._in_audio_burst:
                        self._in_audio_burst = True
                        await self.emit(events.agent_state("speaking"))
                    await self.emit_audio(base64.b64decode(raw))
            elif msg_type == "input.speech.started":
                self._driver_speaking = True
            elif msg_type == "input.speech.stopped":
                self._driver_speaking = False
                self._expect_reply_until = time.monotonic() + REPLY_GRACE
            elif msg_type == "transcript.user":
                self._driver_speaking = False
                self._expect_reply_until = time.monotonic() + REPLY_GRACE
                text = (data.get("text") or "").strip()
                if text:
                    self.driver_turns.append(text)
                    self._driver_answered_offers.update(self.offers)
                    await self.emit(events.transcript("driver", text))
                    await self.emit(events.agent_state("thinking"))
            elif msg_type == "transcript.agent":
                text = (data.get("text") or "").strip()
                if text:
                    self.agent_turns.append(text)
                    await self.emit(events.transcript("agent", text))
            elif msg_type == "tool.call":
                self._start_tool(data)
            elif msg_type == "reply.done":
                self._reply_active = False
                self._in_audio_burst = False  # Reset audio burst flag
                await self._drain_tool_call_burst()
                await self._finish_reply(interrupted=data.get("status") == "interrupted")
                self._announce_wake.set()
            elif msg_type == "session.ended":
                await self.fail("upstream_unavailable", "The voice session ended.", "upstream_session_ended")
                return
            elif msg_type in ("session.error", "error"):
                logger.warning(f"[VoiceWS] Upstream error: {data.get('code')}")
                await self.fail(
                    _upstream_error_code(data), "The voice service hit an error.",
                    _upstream_reason("upstream_session_error", data),
                )
                return

    def _start_tool(self, data: dict) -> None:
        name = data.get("name") or ""
        call_id = data.get("call_id") or f"call_{name}"
        arguments = data.get("arguments") or {}
        if isinstance(arguments, str):
            try:
                arguments = json.loads(arguments)
            except ValueError:
                arguments = {}
        if not isinstance(arguments, dict):
            arguments = {}
        # Reset audio burst flag when tool call starts, so next audio burst emits speaking again
        self._in_audio_burst = False
        task = asyncio.create_task(self._run_tool(name, call_id, arguments))
        self.pending_tools.append((call_id, name, task))

    async def _drain_tool_call_burst(self) -> None:
        """Collect tool.call frames that arrive in the same upstream turn as reply.done."""
        while True:
            try:
                data = await asyncio.wait_for(self.recv_upstream(), 0.01)
            except asyncio.TimeoutError:
                return
            if data is None:
                self._deferred_upstream.append({"type": "session.ended"})
                return
            if data.get("type") != "tool.call":
                self._deferred_upstream.append(data)
                return
            self._start_tool(data)

    async def _finish_reply(self, interrupted: bool = False) -> None:
        """
        reply.done. AssemblyAI takes tool results only now: gather every tool call from this
        turn (they have been running concurrently since their tool.call) and send the results.
        The agent then speaks again, so the app gets `reply_done` only after a tool-free reply.
        """
        if not self.pending_tools:
            await self.emit(events.reply_done(interrupted=interrupted))
            await self.emit(events.agent_state("idle"))
            return

        if interrupted:
            await self.emit(events.reply_done(interrupted=True))

        batch, self.pending_tools = self.pending_tools, []
        self._finishing_tools = True
        try:
            outcomes = await asyncio.gather(*(task for _, _, task in batch), return_exceptions=True)
            for (call_id, name, _), outcome in zip(batch, outcomes):
                if isinstance(outcome, BaseException):
                    outcome = self._error_result(name, call_id, "The tool failed to run.")
                await self.send_upstream({
                    "type": "tool.result",
                    "call_id": outcome["call_id"],
                    "result": outcome["result"],
                    "is_error": outcome["is_error"],
                })
        finally:
            self._finishing_tools = False
            self._expect_reply_until = time.monotonic() + REPLY_GRACE  # the agent speaks from the results

    # ------------------------------------------------------------------ tools → UI events

    @staticmethod
    def _error_result(name: str, call_id: str, error: str) -> dict:
        result = {"success": False, "error": error}
        return {"call_id": call_id, "tool_name": name, "result": json.dumps(result),
                "parsed_result": result, "is_error": True}

    def _driver_answered_offer(self, arguments: dict) -> bool:
        """Whether a driver turn happened after the offer the tool would resolve."""
        order_id = arguments.get("order_id")
        if order_id not in self.offers:
            order_id = next(iter(self.offers), None)
        return order_id is None or order_id in self._driver_answered_offers

    async def _run_tool(
        self,
        name: str,
        call_id: str,
        arguments: dict,
        driver_confirmed: bool = False,
    ) -> dict:
        step = events.step_for_tool(name)
        silent = name == "end_conversation"
        if not silent:
            await self.emit(events.agent_state(events.mood_for_tool(name)))
            await self.emit(events.task_step(step, "active"))

        if name in ROUTING_TOOLS:
            ping = await _try_db(get_latest_location, self.shift_id)
            if ping:
                self._set_location(ping)

        if (
            name in ORDER_RESPONSE_TOOLS
            and not driver_confirmed
            and not self._driver_answered_offer(arguments)
        ):
            outcome = self._error_result(
                name,
                call_id,
                "Wait for the driver to answer before accepting or declining an order.",
            )
        else:
            try:
                outcome = await asyncio.wait_for(
                    ToolOrchestrator.execute_single_tool(name, arguments, self.context, call_id),
                    TOOL_TIMEOUT,
                )
            except asyncio.TimeoutError:
                outcome = self._error_result(name, call_id, f"{name} took too long to respond.")
            except Exception as e:
                outcome = self._error_result(name, call_id, str(e))

        self.tool_calls.append({"name": name, "call_id": call_id, "arguments": arguments})
        self.tool_results.append({"call_id": call_id, "result": outcome["parsed_result"],
                                  "is_error": outcome["is_error"]})

        try:
            await self._emit_tool_events(name, arguments, outcome["parsed_result"])
        except Exception:
            # Mirroring to the UI must never cost the agent its tool result
            logger.exception(f"[VoiceWS] UI events for {name} failed")

        # A failed tool still ends `done` (the enum has no failed state); the reply says what failed
        if not silent:
            # Generate reasoning for successful tool results
            reasoning_text = None
            if outcome["parsed_result"].get("success"):
                reasoning_text = reasoning.format_reasoning(name, outcome["parsed_result"])
            await self.emit(events.task_step(step, "done", reasoning_text))
        return outcome

    async def _emit_tool_events(self, name: str, arguments: dict, result: Any) -> None:
        if not isinstance(result, dict) or not result.get("success"):
            return

        if name == "get_next_delivery":
            if not result.get("has_next"):
                return
            self._set_current_delivery(result)
            stop = self.context["deliveries"][result.get("delivery_id")]
            route = fastest_route(await routes_to_stop(stop, self.context))
            await self._show_route(stop, route_fields(route))

        elif name == "get_best_route":
            stop = resolve_stop(arguments.get("delivery_id"), self.context)
            await self._show_route(stop, route_fields(fastest_route(result.get("all_routes") or [])))

        elif name == "start_navigation":
            stop = resolve_stop(result.get("delivery_id") or arguments.get("delivery_id"), self.context)
            await self._show_route(stop, result.get("route") or route_fields(None))

        elif name == "call_customer":
            call_id = result.get("call_sid")
            if not call_id:
                return
            delivery_id = arguments.get("delivery_id")
            sequence = resolve_stop(delivery_id, self.context).get("sequence")

            if call_id.startswith("demo-"):
                # Simulated customer call demo: start timer instead of watching real call
                self.active_calls[call_id] = None
                self._simulated_call_timer = asyncio.create_task(self._run_simulated_call(call_id))
            else:
                self.active_calls[call_id] = asyncio.create_task(self._watch_call(call_id))

            await self.emit(events.call_started(call_id, delivery_id, result.get("customer_name"), sequence))

        elif name == "update_delivery_status":
            if (result.get("status") or result.get("new_status")) == "delivered":
                await self.emit(events.agent_state("celebrating"))

        elif name == "get_shift_summary":
            await self.stream_summary(result.get("message") or "")

        elif name == "show_screen":
            await self.emit(events.screen_navigate(result["screen"]))

        elif name == "end_conversation":
            await self.emit(events.conversation_end())

        elif name == "accept_order":
            # The accepted order is now a stop on this shift: the navigation tools can route to it
            stop = stop_from_delivery(result)
            self.context["deliveries"][stop["delivery_id"]] = stop
            if not self.context.get("current_delivery"):
                self._set_current_delivery(result)

    async def _show_route(self, stop: dict, route: dict) -> None:
        await self.emit(events.screen_navigate("map"))
        await self.emit(events.map_route(stop, route))

    # ------------------------------------------------------------------ customer calls

    async def _watch_call(self, call_id: str) -> None:
        """Poll the provider until the call ends, then close the app's call overlay."""
        deadline = time.monotonic() + CALL_WATCH_LIMIT
        while time.monotonic() < deadline:
            await asyncio.sleep(CALL_POLL_INTERVAL)
            try:
                status = await asyncio.wait_for(asyncio.to_thread(get_call_status, call_id), DB_TIMEOUT)
            except Exception:
                status = None
            if status in TERMINAL_CALL_STATUSES:
                break
        self.active_calls.pop(call_id, None)
        await self.emit(events.call_ended(call_id))

    async def _run_simulated_call(self, call_id: str) -> None:
        """Run simulated customer call demo: wait 1.5 seconds, then end call and announce outcome."""
        try:
            await asyncio.sleep(DEMO_SIMULATED_CALL_SECONDS)
        except asyncio.CancelledError:
            # Call was ended by driver or session end
            return

        self.active_calls.pop(call_id, None)
        await self.emit(events.call_ended(call_id))

        # Queue announcement of the simulated customer's response
        outcome = self.context.pop("simulated_customer_outcome", None)
        if outcome:
            announcement = f"The simulated customer said {outcome}"
            self._announce(f"simulated:{call_id}", (
                "Tell the driver in one or two short sentences: " + announcement
            ))

    async def _end_call(self, call_id: str, hang_up: bool) -> None:
        known = call_id in self.active_calls
        watcher = self.active_calls.pop(call_id, None)
        if watcher is not None:
            watcher.cancel()

        # Cancel simulated call timer and clean up stored outcome
        if call_id.startswith("demo-") and self._simulated_call_timer is not None:
            self._simulated_call_timer.cancel()
            self._simulated_call_timer = None
            self.context.pop("simulated_customer_outcome", None)

        if hang_up and known and not _is_mock_call(call_id):
            try:
                await asyncio.wait_for(asyncio.to_thread(hang_up_call, call_id), DB_TIMEOUT)
            except Exception as e:
                logger.warning(f"[VoiceWS] Hang-up failed: {e!r}")
        # Always confirm, so a stale overlay (unknown call_id) closes too
        await self.emit(events.call_ended(call_id))


@router.websocket("/ws/voice/{shift_id}")
async def voice_socket(websocket: WebSocket, shift_id: str):
    """
    The app's real-time voice channel. Auth is `Authorization: Bearer <access_token>` on the
    upgrade request (interface.md §4); a rejected token gets an `auth_failed` error event, then
    the socket closes.
    """
    await websocket.accept()

    async def reject(code: str, message: str, reason: str) -> None:
        logger.warning("[VoiceWS] Socket rejected: code=%s reason=%s shift=%s", code, reason, shift_id)
        await websocket.send_text(json.dumps(events.error(code, message)))
        await websocket.close(code=CLOSE_POLICY_VIOLATION if code == "auth_failed" else CLOSE_INTERNAL_ERROR)

    authorization = websocket.headers.get("authorization")
    try:
        user = await authenticate_bearer(authorization)
    except HTTPException as e:
        if e.status_code == 503:
            await reject("voice_not_configured", NOT_CONFIGURED_MESSAGE, "server_auth_not_configured")
        else:
            await reject("auth_failed", f"{e.detail}. Sign in again.", "bearer_rejected")
        return

    # A driver may only open their own shift
    try:
        shift = await _db(get_shift_by_id, shift_id)
    except Exception as e:
        await reject("internal", "Could not load your shift. Try again.", f"shift_lookup_{type(e).__name__}")
        return
    if not shift or str(shift.get("driver_id")) != str(user["id"]):
        await reject("auth_failed", "This shift is not available to you.", "shift_not_owned")
        return

    voice_param = websocket.query_params.get("voice")
    await VoiceSession(websocket, user, shift_id, _token_expiry(authorization), voice=voice_param).run()
