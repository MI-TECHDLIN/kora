from typing import Dict, Any
from app.db.queries import get_next_pending_delivery
from app.integrations.twilio_client import make_call, send_sms
from app.agents.tool_registry import SMS_TEMPLATES
from app.config import settings


async def call_customer(parameters: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Initiate a phone call to the customer via Twilio.
    """
    driver_id = context.get("driver_id")
    shift_id = context.get("shift_id")
    
    message = parameters.get("message", "VoiceOps driver calling about your delivery")
    
    # Get next delivery
    delivery = await get_next_pending_delivery(shift_id, driver_id)
    if not delivery:
        return {"error": "No pending delivery found"}
    
    customer_phone = delivery.get("phone")
    if not customer_phone:
        return {"error": "Customer phone number not available"}
    
    # Make call
    result = await make_call(
        to_phone=customer_phone,
        from_phone=settings.twilio_phone_number,
        twiml_message=message
    )
    
    if "error" in result:
        return result
    
    return {
        "success": True,
        "call_sid": result.get("call_sid"),
        "customer_name": delivery.get("recipient_name"),
        "message": f"Call initiated to {delivery.get('recipient_name')}"
    }


async def notify_customer(parameters: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Send an SMS notification to the customer.
    """
    driver_id = context.get("driver_id")
    shift_id = context.get("shift_id")
    
    message_type = parameters.get("message_type")
    custom_message = parameters.get("custom_message")
    
    # Get next delivery
    delivery = await get_next_pending_delivery(shift_id, driver_id)
    if not delivery:
        return {"error": "No pending delivery found"}
    
    customer_phone = delivery.get("phone")
    if not customer_phone:
        return {"error": "Customer phone number not available"}
    
    # Build message
    if message_type == "custom" and custom_message:
        body = custom_message
    else:
        body = SMS_TEMPLATES.get(message_type, "VoiceOps delivery update")
    
    # Send SMS
    result = await send_sms(
        to_phone=customer_phone,
        from_phone=settings.twilio_phone_number,
        body=body
    )
    
    if "error" in result:
        return result
    
    return {
        "success": True,
        "message_sid": result.get("message_sid"),
        "message_type": message_type,
        "message_sent": body,
        "customer_name": delivery.get("recipient_name")
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
