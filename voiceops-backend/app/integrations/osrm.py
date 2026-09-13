"""
OSRM (Open Source Routing Machine) Integration
Provides turn-by-turn driving directions, route geometry, distance, and duration.
"""
import logging
from typing import Dict, Any, Tuple, Optional
import httpx

logger = logging.getLogger(__name__)


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
