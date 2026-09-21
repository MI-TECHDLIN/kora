"""
Risk Detection Engine
Monitors operational streams (GPS pings, ETAs, idle time, time windows)
and flags risks with confidence and recommended actions.
"""
import logging
from enum import Enum
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from typing import List, Dict, Any, Optional
from app.services.eta_service import eta_service
from app.services.location_service import haversine_distance
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
            # 1. Evaluate idle time (gated on proximity to current delivery stop)
            idle_risk = await self._check_idle_time(driver_id, shift_id, loc)
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
        shift_id: str,
        location_update: Dict[str, Any]
    ) -> Optional[RiskEvent]:
        """
        Flags driver if stationary for an extended period at a delivery stop.
        Gated on being within 100m geofence of the current pending delivery
        to avoid false positives in traffic jams or at traffic lights.
        """
        if not is_valid_uuid(driver_id) or not is_valid_uuid(shift_id):
            return None

        speed = float(location_update.get("speed", 0.0) or 0.0)
        if speed > 2.0:
            return None

        delivery = await get_next_pending_delivery(shift_id, driver_id)
        if not delivery:
            return None

        dest_lat = delivery.get("dropoff_latitude") or delivery.get("latitude")
        dest_lng = delivery.get("dropoff_longitude") or delivery.get("longitude")
        lat = location_update.get("latitude")
        lng = location_update.get("longitude")

        dist = None
        at_stop = False
        if dest_lat is not None and dest_lng is not None and lat is not None and lng is not None:
            try:
                dist = haversine_distance(float(lat), float(lng), float(dest_lat), float(dest_lng))
                if dist <= 100.0:
                    at_stop = True
            except (TypeError, ValueError):
                pass

        if delivery.get("status") == "arrived":
            at_stop = True

        # Gate on stop proximity: don't interrupt drivers who are simply in traffic
        if not at_stop:
            return None

        pings = await get_recent_location_pings(driver_id, limit=6)
        if len(pings) >= 5:
            stationary_pings = sum(1 for p in pings if float(p.get("speed", 0) or 0) <= 1.0)
            if stationary_pings >= 5:
                dwell_seconds = stationary_pings * 15
                if len(pings) >= 2 and pings[0].get("pinged_at") and pings[-1].get("pinged_at"):
                    try:
                        latest_t = datetime.fromisoformat(str(pings[0]["pinged_at"]).replace("Z", "+00:00"))
                        oldest_t = datetime.fromisoformat(str(pings[-1]["pinged_at"]).replace("Z", "+00:00"))
                        diff_s = int((latest_t - oldest_t).total_seconds())
                        if diff_s > 0:
                            dwell_seconds = diff_s
                    except Exception:
                        pass

                prior_failures = int(delivery.get("attempt_count") or 0)
                recipient = delivery.get("recipient_name") or "the customer"
                address = delivery.get("address") or "this stop"

                if prior_failures > 0:
                    question = (
                        f"You've been at this stop a while, and this delivery had a prior failed attempt. "
                        f"Are you stuck at a gate, or having trouble finding {recipient}?"
                    )
                else:
                    question = (
                        f"You've been at this stop a while — "
                        f"are you stuck at a gate, or having trouble finding {recipient}?"
                    )

                return RiskEvent(
                    risk_type=RiskType.EXCESSIVE_IDLE,
                    severity=RiskSeverity.MEDIUM,
                    confidence=0.85,
                    evidence={
                        "consecutive_stationary_pings": stationary_pings,
                        "current_speed": speed,
                        "dwell_seconds": dwell_seconds,
                        "at_stop": True,
                        "distance_to_stop_meters": round(dist, 1) if dist is not None else None,
                        "prior_failures": prior_failures,
                        "recipient_name": recipient,
                        "address": address,
                    },
                    recommended_action=question,
                    delivery_id=delivery["id"],
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
                delivery_id=delivery["id"],
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

                # Check for reroute opportunity when risk is MEDIUM or higher
                reroute_risk = await self._check_reroute_available(
                    driver_id, shift_id, location_update, delivery, eta, sev
                )
                if reroute_risk:
                    return reroute_risk

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

    async def _check_reroute_available(
        self,
        driver_id: str,
        shift_id: str,
        location_update: Dict[str, Any],
        delivery: Dict[str, Any],
        current_eta: int,
        current_severity: RiskSeverity,
    ) -> Optional[RiskEvent]:
        """
        Check if an alternate route offers meaningful time savings.
        Returns ROUTE_DEVIATION risk event if alternate route saves 3+ minutes.
        """
        if not is_valid_uuid(driver_id):
            return None

        # Only check for reroute when current risk is MEDIUM or higher
        if current_severity not in [RiskSeverity.MEDIUM, RiskSeverity.HIGH, RiskSeverity.CRITICAL]:
            return None

        try:
            from app.integrations.traffic_routing import traffic_routing_client
            
            origin_lat = location_update.get("latitude")
            origin_lng = location_update.get("longitude")
            dest_lat = delivery.get("dropoff_latitude") or delivery.get("latitude")
            dest_lng = delivery.get("dropoff_longitude") or delivery.get("longitude")

            if not all([origin_lat, origin_lng, dest_lat, dest_lng]):
                return None

            # Get traffic-aware route (this should return the best available route)
            alternate_route = await traffic_routing_client.get_traffic_aware_eta(
                (float(origin_lat), float(origin_lng)),
                (float(dest_lat), float(dest_lng))
            )

            if alternate_route and alternate_route.get("success"):
                alternate_eta = alternate_route["eta_minutes"]
                time_savings = current_eta - alternate_eta

                # Only suggest reroute if it saves at least 3 minutes
                if time_savings >= 3:
                    traffic_delay = alternate_route.get("traffic_delay_minutes", 0)
                    message = (f"Traffic ahead adds about {traffic_delay:.0f} minutes on your current route. "
                              f"An alternate route saves {time_savings} minutes. Want me to reroute?")

                    return RiskEvent(
                        risk_type=RiskType.ROUTE_DEVIATION,
                        severity=current_severity,
                        confidence=0.85,
                        evidence={
                            "current_eta_minutes": current_eta,
                            "alternate_eta_minutes": alternate_eta,
                            "time_savings_minutes": time_savings,
                            "traffic_delay_minutes": traffic_delay,
                            "geometry": alternate_route.get("geometry", ""),
                        },
                        recommended_action=message,
                        delivery_id=delivery["id"],
                        driver_id=driver_id,
                    )

        except Exception as e:
            logger.warning(f"[RiskEngine] Failed to check reroute availability: {e}")

        return None


risk_engine = RiskEngine()
