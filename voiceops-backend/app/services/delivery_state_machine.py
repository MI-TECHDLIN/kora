"""
VoiceOps Delivery State Machine
Enforces deterministic, valid delivery state transitions.
Rejects any transition not defined in VALID_TRANSITIONS.
"""
from typing import Set, Dict


# --- Transition table ---
VALID_TRANSITIONS: Dict[str, Set[str]] = {
    "pending":     {"en_route", "arrived", "delivered", "failed"},
    "en_route":    {"arrived", "delivered", "failed"},
    "arrived":     {"delivered", "failed"},
    "failed":      {"rescheduled"},
    "rescheduled": {"en_route", "arrived"},
    "delivered":   set(),   # terminal — no outbound transitions
}

# Human-readable labels for voice responses
STATUS_LABELS = {
    "pending":     "pending",
    "en_route":    "en route",
    "arrived":     "arrived",
    "delivered":   "delivered",
    "failed":      "failed",
    "rescheduled": "rescheduled",
}


def validate_transition(current_status: str, next_status: str) -> bool:
    """
    Returns True if the transition is valid, False otherwise.
    Unknown current_status is treated as invalid.
    """
    allowed = VALID_TRANSITIONS.get(current_status, set())
    return next_status in allowed


def assert_transition(current_status: str, next_status: str) -> None:
    """
    Raises ValueError if the transition is not allowed.
    Use this in tool executors and API endpoints.
    """
    if not validate_transition(current_status, next_status):
        allowed = VALID_TRANSITIONS.get(current_status, set())
        allowed_str = ", ".join(sorted(allowed)) if allowed else "none (terminal state)"
        raise ValueError(
            f"Invalid delivery status transition: '{current_status}' → '{next_status}'. "
            f"Allowed next states: {allowed_str}."
        )


def get_allowed_transitions(current_status: str) -> Set[str]:
    """Returns the set of valid next states from the given status."""
    return VALID_TRANSITIONS.get(current_status, set())


def is_terminal(status: str) -> bool:
    """Returns True if the status has no valid outbound transitions."""
    return len(VALID_TRANSITIONS.get(status, set())) == 0
