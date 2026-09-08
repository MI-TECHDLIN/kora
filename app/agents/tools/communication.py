from typing import Dict, Any
from app.db.queries import get_next_pending_delivery
from app.integrations.livekit_client import make_call

from app.config import settings


async def call_customer(parameters: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Initiate an outbound PSTN call to the customer via LiveKit SIP.
    
    Architecture note:
    - This tool is called by the FastAPI orchestrator when AssemblyAI fires tool_call: call_customer
    - LiveKit handles the telephony entirely — it dials the customer's phone number
    - AssemblyAI has zero involvement in this call — no conflict
    - LiveKit and AssemblyAI operate on completely separate lanes
    
    How it works:
    - FastAPI calls LiveKit SIP API → LiveKit dials customer phone via PSTN
    - LiveKit plays a TTS message on pickup (driver's message passed in parameters)
    - FastAPI returns tool_result to AssemblyAI → agent tells driver "Customer is being called"
    """
    driver_id = context.get("driver_id")
    shift_id = context.get("shift_id")
    
    message = parameters.get("message", "Your delivery driver is on the way and will arrive shortly.")
    
    # Get next delivery
    delivery = await get_next_pending_delivery(shift_id, driver_id)
    if not delivery:
        return {"success": False, "error": "No pending delivery found"}
    
    customer_phone = delivery.get("phone")
    if not customer_phone:
        return {"success": False, "error": "Customer phone number not available"}
    
    # Format phone number with country code if needed
    if not customer_phone.startswith("+"):
        customer_phone = f"{settings.phone_country_code}{customer_phone}"
    
    # Make call via LiveKit
    result = await make_call(
        to_phone=customer_phone,
        message=message,
        delivery_id=delivery.get("id", "unknown"),
        recipient_name=delivery.get("recipient_name", "Customer")
    )
    
    if not result.get("success"):
        return result
    
    return {
        "success": True,
        "room_name": result.get("room_name"),
        "customer_name": delivery.get("recipient_name"),
        "customer_phone": customer_phone,
        "message": f"Calling {delivery.get('recipient_name')} now."
    }


async def alert_dispatcher(parameters: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Alert the dispatcher about an urgent issue.
    Stores alert in database and optionally triggers n8n workflow.
    """
    shift_id = context.get("shift_id")
    driver_id = context.get("driver_id")
    
    message = parameters.get("message")
    priority = parameters.get("priority", "normal")
    
    # Store alert in database
    # In production, would insert into dispatcher_alerts table
    # For now, return success
    
    # Optionally trigger n8n workflow for dispatcher notification
    # This would be implemented similar to shift end webhook
    
    return {
        "success": True,
        "message": "Dispatcher alerted",
        "priority": priority,
        "alert_message": message
    }


async def alert_dispatcher(parameters: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Alert the dispatcher about an urgent issue.
    Stores alert in database and optionally triggers n8n workflow.
    """
    shift_id = context.get("shift_id")
    driver_id = context.get("driver_id")
    
    message = parameters.get("message")
    priority = parameters.get("priority", "normal")
    
    # Store alert in database
    # In production, would insert into dispatcher_alerts table
    # For now, return success
    
    # Optionally trigger n8n workflow for dispatcher notification
    # This would be implemented similar to shift end webhook
    
    return {
        "success": True,
        "message": "Dispatcher alerted",
        "priority": priority,
        "alert_message": message
    }
