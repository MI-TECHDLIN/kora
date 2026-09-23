"""
OSRM (Open Source Routing Machine) Integration
Provides route geometry, distance and duration for the in-app map and voice tools.

Geometry and distance always come from the OSRM `driving` profile (the public
demo server serves nothing else). Duration is then derived per vehicle mode by
`app.services.vehicle_modes`, so walking and cycling ETAs are approximate and
follow driving-network roads until a self-hosted OSRM with real profiles exists.

`get_directions` backs the voice navigation tools with route alternatives in
raw metres/seconds plus encoded polylines for the in-app map. `osrm_client`
backs the broader routing service.
"""
import logging
from typing import Dict, Any, List, Tuple, Optional
import httpx

from app.config import settings
from app.services.vehicle_modes import (
    apply_mode_to_routes,
    duration_for_mode,
    resolve_vehicle_mode,
)

logger = logging.getLogger(__name__)

_http_client: Optional[httpx.AsyncClient] = None


def _get_client() -> httpx.AsyncClient:
    global _http_client
    if _http_client is None or _http_client.is_closed:
        _http_client = httpx.AsyncClient(timeout=8.0)
    return _http_client


async def get_directions(
    origin_lat: float,
    origin_lng: float,
    dest_lat: float,
    dest_lng: float,
    vehicle_type: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """
    Fetch route alternatives from OSRM, timed for the driver's vehicle.

    Returns fastest-first route dicts: `summary`, `distance` in metres,
    `duration` in seconds for `vehicle_type` (car when unset), `driving_duration`
    (the raw OSRM seconds), `vehicle_mode`, and `polyline` with Google
    precision 5 encoding. Empty means OSRM could not produce a route.
    """
    coordinates = f"{origin_lng},{origin_lat};{dest_lng},{dest_lat}"
    url = f"{settings.osrm_base_url.rstrip('/')}/route/v1/driving/{coordinates}"
    params = {
        "alternatives": "true",
        "overview": "full",
        "geometries": "polyline",
        "steps": "true",
    }

    try:
        response = await _get_client().get(url, params=params)
        data = response.json()
        if data.get("code") != "Ok":
            if data.get("code") != "NoRoute":
                logger.warning(
                    "[OSRM] Routing error: %s %s",
                    data.get("code"),
                    data.get("message", ""),
                )
            return []

        routes = []
        for route in data.get("routes", []):
            leg = (route.get("legs") or [{}])[0]
            routes.append(
                {
                    "summary": leg.get("summary") or "Route",
                    "distance": round(route.get("distance", 0)),
                    "duration": round(route.get("duration", 0)),
                    "polyline": route.get("geometry", ""),
                }
            )
        return apply_mode_to_routes(routes, vehicle_type)
    except Exception as e:
        logger.warning("[OSRM] Request failed: %s", e)
        return []


class OSRMClient:
    BASE_URL = "https://router.project-osrm.org"

    async def get_route(
        self,
        origin: Tuple[float, float],
        destination: Tuple[float, float],
        overview: str = "simplified",
        steps: bool = True,
        vehicle_type: Optional[str] = None,
    ) -> Optional[Dict[str, Any]]:
        """
        Calculate route between origin (lat, lng) and destination (lat, lng),
        timed for `vehicle_type` (driving geometry and distance either way).
        Note: OSRM uses {longitude},{latitude} in its URL path format.
        """
        origin_lat, origin_lng = origin
        dest_lat, dest_lng = destination

        # OSRM path coordinate order is lng,lat
        coords = f"{origin_lng},{origin_lat};{dest_lng},{dest_lat}"
        url = f"{self.BASE_URL}/route/v1/driving/{coords}"
        params = {
            "overview": overview,
            "steps": "true" if steps else "false",
            "annotations": "false",
        }

        try:
            async with httpx.AsyncClient(timeout=4.0) as client:
                response = await client.get(url, params=params)
                if response.status_code == 200:
                    data = response.json()
                    routes = data.get("routes", [])
                    if routes:
                        primary_route = routes[0]
                        distance_m = primary_route.get("distance", 0.0)
                        mode = resolve_vehicle_mode(vehicle_type)
                        duration_s = duration_for_mode(
                            mode, distance_m, primary_route.get("duration", 0.0)
                        )

                        step_list = []
                        for leg in primary_route.get("legs", []):
                            for step in leg.get("steps", []):
                                step_name = step.get("name", "")
                                instruction = step.get("maneuver", {}).get("type", "continue")
                                step_list.append(f"{instruction}: {step_name}" if step_name else instruction)

                        return {
                            "success": True,
                            "provider": "osrm",
                            "vehicle_mode": mode.value,
                            "distance_km": round(distance_m / 1000.0, 2),
                            "duration_mins": round(duration_s / 60.0, 1),
                            "duration_text": f"{int(duration_s / 60.0)} mins",
                            "geometry": primary_route.get("geometry", ""),
                            "steps": step_list,
                        }

                logger.warning(f"[OSRM] Non-200 response: {response.status_code}")
                return None
        except Exception as e:
            logger.warning(f"[OSRM] Request failed ({e}). Fallback provider will be used.")
            return None


osrm_client = OSRMClient()
