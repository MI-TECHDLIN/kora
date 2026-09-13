"""
OSRM (Open Source Routing Machine) Integration
Provides turn-by-turn driving directions, route geometry, distance, and duration.

`get_directions` backs the get_best_route / start_navigation tools (all routes, raw metres and
seconds, encoded polylines for the in-app map). `osrm_client` backs routing_service.
"""
import logging
from typing import Dict, Any, List, Tuple, Optional
import httpx
from app.config import settings

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
    dest_lng: float
) -> List[Dict[str, Any]]:
    """
    Fetch driving directions from OSRM (`OSRM_BASE_URL`, the public demo by default).

    Returns:
        List of route dicts, fastest first: {summary, distance (metres), duration (seconds),
        polyline (Google encoded polyline, precision 5)}. Empty when there is no route or
        OSRM can't be reached.
    """
    # OSRM takes coordinates as lng,lat
    coordinates = f"{origin_lng},{origin_lat};{dest_lng},{dest_lat}"
    url = f"{settings.osrm_base_url.rstrip('/')}/route/v1/driving/{coordinates}"

    params = {
        "alternatives": "true",
        "overview": "full",
        "geometries": "polyline",
        # A leg's summary (its main road names) is only filled in when steps are requested
        "steps": "true",
    }

    try:
        client = _get_client()
        response = await client.get(url, params=params)
        # OSRM reports a failed lookup (NoRoute, NoSegment) as HTTP 400 with a JSON `code`
        data = response.json()
        if data.get("code") != "Ok":
            if data.get("code") != "NoRoute":
                logger.warning(f"[OSRM] Routing error: {data.get('code')} {data.get('message', '')}")
            return []

        routes = []
        for route in data.get("routes", []):
            leg = route.get("legs", [{}])[0]
            routes.append({
                "summary": leg.get("summary") or "Route",
                "distance": round(route.get("distance", 0)),
                "duration": round(route.get("duration", 0)),
                "polyline": route.get("geometry", "")
            })

        return routes

    except Exception as e:
        logger.warning(f"[OSRM] Request failed: {e}")
        return []


class OSRMClient:
    BASE_URL = "http://router.project-osrm.org"

    async def get_route(
        self,
        origin: Tuple[float, float],
        destination: Tuple[float, float],
        overview: str = "simplified",
        steps: bool = True,
    ) -> Optional[Dict[str, Any]]:
        """
        Calculate route between origin (lat, lng) and destination (lat, lng).
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
                        duration_s = primary_route.get("duration", 0.0)

                        step_list = []
                        for leg in primary_route.get("legs", []):
                            for step in leg.get("steps", []):
                                step_name = step.get("name", "")
                                instruction = step.get("maneuver", {}).get("type", "continue")
                                step_list.append(f"{instruction}: {step_name}" if step_name else instruction)

                        return {
                            "success": True,
                            "provider": "osrm",
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
