"""
Navigation tools for VoiceOps agent.
Tools: get_best_route, start_navigation, accept_reroute
Platform: OSRM primary (routing_service), in-app navigation (no external deeplinks)
"""
import logging
from typing import Dict, Any, Optional
from app.db.queries import (
    get_delivery_by_id,
    get_driver_by_id,
    get_recent_location_pings,
)

logger = logging.getLogger(__name__)

# Screen options for show_screen tool
APP_SCREENS = ["map", "settings", "summary", "voice"]

# Helper functions for WebSocket integration
def stop_from_delivery(delivery: Dict[str, Any]) -> Dict[str, Any]:
    """Convert delivery dict to stop format for map display."""
    return {
        "delivery_id": delivery.get("id"),
        "sequence": delivery.get("sequence_order"),
        "recipient_name": delivery.get("recipient_name", "Customer"),
        "address": delivery.get("address", ""),
        "latitude": delivery.get("latitude"),
        "longitude": delivery.get("longitude"),
    }

def resolve_stop(delivery_id: Optional[str], context: dict) -> Optional[Dict[str, Any]]:
    """Resolve stop information from delivery ID or context."""
    if delivery_id:
        try:
            delivery = get_delivery_by_id(delivery_id)
            if delivery:
                return stop_from_delivery(delivery)
        except Exception as e:
            logger.warning(f"[Navigation] Failed to resolve stop {delivery_id}: {e}")
    
    # Fallback to current delivery from context
    current = context.get("current_delivery")
    if current:
        return stop_from_delivery(current)
    
    return None

def route_fields(route: Dict[str, Any]) -> Dict[str, Any]:
    """Extract standard route fields from routing service response."""
    return {
        "polyline": route.get("geometry", ""),
        "summary": route.get("summary", "Route"),
        "distance_km": route.get("distance_km", 0),
        "duration_mins": route.get("duration_mins", 0),
        "duration_text": route.get("duration_text", "0 mins"),
    }

def fastest_route(origin: tuple, destination: tuple) -> Dict[str, Any]:
    """Get the fastest route between two points."""
    from app.services.routing_service import routing_service
    import asyncio
    
    try:
        route = asyncio.run(routing_service.calculate_route(origin, destination))
        return route_fields(route)
    except Exception as e:
        logger.warning(f"[Navigation] Failed to get fastest route: {e}")
        return route_fields({})

def routes_to_stop(stop: Dict[str, Any], route: Dict[str, Any]) -> Dict[str, Any]:
    """Combine stop and route information for map display."""
    return {
        **stop,
        **route_fields(route),
    }


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
    Get the best route with traffic information via the routing service
    (OSRM primary, Google Directions as fallback only if OSRM is unreachable).
    Trigger phrases: "best route", "any traffic", "check my route", "faster way"
    """
    try:
        stop = resolve_stop(parameters.get("delivery_id"), context)
        routes = await routes_to_stop(stop, context)

        if not routes:
            return {
                "success": True,
                "has_faster_route": False,
                "best_route": {"summary": "Current route", "duration_mins": 14},
                "time_saved_mins": 0,
                "destination_address": stop["address"],
                "all_routes": [],
            }

        best = fastest_route(routes)
        time_saved = (routes[0]["duration"] - best["duration"]) / 60

        return {
            "success": True,
            "best_route": {
                "summary": best.get("summary") or "Route",
                "distance_km": round(best["distance"] / 1000, 1),
                "duration_mins": int(best["duration"] / 60),
                "duration_text": f"{int(best['duration'] / 60)} mins",
            },
            "time_saved_mins": round(time_saved, 1),
            "has_faster_route": time_saved > 1,
            "all_routes": routes,
            "destination_address": stop["address"],
        }
    except Exception as e:
        return {"success": False, "error": str(e)}


async def start_navigation(parameters: dict, context: dict) -> dict:
    """
    Start navigation to delivery location via the routing service.
    Platform: In-app navigation (Flutter map), no external deeplinks
    Trigger phrases: "navigate", "take me there", "get directions"
    """
    try:
        delivery_id = parameters.get("delivery_id")
        dest_lat, dest_lng, address, origin_lat, origin_lng = await _resolve_destination_and_origin(delivery_id, context)

        from app.services.routing_service import routing_service
        route = await routing_service.calculate_route((origin_lat, origin_lng), (dest_lat, dest_lng))

        stop = resolve_stop(delivery_id, context)
        route_with_stop = routes_to_stop(stop or {}, route)

        return {
            "success": True,
            "action": "start_navigation",
            "route": route_with_stop,
            "destination_address": address,
            "message": f"Starting navigation to {address}. Estimated time: {route.get('duration_text', '12 mins')}."
        }
    except Exception as e:
        return {"success": False, "error": str(e)}


async def show_screen(parameters: dict, context: dict) -> dict:
    """Open one of the app's main screens via the existing screen event."""
    screen = parameters.get("screen")
    if screen not in APP_SCREENS:
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
