"""
Multi-Provider Routing Service
Abstracts route calculations across OSRM (primary open-source provider),
Google Directions API (high-accuracy fallback), and Haversine heuristic (offline fallback).
"""
import logging
from abc import ABC, abstractmethod
from typing import Dict, Any, Optional, Tuple
from app.integrations.osrm import osrm_client
from app.integrations.google_maps import get_directions
from app.services.location_service import haversine_distance
from app.services.vehicle_modes import (
    duration_for_mode,
    resolve_vehicle_mode,
    straight_line_speed_kmh,
)

logger = logging.getLogger(__name__)


class RoutingProvider(ABC):
    @abstractmethod
    async def calculate_route(
        self,
        origin: Tuple[float, float],
        destination: Tuple[float, float],
        vehicle_type: Optional[str] = None,
    ) -> Dict[str, Any]:
        pass


class OSRMProvider(RoutingProvider):
    async def calculate_route(
        self,
        origin: Tuple[float, float],
        destination: Tuple[float, float],
        vehicle_type: Optional[str] = None,
    ) -> Dict[str, Any]:
        result = await osrm_client.get_route(origin, destination, vehicle_type=vehicle_type)
        if result and result.get("success"):
            return result
        raise RuntimeError("OSRM routing unavailable")


class GoogleMapsProvider(RoutingProvider):
    async def calculate_route(
        self,
        origin: Tuple[float, float],
        destination: Tuple[float, float],
        vehicle_type: Optional[str] = None,
    ) -> Dict[str, Any]:
        routes = await get_directions(origin[0], origin[1], destination[0], destination[1])
        if routes:
            mode = resolve_vehicle_mode(vehicle_type)
            best = min(routes, key=lambda r: r.get("duration", 999999))
            dist_km = round(best.get("distance", 0) / 1000.0, 2)
            duration_s = duration_for_mode(mode, best.get("distance", 0), best.get("duration", 0))
            duration_mins = round(duration_s / 60.0, 1)
            return {
                "success": True,
                "provider": "google_maps",
                "vehicle_mode": mode.value,
                "summary": best.get("summary", "Fastest route"),
                "distance_km": dist_km,
                "duration_mins": duration_mins,
                "duration_text": f"{int(duration_mins)} mins",
                "geometry": "",
                "steps": [],
            }
        raise RuntimeError("Google Directions returned no routes")


class FallbackHaversineProvider(RoutingProvider):
    async def calculate_route(
        self,
        origin: Tuple[float, float],
        destination: Tuple[float, float],
        vehicle_type: Optional[str] = None,
    ) -> Dict[str, Any]:
        dist_m = haversine_distance(origin[0], origin[1], destination[0], destination[1])
        dist_km = round((dist_m / 1000.0) * 1.35, 2)  # Urban correction
        mode = resolve_vehicle_mode(vehicle_type)
        speed_kmh = straight_line_speed_kmh(mode, 25.0)  # 25 km/h urban car speed
        duration_mins = max(1, round((dist_km / speed_kmh) * 60.0, 1))
        return {
            "success": True,
            "provider": "haversine_fallback",
            "vehicle_mode": mode.value,
            "summary": "Direct route estimation",
            "distance_km": dist_km,
            "duration_mins": duration_mins,
            "duration_text": f"{int(duration_mins)} mins",
            "geometry": "",
            "steps": [],
        }


class RoutingService:
    def __init__(self):
        self.osrm = OSRMProvider()
        self.google_maps = GoogleMapsProvider()
        self.fallback = FallbackHaversineProvider()

    async def calculate_route(
        self,
        origin: Tuple[float, float],
        destination: Tuple[float, float],
        vehicle_type: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Calculate route trying:
        1. OSRM (fast, free, open-source)
        2. Google Maps API (traffic-aware fallback)
        3. Haversine Heuristic (bulletproof fallback)
        """
        try:
            return await self.osrm.calculate_route(origin, destination, vehicle_type)
        except Exception as e1:
            logger.info(f"[RoutingService] OSRM failed ({e1}), falling back to Google Maps...")

        try:
            return await self.google_maps.calculate_route(origin, destination, vehicle_type)
        except Exception as e2:
            logger.info(f"[RoutingService] Google Maps failed ({e2}), falling back to Heuristic...")

        return await self.fallback.calculate_route(origin, destination, vehicle_type)


routing_service = RoutingService()
