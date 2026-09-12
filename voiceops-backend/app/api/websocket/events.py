"""
Server → client events for WS /ws/voice/{shift_id} (docs/contracts/interface.md §1).

Every builder checks its enum fields against the contract vocabularies, so the relay can
never put an off-contract value on the wire.
"""
import re
from typing import Any, Dict, List, Optional

# Contract vocabularies (interface.md §1 "Field vocabularies")
AGENT_STATES = frozenset({"idle", "thinking", "calling", "mapping", "task", "summarizing", "celebrating"})
SCREENS = frozenset({"voice", "map", "summary", "settings"})
TASK_STEP_STATUSES = frozenset({"pending", "active", "done"})
TRANSCRIPT_ROLES = frozenset({"driver", "agent"})
ERROR_CODES = frozenset({
    "auth_failed", "session_expired", "upstream_unavailable", "upstream_timeout",
    "invalid_message", "internal",
})

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


def task_step(step: str, status: str) -> Dict[str, Any]:
    _check(status, TASK_STEP_STATUSES, "task_step.status")
    return {"event": "task_step", "step": step, "status": status}


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


def reply_done() -> Dict[str, Any]:
    return {"event": "reply_done"}


def error(code: str, message: str) -> Dict[str, Any]:
    _check(code, ERROR_CODES, "error.code")
    return {"event": "error", "code": code, "message": message}
