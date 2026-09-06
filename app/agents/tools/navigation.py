from typing import Dict, Any
from app.db.queries import get_next_pending_delivery, save_location_ping
from app.integrations.google_maps import get_directions


async def get_best_route(parameters: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Get the optimal current route to the next delivery with traffic data.
    """
    driver_id = context.get("driver_id")
    shift_id = context.get("shift_id")
    
    # Get next delivery
    delivery = await get_next_pending_delivery(shift_id, driver_id)
    if not delivery:
        return {"error": "No pending delivery found"}
    
    # Get driver's latest location
    # In production, query location_pings table for latest ping
    # For now, use a placeholder or require lat/lng in parameters
    origin_lat = parameters.get("origin_lat", 6.5244)  # Default: Lagos
    origin_lng = parameters.get("origin_lng", 3.3792)
    
    dest_lat = delivery.get("latitude")
    dest_lng = delivery.get("longitude")
    
    if not dest_lat or not dest_lng:
        return {"error": "Delivery coordinates not available"}
    
    try:
        routes = await get_directions(origin_lat, origin_lng, dest_lat, dest_lng)
        
        if not routes:
            return {"error": "Could not fetch route data"}
        
        # Sort by duration and get best route
        best_route = min(routes, key=lambda r: r.get("duration", float('inf')))
        
        # Check if there's a faster alternative
        has_faster_route = len(routes) > 1
        time_saved = 0
        if has_faster_route:
            second_best = sorted(routes, key=lambda r: r.get("duration", float('inf')))[1]
            time_saved = second_best.get("duration", 0) - best_route.get("duration", 0)
        
        return {
            "best_route": {
                "summary": best_route.get("summary", "Route"),
                "distance_km": best_route.get("distance", 0) / 1000,
                "duration_mins": best_route.get("duration", 0) / 60
            },
            "time_saved_mins": time_saved / 60 if time_saved > 0 else 0,
            "has_faster_route": has_faster_route,
            "destination": delivery.get("address")
        }
    except Exception as e:
        return {"error": str(e)}


async def start_navigation(parameters: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Open Google Maps navigation to the next delivery.
    Returns a navigation URL for the Flutter app to open.
    """
    driver_id = context.get("driver_id")
    shift_id = context.get("shift_id")
    
    # Get next delivery
    delivery = await get_next_pending_delivery(shift_id, driver_id)
    if not delivery:
        return {"error": "No pending delivery found"}
    
    dest_lat = delivery.get("latitude")
    dest_lng = delivery.get("longitude")
    address = delivery.get("address")
    
    if not dest_lat or not dest_lng:
        return {"error": "Delivery coordinates not available"}
    
    # Build Google Maps deeplink
    navigation_url = f"https://www.google.com/maps/dir/?api=1&destination={dest_lat},{dest_lng}&travelmode=driving"
    
    return {
        "action": "open_navigation",
        "navigation_url": navigation_url,
        "address": address,
        "latitude": dest_lat,
        "longitude": dest_lng
    }
