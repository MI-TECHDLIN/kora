from twilio.rest import Client
from typing import Optional
from app.config import settings


def get_twilio_client() -> Optional[Client]:
    """Get Twilio client instance."""
    if not settings.twilio_account_sid or not settings.twilio_auth_token:
        return None
    
    return Client(settings.twilio_account_sid, settings.twilio_auth_token)


async def make_call(to_phone: str, from_phone: str, twiml_message: str) -> dict:
    """
    Initiate a phone call via Twilio.
    
    Args:
        to_phone: Destination phone number
        from_phone: Twilio phone number
        twiml_message: Message to speak when call connects
        
    Returns:
        Dict with call_sid or error
    """
    client = get_twilio_client()
    if not client:
        return {"error": "Twilio not configured"}
    
    try:
        # Build TwiML
        twiml = f'<Response><Say>{twiml_message}</Say></Response>'
        
        # Make call
        call = client.calls.create(
            to=to_phone,
            from_=from_phone,
            twiml=twiml
        )
        
        return {
            "success": True,
            "call_sid": call.sid,
            "status": call.status
        }
    except Exception as e:
        return {"error": str(e)}


async def send_sms(to_phone: str, from_phone: str, body: str) -> dict:
    """
    Send SMS via Twilio.
    
    Args:
        to_phone: Destination phone number
        from_phone: Twilio phone number
        body: SMS message body
        
    Returns:
        Dict with message_sid or error
    """
    client = get_twilio_client()
    if not client:
        return {"error": "Twilio not configured"}
    
    try:
        message = client.messages.create(
            body=body,
            from_=from_phone,
            to=to_phone
        )
        
        return {
            "success": True,
            "message_sid": message.sid,
            "status": message.status
        }
    except Exception as e:
        return {"error": str(e)}
