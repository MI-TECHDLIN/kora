from typing import Optional
from app.config import settings

# Conditional import for LiveKit - allow server to start even if not installed
try:
    from livekit import api as livekit_api
    LIVEKIT_AVAILABLE = True
except ImportError:
    LIVEKIT_AVAILABLE = False
    livekit_api = None


def get_livekit_client() -> Optional:
    """Get LiveKit client instance for SIP/PSTN calls."""
    if not LIVEKIT_AVAILABLE:
        return None
    if not settings.livekit_url or not settings.livekit_api_key or not settings.livekit_api_secret:
        return None
    
    return livekit_api.LiveKitAPI(
        url=settings.livekit_url,
        api_key=settings.livekit_api_key,
        api_secret=settings.livekit_api_secret
    )


async def make_call(
    to_phone: str,
    message: str,
    delivery_id: str,
    recipient_name: str
) -> dict:
    """
    Initiate an outbound PSTN call via LiveKit SIP.
    
    Architecture note:
    - LiveKit handles the telephony entirely — it dials the customer's phone number
    - AssemblyAI has zero involvement in this call — no conflict
    - LiveKit and AssemblyAI operate on completely separate lanes
    
    Args:
        to_phone: Destination phone number (e.g., "+2348123456789")
        message: Message to speak when call connects (TTS)
        delivery_id: Unique identifier for the delivery
        recipient_name: Name of the recipient for participant identity
        
    Returns:
        Dict with room_name, call status, or error
    """
    if not LIVEKIT_AVAILABLE:
        return {"success": False, "error": "LiveKit not installed. Install with: pip install livekit livekit-api"}
    
    client = get_livekit_client()
    if not client:
        return {"success": False, "error": "LiveKit not configured"}
    
    if not settings.livekit_sip_trunk_id:
        return {"success": False, "error": "LiveKit SIP trunk ID not configured"}
    
    try:
        # Create a SIP participant (outbound call) in a transient room
        # LiveKit dials the customer's number via the configured SIP trunk
        room_name = f"customer-call-{delivery_id}"
        
        await client.sip.create_sip_participant(
            livekit_api.CreateSIPParticipantRequest(
                sip_trunk_id=settings.livekit_sip_trunk_id,
                sip_url=f"sip:{to_phone}@sip.livekit.cloud",
                room_name=room_name,
                participant_identity=f"customer-{delivery_id}",
                participant_name=recipient_name,
                # Note: TTS message can be played via DTMF or room audio
                # Post-hackathon: bridge driver audio into same room for live conversation
            )
        )
        
        return {
            "success": True,
            "room_name": room_name,
            "customer_name": recipient_name,
            "customer_phone": to_phone,
            "message": f"Calling {recipient_name} now."
        }
        
    except Exception as e:
        return {"success": False, "error": str(e)}
