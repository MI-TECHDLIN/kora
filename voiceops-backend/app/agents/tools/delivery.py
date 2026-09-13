"""
Delivery tools for VoiceOps agent.
Tools: get_next_delivery, update_delivery_status, log_exception, get_next_order, accept_order,
decline_order, get_shift_summary
Platform: Supabase + Onfleet/Mock adapter
"""
from typing import Dict, Any
import json

from app.dispatch.order_dispatch import get_order_dispatcher


async def get_next_delivery(parameters: dict, context: dict) -> dict:
    """
    Get the next delivery in the current shift.
    
    Platform: Supabase (internal DB) + Onfleet/Mock adapter
    Trigger phrases: "next stop", "where to?", "next delivery"
    
    Input: {}
    
    Expected output:
    {
        "success": true,
        "has_next": true,
        "delivery_id": "uuid",
        "recipient_name": "Amara Johnson",
        "address": "14 Broad Street, Lagos Island",
        "latitude": 6.4541,
        "longitude": 3.3947,
        "notes": "Ring bell twice. 3rd floor.",
        "time_window": "2:00 PM – 4:00 PM",
        "sequence": 4
    }
    """
    try:
        driver_id = context.get("driver_id")
        shift_id = context.get("shift_id")
        
        # TODO: Query Supabase for next delivery
        # For now, return mock data
        return {
            "success": True,
            "has_next": True,
            "delivery_id": "mock-delivery-123",
            "recipient_name": "Amara Johnson",
            "address": "14 Broad Street, Lagos Island",
            "latitude": 6.4541,
            "longitude": 3.3947,
            "notes": "Ring bell twice. 3rd floor.",
            "time_window": "2:00 PM – 4:00 PM",
            "sequence": 4
        }
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }


async def update_delivery_status(parameters: dict, context: dict) -> dict:
    """
    Update delivery status to delivered, failed, or rescheduled.
    
    Platform: Supabase + Onfleet/Mock adapter (status synced to both)
    Trigger phrases: "mark as delivered", "done", "package delivered", "failed", "nobody home"
    
    Input:
    {
        "status": "delivered",
        "failure_reason": "",
        "notes": "Customer signed on delivery"
    }
    
    Status enum: delivered | failed | rescheduled
    """
    try:
        status = parameters.get("status")
        failure_reason = parameters.get("failure_reason", "")
        notes = parameters.get("notes", "")
        delivery_id = context.get("current_delivery", {}).get("id") if context.get("current_delivery") else parameters.get("delivery_id")
        
        # TODO: Update Supabase and sync to Onfleet
        return {
            "success": True,
            "delivery_id": delivery_id or "mock-delivery-123",
            "status": status,
            "message": f"Delivery marked as {status} and synced to platform."
        }
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }


async def log_exception(parameters: dict, context: dict) -> dict:
    """
    Log a delivery exception with reason and resolution.
    
    Platform: Supabase + Onfleet/Mock adapter
    Trigger phrases: "failed delivery", "wrong address", "gate locked", "package damaged"
    
    Input:
    {
        "reason": "access_denied",
        "resolution": "reschedule",
        "notes": "Gate code not working, no response from customer"
    }
    
    Reason enum: customer_unavailable | wrong_address | access_denied | damaged | other
    Resolution enum: reschedule | leave_with_neighbor | return_to_depot | await_customer
    """
    try:
        reason = parameters.get("reason")
        resolution = parameters.get("resolution")
        notes = parameters.get("notes", "")
        delivery_id = context.get("current_delivery", {}).get("id") if context.get("current_delivery") else parameters.get("delivery_id")
        
        # TODO: Log to Supabase and sync to Onfleet
        return {
            "success": True,
            "delivery_id": delivery_id or "mock-delivery-123",
            "reason": reason,
            "resolution": resolution,
            "message": f"Exception logged. Resolution: {resolution}."
        }
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }


async def get_next_order(parameters: dict, context: dict) -> dict:
    """
    Get the next order waiting for a driver, from the logistics adapter's order queue.
    
    Platform: Onfleet/Mock adapter orders, held by the order dispatcher (app/dispatch)
    Trigger phrases: "next order in queue", "what's coming after this", "next job"
    
    Input: {}
    
    Returns the order currently offered to this driver, else the nearest unassigned one.
    Expected output:
    {
        "success": true,
        "has_next": true,
        "order_id": "uuid",
        "external_id": "MLX-20260913-7F3K2Q",
        "status": "offered",
        "offered_to_you": true,
        "recipient_name": "Priya Patel",
        "address": "812 Lavaca St, Apt 3B, Austin, TX 78701",
        "notes": "Leave with the front desk.",
        "time_window": "3:00 PM – 5:00 PM",
        "distance_km": 0.6,
        "expires_in_s": 52,
        "sequence_order": null,
        "message": "..."
    }
    """
    try:
        found = get_order_dispatcher().next_order_for(
            context.get("driver_id"), context.get("latitude"), context.get("longitude"))
        if not found:
            return {"success": True, "has_next": False, "message": "No new orders are waiting right now."}
        if found["offered_to_you"]:
            message = (f"Order offered to you: {found['address']}, {found['distance_km']:.1f} km away. "
                       "Accept or decline it.")
        else:
            message = (f"Next order in the queue: {found['address']}, {found['distance_km']:.1f} km away. "
                       "It is not assigned to anyone yet.")
        # sequence_order: an order has no place on a run until a driver accepts it
        return {"success": True, "has_next": True, **found, "sequence_order": None, "message": message}
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }


async def accept_order(parameters: dict, context: dict) -> dict:
    """
    Accept a new order: it becomes the last pending stop on the driver's shift.
    
    Platform: order dispatcher + Onfleet/Mock adapter (the platform is told who has it)
    Trigger phrases: "yes, I'll take it", "accept", "add it to my run"
    
    Input:
    {
        "order_id": "uuid"   (optional: defaults to the order currently offered to the driver)
    }
    
    Expected output:
    {
        "success": true,
        "order_id": "uuid",
        "delivery_id": "uuid",
        "external_id": "MLX-20260913-7F3K2Q",
        "recipient_name": "Priya Patel",
        "address": "812 Lavaca St, Apt 3B, Austin, TX 78701",
        "latitude": 30.2713,
        "longitude": -97.7455,
        "notes": "Leave with the front desk.",
        "time_window": "3:00 PM – 5:00 PM",
        "sequence": 8,
        "status": "pending",
        "message": "Order accepted. Priya Patel at 812 Lavaca St ... is now stop 8 on your run."
    }
    """
    try:
        if not context.get("driver_id") or not context.get("shift_id"):
            return {"success": False, "error": "No active shift to add the order to."}
        return await get_order_dispatcher().accept(
            context["driver_id"], context["shift_id"], parameters.get("order_id"))
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }


async def decline_order(parameters: dict, context: dict) -> dict:
    """
    Decline the order offered to the driver: it goes to the next-nearest free driver.
    
    Platform: order dispatcher (nearest driver by straight-line distance)
    Trigger phrases: "no", "pass", "decline it", "I can't take it"
    
    Input:
    {
        "order_id": "uuid",   (optional: defaults to the order currently offered to the driver)
        "reason": "Too far from my route"
    }
    
    Expected output:
    {
        "success": true,
        "order_id": "uuid",
        "status": "offered",
        "passed_to": {"driver_name": "Maria", "distance_km": 3.4},
        "message": "Declined. Passed it to Maria, 3.4 km from the drop-off."
    }
    
    `passed_to` is null and `status` is "unassigned" when no other driver is free.
    """
    try:
        if not context.get("driver_id"):
            return {"success": False, "error": "No driver on this session."}
        return await get_order_dispatcher().decline(
            context["driver_id"], parameters.get("order_id"), parameters.get("reason"))
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }


async def get_shift_summary(parameters: dict, context: dict) -> dict:
    """
    Get shift statistics and progress.
    
    Platform: Supabase (aggregates shift delivery stats)
    Trigger phrases: "how am I doing", "how many left", "my progress", "shift summary"
    
    Input: {}
    
    Expected output:
    {
        "success": true,
        "total": 22,
        "delivered": 14,
        "failed": 2,
        "remaining": 6,
        "success_rate_percent": 87.5,
        "avg_time_per_stop_mins": 6.3,
        "message": "14 of 22 complete. 6 remaining. 2 failed."
    }
    """
    try:
        shift_id = context.get("shift_id")
        
        # TODO: Query Supabase for shift stats
        # For now, return mock data
        return {
            "success": True,
            "total": 22,
            "delivered": 14,
            "failed": 2,
            "remaining": 6,
            "success_rate_percent": 87.5,
            "avg_time_per_stop_mins": 6.3,
            "message": "14 of 22 complete. 6 remaining. 2 failed."
        }
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }