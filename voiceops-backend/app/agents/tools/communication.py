"""
Communication tools for VoiceOps agent.
Tools: call_customer, notify_customer, alert_dispatcher
Platform: Twilio Voice & SMS, Supabase + n8n webhook
"""
import logging
from typing import Dict, Any, Optional
from app.integrations.twilio_client import make_call, send_sms
from app.integrations.n8n_client import trigger_dispatcher_alert_background
from app.db.queries import get_delivery_by_id, get_supabase, is_valid_uuid

logger = logging.getLogger(__name__)


async def _resolve_customer_info(delivery_id: Optional[str], context: dict) -> tuple[Optional[str], str, str]:
    """
    Resolve customer phone, customer name, and effective delivery_id.
    Looks in Supabase deliveries table first, then context fallback.
    """
    current_delivery = context.get("current_delivery") or {}
    resolved_del_id = delivery_id or current_delivery.get("id")

    delivery_row = None
    if resolved_del_id:
        try:
            delivery_row = await get_delivery_by_id(resolved_del_id)
        except Exception as e:
            logger.warning(f"[Communication] Could not fetch delivery {resolved_del_id}: {e}")

    if delivery_row:
        phone = delivery_row.get("phone") or delivery_row.get("customer_phone")
        name = delivery_row.get("recipient_name") or delivery_row.get("customer_name") or "Customer"
        return phone, name, resolved_del_id
    elif current_delivery:
        phone = current_delivery.get("customer_phone") or current_delivery.get("phone")
        name = current_delivery.get("recipient_name") or current_delivery.get("customer_name") or "Customer"
        return phone, name, resolved_del_id

    return None, "Customer", resolved_del_id


async def _log_customer_interaction(
    delivery_id: Optional[str],
    channel: str,
    content: str,
    status: str = "sent",
    external_id: Optional[str] = None
):
    """Safely log interaction to customer_interactions table."""
    if not delivery_id or not is_valid_uuid(delivery_id):
        return
    try:
        get_supabase().table("customer_interactions").insert({
            "delivery_id": delivery_id,
            "channel": channel,
            "direction": "outbound",
            "sender_type": "voice_agent",
            "content": content,
            "status": status,
            "external_id": external_id,
        }).execute()
    except Exception as e:
        logger.warning(f"[Communication] Failed to log interaction: {e}")


async def call_customer(parameters: dict, context: dict) -> dict:
    """
    Call the customer via Twilio Voice API.
    Trigger phrases: "call the customer", "ring the customer", "call them"
    """
    try:
        delivery_id = parameters.get("delivery_id")
        message = parameters.get("message", "Your delivery driver is calling regarding your delivery.")

        customer_phone, customer_name, resolved_del_id = await _resolve_customer_info(delivery_id, context)

        if not customer_phone:
            return {
                "success": False,
                "error": "No customer phone number on file for this delivery."
            }

        # Call Twilio integration
        result = await make_call(
            to_phone=customer_phone,
            message=message,
            delivery_id=resolved_del_id or "",
            recipient_name=customer_name
        )

        call_sid = result.get("call_sid")
        await _log_customer_interaction(
            delivery_id=resolved_del_id,
            channel="call",
            content=message,
            status="initiated" if result.get("success") else "failed",
            external_id=call_sid
        )

        return result
    except Exception as e:
        logger.error(f"[Tool:call_customer] {e}")
        return {
            "success": False,
            "error": str(e)
        }


async def notify_customer(parameters: dict, context: dict) -> dict:
    """
    Send SMS notification to customer via Twilio.
    Trigger phrases: "message the customer", "tell customer I'm close", "send ETA", "I'm 5 minutes away"
    """
    try:
        delivery_id = parameters.get("delivery_id")
        message_type = parameters.get("message_type")
        custom_message = parameters.get("custom_message", "")

        customer_phone, customer_name, resolved_del_id = await _resolve_customer_info(delivery_id, context)

        if not customer_phone:
            return {
                "success": False,
                "error": "No customer phone number on file for this delivery."
            }

        # Build message based on type
        message_templates = {
            "on_my_way": f"Hi {customer_name}, your driver is on the way with your package.",
            "nearby": f"Hi {customer_name}, your driver is nearby — please be ready to receive your delivery.",
            "running_late": f"Hi {customer_name}, your driver is experiencing delays but is on the way.",
            "missed": f"Hi {customer_name}, your driver attempted delivery but was unable to reach you. Please contact support to reschedule.",
            "custom": custom_message or f"Update regarding your delivery for {customer_name}."
        }

        message = message_templates.get(message_type, message_templates["nearby"])

        # Call Twilio SMS integration
        result = await send_sms(
            to_phone=customer_phone,
            message=message,
            customer_name=customer_name
        )

        message_sid = result.get("message_sid")
        await _log_customer_interaction(
            delivery_id=resolved_del_id,
            channel="sms",
            content=message,
            status="sent" if result.get("success") else "failed",
            external_id=message_sid
        )

        return result
    except Exception as e:
        logger.error(f"[Tool:notify_customer] {e}")
        return {
            "success": False,
            "error": str(e)
        }


async def alert_dispatcher(parameters: dict, context: dict) -> dict:
    """
    Alert dispatcher with priority message.
    Stores alert in Supabase dispatcher_alerts + triggers n8n webhook.
    Trigger phrases: "alert the dispatcher", "contact dispatch", "I need help"
    """
    try:
        delivery_id = parameters.get("delivery_id")
        message = parameters.get("message", "")
        priority = parameters.get("priority", "normal")

        severity = "critical" if str(priority).lower() in ["urgent", "critical"] else "normal"
        alert_type = "safety_incident" if severity == "critical" else "driver_alert"

        driver_id = context.get("driver_id", "unknown_driver")
        driver_name = context.get("driver_name", "Driver")
        shift_id = context.get("shift_id", "unknown_shift")

        location = context.get("location")
        if not location:
            current_delivery = context.get("current_delivery")
            if isinstance(current_delivery, dict):
                location = current_delivery.get("address", "unknown")
            else:
                location = "unknown"

        # 1. Insert alert in Supabase dispatcher_alerts table
        try:
            get_supabase().table("dispatcher_alerts").insert({
                "driver_id": str(driver_id),
                "driver_name": str(driver_name),
                "alert_type": alert_type,
                "message": str(message),
                "severity": severity,
                "location": str(location),
                "shift_id": str(shift_id),
                "is_critical": (severity == "critical"),
            }).execute()
        except Exception as e:
            logger.warning(f"[Communication] Failed to insert dispatcher_alert in DB: {e}")

        # 2. Trigger n8n dispatcher alert workflow in background
        trigger_dispatcher_alert_background(
            driver_id=str(driver_id),
            driver_name=str(driver_name),
            alert_type=alert_type,
            message=str(message),
            severity=severity,
            location=str(location),
            shift_id=str(shift_id)
        )

        return {
            "success": True,
            "priority": priority,
            "severity": severity,
            "message": "Dispatcher has been alerted."
        }
    except Exception as e:
        logger.error(f"[Tool:alert_dispatcher] {e}")
        return {
            "success": False,
            "error": str(e)
        }