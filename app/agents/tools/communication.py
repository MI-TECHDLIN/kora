"""
Communication tools for VoiceOps agent.
Tools: call_customer, notify_customer, alert_dispatcher
Platform: Twilio Voice & SMS, Supabase + n8n webhook
"""
from typing import Dict, Any
import json
from app.integrations.twilio_client import make_call, send_sms


async def call_customer(parameters: dict, context: dict) -> dict:
    """
    Call the customer via Twilio Voice API.
    
    Platform: Twilio Voice (outbound call to customer's real phone number)
    Twilio operates on a completely separate lane from AssemblyAI. Zero conflict.
    Trigger phrases: "call the customer", "ring the customer", "call them"
    
    Input:
    {
        "delivery_id": "uuid",
        "message": "Your delivery driver is on the way and will arrive in 5 minutes."
    }
    
    Expected output:
    {
        "success": true,
        "call_sid": "CA123456789...",
        "customer_name": "Amara Johnson",
        "customer_phone": "+2348012345678",
        "message": "Calling Amara Johnson now via Twilio."
    }
    
    Failure (no phone number):
    {
        "success": false,
        "error": "No customer phone number on file."
    }
    """
    try:
        delivery_id = parameters.get("delivery_id")
        message = parameters.get("message", "")
        
        # TODO: Get customer phone from Supabase
        # For now, use mock phone
        customer_phone = "+2348012345678"
        customer_name = "Amara Johnson"
        
        # Call Twilio integration
        result = await make_call(
            to_phone=customer_phone,
            message=message,
            delivery_id=delivery_id,
            recipient_name=customer_name
        )
        
        return result
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }


async def notify_customer(parameters: dict, context: dict) -> dict:
    """
    Send SMS notification to customer via Twilio.
    
    Platform: Twilio Messages API (global coverage)
    Trigger phrases: "message the customer", "tell customer I'm close", "send ETA", "I'm 5 minutes away"
    
    Input:
    {
        "delivery_id": "uuid",
        "message_type": "nearby",
        "custom_message": ""
    }
    
    Message type enum: on_my_way | nearby | running_late | missed | custom
    
    Expected output:
    {
        "success": true,
        "status": "delivered",
        "customer_name": "Amara Johnson",
        "message_sent": "Hi Amara, your driver is nearby — please be ready to receive your delivery.",
        "message": "SMS sent to Amara Johnson via Twilio."
    }
    """
    try:
        delivery_id = parameters.get("delivery_id")
        message_type = parameters.get("message_type")
        custom_message = parameters.get("custom_message", "")
        
        # TODO: Get customer phone and name from Supabase
        # For now, use mock data
        customer_phone = "+2348012345678"
        customer_name = "Amara Johnson"
        
        # Build message based on type
        message_templates = {
            "on_my_way": f"Hi {customer_name}, your driver is on the way.",
            "nearby": f"Hi {customer_name}, your driver is nearby — please be ready to receive your delivery.",
            "running_late": f"Hi {customer_name}, your driver is running slightly late but will be there soon.",
            "missed": f"Hi {customer_name}, your driver attempted delivery but missed you. Please call to reschedule.",
            "custom": custom_message
        }
        
        message = message_templates.get(message_type, message_templates["nearby"])
        
        # Call Twilio SMS integration
        result = await send_sms(
            to_phone=customer_phone,
            message=message,
            customer_name=customer_name
        )
        
        return result
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }


async def alert_dispatcher(parameters: dict, context: dict) -> dict:
    """
    Alert dispatcher with priority message.
    
    Platform: Supabase (stores alert) + optional n8n webhook (Slack/email notification)
    Trigger phrases: "alert the dispatcher", "contact dispatch", "I need help"
    
    Input:
    {
        "delivery_id": "uuid",
        "message": "Customer is being aggressive. Need support at 14 Broad Street.",
        "priority": "urgent"
    }
    
    Priority enum: normal | urgent
    
    Expected output:
    {
        "success": true,
        "priority": "urgent",
        "message": "Dispatcher has been alerted."
    }
    """
    try:
        delivery_id = parameters.get("delivery_id")
        message = parameters.get("message")
        priority = parameters.get("priority")
        
        # TODO: Store alert in Supabase
        # TODO: Optionally trigger n8n webhook for Slack/email notification
        # For now, return mock data
        return {
            "success": True,
            "priority": priority,
            "message": "Dispatcher has been alerted."
        }
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }