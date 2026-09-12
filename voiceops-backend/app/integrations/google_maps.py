import httpx
from typing import List, Dict, Any, Optional, Tuple
from app.config import settings


_http_client: Optional[httpx.AsyncClient] = None


def _get_client() -> httpx.AsyncClient:
    global _http_client
    if _http_client is None or _http_client.is_closed:
        _http_client = httpx.AsyncClient(timeout=8.0)
    return _http_client


def encode_polyline(points: List[Tuple[float, float]]) -> str:
    """Encode (lat, lng) points in Google's encoded polyline format."""
    encoded = []
    prev_lat = prev_lng = 0
    for lat, lng in points:
        lat_e5, lng_e5 = round(lat * 1e5), round(lng * 1e5)
        for delta in (lat_e5 - prev_lat, lng_e5 - prev_lng):
            value = ~(delta << 1) if delta < 0 else delta << 1
            while value >= 0x20:
                encoded.append(chr((0x20 | (value & 0x1F)) + 63))
                value >>= 5
            encoded.append(chr(value + 63))
        prev_lat, prev_lng = lat_e5, lng_e5
    return "".join(encoded)


async def get_directions(
    origin_lat: float,
    origin_lng: float,
    dest_lat: float,
    dest_lng: float
) -> List[Dict[str, Any]]:
    """
    Fetch directions from Google Directions API.
    
    Args:
        origin_lat: Origin latitude
        origin_lng: Origin longitude
        dest_lat: Destination latitude
        dest_lng: Destination longitude
        
    Returns:
        List of route dicts with distance, duration, summary
    """
    if not settings.google_maps_api_key:
        # Return mock data if no API key. The polyline is a real (straight-line) encoding so the
        # in-app map can still draw it.
        return [
            {
                "summary": "Mock Route",
                "distance": 5000,  # meters
                "duration": 900,   # seconds
                "polyline": encode_polyline([(origin_lat, origin_lng), (dest_lat, dest_lng)])
            }
        ]
    
    url = "https://maps.googleapis.com/maps/api/directions/json"
    
    params = {
        "origin": f"{origin_lat},{origin_lng}",
        "destination": f"{dest_lat},{dest_lng}",
        "departure_time": "now",
        "traffic_model": "best_guess",
        "alternatives": "true",
        "key": settings.google_maps_api_key
    }
    
    try:
        client = _get_client()
        response = await client.get(url, params=params)
        response.raise_for_status()
        data = response.json()
        if data.get("status") != "OK":

            return []
        
        routes = []
        for route in data.get("routes", []):
            leg = route.get("legs", [{}])[0]
            routes.append({
                "summary": route.get("summary", "Route"),
                "distance": leg.get("distance", {}).get("value", 0),
                "duration": leg.get("duration", {}).get("value", 0),
                "polyline": route.get("overview_polyline", {}).get("points", "")
            })
        
        return routes

            
    except Exception as e:
        print(f"Google Maps API error: {e}")
        return []
