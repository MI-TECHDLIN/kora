"""
Navigation tools for VoiceOps agent.
Tools: get_best_route, start_navigation, accept_reroute
Platform: Google Directions API + Google Maps deeplink
"""
import logging
from typing import Dict, Any, Optional
from app.integrations.google_maps import get_directions
from app.db.queries import (
    get_delivery_by_id,
    get_driver_by_id,
    get_recent_location_pings,
)

logger = logging.getLogger(__name__)


async def _resolve_destination_and_origin(
    delivery_id: Optional[str],
    context: dict
) -> tuple[float, float, str, float, float]:
    """
    Helper to resolve destination (lat, lng, address) and origin (lat, lng).
    Uses Supabase deliveries & drivers tables with context fallback.
    """
    dest_lat = None
    dest_lng = None
    destination_address = "Destination"

    # 1. Resolve Delivery
    current_delivery = context.get("current_delivery") or {}
    resolved_del_id = delivery_id or current_delivery.get("id")

    delivery_row = None
    if resolved_del_id:
        try:
            delivery_row = await get_delivery_by_id(resolved_del_id)
        except Exception as e:
            logger.warning(f"[Navigation] Failed to fetch delivery {resolved_del_id}: {e}")

    if delivery_row:
        dest_lat = delivery_row.get("dropoff_latitude") or delivery_row.get("latitude")
        dest_lng = delivery_row.get("dropoff_longitude") or delivery_row.get("longitude")
        destination_address = delivery_row.get("address") or delivery_row.get("pickup_address") or "Customer Address"
    elif current_delivery:
        dest_lat = current_delivery.get("latitude")
        dest_lng = current_delivery.get("longitude")
        destination_address = current_delivery.get("address") or "Customer Address"

    # Default destination fallback if not found
    if dest_lat is None or dest_lng is None:
        dest_lat, dest_lng = 6.4286, 3.4108
        destination_address = destination_address or "22 Victoria Island Drive"

    # 2. Resolve Driver Origin
    origin_lat = context.get("current_latitude")
    origin_lng = context.get("current_longitude")

    driver_id = context.get("driver_id")
    if (origin_lat is None or origin_lng is None) and driver_id:
        # Check latest location ping
        try:
            pings = await get_recent_location_pings(driver_id, limit=1)
            if pings:
                origin_lat = pings[0].get("latitude")
                origin_lng = pings[0].get("longitude")
        except Exception as e:
            logger.warning(f"[Navigation] Failed to fetch pings for driver {driver_id}: {e}")

    if (origin_lat is None or origin_lng is None) and driver_id:
        # Check driver current coordinates in DB
        try:
            driver = await get_driver_by_id(driver_id)
            if driver:
                origin_lat = driver.get("current_latitude")
                origin_lng = driver.get("current_longitude")
        except Exception as e:
            logger.warning(f"[Navigation] Failed to fetch driver {driver_id}: {e}")

    # Fallback origin coordinates if driver location unknown
    if origin_lat is None or origin_lng is None:
        origin_lat, origin_lng = 6.4400, 3.3900

    return float(dest_lat), float(dest_lng), str(destination_address), float(origin_lat), float(origin_lng)


async def get_best_route(parameters: dict, context: dict) -> dict:
    """
    Get the best route with traffic information using Google Directions API.
    Trigger phrases: "best route", "any traffic", "check my route", "faster way"
    """
    try:
        delivery_id = parameters.get("delivery_id")
        dest_lat, dest_lng, destination_address, origin_lat, origin_lng = await _resolve_destination_and_origin(
            delivery_id, context
        )

        from app.services.routing_service import routing_service
        route = await routing_service.calculate_route((origin_lat, origin_lng), (dest_lat, dest_lng))

        return {
            "success": True,
            "best_route": {
                "summary": route.get("summary", "Fastest Route"),
                "distance_km": route.get("distance_km", 3.5),
                "duration_mins": route.get("duration_mins", 12.0),
                "duration_text": route.get("duration_text", "12 mins"),
                "provider": route.get("provider", "routing_service"),
            },
            "time_saved_mins": 0,
            "has_faster_route": False,
            "steps": route.get("steps", []),
            "destination_address": destination_address,
        }
    except Exception as e:
        logger.error(f"[Tool:get_best_route] {e}")
        return {
            "success": False,
            "error": str(e)
        }


async def start_navigation(parameters: dict, context: dict) -> dict:
    """
    Start navigation to delivery location using Google Maps.
    Platform: Google Maps deeplink (opened by Flutter via url_launcher)
    Trigger phrases: "navigate", "take me there", "get directions"
    """
    try:
        delivery_id = parameters.get("delivery_id")
        dest_lat, dest_lng, address, _, _ = await _resolve_destination_and_origin(delivery_id, context)

        navigation_url = f"https://www.google.com/maps/dir/?api=1&destination={dest_lat},{dest_lng}&travelmode=driving"

        return {
            "success": True,
            "action": "open_navigation",
            "navigation_url": navigation_url,
            "address": address,
            "latitude": dest_lat,
            "longitude": dest_lng,
            "message": f"Navigation opening to {address}."
        }
    except Exception as e:
        logger.error(f"[Tool:start_navigation] {e}")
        return {
            "success": False,
            "error": str(e)
        }


async def accept_reroute(parameters: dict, context: dict) -> dict:
    """
    Accept a suggested reroute and set it as the active navigation route.
    Trigger phrases: "yes take that route", "accept reroute", "use the alternate route"
    
    Parameters:
        - eta_minutes: int (optional) - ETA of the suggested route
        - geometry: str (optional) - Route geometry/polyline
        - delivery_id: str (optional) - Delivery ID for the route
    """
    try:
        delivery_id = parameters.get("delivery_id")
        eta_minutes = parameters.get("eta_minutes")
        geometry = parameters.get("geometry")
        
        # Resolve destination and origin
        dest_lat, dest_lng, destination_address, origin_lat, origin_lng = await _resolve_destination_and_origin(
            delivery_id, context
        )
        
        # If geometry is provided, use it; otherwise calculate a fresh route
        if geometry:
            route_info = {
                "summary": "Suggested Reroute",
                "distance_km": 0.0,  # Would need to be calculated from geometry
                "duration_mins": eta_minutes or 12.0,
                "duration_text": f"{eta_minutes or 12} mins",
                "provider": "traffic_reroute",
                "geometry": geometry,
            }
        else:
            # Fallback to routing service if no geometry provided
            from app.services.routing_service import routing_service
            route = await routing_service.calculate_route((origin_lat, origin_lng), (dest_lat, dest_lng))
            route_info = {
                "summary": route.get("summary", "Reroute"),
                "distance_km": route.get("distance_km", 3.5),
                "duration_mins": route.get("duration_mins", 12.0),
                "duration_text": route.get("duration_text", "12 mins"),
                "provider": route.get("provider", "routing_service"),
                "geometry": route.get("geometry", ""),
            }
        
        # In a real implementation, this would push the route to the Flutter app
        # For now, we return the route information for the agent to communicate
        return {
            "success": True,
            "action": "reroute_accepted",
            "route": route_info,
            "message": f"Rerouting to {destination_address}. Estimated time: {route_info['duration_text']}.",
            "destination_address": destination_address,
        }
    except Exception as e:
        logger.error(f"[Tool:accept_reroute] {e}")
        return {
            "success": False,
            "error": str(e)
        }