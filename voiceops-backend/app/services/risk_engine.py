"""
Risk Detection Engine
Monitors operational streams (GPS pings, ETAs, idle time, time windows)
and flags risks with confidence and recommended actions.
"""
import logging
from enum import Enum
from dataclasses import dataclass, asdict
from typing import List, Dict, Any, Optional
from app.services.eta_service import eta_service
from app.db.queries import (
    get_next_pending_delivery,
    get_recent_location_pings,
    is_valid_uuid,
)

logger = logging.getLogger(__name__)


class RiskType(str, Enum):
    LATE_DELIVERY = "LATE_DELIVERY"
    CUSTOMER_UNAVAILABLE = "CUSTOMER_UNAVAILABLE"
    EXCESSIVE_IDLE = "EXCESSIVE_IDLE"
    DRIVER_NO_RESPONSE = "DRIVER_NO_RESPONSE"
    TIME_WINDOW_RISK = "TIME_WINDOW_RISK"
    ROUTE_DEVIATION = "ROUTE_DEVIATION"


class RiskSeverity(str, Enum):
    LOW = "LOW"
    MEDIUM = "MEDIUM"
    HIGH = "HIGH"
    CRITICAL = "CRITICAL"


@dataclass
class RiskEvent:
    risk_type: RiskType
    severity: RiskSeverity
    confidence: float
    evidence: Dict[str, Any]
    recommended_action: str
    delivery_id: Optional[str]
    driver_id: str

    def to_dict(self) -> Dict[str, Any]:
        return {
            "risk_type": self.risk_type.value,
            "severity": self.severity.value,
            "confidence": self.confidence,
            "evidence": self.evidence,
            "recommended_action": self.recommended_action,
            "delivery_id": self.delivery_id,
            "driver_id": self.driver_id,
        }


class RiskEngine:
    async def evaluate(
        self,
        driver_id: str,
        shift_id: str,
        location_update: Optional[Dict[str, Any]] = None,
    ) -> List[RiskEvent]:
        """
        Runs risk evaluators against current driver & shift state.
        Returns all detected risks.
        """
        risks: List[RiskEvent] = []
        loc = location_update or {}

        try:
            # 1. Evaluate idle time
            idle_risk = await self._check_idle_time(driver_id, loc)
            if idle_risk:
                risks.append(idle_risk)

            # 2. Evaluate time window and ETA risk
            window_risk = await self._check_time_window(driver_id, shift_id, loc)
            if window_risk:
                risks.append(window_risk)

        except Exception as e:
            logger.error(f"[RiskEngine] Error evaluating risks: {e}")

        return risks

    async def _check_idle_time(
        self,
        driver_id: str,
        location_update: Dict[str, Any]
    ) -> Optional[RiskEvent]:
        """Flags driver if stationary for an extended period."""
        if not is_valid_uuid(driver_id):
            return None

        speed = float(location_update.get("speed", 0.0) or 0.0)
        if speed > 2.0:
            return None

        pings = await get_recent_location_pings(driver_id, limit=6)
        if len(pings) >= 5:
            stationary_pings = sum(1 for p in pings if float(p.get("speed", 0) or 0) <= 1.0)
            if stationary_pings >= 5:
                return RiskEvent(
                    risk_type=RiskType.EXCESSIVE_IDLE,
                    severity=RiskSeverity.MEDIUM,
                    confidence=0.85,
                    evidence={"consecutive_stationary_pings": stationary_pings, "current_speed": speed},
                    recommended_action="Driver has been stationary for over 5 minutes. Check if there are vehicle issues or parking delays.",
                    delivery_id=None,
                    driver_id=driver_id,
                )
        return None

    async def _check_time_window(
        self,
        driver_id: str,
        shift_id: str,
        location_update: Dict[str, Any]
    ) -> Optional[RiskEvent]:
        """Checks whether ETA exceeds promised customer time window."""
        if not is_valid_uuid(shift_id) or not is_valid_uuid(driver_id):
            return None

        delivery = await get_next_pending_delivery(shift_id, driver_id)
        if not delivery:
            return None

        dest_lat = delivery.get("dropoff_latitude") or delivery.get("latitude")
        dest_lng = delivery.get("dropoff_longitude") or delivery.get("longitude")
        origin_lat = location_update.get("latitude")
        origin_lng = location_update.get("longitude")

        if dest_lat is not None and dest_lng is not None and origin_lat is not None and origin_lng is not None:
            speed = float(location_update.get("speed", 30.0) or 30.0)
            # Use traffic-aware ETA with fallback to haversine
            eta_result = await eta_service.compute_eta_minutes_traffic_aware(
                (float(origin_lat), float(origin_lng)),
                (float(dest_lat), float(dest_lng)),
                delivery_id=delivery_id,
                current_speed_kmh=speed
            )
            eta = eta_result["eta_minutes"]

            # Update estimated arrival
            delivery_id = delivery["id"]
            await eta_service.update_delivery_eta(delivery_id, eta)

            # Check time window risk
            risk_check = await eta_service.check_time_window_risk(delivery_id, eta)
            if risk_check.get("risk") in ["MEDIUM", "HIGH", "CRITICAL"]:
                mins_late = risk_check.get("minutes_late", 0)
                severity_map = {
                    "CRITICAL": RiskSeverity.CRITICAL,
                    "HIGH": RiskSeverity.HIGH,
                    "MEDIUM": RiskSeverity.MEDIUM,
                }
                sev = severity_map.get(risk_check["risk"], RiskSeverity.MEDIUM)

                return RiskEvent(
                    risk_type=RiskType.TIME_WINDOW_RISK,
                    severity=sev,
                    confidence=0.90,
                    evidence={"eta_minutes": eta, "minutes_late": mins_late},
                    recommended_action=f"Delivery is projected {mins_late} minutes late. Notify customer and consider re-routing.",
                    delivery_id=delivery_id,
                    driver_id=driver_id,
                )

        return None


risk_engine = RiskEngine()
