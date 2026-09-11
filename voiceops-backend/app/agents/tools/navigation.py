"""
Navigation tools for VoiceOps agent.
Tools: get_best_route, start_navigation
Platform: Google Directions API + Google Maps deeplink
"""
from typing import Dict, Any
import json
from app.integrations.google_maps import get_directions


async def get_best_route(parameters: dict, context: dict) -> dict:
    """
    Get the best route with traffic information.
    
    Platform: Google Directions API (departure_time=now, alternatives=true, traffic_model=best_guess)
    Trigger phrases: "best route", "any traffic", "check my route", "faster way"
    
    Input:
    {
        "delivery_id": "uuid"
    }
    
    Expected output:
    {
        "success": true,
        "best_route": {
            "summary": "Victoria Bridge",
            "distance_km": 3.2,
            "duration_mins": 11,
            "duration_text": "11 mins"
        },
        "time_saved_mins": 7,
        "has_faster_route": true,
        "all_routes": [...],
        "destination_address": "22 Victoria Island Drive"
    }
    """
    try:
        delivery_id = parameters.get("delivery_id")
        
        # TODO: Get origin and destination coordinates from Supabase
        # For now, use mock coordinates
        origin_lat, origin_lng = 6.44, 3.39  # Current location
        dest_lat, dest_lng = 6.4286, 3.4108  # Delivery location
        destination_address = "22 Victoria Island Drive"
        
        # Call Google Directions API
        routes = await get_directions(origin_lat, origin_lng, dest_lat, dest_lng)
        
        if not routes:
            return {
                "success": True,
                "has_faster_route": False,
                "best_route": {"summary": "Current route", "duration_mins": 14},
                "time_saved_mins": 0,
                "destination_address": destination_address
            }
        
        # Find best route (shortest duration)
        best_route = min(routes, key=lambda r: r["duration"])
        
        # Calculate time saved vs first route
        current_duration = routes[0]["duration"]
        best_duration = best_route["duration"]
        time_saved = (current_duration - best_duration) / 60  # convert to minutes
        
        return {
            "success": True,
            "best_route": {
                "summary": best_route["summary"],
                "distance_km": best_route["distance"] / 1000,
                "duration_mins": best_route["duration"] / 60,
                "duration_text": f"{int(best_route['duration'] / 60)} mins"
            },
            "time_saved_mins": round(time_saved, 1),
            "has_faster_route": time_saved > 1,
            "all_routes": routes,
            "destination_address": destination_address
        }
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }


async def start_navigation(parameters: dict, context: dict) -> dict:
    """
    Start navigation to delivery location using Google Maps.
    
    Platform: Google Maps deeplink (opened by Flutter via url_launcher)
    Trigger phrases: "navigate", "take me there", "get directions"
    
    Input:
    {
        "delivery_id": "uuid"
    }
    
    Expected output:
    {
        "success": true,
        "action": "open_navigation",
        "navigation_url": "https://www.google.com/maps/dir/?api=1&destination=6.4286,3.4108&travelmode=driving",
        "address": "22 Victoria Island Drive",
        "message": "Navigation opening to 22 Victoria Island Drive."
    }
    
    Flutter listens for action: "open_navigation" on the WebSocket and calls
    url_launcher to open Maps.
    """
    try:
        delivery_id = parameters.get("delivery_id")
        
        # TODO: Get delivery coordinates from Supabase
        # For now, use mock coordinates
        latitude = 6.4286
        longitude = 3.4108
        address = "22 Victoria Island Drive"
        
        navigation_url = f"https://www.google.com/maps/dir/?api=1&destination={latitude},{longitude}&travelmode=driving"
        
        return {
            "success": True,
            "action": "open_navigation",
            "navigation_url": navigation_url,
            "address": address,
            "message": f"Navigation opening to {address}."
        }
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }