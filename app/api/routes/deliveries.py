from fastapi import APIRouter, HTTPException, status, Depends, Query
from pydantic import BaseModel
from typing import Optional
from app.dependencies import get_current_driver
from app.db.queries import (
    get_shift_deliveries,
    mark_delivery_status,
    save_location_ping
)


router = APIRouter()


class DeliveryStatusUpdate(BaseModel):
    status: str
    notes: Optional[str] = None
    failure_reason: Optional[str] = None


class NotifyCustomerRequest(BaseModel):
    message_type: str
    custom_message: Optional[str] = None


class LocationPing(BaseModel):
    latitude: float
    longitude: float


@router.get("")
async def get_deliveries(
    shift_id: Optional[str] = Query(None),
    current_user: dict = Depends(get_current_driver)
):
    """Get deliveries for current shift."""
    if not shift_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="shift_id query parameter required"
        )
    
    deliveries = await get_shift_deliveries(shift_id)
    return {"deliveries": deliveries}


@router.put("/{delivery_id}/status")
async def update_delivery_status_endpoint(
    delivery_id: str,
    request: DeliveryStatusUpdate,
    current_user: dict = Depends(get_current_driver)
):
    """Update delivery status."""
    try:
        updated = await mark_delivery_status(
            delivery_id,
            request.status,
            request.failure_reason,
            request.notes
        )
        return updated
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update delivery status: {str(e)}"
        )


@router.post("/{delivery_id}/notify")
async def notify_customer_endpoint(
    delivery_id: str,
    request: NotifyCustomerRequest,
    current_user: dict = Depends(get_current_driver)
):
    """Send customer notification (SMS/call)."""
    # This will be implemented with Vonage SMS and LiveKit SIP integration
    # For now, return a placeholder
    return {
        "message": "Customer notification feature requires Vonage/LiveKit integration",
        "delivery_id": delivery_id,
        "message_type": request.message_type
    }


@router.post("/location")
async def save_location_endpoint(
    request: LocationPing,
    shift_id: str = Query(...),
    current_user: dict = Depends(get_current_driver)
):
    """Save GPS location ping."""
    try:
        ping = await save_location_ping(
            current_user["id"],
            shift_id,
            request.latitude,
            request.longitude
        )
        return ping
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to save location: {str(e)}"
        )
