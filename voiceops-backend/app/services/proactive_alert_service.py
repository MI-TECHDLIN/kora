"""
Proactive Alert Service
Dispatches real-time proactive voice/push alerts to drivers and dispatchers.
Enforces alert cooldowns to avoid repetitive driver interruption.
"""
import logging
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional
from app.db.queries import get_supabase

logger = logging.getLogger(__name__)


class ProactiveAlertService:
    def __init__(self):
        # In-memory cooldown tracker: key = f"{driver_id}:{risk_type}"
        self._last_alert_timestamps: Dict[str, datetime] = {}

    async def should_alert(
        self,
        driver_id: str,
        risk_type: str,
        cooldown_minutes: int = 15,
    ) -> bool:
        """
        Check if an alert of this type can be sent without violating cooldown.
        """
        key = f"{driver_id}:{risk_type}"
        now = datetime.now(timezone.utc)

        last_sent = self._last_alert_timestamps.get(key)
        if last_sent is not None:
            if (now - last_sent) < timedelta(minutes=cooldown_minutes):
                logger.info(f"[AlertService] Cooldown active for {key}. Suppressing alert.")
                return False

        self._last_alert_timestamps[key] = now
        return True

    async def emit_voice_alert(
        self,
        driver_id: str,
        message: str,
        severity: str = "normal",
        risk_type: str = "operational_alert",
        delivery_id: Optional[str] = None,
        route_suggestion: Optional[Dict[str, Any]] = None,
        shift_id: Optional[str] = None,
        spoken_instructions: Optional[str] = None,
    ) -> bool:
        """
        Dispatches proactive voice alert to the driver.
        Stores record in dispatcher_alerts for real-time WebSocket pickup and telemetry.
        Pushes to the driver's active voice WebSocket and queues unprompted co-rider speech.
        
        Args:
            route_suggestion: Optional dict with route data for ROUTE_DEVIATION alerts
                {"eta_minutes": int, "current_eta_minutes": int, "geometry": str}
            shift_id: Optional shift ID to target specific shift session
            spoken_instructions: Prompt instructions for AssemblyAI reply.create
        """
        logger.info(f"[AlertService] 📢 Proactive Alert [{severity.upper()}] to driver {driver_id}: {message}")

        # The audit-trail write is a nice-to-have; it must never be able to silence the driver
        # announcement below (this is the only mechanism auto-accept and other proactive
        # alerts use to speak up, so a Supabase hiccup here must not suppress it).
        try:
            get_supabase().table("dispatcher_alerts").insert({
                "driver_id": str(driver_id),
                "alert_type": risk_type,
                "message": message,
                "severity": severity,
                "is_critical": (severity.lower() in ["high", "critical"]),
                "created_at": datetime.now(timezone.utc).isoformat(),
            }).execute()
        except Exception as e:
            logger.warning(f"[AlertService] Failed to record alert to DB: {e}")

        try:
            from app.api.websocket import events
            from app.api.websocket.voice import present_proactive_alert

            # Contract-compliant payload: {"event": "PROACTIVE_ALERT", ...}
            ws_payload = events.proactive_alert(
                severity=severity,
                risk_type=risk_type,
                message=message,
                delivery_id=delivery_id,
                route_suggestion=route_suggestion,
            )

            # 1. Push to voice socket and trigger unprompted co-rider speech
            await present_proactive_alert(
                driver_id=driver_id,
                alert_payload=ws_payload,
                spoken_instructions=spoken_instructions,
                shift_id=shift_id,
            )

            # 2. Push to legacy driver WebSocket if connected
            try:
                from app.api.websocket.driver_ws import ws_manager
                legacy_payload = {
                    "type": "PROACTIVE_ALERT",
                    **ws_payload
                }
                await ws_manager.send_to_driver(driver_id, legacy_payload)
            except Exception:
                pass

            return True
        except Exception as e:
            logger.warning(f"[AlertService] Failed to push proactive alert: {e}")
            return False


alert_service = ProactiveAlertService()
