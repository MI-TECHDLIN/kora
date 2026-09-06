from typing import Dict, Any
from app.db.queries import (
    get_next_pending_delivery,
    mark_delivery_status,
    get_shift_stats
)
from app.integrations.base import get_logistics_adapter


async def get_next_delivery(parameters: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Get the next pending delivery for the current shift.
    """
    driver_id = context.get("driver_id")
    shift_id = context.get("shift_id")
    
    # Get from database
    delivery = await get_next_pending_delivery(shift_id, driver_id)
    
    if not delivery:
        return {
            "has_next": False,
            "message": "No more pending deliveries for this shift"
        }
    
    return {
        "has_next": True,
        "delivery_id": delivery.get("id"),
        "recipient_name": delivery.get("recipient_name"),
        "address": delivery.get("address"),
        "phone": delivery.get("phone"),
        "notes": delivery.get("notes"),
        "time_window": delivery.get("time_window"),
        "latitude": delivery.get("latitude"),
        "longitude": delivery.get("longitude"),
        "sequence": delivery.get("sequence_order")
    }


async def update_delivery_status(parameters: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Update delivery status (delivered, failed, rescheduled).
    Also syncs with logistics platform adapter.
    """
    shift_id = context.get("shift_id")
    driver_id = context.get("driver_id")
    
    status = parameters.get("status")
    failure_reason = parameters.get("failure_reason")
    notes = parameters.get("notes")
    
    # Get current delivery to update
    delivery = await get_next_pending_delivery(shift_id, driver_id)
    if not delivery:
        return {"error": "No pending delivery found"}
    
    delivery_id = delivery.get("id")
    
    # Update in database
    updated = await mark_delivery_status(delivery_id, status, failure_reason, notes)
    
    # Sync with logistics platform
    try:
        adapter = get_logistics_adapter(driver_id)
        await adapter.update_task_status(delivery_id, status)
    except Exception as e:
        # Log error but don't fail the operation
        print(f"Logistics sync error: {e}")
    
    return {
        "success": True,
        "delivery_id": delivery_id,
        "status": status,
        "message": f"Delivery marked as {status}"
    }


async def log_exception(parameters: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Log a delivery exception with reason and resolution.
    """
    shift_id = context.get("shift_id")
    driver_id = context.get("driver_id")
    
    reason = parameters.get("reason")
    resolution = parameters.get("resolution")
    
    # Get current delivery
    delivery = await get_next_pending_delivery(shift_id, driver_id)
    if not delivery:
        return {"error": "No pending delivery found"}
    
    delivery_id = delivery.get("id")
    
    # Mark as failed with exception details
    await mark_delivery_status(
        delivery_id,
        "failed",
        failure_reason=reason,
        notes=f"Resolution: {resolution}"
    )
    
    # Sync with logistics platform
    try:
        adapter = get_logistics_adapter(driver_id)
        await adapter.update_task_status(delivery_id, "failed")
    except Exception as e:
        print(f"Logistics sync error: {e}")
    
    return {
        "success": True,
        "delivery_id": delivery_id,
        "reason": reason,
        "resolution": resolution,
        "message": f"Exception logged: {reason}, will {resolution}"
    }


async def get_next_order(parameters: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Get the next order from the company queue (for multi-platform drivers).
    """
    driver_id = context.get("driver_id")
    
    try:
        adapter = get_logistics_adapter(driver_id)
        next_order = await adapter.get_next_queued_order()
        
        if not next_order:
            return {
                "has_next": False,
                "message": "No queued orders available"
            }
        
        return {
            "has_next": True,
            "order": next_order
        }
    except Exception as e:
        return {"error": str(e)}


async def get_shift_summary(parameters: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Get current shift progress statistics.
    """
    shift_id = context.get("shift_id")
    
    stats = await get_shift_stats(shift_id)
    
    return {
        "total_deliveries": stats["total"],
        "delivered": stats["delivered"],
        "failed": stats["failed"],
        "success_rate": f"{stats['success_rate']:.1f}%",
        "remaining": stats["total"] - stats["delivered"] - stats["failed"]
    }
