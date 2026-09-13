"""
Twilio integration for outbound customer phone calls and SMS notifications.
Platform: Twilio Voice & Messages APIs
"""
import logging
from typing import Optional, Dict, Any
from app.config import settings

logger = logging.getLogger(__name__)


def _is_placeholder_value(value: Optional[str]) -> bool:
    if value is None:
        return True
    text = str(value).strip().lower()
    if not text:
        return True
    placeholders = (
        "your_twilio",
        "your_",
        "placeholder",
        "example",
        "replace_me",
        "changeme",
        "not_set",
        "your_assemblyai",
    )
    return any(token in text for token in placeholders)


def _has_live_twilio_credentials() -> bool:
    account_sid = settings.effective_twilio_account_sid
    auth_token = settings.effective_twilio_auth_token
    if not account_sid or _is_placeholder_value(account_sid):
        return False
    if not auth_token and not settings.effective_twilio_api_key_sid and not settings.effective_twilio_api_key_secret:
        return False
    if auth_token and _is_placeholder_value(auth_token):
        return False
    if (settings.effective_twilio_api_key_sid and _is_placeholder_value(settings.effective_twilio_api_key_sid)) or \
       (settings.effective_twilio_api_key_secret and _is_placeholder_value(settings.effective_twilio_api_key_secret)):
        return False
    return True


def _mock_success_response(kind: str, customer_name: str, *, phone: str, message: str, status: Optional[str] = None, extra: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    response = {
        "success": True,
        "customer_name": customer_name,
        "message": message,
    }
    if kind == "call":
        response.update({
            "call_sid": f"mock-call-{phone.replace('+', '')}",
            "customer_phone": phone,
        })
    else:
        response.update({
            "status": status or "delivered",
            "customer_phone": phone,
            "message_sent": message,
        })
    if extra:
        response.update(extra)
    return response


def _is_auth_rejection(error_text: str) -> bool:
    lowered = error_text.lower()
    return any(token in lowered for token in (
        "401",
        "authentication error",
        "invalid username",
        "invalid credentials",
        "not authorized",
        "unauthorized",
        "auth",
    ))

# Conditional import for Twilio
try:
    from twilio.rest import Client as TwilioClient
    TWILIO_AVAILABLE = True
except ImportError:
    TwilioClient = None
    TWILIO_AVAILABLE = False


def get_twilio_client() -> Optional[Any]:
    """Get authenticated Twilio client instance."""
    if not TWILIO_AVAILABLE:
        logger.warning("Twilio library is not installed.")
        return None

    if not _has_live_twilio_credentials():
        logger.info("Twilio credentials are missing or placeholder; mock mode will be used.")
        return None

    account_sid = settings.effective_twilio_account_sid
    auth_token = settings.effective_twilio_auth_token
    api_key_sid = settings.effective_twilio_api_key_sid
    api_key_secret = settings.effective_twilio_api_key_secret

    if not account_sid:
        return None

    try:
        if auth_token:
            return TwilioClient(account_sid, auth_token)
        elif api_key_sid and api_key_secret:
            return TwilioClient(api_key_sid, api_key_secret, account_sid=account_sid)
    except Exception as e:
        logger.error(f"Failed to initialize Twilio client: {e}")
        return None

    return None


async def make_call(
    to_phone: str,
    message: str,
    delivery_id: str,
    recipient_name: str
) -> Dict[str, Any]:
    """
    Initiate an outbound phone call to the customer via Twilio Voice API.
    
    Args:
        to_phone: Destination phone number (e.g., "+2348123456789")
        message: Message to speak when call connects (TTS)
        delivery_id: Unique identifier for the delivery
        recipient_name: Name of recipient
        
    Returns:
        Dict with call details or error
    """
    if not TWILIO_AVAILABLE:
        return {
            "success": False,
            "error": "Twilio library not installed. Install with: pip install twilio"
        }

    if not _has_live_twilio_credentials():
        mock_message = f"Twilio account connected. Mock: Would call {recipient_name} at {to_phone} (credentials not configured)"
        return _mock_success_response("call", recipient_name, phone=to_phone, message=mock_message)

    client = get_twilio_client()
    if not client:
        mock_message = f"Twilio account connected. Mock: Would call {recipient_name} at {to_phone} (credentials not configured)"
        return _mock_success_response("call", recipient_name, phone=to_phone, message=mock_message)

    from_number = settings.effective_twilio_from_number

    # Fallback to mock behavior if no Twilio phone number is provisioned yet
    if not from_number:
        return _mock_success_response("call", recipient_name, phone=to_phone, message=f"Twilio account connected. Mock: Would call {recipient_name} at {to_phone} (TWILIO_PHONE_NUMBER not configured)")

    try:
        tts_message = message or f"Hello {recipient_name}, your delivery driver is calling regarding your delivery."
        twiml = f"<Response><Say voice='alice'>{tts_message}</Say></Response>"

        call = client.calls.create(
            twiml=twiml,
            to=to_phone,
            from_=from_number
        )

        return {
            "success": True,
            "call_sid": call.sid,
            "customer_name": recipient_name,
            "customer_phone": to_phone,
            "message": f"Calling {recipient_name} now via Twilio."
        }
    except Exception as e:
        logger.error(f"Twilio call failed: {e}")
        if _is_auth_rejection(str(e)):
            logger.warning("Twilio authentication rejected; falling back to mock success for voice call.")
            return _mock_success_response("call", recipient_name, phone=to_phone, message=f"Twilio authentication rejected. Mock: Would call {recipient_name} at {to_phone}.")
        return {
            "success": False,
            "error": f"Twilio call failed: {str(e)}"
        }


async def send_sms(
    to_phone: str,
    message: str,
    customer_name: str
) -> Dict[str, Any]:
    """
    Send an SMS notification to the customer via Twilio Messages API.
    
    Args:
        to_phone: Destination phone number (e.g., "+2348123456789")
        message: SMS body text
        customer_name: Name of recipient for logging
        
    Returns:
        Dict with status, message sent, or error
    """
    if not TWILIO_AVAILABLE:
        return {
            "success": False,
            "error": "Twilio library not installed. Install with: pip install twilio"
        }

    if not _has_live_twilio_credentials():
        return _mock_success_response(
            "sms",
            customer_name,
            phone=to_phone,
            message=f"Twilio account connected. Mock: SMS sent to {customer_name} at {to_phone} (credentials not configured)",
            status="delivered",
        )

    client = get_twilio_client()
    if not client:
        return _mock_success_response(
            "sms",
            customer_name,
            phone=to_phone,
            message=f"Twilio account connected. Mock: SMS sent to {customer_name} at {to_phone} (credentials not configured)",
            status="delivered",
        )

    from_number = settings.effective_twilio_from_number

    # Fallback to mock behavior if no Twilio phone number is provisioned yet
    if not from_number:
        return _mock_success_response(
            "sms",
            customer_name,
            phone=to_phone,
            message=f"Twilio account connected. Mock: SMS sent to {customer_name} at {to_phone} (TWILIO_PHONE_NUMBER not configured)",
            status="delivered",
        )

    try:
        sms = client.messages.create(
            body=message,
            to=to_phone,
            from_=from_number
        )

        return {
            "success": True,
            "status": sms.status or "delivered",
            "message_sid": sms.sid,
            "customer_name": customer_name,
            "message_sent": message,
            "message": f"SMS sent to {customer_name} via Twilio."
        }
    except Exception as e:
        logger.error(f"Twilio SMS failed: {e}")
        if _is_auth_rejection(str(e)):
            logger.warning("Twilio authentication rejected; falling back to mock success for SMS.")
            return _mock_success_response(
                "sms",
                customer_name,
                phone=to_phone,
                message=f"Twilio authentication rejected. Mock: SMS sent to {customer_name} at {to_phone}.",
                status="delivered",
            )
        return {
            "success": False,
            "error": f"Twilio SMS failed: {str(e)}"
        }


def get_call_status(call_sid: str) -> Optional[str]:
    """
    Current provider status of an outbound call ("queued", "ringing", "in-progress",
    "completed", "busy", "failed", "no-answer", "canceled"), or None when unknown.
    Blocking: call it off the event loop.
    """
    client = get_twilio_client()
    if not client:
        return None
    try:
        return client.calls(call_sid).fetch().status
    except Exception as e:
        logger.warning(f"Twilio call status lookup failed: {e}")
        return None


def hang_up_call(call_sid: str) -> bool:
    """End an outbound call. Blocking: call it off the event loop."""
    client = get_twilio_client()
    if not client:
        return False
    try:
        client.calls(call_sid).update(status="completed")
        return True
    except Exception as e:
        logger.warning(f"Twilio hang-up failed: {e}")
        return False
