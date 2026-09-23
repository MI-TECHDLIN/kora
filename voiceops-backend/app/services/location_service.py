"""
Location Intelligence Service
Handles geofencing, automatic arrival detection, ETA calculations,
and driver movement state tracking.
"""
import math
import logging
from typing import List, Dict, Any, Optional
from datetime import datetime, timezone

logger = logging.getLogger(__name__)


def haversine_distance(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """
    Calculate great-circle distance between two GPS coordinates in meters.
    """
    R = 6371000.0  # Earth's radius in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lng2 - lng1)

    a = (
        math.sin(delta_phi / 2.0) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0) ** 2
    )
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
    return R * c


class LocationIntelligenceService:
    GEOFENCE_RADIUS_METERS: float = 100.0
    IDLE_THRESHOLD_SECONDS: int = 300
    DEVIATION_THRESHOLD_METERS: float = 500.0

    @staticmethod
    def compute_eta(
        origin_lat: float,
        origin_lng: float,
        dest_lat: float,
        dest_lng: float,
        speed_kmh: float = 30.0,
    ) -> int:
        """
        Compute ETA in minutes using haversine distance with 1.3x urban congestion factor.
        Defaults to 25 km/h if current speed is too low or zero.
        """
        distance_m = haversine_distance(origin_lat, origin_lng, dest_lat, dest_lng)
        distance_km = (distance_m / 1000.0) * 1.3  # 1.3x urban routing multiplier

        effective_speed = speed_kmh if speed_kmh >= 10.0 else 25.0
        duration_hours = distance_km / effective_speed
        duration_minutes = max(1, math.ceil(duration_hours * 60))
        return duration_minutes

    async def process_location_update(
        self,
        driver_id: str,
        shift_id: str,
        lat: float,
        lng: float,
        speed: float = 0.0,
        heading: float = 0.0,
        accuracy: float = 0.0,
    ) -> List[str]:
        """
        Process a new GPS location ping and emit operational events.
        Possible events:
          - DRIVER_ARRIVED: within 100m of delivery dropoff
          - DRIVER_MOVING: speed > 5 km/h
          - DRIVER_STOPPED: speed <= 1 km/h
          - DRIVER_IDLE: stationary for > 5 minutes
        """
        from app.db.queries import (
            get_next_pending_delivery,
            mark_delivery_status,
            create_delivery_event,
            get_recent_location_pings,
            is_valid_uuid,
        )

        events: List[str] = []

        # 1. Movement State
        if speed > 5.0:
            events.append("DRIVER_MOVING")
        elif speed <= 1.0:
            events.append("DRIVER_STOPPED")

            # Check if stationary across recent pings
            if is_valid_uuid(driver_id):
                try:
                    pings = await get_recent_location_pings(driver_id, limit=5)
                    if len(pings) >= 3:
                        stationary_count = sum(1 for p in pings if float(p.get("speed", 0) or 0) <= 1.0)
                        if stationary_count == len(pings):
                            events.append("DRIVER_IDLE")
                except Exception as e:
                    logger.warning(f"[LocationService] Error checking idle pings: {e}")

        # 2. Geofencing & Arrival Detection
        if is_valid_uuid(shift_id) and is_valid_uuid(driver_id):
            try:
                delivery = await get_next_pending_delivery(shift_id, driver_id)
                if delivery:
                    dest_lat = delivery.get("dropoff_latitude") or delivery.get("latitude")
                    dest_lng = delivery.get("dropoff_longitude") or delivery.get("longitude")

                    if dest_lat is not None and dest_lng is not None:
                        dist = haversine_distance(lat, lng, float(dest_lat), float(dest_lng))
                        current_status = delivery.get("status", "pending")

                        if dist <= self.GEOFENCE_RADIUS_METERS and current_status in ["pending", "en_route"]:
                            events.append("DRIVER_ARRIVED")
                            delivery_id = delivery["id"]

                            # Auto-update status to arrived
                            await mark_delivery_status(delivery_id, "arrived")
                            await create_delivery_event(
                                delivery_id=delivery_id,
                                driver_id=driver_id,
                                event_type="DRIVER_ARRIVED",
                                status_before=current_status,
                                status_after="arrived",
                                latitude=lat,
                                longitude=lng,
                                metadata={
                                    "distance_meters": round(dist, 1),
                                    "auto_detected": True,
                                }
                            )
                            from app.services.order_queue_service import notify_queue_changed
                            await notify_queue_changed(shift_id, driver_id)
                            logger.info(
                                f"[LocationService] 🎯 Driver {driver_id} auto-arrived at delivery {delivery_id} ({round(dist, 1)}m away)"
                            )

            except Exception as e:
                logger.error(f"[LocationService] Geofence check failed: {e}")

        return events


location_service = LocationIntelligenceService()
