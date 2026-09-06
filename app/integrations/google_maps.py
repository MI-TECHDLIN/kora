import httpx
from typing import List, Dict, Any, Optional
from app.config import settings


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
        # Return mock data if no API key
        return [
            {
                "summary": "Mock Route",
                "distance": 5000,  # meters
                "duration": 900,   # seconds
                "polyline": "mock_polyline_data"
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
        async with httpx.AsyncClient() as client:
            response = await client.get(url, params=params, timeout=10.0)
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
