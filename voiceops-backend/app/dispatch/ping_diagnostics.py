"""Value-free process-local diagnostics for the driver location-ping endpoint."""

import time
from typing import Any, Dict, Optional


PING_REJECTION_REASONS = (
    "no_auth",
    "auth_unavailable",
    "bad_payload",
    "missing_shift",
    "shift_not_found",
    "not_owner",
    "shift_not_active",
    "storage_error",
    "processing_error",
)

_received = 0
_accepted = 0
_rejected = 0
_rejections = {reason: 0 for reason in PING_REJECTION_REASONS}
_storage_error_types: Dict[str, int] = {}
_last_received_at: Optional[float] = None
_last_accepted_at: Optional[float] = None
_last_rejected_at: Optional[float] = None
_last_rejection_reason: Optional[str] = None
_last_accepted_shift_active: Optional[bool] = None


def record_ping_received() -> None:
    global _received, _last_received_at
    _received += 1
    _last_received_at = time.time()


def record_ping_accepted(*, shift_active: bool) -> None:
    global _accepted, _last_accepted_at, _last_accepted_shift_active
    _accepted += 1
    _last_accepted_at = time.time()
    _last_accepted_shift_active = shift_active


def record_ping_rejected(reason: str) -> None:
    global _rejected, _last_rejected_at, _last_rejection_reason
    if reason not in _rejections:
        reason = "processing_error"
    _rejected += 1
    _rejections[reason] += 1
    _last_rejected_at = time.time()
    _last_rejection_reason = reason


def record_ping_storage_error(error_type: str) -> None:
    """Count a failed insert by exception class (or the fixed `empty_result` token)."""
    record_ping_rejected("storage_error")
    _storage_error_types[error_type] = _storage_error_types.get(error_type, 0) + 1


def ping_diagnostics() -> Dict[str, Any]:
    return {
        "ping_received": _received,
        "ping_accepted": _accepted,
        "ping_rejected": _rejected,
        "ping_rejections": dict(_rejections),
        "ping_storage_error_types": dict(_storage_error_types),
        "last_ping_received_at": _last_received_at,
        "last_ping_accepted_at": _last_accepted_at,
        "last_ping_rejected_at": _last_rejected_at,
        "last_ping_rejection_reason": _last_rejection_reason,
        "last_accepted_ping_shift_active": _last_accepted_shift_active,
    }


def reset_ping_diagnostics() -> None:
    """Tests only: reset the process-local counters."""
    global _received, _accepted, _rejected
    global _last_received_at, _last_accepted_at, _last_rejected_at
    global _last_rejection_reason, _last_accepted_shift_active
    _received = _accepted = _rejected = 0
    for reason in _rejections:
        _rejections[reason] = 0
    _storage_error_types.clear()
    _last_received_at = _last_accepted_at = _last_rejected_at = None
    _last_rejection_reason = None
    _last_accepted_shift_active = None
