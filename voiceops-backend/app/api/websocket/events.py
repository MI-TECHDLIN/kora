"""
Server → client events for WS /ws/voice/{shift_id} (docs/contracts/interface.md §1).

Every builder checks its enum fields against the contract vocabularies, so the relay can
never put an off-contract value on the wire.
"""
import re
from typing import Any, Dict, List, Optional

# Contract vocabularies (interface.md §1 "Field vocabularies")
AGENT_STATES = frozenset({"idle", "thinking", "calling", "mapping", "task", "summarizing", "celebrating", "speaking"})
SCREENS = frozenset({"voice", "map", "summary", "settings"})
TASK_STEP_STATUSES = frozenset({"pending", "active", "done"})
TRANSCRIPT_ROLES = frozenset({"driver", "agent"})
ERROR_CODES = frozenset({
    "auth_failed", "session_expired", "upstream_unavailable", "upstream_timeout",
    "invalid_message", "internal", "voice_not_configured",
})
OFFER_OUTCOMES = frozenset({"accepted", "declined", "expired", "withdrawn"})

STOP_FIELDS = ("delivery_id", "sequence", "recipient_name", "address", "latitude", "longitude")
ROUTE_FIELDS = ("polyline", "summary", "distance_km", "duration_mins", "duration_text")

# Co-rider mood while each tool runs
TOOL_MOODS = {
    "get_next_delivery": "mapping",
    "get_best_route": "mapping",
    "start_navigation": "mapping",
    "call_customer": "calling",
    "get_shift_summary": "summarizing",
}
DEFAULT_TOOL_MOOD = "task"

# Task-progress label for each tool
TOOL_STEPS = {
    "get_next_delivery": "Finding your next stop",
    "update_delivery_status": "Updating delivery status",
    "log_exception": "Logging the exception",
    "get_best_route": "Checking delivery route",
    "start_navigation": "Starting navigation",
    "call_customer": "Calling the customer",
    "notify_customer": "Messaging the customer",
    "get_next_order": "Checking the order queue",
    "get_shift_summary": "Summarising your shift",
    "alert_dispatcher": "Alerting dispatch",
    "show_screen": "Opening the screen",
    "accept_order": "Accepting the order",
    "decline_order": "Passing the order on",
}


def _check(value: Any, allowed: frozenset, field: str) -> None:
    if value not in allowed:
        raise ValueError(f"{field}={value!r} is not in the interface contract")


def mood_for_tool(tool_name: str) -> str:
    return TOOL_MOODS.get(tool_name, DEFAULT_TOOL_MOOD)


def step_for_tool(tool_name: str) -> str:
    return TOOL_STEPS.get(tool_name) or f"Running {tool_name.replace('_', ' ')}"


def agent_state(state: str) -> Dict[str, Any]:
    _check(state, AGENT_STATES, "agent_state.state")
    return {"event": "agent_state", "state": state}


def screen_navigate(screen: str) -> Dict[str, Any]:
    _check(screen, SCREENS, "screen_navigate.screen")
    return {"event": "screen_navigate", "screen": screen}


def task_step(step: str, status: str, reasoning: Optional[str] = None) -> Dict[str, Any]:
    _check(status, TASK_STEP_STATUSES, "task_step.status")
    event = {"event": "task_step", "step": step, "status": status}
    # Only include reasoning for done status
    if reasoning is not None and status == "done":
        if len(reasoning) > 140:
            raise ValueError(f"reasoning exceeds 140 character limit: {len(reasoning)} chars")
        event["reasoning"] = reasoning
    return event


def map_route(stop: Dict[str, Any], route: Dict[str, Any]) -> Dict[str, Any]:
    """`stop` in the stop shape (`navigation.stop_from_delivery`), `route` from `navigation.route_fields`."""
    return {
        "event": "map_route",
        "delivery_id": stop.get("delivery_id"),
        "stops": [{key: stop.get(key) for key in STOP_FIELDS}],
        **{key: route.get(key) for key in ROUTE_FIELDS},
    }


def call_started(call_id: str, delivery_id: Optional[str], customer_name: Optional[str],
                 sequence: Optional[int]) -> Dict[str, Any]:
    # Name only: no server event carries a customer phone number (interface.md §1 Privacy)
    return {"event": "call_started", "call_id": call_id, "delivery_id": delivery_id,
            "customer_name": customer_name, "sequence": sequence}


def call_ended(call_id: str) -> Dict[str, Any]:
    return {"event": "call_ended", "call_id": call_id}


def summary_chunks(text: str) -> List[Dict[str, Any]]:
    """Split a summary into sentence chunks; concatenating every chunk's text restores it."""
    pieces = [piece for piece in re.split(r"(?<=[.!?])(?=\s)", text or "") if piece]
    if not pieces:
        return []
    return [{"event": "summary_chunk", "text": piece, "final": index == len(pieces) - 1}
            for index, piece in enumerate(pieces)]


def transcript(role: str, text: str) -> Dict[str, Any]:
    _check(role, TRANSCRIPT_ROLES, "transcript.role")
    return {"event": "transcript", "role": role, "text": text}


def reply_done(interrupted: bool = False) -> Dict[str, Any]:
    return {"event": "reply_done", "interrupted": True} if interrupted else {"event": "reply_done"}


def conversation_end() -> Dict[str, Any]:
    return {"event": "conversation_end"}


def order_offer(offer: Dict[str, Any]) -> Dict[str, Any]:
    """
    A new order offered to this driver (`order_dispatch.offer_payload`). Before the driver
    accepts, the app gets the street and city only, and the drop-off to about 100 m.
    """
    def approx(value: Any) -> Optional[float]:
        return round(float(value), 3) if value is not None else None

    return {
        "event": "order_offer",
        "order_id": offer["order_id"],
        "area": offer.get("area"),
        "latitude": approx(offer.get("latitude")),
        "longitude": approx(offer.get("longitude")),
        "distance_km": offer.get("distance_km"),
        "time_window": offer.get("time_window"),
        "package_count": offer.get("package_count"),
        "expires_in_s": offer.get("window_seconds"),
    }


def order_offer_closed(order_id: str, outcome: str) -> Dict[str, Any]:
    _check(outcome, OFFER_OUTCOMES, "order_offer_closed.outcome")
    return {"event": "order_offer_closed", "order_id": order_id, "outcome": outcome}


def queue_updated(snapshot: Dict[str, Any]) -> Dict[str, Any]:
    """The exact queue REST snapshot, tagged for transport over the voice socket."""
    return {"event": "queue_updated", **snapshot}


def error(code: str, message: str) -> Dict[str, Any]:
    _check(code, ERROR_CODES, "error.code")
    return {"event": "error", "code": code, "message": message}


def voice_change_accepted(voice: str) -> Dict[str, Any]:
    """Confirm voice change and signal client to reconnect with new voice."""
    return {
        "event": "voice_change_accepted",
        "voice": voice,
        "message": f"Voice will change to {voice}. Reconnecting..."
    }


def voice_unchanged(voice: str) -> Dict[str, Any]:
    """Signal that voice is already set to the requested value."""
    return {
        "event": "voice_unchanged",
        "voice": voice,
        "message": f"Voice is already set to {voice}"
    }


def proactive_alert(
    severity: str,
    risk_type: str,
    message: str,
    delivery_id: Optional[str] = None,
    route_suggestion: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """
    Proactive alert from the risk engine for time window risks, excessive idle,
    or route deviations (interface.md §1).
    """
    payload: Dict[str, Any] = {
        "event": "PROACTIVE_ALERT",
        "severity": severity,
        "risk_type": risk_type,
        "message": message,
        "delivery_id": delivery_id,
    }
    if route_suggestion:
        payload["route_suggestion"] = route_suggestion
    return payload
