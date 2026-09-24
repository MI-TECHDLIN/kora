"""Driver-facing order queue snapshots and real-time synchronization."""
import asyncio
import logging
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from app.db.queries import get_active_shift_for_driver, get_shift_deliveries
from app.services.preference_service import (
    INTERNAL_TARGET_ACK_KEY,
    MAX_DAILY_DELIVERY_TARGET,
    preference_service,
)

logger = logging.getLogger(__name__)

# Render runs one application worker, so this makes the acknowledgement's
# read/upsert pair atomic for each driver without changing the storage schema.
_target_ack_locks: Dict[str, asyncio.Lock] = {}


def _sequence_key(delivery: Dict[str, Any]) -> tuple:
    sequence = delivery.get("sequence_order")
    if isinstance(sequence, (int, float)) and not isinstance(sequence, bool):
        return (0, float(sequence), str(delivery.get("id") or ""))
    return (1, 0.0, str(delivery.get("id") or ""))


def _target_from_preference(value: Any) -> Optional[int]:
    try:
        target = int(str(value).strip())
    except (TypeError, ValueError):
        return None
    if str(target) != str(value).strip() or not 1 <= target <= MAX_DAILY_DELIVERY_TARGET:
        return None
    return target


def build_snapshot_from_deliveries(
    shift_id: str,
    deliveries: List[Dict[str, Any]],
    target: Optional[int],
) -> Dict[str, Any]:
    """Build the contract snapshot from already-loaded rows (kept pure for tests)."""
    ordered = sorted(deliveries, key=_sequence_key)
    active_id = next(
        (delivery.get("id") for delivery in ordered if delivery.get("status") == "pending"),
        None,
    )
    orders = []
    for delivery in ordered:
        status = delivery.get("status", "pending")
        if status == "pending":
            state = "active" if delivery.get("id") == active_id else "pending"
        elif status == "delivered":
            state = "completed"
        else:
            state = status

        eta = delivery.get("eta_minutes")
        if not isinstance(eta, (int, float)) or isinstance(eta, bool):
            eta = None
        orders.append({
            "delivery_id": delivery.get("id"),
            "sequence": delivery.get("sequence_order"),
            "recipient_name": delivery.get("recipient_name") or "Customer",
            "address": delivery.get("address") or "",
            "time_window": delivery.get("time_window"),
            "status": status,
            "state": state,
            "eta_minutes": eta,
        })

    return {
        "shift_id": shift_id,
        "target": target,
        "counts": {
            "total": len(orders),
            "completed": sum(order["status"] == "delivered" for order in orders),
            "active": 1 if active_id is not None else 0,
            "pending": sum(order["state"] == "pending" for order in orders),
            "failed": sum(order["status"] == "failed" for order in orders),
            "rescheduled": sum(order["status"] == "rescheduled" for order in orders),
        },
        "orders": orders,
    }


async def build_queue_snapshot(shift_id: str, driver_id: str) -> Dict[str, Any]:
    """Load and build the snapshot used by both REST and WebSocket delivery."""
    deliveries = await get_shift_deliveries(shift_id)
    target_value = await preference_service.get_preference(driver_id, "daily_delivery_target")
    return build_snapshot_from_deliveries(
        shift_id,
        deliveries,
        _target_from_preference(target_value),
    )


async def _acknowledge_target_once(
    snapshot: Dict[str, Any],
    driver_id: str,
) -> bool:
    target = snapshot.get("target")
    completed = snapshot.get("counts", {}).get("completed", 0)
    if not target or completed < target:
        return False

    day = datetime.now(timezone.utc).date().isoformat()
    marker = f"{day}:{target}"
    lock = _target_ack_locks.setdefault(driver_id, asyncio.Lock())
    async with lock:
        stored = await preference_service.get_preference(driver_id, INTERNAL_TARGET_ACK_KEY)
        # Existing rows use YYYY-MM-DD:<target>. Comparing the date prefix keeps
        # those rows valid while making acknowledgement independent of target edits.
        if str(stored or "").split(":", 1)[0] == day:
            return False
        if not await preference_service.set_target_acknowledged(driver_id, marker):
            logger.warning(
                "[OrderQueue] Could not persist target acknowledgement for driver %s",
                driver_id,
            )
            return False

        from app.api.websocket.voice import announce_target_reached

        await announce_target_reached(driver_id, snapshot["shift_id"], target)
        return True


async def publish_queue_update(shift_id: str, driver_id: str) -> Dict[str, Any]:
    """Build once, then push that exact object and evaluate the target milestone."""
    snapshot = await build_queue_snapshot(shift_id, driver_id)
    from app.api.websocket.voice import broadcast_queue_update

    await broadcast_queue_update(shift_id, snapshot)
    await _acknowledge_target_once(snapshot, driver_id)
    return snapshot


async def notify_queue_changed(shift_id: Optional[str], driver_id: Optional[str]) -> None:
    """Best-effort synchronization: notification failure never rolls back a committed write."""
    if not shift_id or not driver_id:
        return
    try:
        await publish_queue_update(str(shift_id), str(driver_id))
    except Exception:
        logger.exception("[OrderQueue] Failed to publish queue update for shift %s", shift_id)


async def notify_active_queue_changed(driver_id: Optional[str], shift_id: Optional[str] = None) -> None:
    """Publish a target change to the supplied shift, or the driver's active shift."""
    if not driver_id:
        return
    if not shift_id:
        shift = await get_active_shift_for_driver(str(driver_id))
        shift_id = shift.get("id") if shift else None
    await notify_queue_changed(shift_id, str(driver_id))
