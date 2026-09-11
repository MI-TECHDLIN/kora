import asyncio
from datetime import datetime, timezone
import logging
from typing import Dict, Any, Optional
import httpx

from app.config import settings

logger = logging.getLogger(__name__)


async def send_dispatcher_alert(
    driver_id: str,
    driver_name: str,
    alert_type: str,
    message: str,
    severity: str = "normal",
    location: str = "unknown",
    shift_id: Optional[str] = None,
    timestamp: Optional[str] = None,
    dispatcher_email: Optional[str] = None,
    webhook_url: Optional[str] = None,
    timeout: float = 5.0
) -> Dict[str, Any]:
    """
    Trigger the n8n dispatcher alert webhook.
    
    Payload schema matches the n8n workflow 'Normalize Alert Payload' node:
    {
        "driver_id": str,
        "driver_name": str,
        "alert_type": str,
        "message": str,
        "severity": str ("normal" | "critical"),
        "location": str,
        "shift_id": str,
        "timestamp": str (ISO 8601),
        "dispatcher_email": str,
        "supabase_url": str,
        "supabase_service_key": str
    }
    
    Returns:
        Dict with success status and details.
    """
    target_url = webhook_url or settings.n8n_dispatcher_webhook_url
    
    if not target_url or "your-n8n-instance.com" in target_url:
        logger.warning("n8n dispatcher webhook URL is not configured.")
        return {
            "success": False,
            "error": "n8n webhook URL not configured",
            "mock": True
        }
    
    if not timestamp:
        timestamp = datetime.now(timezone.utc).isoformat()
        
    payload = {
        "driver_id": driver_id or "unknown_driver",
        "driver_name": driver_name or "Driver",
        "alert_type": alert_type or "dispatcher_alert",
        "message": message,
        "severity": severity,
        "location": location or "unknown",
        "shift_id": shift_id or "unknown_shift",
        "timestamp": timestamp,
        "dispatcher_email": dispatcher_email or settings.dispatcher_escalation_email or "dispatcher@voiceops.app",
        "supabase_url": settings.supabase_url or "",
        "supabase_service_key": settings.supabase_service_key or ""
    }
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(target_url, json=payload, timeout=timeout)
            response.raise_for_status()
            
            try:
                data = response.json()
            except Exception:
                data = {"status": "received", "raw_text": response.text}
                
            logger.info(f"n8n alert sent successfully: {response.status_code}")
            return {
                "success": True,
                "status_code": response.status_code,
                "response": data
            }
    except httpx.HTTPStatusError as e:
        logger.error(f"n8n webhook HTTP error: {e.response.status_code} - {e.response.text}")
        return {
            "success": False,
            "error": f"HTTP {e.response.status_code}: {e.response.text}"
        }
    except Exception as e:
        logger.error(f"Failed to post to n8n webhook: {e}")
        return {
            "success": False,
            "error": str(e)
        }


# Module-level set that holds strong references to background tasks.
# Without this, asyncio tasks with no other references are eligible for GC
# as soon as the caller's stack frame exits (e.g. when a WebSocket session
# closes), which kills the HTTP POST before it reaches n8n.
_background_tasks: set = set()


def trigger_dispatcher_alert_background(
    driver_id: str,
    driver_name: str,
    alert_type: str,
    message: str,
    severity: str = "normal",
    location: str = "unknown",
    shift_id: Optional[str] = None,
    timestamp: Optional[str] = None,
    dispatcher_email: Optional[str] = None,
    webhook_url: Optional[str] = None
) -> None:
    """
    Fire-and-forget trigger for n8n alert webhook.
    Zero latency impact on the real-time voice path — n8n runs fully async.
    Task is anchored in _background_tasks so it survives WebSocket teardown.
    """
    try:
        loop = asyncio.get_running_loop()
        task = loop.create_task(
            send_dispatcher_alert(
                driver_id=driver_id,
                driver_name=driver_name,
                alert_type=alert_type,
                message=message,
                severity=severity,
                location=location,
                shift_id=shift_id,
                timestamp=timestamp,
                dispatcher_email=dispatcher_email,
                webhook_url=webhook_url
            )
        )
        # Keep a strong reference until the task completes, then release it.
        _background_tasks.add(task)
        task.add_done_callback(_background_tasks.discard)
    except RuntimeError:
        # No running event loop (e.g. called from a sync test) — run directly.
        asyncio.run(
            send_dispatcher_alert(
                driver_id=driver_id,
                driver_name=driver_name,
                alert_type=alert_type,
                message=message,
                severity=severity,
                location=location,
                shift_id=shift_id,
                timestamp=timestamp,
                dispatcher_email=dispatcher_email,
                webhook_url=webhook_url
            )
        )


async def send_post_shift_report(
    shift_id: str,
    driver_id: str,
    driver_name: str,
    total_deliveries: int,
    delivered_count: int,
    failed_count: int,
    shift_duration_min: int,
    dispatcher_alerts: int = 0,
    voice_sessions: int = 0,
    incidents: list = None,
    shift_date: Optional[str] = None,
    ended_at: Optional[str] = None,
    operator_email: Optional[str] = None,
    webhook_url: Optional[str] = None,
    timeout: float = 8.0
) -> Dict[str, Any]:
    """
    Trigger the n8n post-shift intelligence webhook.

    Payload schema matches the workflow's 'Normalize Shift Payload' node.
    Called after a driver's shift ends — fully async, no voice path impact.
    """
    target_url = webhook_url or settings.n8n_post_shift_webhook_url

    if not target_url:
        logger.warning("n8n post-shift webhook URL is not configured.")
        return {"success": False, "error": "n8n post-shift webhook URL not configured", "mock": True}

    success_rate = round((delivered_count / total_deliveries * 100), 1) if total_deliveries > 0 else 0.0
    now = datetime.now(timezone.utc).isoformat()

    payload = {
        "shift_id": shift_id,
        "driver_id": driver_id,
        "driver_name": driver_name,
        "total_deliveries": total_deliveries,
        "delivered_count": delivered_count,
        "failed_count": failed_count,
        "success_rate": success_rate,
        "shift_duration_min": shift_duration_min,
        "dispatcher_alerts": dispatcher_alerts,
        "voice_sessions": voice_sessions,
        "incidents": incidents or [],
        "shift_date": shift_date or now[:10],
        "ended_at": ended_at or now,
        "operator_email": operator_email or settings.operator_report_email or "ops@voiceops.app",
        "supabase_url": settings.supabase_url or "",
        "supabase_service_key": settings.supabase_service_key or ""
    }

    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(target_url, json=payload, timeout=timeout)
            response.raise_for_status()
            try:
                data = response.json()
            except Exception:
                data = {"status": "received", "raw_text": response.text}
            logger.info(f"Post-shift report sent to n8n: {response.status_code}")
            return {"success": True, "status_code": response.status_code, "response": data}
    except httpx.HTTPStatusError as e:
        logger.error(f"Post-shift n8n HTTP error: {e.response.status_code} - {e.response.text}")
        return {"success": False, "error": f"HTTP {e.response.status_code}: {e.response.text}"}
    except Exception as e:
        logger.error(f"Failed to post shift report to n8n: {e}")
        return {"success": False, "error": str(e)}


def trigger_post_shift_report_background(
    shift_id: str,
    driver_id: str,
    driver_name: str,
    total_deliveries: int,
    delivered_count: int,
    failed_count: int,
    shift_duration_min: int,
    dispatcher_alerts: int = 0,
    voice_sessions: int = 0,
    incidents: list = None,
    shift_date: Optional[str] = None,
    ended_at: Optional[str] = None,
    operator_email: Optional[str] = None,
    webhook_url: Optional[str] = None
) -> None:
    """
    Fire-and-forget post-shift intelligence trigger.
    Task is anchored in _background_tasks to survive event loop teardown.
    """
    try:
        loop = asyncio.get_running_loop()
        task = loop.create_task(
            send_post_shift_report(
                shift_id=shift_id,
                driver_id=driver_id,
                driver_name=driver_name,
                total_deliveries=total_deliveries,
                delivered_count=delivered_count,
                failed_count=failed_count,
                shift_duration_min=shift_duration_min,
                dispatcher_alerts=dispatcher_alerts,
                voice_sessions=voice_sessions,
                incidents=incidents,
                shift_date=shift_date,
                ended_at=ended_at,
                operator_email=operator_email,
                webhook_url=webhook_url
            )
        )
        _background_tasks.add(task)
        task.add_done_callback(_background_tasks.discard)
    except RuntimeError:
        asyncio.run(
            send_post_shift_report(
                shift_id=shift_id,
                driver_id=driver_id,
                driver_name=driver_name,
                total_deliveries=total_deliveries,
                delivered_count=delivered_count,
                failed_count=failed_count,
                shift_duration_min=shift_duration_min,
                dispatcher_alerts=dispatcher_alerts,
                voice_sessions=voice_sessions,
                incidents=incidents,
                shift_date=shift_date,
                ended_at=ended_at,
                operator_email=operator_email,
                webhook_url=webhook_url
            )
        )
