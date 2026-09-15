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
    ) -> bool:
        """
        Dispatches proactive voice alert to the driver.
        Stores record in dispatcher_alerts for real-time WebSocket pickup and telemetry.
        
        Args:
            route_suggestion: Optional dict with route data for ROUTE_DEVIATION alerts
                {"eta_minutes": int, "current_eta_minutes": int, "geometry": str}
        """
        logger.info(f"[AlertService] 📢 Proactive Alert [{severity.upper()}] to driver {driver_id}: {message}")

        try:
            get_supabase().table("dispatcher_alerts").insert({
                "driver_id": str(driver_id),
                "alert_type": risk_type,
                "message": message,
                "severity": severity,
                "is_critical": (severity.lower() in ["high", "critical"]),
                "created_at": datetime.now(timezone.utc).isoformat(),
            }).execute()

            # Push directly to driver via live WebSocket channel
            from app.api.websocket.driver_ws import ws_manager
            
            ws_payload = {
                "type": "PROACTIVE_ALERT",
                "severity": severity,
                "risk_type": risk_type,
                "message": message,
                "delivery_id": delivery_id,
            }
            
            # Add route suggestion for ROUTE_DEVIATION alerts
            if risk_type == "ROUTE_DEVIATION" and route_suggestion:
                ws_payload["route_suggestion"] = route_suggestion
            
            await ws_manager.send_to_driver(driver_id, ws_payload)
            return True
        except Exception as e:
            logger.warning(f"[AlertService] Failed to record alert to DB: {e}")
            return False


alert_service = ProactiveAlertService()
