"""
Delivery tools for VoiceOps agent.
Tools: get_next_delivery, update_delivery_status, log_exception, get_next_order, get_shift_summary
Platform: Supabase + Onfleet/Mock adapter
"""
from typing import Dict, Any
import json


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
    Get the next order in the queue from Onfleet.
    
    Platform: Onfleet/Mock adapter (queries unassigned task queue)
    Trigger phrases: "next order in queue", "what's coming after this", "next job"
    
    Input: {}
    
    Expected output:
    {
        "success": true,
        "has_next": true,
        "external_id": "onfleet_task_xyz",
        "recipient_name": "Emeka Okonkwo",
        "address": "3 Marina Road, Lagos",
        "notes": "Corporate delivery. Security clearance required.",
        "sequence_order": 5
    }
    """
    try:
        # TODO: Query Onfleet for next unassigned task
        # For now, return mock data
        return {
            "success": True,
            "has_next": True,
            "external_id": "onfleet_task_xyz",
            "recipient_name": "Emeka Okonkwo",
            "address": "3 Marina Road, Lagos",
            "notes": "Corporate delivery. Security clearance required.",
            "sequence_order": 5
        }
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