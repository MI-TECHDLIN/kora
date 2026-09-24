"""Shared ownership checks for driver-scoped REST resources."""

from typing import Any, Dict, Optional

from fastapi import HTTPException, status

from app.db.queries import get_delivery_by_id, get_shift_by_id, is_valid_uuid


async def require_owned_shift(
    shift_id: str,
    driver_id: Any,
    *,
    allow_mock_id: bool = False,
) -> Optional[Dict[str, Any]]:
    """Return a shift owned by the driver, hiding missing and foreign IDs alike."""
    if allow_mock_id and not is_valid_uuid(shift_id):
        # Demo flows use non-UUID shift IDs and never resolve to persisted Supabase rows.
        return None

    shift = await get_shift_by_id(shift_id)
    if not shift or str(shift.get("driver_id")) != str(driver_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Shift not found")
    return shift


async def require_owned_delivery(
    delivery_id: str,
    driver_id: Any,
) -> Optional[Dict[str, Any]]:
    """Return a delivery whose parent shift belongs to the authenticated driver."""
    if not is_valid_uuid(delivery_id):
        # Mock/demo deliveries are intentionally not database-backed, so there is no
        # ownership chain to verify. Preserve their previous in-memory behavior.
        return None

    delivery = await get_delivery_by_id(delivery_id)
    if not delivery:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Delivery not found")

    shift = await get_shift_by_id(str(delivery.get("shift_id") or ""))
    if not shift or str(shift.get("driver_id")) != str(driver_id):
        # Use the same response as a missing delivery so foreign IDs are not disclosed.
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Delivery not found")
    return delivery
