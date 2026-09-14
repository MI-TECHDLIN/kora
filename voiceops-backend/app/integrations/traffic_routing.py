"""
Traffic-Aware Routing Integration
Provides real-time traffic-aware ETA calculation using TomTom Routing API.
"""
import logging
from typing import Dict, Any, Tuple, Optional
import httpx
from app.config import settings

logger = logging.getLogger(__name__)


class TrafficRoutingClient:
    """
    TomTom Routing API client for traffic-aware ETA calculations.
    Uses TomTom's Routing API with traffic=true to get real-time traffic conditions.
    """
    
    BASE_URL = "https://api.tomtom.com/routing/1"
    
    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key or getattr(settings, 'tomtom_api_key', None)
        if not self.api_key:
            logger.warning("[TrafficRouting] No TomTom API key configured. Traffic-aware routing will be disabled.")
    
    async def get_traffic_aware_eta(
        self,
        origin: Tuple[float, float],
        destination: Tuple[float, float],
    ) -> Optional[Dict[str, Any]]:
        """
        Calculate traffic-aware ETA between origin (lat, lng) and destination (lat, lng).
        
        Returns:
            {
                "eta_minutes": int,
                "distance_km": float,
                "route_geometry": str,
                "provider": "tomtom",
                "traffic_delay_minutes": float,
                "free_flow_eta_minutes": int
            }
        or None if the API call fails.
        """
        if not self.api_key:
            logger.warning("[TrafficRouting] No API key available for traffic-aware routing")
            return None
        
        origin_lat, origin_lng = origin
        dest_lat, dest_lng = destination
        
        # TomTom API expects coordinates in lat,lng format
        url = f"{self.BASE_URL}/calculateRoute/{origin_lat},{origin_lng}:{dest_lat},{dest_lng}/json"
        params = {
            "key": self.api_key,
            "traffic": "true",  # Include traffic data
            "travelMode": "car",
            "routeType": "fastest",
            "computeTravelTimeFor": "all",
        }
        
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(url, params=params)
                if response.status_code == 200:
                    data = response.json()
                    routes = data.get("routes", [])
                    if routes:
                        primary_route = routes[0]
                        summary = primary_route.get("summary", {})
                        
                        # Extract traffic-aware duration
                        travel_time_seconds = summary.get("travelTimeInSeconds", 0)
                        traffic_delay_seconds = summary.get("trafficDelayInSeconds", 0)
                        free_flow_seconds = travel_time_seconds - traffic_delay_seconds
                        
                        distance_meters = summary.get("lengthInMeters", 0)
                        
                        # Extract route geometry (encoded polyline)
                        geometry = primary_route.get("legs", [{}])[0].get("points", [])
                        
                        return {
                            "success": True,
                            "provider": "tomtom",
                            "eta_minutes": int(travel_time_seconds / 60),
                            "distance_km": round(distance_meters / 1000.0, 2),
                            "traffic_delay_minutes": round(traffic_delay_seconds / 60, 1),
                            "free_flow_eta_minutes": int(free_flow_seconds / 60),
                            "geometry": str(geometry),  # Simplified geometry representation
                        }
                
                logger.warning(f"[TrafficRouting] Non-200 response: {response.status_code}")
                return None
        except httpx.TimeoutException:
            logger.warning("[TrafficRouting] Request timed out")
            return None
        except Exception as e:
            logger.warning(f"[TrafficRouting] Request failed ({e})")
            return None


# Global instance
traffic_routing_client = TrafficRoutingClient()