import httpx
from typing import Dict, Any, Optional
from app.config import settings


async def trigger_n8n_webhook(workflow_name: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    Trigger an n8n workflow via webhook.
    Fire-and-forget - never await in response path.
    
    Args:
        workflow_name: Name of the workflow (shift-end, driver-signup, etc.)
        payload: Data to send to the webhook
        
    Returns:
        Dict with success status or error
    """
    # Map workflow names to webhook URLs
    webhook_urls = {
        "shift-end": settings.n8n_shift_webhook_url,
        "driver-signup": settings.n8n_driver_signup_webhook_url
    }
    
    webhook_url = webhook_urls.get(workflow_name)
    
    if not webhook_url:
        return {
            "success": False,
            "error": f"No webhook URL configured for workflow: {workflow_name}"
        }
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                webhook_url,
                json=payload,
                timeout=5.0
            )
            response.raise_for_status()
            
            return {
                "success": True,
                "workflow": workflow_name,
                "status_code": response.status_code
            }
    except Exception as e:
        # Log error but don't fail - n8n is fire-and-forget
        print(f"n8n webhook trigger error: {e}")
        return {
            "success": False,
            "error": str(e),
            "workflow": workflow_name
        }


async def trigger_shift_end_webhook(shift_id: str, driver_id: str) -> Dict[str, Any]:
    """
    Trigger the post-shift intelligence workflow in n8n.
    """
    return await trigger_n8n_webhook("shift-end", {
        "shift_id": shift_id,
        "driver_id": driver_id
    })


async def trigger_driver_signup_webhook(driver_id: str, phone: str, name: str) -> Dict[str, Any]:
    """
    Trigger the new driver welcome workflow in n8n.
    """
    return await trigger_n8n_webhook("driver-signup", {
        "driver_id": driver_id,
        "phone": phone,
        "name": name
    })
