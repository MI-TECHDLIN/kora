"""
Order dispatch: offer each new order to the nearest available driver, one driver at a time.

    platform order (Order Intake API or the adapter's feed)
      → deliveries row, shift_id NULL, status `offered` (or `unassigned` if nobody is free)
      → offer to the nearest driver: `order_offer` on their voice socket, spoken via reply.create
      → accept_order: shift_id = their shift, status `pending`, last stop on their run
        decline_order / offer window runs out: the next-nearest driver gets it
        nobody left: status `unassigned`, retried when a driver comes online or frees up

Only a driver with an open voice socket can be offered an order: the co-rider tells them
through that session, and nothing reaches a driver without one. An order that finds nobody
online waits unassigned and is offered on the next connect. An offer whose driver disconnects
moves on at once.

"Nearest" is straight-line (haversine) distance from each online driver's latest GPS ping on
an active shift. One with no ping yet is placed at the demo area centre, so the demo driver
can take orders before the app posts location. A driver holding one offer gets no second
offer until it resolves.

Offer state lives in this process (one uvicorn worker). The `deliveries` row carries the
durable part, and open orders are reloaded as `unassigned` on startup.

Offer payload includes traffic-aware ETA for the winning candidate (computed only once per offer,
not during candidate ranking to avoid excessive API calls).
"""
import asyncio
import logging
import os
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Protocol, Set, Tuple

from app.config import settings
from app.db.queries import (
    assign_order_to_shift,
    get_active_driver_positions,
    get_delivery_by_external_id,
    get_open_orders,
    insert_incoming_order,
    set_open_order_status,
)
from app.integrations.logistics import DEMO_AREA_CENTER, IncomingOrder, LogisticsAdapter, get_logistics_adapter
from app.utils.geo import haversine_km

logger = logging.getLogger(__name__)

OFFERED = "offered"
UNASSIGNED = "unassigned"
DB_TIMEOUT = 3.0
NOBODY_FREE = "no driver is online and free"
EVERYONE_PASSED = "every online driver passed"


class DispatchUnavailable(Exception):
    """The order could not be stored (database unreachable)."""


class SessionHub(Protocol):
    """How the dispatcher reaches drivers' open voice sockets (app/api/websocket/voice.py)."""

    def live_shifts(self) -> Dict[str, str]:
        """shift_id → driver_id for every shift with an open voice socket."""

    async def present_offer(self, shift_id: str, offer: Dict[str, Any]) -> int:
        """Show and speak an offer on the shift's sockets. Returns how many sockets got it."""

    async def close_offer(self, shift_id: str, order_id: str, outcome: str) -> None:
        """The offer is over (accepted | declined | expired | withdrawn)."""


class _VoiceHub:
    """The real hub: the voice relay's session registry, imported late (it imports the tools)."""

    def live_shifts(self) -> Dict[str, str]:
        from app.api.websocket import voice
        return voice.live_shifts()

    async def present_offer(self, shift_id: str, offer: Dict[str, Any]) -> int:
        from app.api.websocket import voice
        return await voice.present_offer(shift_id, offer)

    async def close_offer(self, shift_id: str, order_id: str, outcome: str) -> None:
        from app.api.websocket import voice
        await voice.close_offer(shift_id, order_id, outcome)


async def _db(query, *args):
    """Run a Supabase query (sync client under an async def) off the event loop, with a timeout."""
    return await asyncio.wait_for(asyncio.to_thread(lambda: asyncio.run(query(*args))), DB_TIMEOUT)


async def _try_db(query, *args):
    try:
        return await _db(query, *args)
    except Exception as e:
        logger.warning(f"[Dispatch] {query.__name__} failed: {e!r}")
        return None


def _first_name(name: Optional[str]) -> Optional[str]:
    return name.split()[0] if name and name.strip() else None


@dataclass
class Candidate:
    driver_id: str
    shift_id: str
    driver_name: Optional[str]
    distance_km: float  # straight line from the driver to the drop-off
    origin: Tuple[float, float] = (0.0, 0.0)  # the driver's own lat/lng used for distance_km


@dataclass
class OpenOrder:
    delivery_id: str
    order: IncomingOrder
    status: str
    offered_to: Optional[Candidate] = None
    expires_at: Optional[float] = None  # epoch seconds
    passed_over: Set[str] = field(default_factory=set)  # drivers who declined or let it lapse
    declined_by: Set[str] = field(default_factory=set)  # the ones who said no
    timer: Optional[asyncio.Task] = None


class OrderDispatcher:
    def __init__(
        self,
        adapter: LogisticsAdapter,
        hub: Optional[SessionHub] = None,
        offer_window: Optional[float] = None,
        max_open_orders: Optional[int] = None,
        ping_max_age_minutes: Optional[float] = None,
        feed_enabled: Optional[bool] = None,
        fallback_origin: Tuple[float, float] = DEMO_AREA_CENTER,
    ):
        self.adapter = adapter
        self.hub: SessionHub = hub or _VoiceHub()
        self.offer_window = settings.order_offer_window_seconds if offer_window is None else offer_window
        self.max_open_orders = settings.order_feed_max_open_orders if max_open_orders is None else max_open_orders
        self.ping_max_age_minutes = (settings.order_dispatch_ping_max_age_minutes
                                     if ping_max_age_minutes is None else ping_max_age_minutes)
        self.feed_enabled = settings.order_feed_enabled if feed_enabled is None else feed_enabled
        if fallback_origin == DEMO_AREA_CENTER and settings.demo_area_lat is not None and settings.demo_area_lng is not None:
            fallback_origin = (float(settings.demo_area_lat), float(settings.demo_area_lng))
        self.fallback_origin = fallback_origin
        self._orders: Dict[str, OpenOrder] = {}
        self._lock = asyncio.Lock()
        self._background: Set[asyncio.Task] = set()

    async def get_target_location(self) -> Optional[Tuple[float, float]]:
        """Location around which to generate mock orders: online drivers' location or recent pings."""
        online_shifts = self.hub.live_shifts()
        if online_shifts:
            positions = await _try_db(get_active_driver_positions) or []
            valid_positions = [
                (float(p["latitude"]), float(p["longitude"]))
                for p in positions
                if p.get("shift_id") in online_shifts and p.get("latitude") is not None and p.get("longitude") is not None
            ]
            if valid_positions:
                rng = getattr(self.adapter, "_rng", None)
                return rng.choice(valid_positions) if rng else valid_positions[0]

        if settings.demo_area_lat is not None and settings.demo_area_lng is not None:
            return float(settings.demo_area_lat), float(settings.demo_area_lng)

        try:
            from app.db.queries import get_supabase
            resp = (
                get_supabase()
                .table("location_pings")
                .select("latitude, longitude")
                .order("pinged_at", desc=True)
                .limit(1)
                .execute()
            )
            if resp.data and resp.data[0].get("latitude") is not None and resp.data[0].get("longitude") is not None:
                return float(resp.data[0]["latitude"]), float(resp.data[0]["longitude"])
        except Exception:
            pass

        return None

    # ------------------------------------------------------------------ lifecycle

    async def start(self) -> None:
        logger.info(f"[Dispatch] started pid={os.getpid()}")
        await self._recover()
        if self.feed_enabled:
            await self.adapter.start_order_feed(
                self.ingest,
                self.should_generate,
                get_location=self.get_target_location,
            )

    async def stop(self) -> None:
        await self.adapter.stop_order_feed()
        tasks = [o.timer for o in self._orders.values() if o.timer] + list(self._background)
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)

    async def _recover(self) -> None:
        """Reload orders nobody had when the process stopped. Their offers died with it."""
        rows = await _try_db(get_open_orders) or []
        for row in rows:
            try:
                open_order = OpenOrder(row["id"], IncomingOrder.from_delivery_row(row), row["status"])
            except (KeyError, TypeError, ValueError):
                continue
            self._orders[open_order.delivery_id] = open_order
            await self._set_status(open_order, UNASSIGNED)
        if rows:
            logger.info(f"[Dispatch] Reloaded {len(self._orders)} open orders pid={os.getpid()}")

    def should_generate(self) -> bool:
        """
        A generated order is worth making only while a driver is online, and while fewer than
        max_open_orders are still in play. An order every online driver has declined is out of
        play, so a driver who keeps saying no keeps getting orders. One they let lapse stays in
        play, so an app left open and unattended stops the feed.
        """
        online = set(self.hub.live_shifts().values())
        in_play = [o for o in self._orders.values() if not online <= o.declined_by]
        return bool(online) and len(in_play) < self.max_open_orders

    def _spawn(self, coro) -> None:
        task = asyncio.create_task(coro)
        self._background.add(task)
        task.add_done_callback(self._background.discard)

    # ------------------------------------------------------------------ inbound orders

    async def ingest(self, order: IncomingOrder) -> Dict[str, Any]:
        """
        Store a new order and offer it. Idempotent on (source, external_id): a platform retrying
        its webhook gets the first result back. Raises DispatchUnavailable if it can't be stored.
        """
        async with self._lock:
            for known in self._orders.values():
                if (known.order.source, known.order.external_id) == (order.source, order.external_id):
                    return {"order_id": known.delivery_id, "status": known.status, "duplicate": True}
            try:
                existing = await _db(get_delivery_by_external_id, order.source, order.external_id)
                if existing:
                    return {"order_id": existing["id"], "status": existing.get("status"), "duplicate": True}
                candidates = await self._candidates(order, exclude=set())
                row = await _db(insert_incoming_order, {
                    "source": order.source,
                    "external_id": order.external_id,
                    "recipient_name": order.recipient_name,
                    "phone": order.recipient_phone,
                    "address": order.address,
                    "latitude": order.latitude,
                    "longitude": order.longitude,
                    "notes": order.notes,
                    "time_window": order.time_window,
                    "status": OFFERED if candidates else UNASSIGNED,
                })
            except Exception as e:
                logger.warning(f"[Dispatch] Could not store {order.external_id}: {e!r}")
                raise DispatchUnavailable("The order could not be stored.") from e
            if not row.get("id"):
                raise DispatchUnavailable("The order could not be stored.")

            open_order = OpenOrder(row["id"], order, row.get("status") or UNASSIGNED)
            self._orders[open_order.delivery_id] = open_order
            logger.info(f"[Dispatch] New order {order.external_id} from {order.source}")
            if candidates:
                await self._make_offer(open_order, candidates[0])
            else:
                await self._tell_platform_unassigned(open_order, NOBODY_FREE)
            return {"order_id": open_order.delivery_id, "status": open_order.status, "duplicate": False}

    # ------------------------------------------------------------------ candidates

    def _fresh(self, pinged_at: Any) -> bool:
        if self.ping_max_age_minutes is None:
            return True
        try:
            moment = datetime.fromisoformat(str(pinged_at).replace("Z", "+00:00"))
        except ValueError:
            return False
        if moment.tzinfo is None:
            moment = moment.replace(tzinfo=timezone.utc)
        return (datetime.now(timezone.utc) - moment).total_seconds() <= self.ping_max_age_minutes * 60

    async def _candidates(self, order: IncomingOrder, exclude: Set[str]) -> List[Candidate]:
        """Free online drivers not in `exclude`, nearest to the drop-off first."""
        live = self.hub.live_shifts()
        if not live:
            return []
        positions = await _try_db(get_active_driver_positions)
        if positions is None:
            # Database unreachable: the drivers on an open socket are still reachable
            positions = [{"driver_id": d, "shift_id": s, "driver_name": None, "latitude": None,
                          "longitude": None, "pinged_at": None} for s, d in live.items()]
        busy = {o.offered_to.driver_id for o in self._orders.values() if o.offered_to}

        best: Dict[str, Candidate] = {}
        for p in positions:
            driver_id = str(p["driver_id"])
            if p["shift_id"] not in live or driver_id in exclude or driver_id in busy:
                continue
            if p.get("latitude") is not None and p.get("longitude") is not None and self._fresh(p.get("pinged_at")):
                origin = (float(p["latitude"]), float(p["longitude"]))
            else:
                origin = self.fallback_origin
            candidate = Candidate(driver_id, p["shift_id"], p.get("driver_name"),
                                  round(haversine_km(*origin, order.latitude, order.longitude), 2), origin)
            current = best.get(driver_id)
            if current is None or candidate.distance_km < current.distance_km:  # one shift per driver
                best[driver_id] = candidate
        return sorted(best.values(), key=lambda c: c.distance_km)

    # ------------------------------------------------------------------ offers

    async def offer_payload(self, open_order: OpenOrder) -> Dict[str, Any]:
        """
        What a driver's session needs to show and speak the offer.
        Now includes traffic-aware ETA for the winning candidate.
        """
        order, candidate = open_order.order, open_order.offered_to
        payload = {
            "order_id": open_order.delivery_id,
            "external_id": order.external_id,
            "area": order.area,
            "latitude": order.latitude,
            "longitude": order.longitude,
            "distance_km": candidate.distance_km if candidate else None,
            "time_window": order.time_window,
            "package_count": order.package_count,
            "expires_at": open_order.expires_at,
            "window_seconds": max(0, round((open_order.expires_at or 0) - time.time())),
        }
        
        # Add traffic-aware ETA for the winning candidate only (not in ranking loop)
        if candidate:
            try:
                from app.services.eta_service import eta_service
                
                # Get driver's current location
                driver_origin = self.fallback_origin  # Default fallback
                
                # Try to get actual driver location from database
                try:
                    positions = await _try_db(get_active_driver_positions)
                    if positions:
                        for p in positions:
                            if str(p["driver_id"]) == candidate.driver_id:
                                if p.get("latitude") is not None and p.get("longitude") is not None:
                                    driver_origin = (float(p["latitude"]), float(p["longitude"]))
                                    break
                except Exception as e:
                    logger.warning(f"[Dispatch] Could not fetch driver location for traffic ETA: {e}")
                
                # Calculate traffic-aware ETA
                destination = (order.latitude, order.longitude)
                eta_result = await eta_service.compute_eta_minutes_traffic_aware(
                    driver_origin,
                    destination,
                    delivery_id=open_order.delivery_id,
                )
                
                if eta_result:
                    payload["eta_minutes"] = eta_result["eta_minutes"]
                    payload["traffic_delay_minutes"] = eta_result.get("traffic_delay_minutes", 0)
                    
                    logger.info(f"[Dispatch] Added traffic ETA to offer: {eta_result['eta_minutes']} mins "
                               f"(delay: {eta_result.get('traffic_delay_minutes', 0)} mins)")
            except Exception as e:
                logger.warning(f"[Dispatch] Failed to add traffic ETA to offer: {e}")
        
        return payload

    async def _set_status(self, open_order: OpenOrder, status: str) -> None:
        if open_order.status != status:
            open_order.status = status
            await _try_db(set_open_order_status, open_order.delivery_id, status)

    async def _make_offer(self, open_order: OpenOrder, candidate: Candidate) -> None:
        open_order.offered_to = candidate
        open_order.expires_at = time.time() + self.offer_window
        open_order.timer = asyncio.create_task(
            self._expire_after(open_order.delivery_id, candidate.driver_id, self.offer_window))
        await self._set_status(open_order, OFFERED)
        try:
            reached = await self.hub.present_offer(candidate.shift_id, await self.offer_payload(open_order))
        except Exception:
            logger.exception("[Dispatch] Presenting an offer failed")
            reached = 0
        logger.info(f"[Dispatch] {open_order.order.external_id} offered to driver {candidate.driver_id} "
                    f"({candidate.distance_km} km, {reached} socket(s))")
        
        # Check for automatic order acceptance
        await self._maybe_auto_accept(open_order, candidate)
    
    async def _maybe_auto_accept(self, open_order: OpenOrder, candidate: Candidate) -> None:
        """
        Check if the order should be automatically accepted based on driver preferences.
        If auto-accept is enabled and the order meets all preferences, accept it immediately.
        """
        try:
            from app.services.preference_service import preference_service
            from app.utils.geo_preferences import is_order_acceptable_by_location
            from app.utils.order_type_preferences import is_order_type_accepted
            from app.utils.time_preferences import should_accept_order_by_time
            from datetime import datetime

            # Get basic preferences
            basic_prefs = await preference_service.get_preferences(candidate.driver_id)
            
            # Check if auto-accept is enabled
            if basic_prefs.get("auto_accept_orders") != "true":
                logger.info(f"[Dispatch] Auto-accept not enabled for driver {candidate.driver_id}")
                return
            
            # Check if auto-decline is enabled (takes priority)
            if basic_prefs.get("auto_decline_orders") == "true":
                logger.info(f"[Dispatch] Auto-decline enabled for driver {candidate.driver_id}, skipping auto-accept")
                return
            
            # Get enhanced preferences
            enhanced_prefs = await preference_service.get_enhanced_preferences(candidate.driver_id)
            
            # Get order details
            order = open_order.order
            
            # Check geographic preferences
            location_acceptable, location_reason = is_order_acceptable_by_location(
                order.latitude, order.longitude,
                *candidate.origin,
                max_distance_km=basic_prefs.get("max_order_distance_km"),
                pickup_radius_km=enhanced_prefs.pickup_radius_km,
                zones=enhanced_prefs.geographic_zones
            )
            
            if not location_acceptable:
                logger.info(f"[Dispatch] Order {order.external_id} not auto-accepted: {location_reason}")
                return
            
            # Check order type preferences
            type_acceptable, type_reason = is_order_type_accepted(
                order.category, 
                getattr(order, 'weight_kg', None), 
                getattr(order, 'dimensions', None), 
                getattr(order, 'value', None),
                enhanced_prefs.order_type_prefs
            )
            
            if not type_acceptable:
                logger.info(f"[Dispatch] Order {order.external_id} not auto-accepted: {type_reason}")
                return
            
            # Check time-based preferences
            time_acceptable, time_reason = should_accept_order_by_time(
                datetime.now(), enhanced_prefs.time_based_prefs
            )
            
            if not time_acceptable:
                logger.info(f"[Dispatch] Order {order.external_id} not auto-accepted: {time_reason}")
                return
            
            # All checks passed - auto-accept the order
            logger.info(f"[Dispatch] Auto-accepting order {order.external_id} for driver {candidate.driver_id}")
            
            # Accept the order. `_maybe_auto_accept` always runs under `self._lock` already
            # (via `_make_offer`, called from `ingest`/`_offer_next`/`redispatch`), so this must
            # call the lock-free `_accept_locked` — `accept()` itself would deadlock on the
            # non-reentrant lock it's already holding.
            accept_result = await self._accept_locked(candidate.driver_id, candidate.shift_id, open_order.delivery_id)

            if accept_result.get("success"):
                logger.info(f"[Dispatch] Successfully auto-accepted order {order.external_id}")

                # Announce to the driver via Kora — build natural spoken instructions
                category_str = f"{order.category} order" if order.category else "order"
                dist_str = f"{candidate.distance_km:.1f} km away" if candidate.distance_km else "nearby"
                area_str = order.area if order.address else ""
                recipient_str = order.recipient_name or "the customer"
                area_clause = f" in {area_str}" if area_str else ""

                spoken_instructions = (
                    f"You've just had an order auto-accepted for you because it matched your preferences. "
                    f"It's a {category_str} for {recipient_str}{area_clause}, {dist_str}. "
                    f"Let the driver know naturally and tell them they can say "
                    f"'show me the route' or 'navigate there' whenever they're ready."
                )

                try:
                    from app.services.proactive_alert_service import ProactiveAlertService
                    alert_service = ProactiveAlertService()
                    await alert_service.emit_voice_alert(
                        driver_id=candidate.driver_id,
                        message=f"Auto-accepted {category_str} for {recipient_str}{area_clause} ({dist_str})",
                        severity="normal",
                        risk_type=f"auto_accept_announce:{open_order.delivery_id}",
                        delivery_id=open_order.delivery_id,
                        shift_id=candidate.shift_id,
                        spoken_instructions=spoken_instructions,
                    )
                except Exception as ann_err:
                    # Never let the announcement failure roll back the accepted order
                    logger.warning(f"[Dispatch] Auto-accept announcement failed: {ann_err}")

            else:
                logger.warning(f"[Dispatch] Auto-accept failed for order {order.external_id}: {accept_result.get('error')}")

        except Exception as e:
            logger.warning(f"[Dispatch] Auto-accept check failed for order {open_order.order.external_id}: {e}")
            # Continue with normal offer flow if auto-accept check fails

    async def _tell_platform_unassigned(self, open_order: OpenOrder, reason: str) -> None:
        try:
            await self.adapter.order_unassigned(open_order.order, open_order.delivery_id, reason)
        except Exception:
            logger.exception("[Dispatch] Platform write-back failed")

    async def _offer_next(self, open_order: OpenOrder, reason: str) -> Optional[Candidate]:
        """Offer to the nearest driver who hasn't passed on it, or park it as unassigned."""
        candidates = await self._candidates(open_order.order, exclude=open_order.passed_over)
        if candidates:
            await self._make_offer(open_order, candidates[0])
            return candidates[0]
        was_offered = open_order.status == OFFERED
        open_order.offered_to, open_order.expires_at = None, None
        await self._set_status(open_order, UNASSIGNED)
        if was_offered:
            await self._tell_platform_unassigned(open_order, reason)
        return None

    def _stop_timer(self, open_order: OpenOrder) -> None:
        if open_order.timer is not None and open_order.timer is not asyncio.current_task():
            open_order.timer.cancel()
        open_order.timer = None

    def _release(self, open_order: OpenOrder) -> Optional[Candidate]:
        """Take the offer back from its driver; returns who had it."""
        self._stop_timer(open_order)
        holder, open_order.offered_to, open_order.expires_at = open_order.offered_to, None, None
        return holder

    async def _expire_after(self, order_id: str, driver_id: str, delay: float) -> None:
        await asyncio.sleep(delay)
        async with self._lock:
            open_order = self._orders.get(order_id)
            if open_order is None or not open_order.offered_to or open_order.offered_to.driver_id != driver_id:
                return
            open_order.timer = None  # this task: _release must not cancel it
            holder = self._release(open_order)
            open_order.passed_over.add(driver_id)
            await self.hub.close_offer(holder.shift_id, order_id, "expired")
            logger.info(f"[Dispatch] Offer of {open_order.order.external_id} to driver {driver_id} expired")
            await self._offer_next(open_order, EVERYONE_PASSED)
        self._spawn(self.redispatch())

    async def redispatch(self) -> None:
        """Offer every unassigned order again (a driver came online or freed up)."""
        async with self._lock:
            for open_order in list(self._orders.values()):
                if open_order.offered_to is None:
                    await self._offer_next(open_order, EVERYONE_PASSED)

    async def driver_available(self, driver_id: str, shift_id: str) -> None:
        """A driver opened a voice socket: show them any offer they hold, then retry the queue."""
        async with self._lock:
            for open_order in self._orders.values():
                holder = open_order.offered_to
                if holder and holder.driver_id == driver_id:
                    holder.shift_id = shift_id
                    await self.hub.present_offer(shift_id, await self.offer_payload(open_order))
        await self.redispatch()

    def driver_left(self, driver_id: str) -> None:
        """A driver's last voice socket closed: their offer goes to the next online driver now."""
        if driver_id not in set(self.hub.live_shifts().values()):
            self._spawn(self._move_offers_from(driver_id))

    async def _move_offers_from(self, driver_id: str) -> None:
        async with self._lock:
            for open_order in list(self._orders.values()):
                if open_order.offered_to and open_order.offered_to.driver_id == driver_id:
                    self._release(open_order)
                    logger.info(f"[Dispatch] Driver {driver_id} went offline holding "
                                f"{open_order.order.external_id}")
                    await self._offer_next(open_order, NOBODY_FREE)

    # ------------------------------------------------------------------ the driver's answer

    def _find(self, driver_id: str, order_id: Optional[str]) -> Optional[OpenOrder]:
        """The named open order, else the one offered to this driver (the agent may garble ids)."""
        if order_id and order_id in self._orders:
            return self._orders[order_id]
        for open_order in self._orders.values():
            if open_order.offered_to and open_order.offered_to.driver_id == driver_id:
                return open_order
        return None

    async def accept(self, driver_id: str, shift_id: str, order_id: Optional[str] = None) -> Dict[str, Any]:
        """The driver takes the order: it becomes the last pending stop on their shift."""
        async with self._lock:
            return await self._accept_locked(driver_id, shift_id, order_id)

    async def _accept_locked(self, driver_id: str, shift_id: str, order_id: Optional[str] = None) -> Dict[str, Any]:
        """
        `accept()`'s body, for a caller that already holds `self._lock` — namely
        `_maybe_auto_accept`, reached through `_make_offer` from `ingest`/`_offer_next`/
        `redispatch`, all of which hold the lock for their whole duration. `asyncio.Lock` isn't
        reentrant, so `accept()` itself must never be called from in here.
        """
        open_order = self._find(driver_id, order_id)
        if open_order is None:
            logger.warning(
                "[Dispatch] accept_failed order_id=%s shift_id=%s reason=no_matching_order pid=%s",
                order_id or "-", shift_id or "-", os.getpid(),
            )
            return {"success": False, "error": "No order is waiting for you right now."}
        holder = open_order.offered_to
        if holder and holder.driver_id != driver_id:
            logger.warning(
                "[Dispatch] accept_failed order_id=%s shift_id=%s reason=offered_to_other_driver pid=%s",
                open_order.delivery_id, shift_id or "-", os.getpid(),
            )
            return {"success": False, "error": "That order is offered to another driver right now."}
        try:
            row = await _db(assign_order_to_shift, open_order.delivery_id, shift_id)
        except Exception as e:
            logger.warning(
                "[Dispatch] accept_failed order_id=%s shift_id=%s "
                "reason=database_error error_type=%s pid=%s",
                open_order.delivery_id, shift_id or "-", type(e).__name__, os.getpid(),
            )
            return {"success": False, "error": "Couldn't reach the order system. Try accepting again."}

        self._release(open_order)
        del self._orders[open_order.delivery_id]
        if holder:
            await self.hub.close_offer(holder.shift_id, open_order.delivery_id,
                                       "accepted" if row else "withdrawn")
        if row is None:
            logger.warning(
                "[Dispatch] accept_failed order_id=%s shift_id=%s reason=already_assigned pid=%s",
                open_order.delivery_id, shift_id or "-", os.getpid(),
            )
            return {"success": False, "error": "Someone else already took that order."}
        try:
            await self.adapter.order_assigned(open_order.order, open_order.delivery_id, driver_id)
        except Exception:
            logger.exception("[Dispatch] Platform write-back failed")

        self._spawn(self.redispatch())
        order = open_order.order
        sequence = row.get("sequence_order")
        message = f"Order accepted. {order.recipient_name} at {order.address} is now stop {sequence} on your run."
        if order.time_window:
            message += f" Delivery window {order.time_window}."
        return {
            "success": True,
            "order_id": open_order.delivery_id,
            "delivery_id": open_order.delivery_id,
            "external_id": order.external_id,
            "recipient_name": order.recipient_name,
            "address": order.address,
            "latitude": order.latitude,
            "longitude": order.longitude,
            "notes": order.notes,
            "time_window": order.time_window,
            "sequence": sequence,
            "status": "pending",
            "message": message,
        }

    async def decline(self, driver_id: str, order_id: Optional[str] = None,
                      reason: Optional[str] = None, shift_id: Optional[str] = None) -> Dict[str, Any]:
        """The driver passes: the next-nearest free driver gets the offer."""
        async with self._lock:
            open_order = self._find(driver_id, order_id)
            if open_order is None or not open_order.offered_to or open_order.offered_to.driver_id != driver_id:
                offered_shift = (
                    open_order.offered_to.shift_id
                    if open_order is not None and open_order.offered_to is not None
                    else None
                )
                logger.warning(
                    "[Dispatch] decline_failed order_id=%s shift_id=%s reason=no_matching_offer pid=%s",
                    open_order.delivery_id if open_order is not None else order_id or "-",
                    shift_id or offered_shift or "-", os.getpid(),
                )
                return {"success": False, "error": "No order is offered to you right now."}
            holder = self._release(open_order)
            open_order.passed_over.add(driver_id)
            open_order.declined_by.add(driver_id)
            await self.hub.close_offer(holder.shift_id, open_order.delivery_id, "declined")
            logger.info(f"[Dispatch] Driver {driver_id} declined {open_order.order.external_id}"
                        + (f" ({reason})" if reason else ""))
            nxt = await self._offer_next(open_order, EVERYONE_PASSED)

        self._spawn(self.redispatch())
        if nxt:
            who = _first_name(nxt.driver_name) or "the next nearest driver"
            message = f"Declined. Passed it to {who}, {nxt.distance_km:.1f} km from the drop-off."
            passed_to = {"driver_name": _first_name(nxt.driver_name), "distance_km": nxt.distance_km}
        else:
            message = "Declined. No other driver is online and free, so it waits in the unassigned queue."
            passed_to = None
        return {
            "success": True,
            "order_id": open_order.delivery_id,
            "status": open_order.status,
            "passed_to": passed_to,
            "message": message,
        }

    # ------------------------------------------------------------------ the queue

    def next_order_for(self, driver_id: str, latitude: Optional[float] = None,
                       longitude: Optional[float] = None) -> Optional[Dict[str, Any]]:
        """The order offered to this driver, else the nearest unassigned one; None if the queue is empty."""
        origin = (latitude, longitude) if latitude is not None and longitude is not None else self.fallback_origin
        offered = next((o for o in self._orders.values()
                        if o.offered_to and o.offered_to.driver_id == driver_id), None)
        waiting = sorted((o for o in self._orders.values() if o.offered_to is None),
                         key=lambda o: haversine_km(*origin, o.order.latitude, o.order.longitude))
        open_order = offered or (waiting[0] if waiting else None)
        if open_order is None:
            return None
        order = open_order.order
        return {
            "order_id": open_order.delivery_id,
            "external_id": order.external_id,
            "status": open_order.status,
            "offered_to_you": offered is not None,
            "recipient_name": order.recipient_name,
            "address": order.address,
            "notes": order.notes,
            "time_window": order.time_window,
            "distance_km": round(haversine_km(*origin, order.latitude, order.longitude), 2),
            "expires_in_s": (max(0, round(open_order.expires_at - time.time()))
                             if offered is not None and open_order.expires_at else None),
        }


_dispatcher: Optional[OrderDispatcher] = None


def get_order_dispatcher() -> OrderDispatcher:
    global _dispatcher
    if _dispatcher is None:
        _dispatcher = OrderDispatcher(get_logistics_adapter())
    return _dispatcher
