"""
Navigation tools for VoiceOps agent.

Routes render in the Flutter app through `screen_navigate` + `map_route`
events. No navigation tool returns an external maps deep link.
"""
from typing import Any, Dict, List, Optional, Tuple

from app.integrations.osrm import get_directions


MOCK_ORIGIN = (6.44, 3.39)
MOCK_DESTINATION = {
    "address": "22 Victoria Island Drive",
    "latitude": 6.4286,
    "longitude": 3.4108,
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
        "address": delivery.get("address"),
        "latitude": _to_float(delivery.get("latitude")),
        "longitude": _to_float(delivery.get("longitude")),
    }


def resolve_origin(context: dict) -> Tuple[float, float]:
    """Driver's last known position from the voice context, else demo fallback."""
    lat = _to_float(context.get("latitude"))
    lng = _to_float(context.get("longitude"))
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


async def routes_to_stop(stop: dict, context: dict) -> List[Dict[str, Any]]:
    """OSRM routes from the driver's position to a normalized stop."""
    origin_lat, origin_lng = resolve_origin(context)
    return await get_directions(origin_lat, origin_lng, stop["latitude"], stop["longitude"])


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


async def get_best_route(parameters: dict, context: dict) -> dict:
    """
    Get the best route to a delivery using OSRM.

    The public OSRM demo server has no live traffic; it returns alternatives
    when available, and the fastest route feeds the in-app map.
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
