"""
ETA Service
Computes estimated arrival times using geographic metrics,
updates deliveries table, and detects time window compliance risks.
"""
import math
import logging
from datetime import datetime, timedelta, timezone
from typing import Tuple, Dict, Any, Optional
from app.services.location_service import haversine_distance
from app.db.queries import get_delivery_by_id, get_supabase, is_valid_uuid

logger = logging.getLogger(__name__)


class ETAService:
    URBAN_FACTOR: float = 1.35  # compensates for urban traffic and street grid

    @classmethod
    def compute_eta_minutes(
        cls,
        origin: Tuple[float, float],
        destination: Tuple[float, float],
        current_speed_kmh: float = 30.0,
    ) -> int:
        """
        Compute ETA in minutes using haversine distance with an urban street factor.
        """
        dist_m = haversine_distance(origin[0], origin[1], destination[0], destination[1])
        dist_km = (dist_m / 1000.0) * cls.URBAN_FACTOR

        effective_speed = current_speed_kmh if current_speed_kmh >= 10.0 else 25.0
        hours = dist_km / effective_speed
        return max(1, math.ceil(hours * 60))

    # Cache for traffic-aware ETA results: {delivery_id: (timestamp, result)}
    _traffic_eta_cache: Dict[str, Tuple[float, Dict[str, Any]]] = {}
    _cache_ttl_seconds: int = 75  # Cache traffic results for ~75 seconds

    async def compute_eta_minutes_traffic_aware(
        self,
        origin: Tuple[float, float],
        destination: Tuple[float, float],
        delivery_id: Optional[str] = None,
        current_speed_kmh: float = 30.0,
    ) -> Dict[str, Any]:
        """
        Compute ETA in minutes using traffic-aware routing API.
        Falls back to haversine-based calculation if the traffic API fails.
        
        Returns:
            {
                "eta_minutes": int,
                "distance_km": float,
                "traffic_delay_minutes": float,
                "provider": "tomtom" | "haversine",
                "geometry": str (optional)
            }
        """
        # Check cache first if delivery_id is provided
        if delivery_id:
            import time
            current_time = time.time()
            if delivery_id in self._traffic_eta_cache:
                timestamp, cached_result = self._traffic_eta_cache[delivery_id]
                if current_time - timestamp < self._cache_ttl_seconds:
                    logger.debug(f"[ETAService] Using cached traffic ETA for delivery {delivery_id}")
                    return cached_result

        # Try traffic-aware routing
        try:
            from app.integrations.traffic_routing import traffic_routing_client
            traffic_result = await traffic_routing_client.get_traffic_aware_eta(origin, destination)
            
            if traffic_result and traffic_result.get("success"):
                result = {
                    "eta_minutes": traffic_result["eta_minutes"],
                    "distance_km": traffic_result["distance_km"],
                    "traffic_delay_minutes": traffic_result.get("traffic_delay_minutes", 0),
                    "provider": "tomtom",
                    "geometry": traffic_result.get("geometry", ""),
                }
                
                # Cache the result if delivery_id is provided
                if delivery_id:
                    self._traffic_eta_cache[delivery_id] = (time.time(), result)
                
                logger.info(f"[ETAService] Traffic-aware ETA: {result['eta_minutes']} mins (delay: {result['traffic_delay_minutes']} mins)")
                return result
        except Exception as e:
            logger.warning(f"[ETAService] Traffic-aware routing failed: {e}")

        # Fallback to haversine-based calculation
        logger.info("[ETAService] Falling back to haversine-based ETA calculation")
        eta_minutes = self.compute_eta_minutes(origin, destination, current_speed_kmh)
        dist_m = haversine_distance(origin[0], origin[1], destination[0], destination[1])
        dist_km = (dist_m / 1000.0) * self.URBAN_FACTOR
        
        result = {
            "eta_minutes": eta_minutes,
            "distance_km": round(dist_km, 2),
            "traffic_delay_minutes": 0.0,
            "provider": "haversine",
            "geometry": "",
        }
        
        # Cache the fallback result if delivery_id is provided
        if delivery_id:
            import time
            self._traffic_eta_cache[delivery_id] = (time.time(), result)
        
        return result

    async def update_delivery_eta(
        self,
        delivery_id: str,
        eta_minutes: int,
    ) -> Dict[str, Any]:
        """
        Calculate target arrival timestamp and persist to deliveries.estimated_arrival.
        """
        if not is_valid_uuid(delivery_id):
            return {}

        try:
            target_time = datetime.now(timezone.utc) + timedelta(minutes=eta_minutes)
            res = (
                get_supabase().table("deliveries")
                .update({"estimated_arrival": target_time.isoformat()})
                .eq("id", delivery_id)
                .execute()
            )
            return res.data[0] if res.data else {}
        except Exception as e:
            logger.error(f"[ETAService] Failed to update delivery ETA: {e}")
            return {}

    async def check_time_window_risk(
        self,
        delivery_id: str,
        current_eta_minutes: int,
    ) -> Dict[str, Any]:
        """
        Compare current ETA with the delivery's promised time window.
        Returns risk level and estimated delay in minutes.
        """
        if not is_valid_uuid(delivery_id):
            return {"risk": "NONE", "minutes_late": 0, "delivery_id": delivery_id}

        delivery = await get_delivery_by_id(delivery_id)
        if not delivery:
            return {"risk": "NONE", "minutes_late": 0, "delivery_id": delivery_id}

        target_arrival = datetime.now(timezone.utc) + timedelta(minutes=current_eta_minutes)

        time_window_end = delivery.get("time_window_end")
        if time_window_end:
            try:
                end_dt = datetime.fromisoformat(str(time_window_end).replace("Z", "+00:00"))
                if target_arrival > end_dt:
                    diff_mins = int((target_arrival - end_dt).total_seconds() / 60)
                    severity = "CRITICAL" if diff_mins > 30 else ("HIGH" if diff_mins > 15 else "MEDIUM")
                    return {
                        "risk": severity,
                        "minutes_late": diff_mins,
                        "delivery_id": delivery_id,
                        "window_end": time_window_end,
                    }
            except Exception as e:
                logger.warning(f"[ETAService] Failed to parse time_window_end: {e}")

        return {"risk": "NONE", "minutes_late": 0, "delivery_id": delivery_id}


eta_service = ETAService()
