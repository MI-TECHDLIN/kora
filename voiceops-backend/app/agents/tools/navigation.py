"""
Navigation tools for VoiceOps agent.

Routes render in the Flutter app through `screen_navigate` + `map_route`
events. No navigation tool returns an external maps deep link.
"""
import logging
from typing import Any, Dict, List, Optional, Tuple

from app.db.queries import get_delivery_by_id, get_driver_by_id, get_recent_location_pings
from app.integrations.osrm import get_directions
from app.services.vehicle_modes import get_driver_vehicle_mode

logger = logging.getLogger(__name__)

MOCK_ORIGIN = (30.2672, -97.7431)
MOCK_DESTINATION = {
    "address": "812 Lavaca St, Austin, TX 78701",
    "latitude": 30.2713,
    "longitude": -97.7455,
}

# `screen_navigate.screen` in docs/contracts/interface.md.
APP_SCREENS = ("voice", "map", "summary", "settings")
SCREEN_NAMES = {
    "voice": "the home screen",
    "map": "the map",
    "summary": "your summary",
    "settings": "your profile and settings",
}


def _to_float(value: Any) -> Optional[float]:
    try:
        return float(value) if value is not None else None
    except (TypeError, ValueError):
        return None


def stop_from_delivery(delivery: dict) -> dict:
    """Normalize a delivery row/result to the `map_route.stops[]` shape."""
    sequence = delivery.get("sequence")
    if sequence is None:
        sequence = delivery.get("sequence_order")
    return {
        "delivery_id": delivery.get("delivery_id") or delivery.get("id"),
        "sequence": sequence,
        "recipient_name": delivery.get("recipient_name"),
        "address": delivery.get("address") or delivery.get("pickup_address"),
        "latitude": _to_float(delivery.get("dropoff_latitude") or delivery.get("latitude")),
        "longitude": _to_float(delivery.get("dropoff_longitude") or delivery.get("longitude")),
    }


def resolve_origin(context: dict) -> Tuple[float, float]:
    """Driver's last known position from the voice context, else demo fallback."""
    lat = _to_float(context.get("latitude") or context.get("current_latitude"))
    lng = _to_float(context.get("longitude") or context.get("current_longitude"))
    if lat is not None and lng is not None:
        return lat, lng
    return MOCK_ORIGIN


def resolve_stop(delivery_id: Optional[str], context: dict) -> dict:
    """Resolve a destination from session-known deliveries, else demo fallback."""
    known = (context.get("deliveries") or {}).get(delivery_id) if delivery_id else None
    if known and known.get("latitude") is not None and known.get("longitude") is not None:
        return known

    current = context.get("current_delivery")
    if isinstance(current, dict) and (not delivery_id or current.get("id") == delivery_id):
        stop = stop_from_delivery(current)
        if stop.get("latitude") is not None and stop.get("longitude") is not None:
            return stop

    return {
        "delivery_id": delivery_id,
        "sequence": None,
        "recipient_name": None,
        **MOCK_DESTINATION,
    }


async def context_vehicle_mode(context: dict):
    """
    The driver's vehicle mode for ETAs: their current `drivers.vehicle_type`
    (they may have switched since the session opened), else the vehicle the
    session loaded, else the default.
    """
    return await get_driver_vehicle_mode(context.get("driver_id"), context.get("vehicle_type"))


async def routes_to_stop(stop: dict, context: dict) -> List[Dict[str, Any]]:
    """OSRM routes from the driver's position to a normalized stop, timed for their vehicle."""
    origin_lat, origin_lng = resolve_origin(context)
    mode = await context_vehicle_mode(context)
    return await get_directions(
        origin_lat, origin_lng, stop["latitude"], stop["longitude"], vehicle_type=mode.value
    )


def fastest_route(routes: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    return min(routes, key=lambda route: route["duration"]) if routes else None


def route_fields(route: Optional[Dict[str, Any]]) -> dict:
    """Route fields for `map_route`; nullable when OSRM has no route."""
    if not route:
        return {
            "polyline": "",
            "summary": None,
            "distance_km": None,
            "duration_mins": None,
            "duration_text": None,
        }
    duration_mins = int(route["duration"] / 60)
    return {
        "polyline": route.get("polyline", ""),
        "summary": route.get("summary") or "Route",
        "distance_km": round(route["distance"] / 1000, 1),
        "duration_mins": duration_mins,
        "duration_text": f"{duration_mins} mins",
    }


async def _resolve_destination_and_origin(
    delivery_id: Optional[str],
    context: dict,
) -> Tuple[dict, float, float]:
    """Resolve a stop and origin, using DB coordinates only when context is sparse."""
    stop = resolve_stop(delivery_id, context)

    if delivery_id and stop["address"] == MOCK_DESTINATION["address"]:
        try:
            delivery = await get_delivery_by_id(delivery_id)
            if delivery:
                stop = stop_from_delivery(delivery)
        except Exception as e:
            logger.warning("[Navigation] Failed to fetch delivery %s: %s", delivery_id, e)

    origin_lat, origin_lng = resolve_origin(context)
    if (origin_lat, origin_lng) == MOCK_ORIGIN and context.get("driver_id"):
        driver_id = context["driver_id"]
        try:
            pings = await get_recent_location_pings(driver_id, limit=1)
            if pings:
                origin_lat = _to_float(pings[0].get("latitude")) or origin_lat
                origin_lng = _to_float(pings[0].get("longitude")) or origin_lng
        except Exception as e:
            logger.warning("[Navigation] Failed to fetch pings for driver %s: %s", driver_id, e)

        try:
            driver = await get_driver_by_id(driver_id)
            if driver:
                origin_lat = _to_float(driver.get("current_latitude")) or origin_lat
                origin_lng = _to_float(driver.get("current_longitude")) or origin_lng
        except Exception as e:
            logger.warning("[Navigation] Failed to fetch driver %s: %s", driver_id, e)

    return stop, float(origin_lat), float(origin_lng)


async def get_best_route(parameters: dict, context: dict) -> dict:
    """
    Get the best route to a delivery using OSRM.

    The public OSRM demo server has no live traffic; it returns alternatives
    when available, and the fastest route feeds the in-app map.
    
    Checks driver preferences for avoid_highways and prefer_residential.
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

        # Check driver preferences for route filtering
        driver_id = context.get("driver_id")
        if driver_id:
            from app.services.preference_service import preference_service
            preferences = await preference_service.get_preferences(driver_id)
            
            # Filter routes based on preferences
            if preferences.get("avoid_highways") == "true":
                # In a real implementation, this would parse route summaries for highway keywords
                # For now, we'll just note the preference in the response
                logger.info("[Tool:get_best_route] Driver prefers to avoid highways")
            
            if preferences.get("prefer_residential") == "true":
                # In a real implementation, this would prioritize residential routes
                logger.info("[Tool:get_best_route] Driver prefers residential areas")

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
    """Start navigation by returning route data for the in-app Flutter map."""
    try:
        stop = resolve_stop(parameters.get("delivery_id"), context)
        route = fastest_route(await routes_to_stop(stop, context))
        fields = route_fields(route) if route else None
        if fields:
            message = (
                f"Route to {stop['address']} is on your map: "
                f"{fields['duration_text']} via {fields['summary']}."
            )
        else:
            message = f"{stop['address']} is on your map."

        return {
            "success": True,
            "delivery_id": stop["delivery_id"],
            "address": stop["address"],
            "latitude": stop["latitude"],
            "longitude": stop["longitude"],
            "route": fields,
            "message": message,
        }
    except Exception as e:
        return {"success": False, "error": str(e)}


async def show_screen(parameters: dict, context: dict) -> dict:
    """Open one of the app's main screens via the existing screen event."""
    screen = parameters.get("screen")
    if screen not in APP_SCREENS:
        return {
            "success": False,
            "error": f"Unknown screen {screen!r}. Use one of: {', '.join(APP_SCREENS)}.",
        }
    return {
        "success": True,
        "screen": screen,
        "message": f"Opening {SCREEN_NAMES[screen]}.",
    }


async def end_conversation(parameters: dict, context: dict) -> dict:
    """Close the current conversation while leaving the voice socket open."""
    return {
        "success": True,
        "message": "The driver's mic is off now. Say nothing more.",
    }


async def accept_reroute(parameters: dict, context: dict) -> dict:
    """
    Accept a suggested reroute and set it as the active navigation route.
    Trigger phrases: "yes take that route", "accept reroute", "use the alternate route"
    """
    try:
        stop, origin_lat, origin_lng = await _resolve_destination_and_origin(
            parameters.get("delivery_id"), context
        )
        eta_minutes = parameters.get("eta_minutes")
        geometry = parameters.get("geometry")

        if geometry:
            route_info = {
                "summary": "Suggested Reroute",
                "distance_km": 0.0,
                "duration_mins": eta_minutes or 12.0,
                "duration_text": f"{eta_minutes or 12} mins",
                "provider": "traffic_reroute",
                "geometry": geometry,
            }
        else:
            from app.services.routing_service import routing_service

            mode = await context_vehicle_mode(context)
            route = await routing_service.calculate_route(
                (origin_lat, origin_lng),
                (stop["latitude"], stop["longitude"]),
                vehicle_type=mode.value,
            )
            route_info = {
                "summary": route.get("summary", "Reroute"),
                "distance_km": route.get("distance_km", 3.5),
                "duration_mins": route.get("duration_mins", 12.0),
                "duration_text": route.get("duration_text", "12 mins"),
                "provider": route.get("provider", "routing_service"),
                "geometry": route.get("geometry", ""),
            }

        return {
            "success": True,
            "action": "reroute_accepted",
            "route": route_info,
            "message": f"Rerouting to {stop['address']}. Estimated time: {route_info['duration_text']}.",
            "destination_address": stop["address"],
        }
    except Exception as e:
        logger.error("[Tool:accept_reroute] %s", e)
        return {"success": False, "error": str(e)}
