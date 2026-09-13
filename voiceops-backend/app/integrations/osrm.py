"""
OSRM (Open Source Routing Machine) directions. Free, no API key.

Defaults to the public demo server (`OSRM_BASE_URL`). Point that at a self-hosted `osrm-routed`
when the demo's rate limits or availability get in the way. The demo has no live traffic, so
durations are typical driving times.
"""
import httpx
from typing import List, Dict, Any, Optional
from app.config import settings


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
    Fetch driving directions from OSRM.

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
                print(f"OSRM routing error: {data.get('code')} {data.get('message', '')}")
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
        print(f"OSRM API error: {e}")
        return []
