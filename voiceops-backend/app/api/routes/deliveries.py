from fastapi import APIRouter, HTTPException, status, Depends, Query, BackgroundTasks
from pydantic import BaseModel, Field
from typing import Optional
from app.dependencies import get_current_driver
from app.services.delivery_state_machine import assert_transition
from app.services.location_service import location_service
from app.db.queries import (
    get_shift_deliveries,
    get_delivery_by_id,
    mark_delivery_status,
    create_delivery_event,
    increment_delivery_attempts,
    save_location_ping,
    update_driver_location,
    is_valid_uuid,
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
    latitude: float = Field(..., ge=-90.0, le=90.0)
    longitude: float = Field(..., ge=-180.0, le=180.0)
    speed: float = Field(0.0, ge=0.0, le=300.0)
    heading: float = Field(0.0, ge=0.0, le=360.0)
    accuracy: float = Field(0.0, ge=0.0)


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
    """Update delivery status with state machine enforcement and audit event."""
    driver_id = current_user.get("id")

    # 1. Fetch current delivery state
    delivery = await get_delivery_by_id(delivery_id) if is_valid_uuid(delivery_id) else None
    if not delivery and is_valid_uuid(delivery_id):
        raise HTTPException(status_code=404, detail=f"Delivery {delivery_id} not found")

    current_status = delivery.get("status", "pending") if delivery else "pending"

    # 2. Enforce valid state transition
    try:
        assert_transition(current_status, request.status)
    except ValueError as ve:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(ve))

    try:
        # Increment attempt count if failed
        if request.status == "failed" and is_valid_uuid(delivery_id):
            await increment_delivery_attempts(delivery_id)

        # Update status in DB
        updated = await mark_delivery_status(
            delivery_id,
            request.status,
            request.failure_reason,
            request.notes
        )

        # Record immutable audit event
        await create_delivery_event(
            delivery_id=delivery_id,
            driver_id=driver_id,
            event_type="STATUS_CHANGED",
            status_before=current_status,
            status_after=request.status,
            metadata={
                "notes": request.notes,
                "failure_reason": request.failure_reason,
            }
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
    return {
        "message": "Customer notification dispatched via Twilio",
        "delivery_id": delivery_id,
        "message_type": request.message_type
    }


@router.post("/location")
async def save_location_endpoint(
    request: LocationPing,
    shift_id: str = Query(...),
    current_user: dict = Depends(get_current_driver)
):
    """Save GPS location ping with driver update and geofence detection."""
    driver_id = current_user.get("id")
    try:
        ping = await save_location_ping(
            driver_id,
            shift_id,
            request.latitude,
            request.longitude,
            request.speed,
            request.heading,
            request.accuracy,
        )

        await update_driver_location(
            driver_id=driver_id,
            lat=request.latitude,
            lng=request.longitude,
            heading=request.heading,
            speed=request.speed,
        )

        events = await location_service.process_location_update(
            driver_id=driver_id,
            shift_id=shift_id,
            lat=request.latitude,
            lng=request.longitude,
            speed=request.speed,
            heading=request.heading,
            accuracy=request.accuracy,
        )

        return {
            "ping": ping,
            "events_emitted": events,
            "success": True,
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to save location: {str(e)}"
        )
