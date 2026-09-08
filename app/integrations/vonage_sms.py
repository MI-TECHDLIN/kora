"""
Vonage SMS integration for customer notifications.
Platform: Vonage SMS API (global coverage, free trial)
"""
import httpx
from typing import Dict, Any
from app.config import settings


async def send_sms(
    to_phone: str,
    message: str,
    customer_name: str
) -> dict:
    """
    Send SMS notification to customer via Vonage.
    
    Platform: Vonage SMS API (global coverage, free trial)
    
    Args:
        to_phone: Destination phone number (e.g., "+2348123456789")
        message: Message to send
        customer_name: Name of the customer for logging
        
    Returns:
        Dict with status, message sent, or error
    """
    if not settings.vonage_api_key or settings.vonage_api_key == "your_vonage_api_key":
        # Return mock data if Vonage not configured
        return {
            "success": True,
            "status": "delivered",
            "customer_name": customer_name,
            "message_sent": message,
            "message": f"Mock: SMS sent to {customer_name} at {to_phone} (Vonage not configured)"
        }
    
    url = "https://rest.nexmo.com/sms/json"
    
    data = {
        "from": "VoiceOps",
        "to": to_phone,
        "text": message,
        "api_key": settings.vonage_api_key,
        "api_secret": settings.vonage_api_secret
    }
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(url, data=data, timeout=10.0)
            response.raise_for_status()
            result = response.json()
            
            if result.get("messages")[0].get("status") == "0":
                return {
                    "success": True,
                    "status": "delivered",
                    "customer_name": customer_name,
                    "message_sent": message,
                    "message": f"SMS sent to {customer_name}."
                }
            else:
                error_msg = result.get("messages")[0].get("error-text", "Unknown error")
                return {
                    "success": False,
                    "error": f"Vonage error: {error_msg}"
                }
            
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }