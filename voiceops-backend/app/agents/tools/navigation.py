"""
Navigation tools for VoiceOps agent.
Tools: get_best_route, start_navigation
Platform: Google Directions API. Routes render in-app on the Flutter map: the voice
WebSocket turns these results into `screen_navigate` + `map_route` events. There is no
external maps deep link.
"""
from typing import Dict, Any, List, Optional, Tuple
from app.integrations.google_maps import get_directions


# Used until the session knows the driver's position / the delivery's coordinates.
MOCK_ORIGIN = (6.44, 3.39)
MOCK_DESTINATION = {"address": "22 Victoria Island Drive", "latitude": 6.4286, "longitude": 3.4108}


def _to_float(value: Any) -> Optional[float]:
    try:
        return float(value) if value is not None else None
    except (TypeError, ValueError):
        return None


def stop_from_delivery(delivery: dict) -> dict:
    """
    Normalise a delivery (DB row, context delivery, or get_next_delivery result) to a
    `map_route` stop: {delivery_id, sequence, recipient_name, address, latitude, longitude}.
    """
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
    """The driver's last known position (context latitude/longitude), else the mock origin."""
    lat, lng = _to_float(context.get("latitude")), _to_float(context.get("longitude"))
    if lat is not None and lng is not None:
        return lat, lng
    return MOCK_ORIGIN


def resolve_stop(delivery_id: Optional[str], context: dict) -> dict:
    """
    The stop for `delivery_id`, from deliveries this session already knows about
    (`context["deliveries"]`, then `context["current_delivery"]`), else the mock destination.
    """
    candidates = []
    known = (context.get("deliveries") or {}).get(delivery_id) if delivery_id else None
    if known:
        candidates.append(known)
    current = context.get("current_delivery")
    if isinstance(current, dict) and (not delivery_id or current.get("id") == delivery_id):
        candidates.append(stop_from_delivery(current))

    for stop in candidates:
        if stop.get("latitude") is not None and stop.get("longitude") is not None:
            return stop

    return {"delivery_id": delivery_id, "sequence": None, "recipient_name": None, **MOCK_DESTINATION}


async def routes_to_stop(stop: dict, context: dict) -> List[Dict[str, Any]]:
    """Directions routes from the driver's position to `stop` (raw metres / seconds)."""
    origin_lat, origin_lng = resolve_origin(context)
    return await get_directions(origin_lat, origin_lng, stop["latitude"], stop["longitude"])


def fastest_route(routes: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    return min(routes, key=lambda r: r["duration"]) if routes else None


def route_fields(route: Optional[Dict[str, Any]]) -> dict:
    """The `map_route` route fields for one raw Directions route (all empty when there is none)."""
    if not route:
        return {"polyline": "", "summary": None, "distance_km": None,
                "duration_mins": None, "duration_text": None}
    duration_mins = int(route["duration"] / 60)
    return {
        "polyline": route.get("polyline", ""),
        "summary": route["summary"],
        "distance_km": round(route["distance"] / 1000, 1),
        "duration_mins": duration_mins,
        "duration_text": f"{duration_mins} mins",
    }


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

        # Origin is the driver's last known position, destination the delivery's coordinates
        # (both fall back to mock coordinates until the session knows them)
        stop = resolve_stop(delivery_id, context)
        destination_address = stop["address"]

        # Call Google Directions API
        routes = await routes_to_stop(stop, context)

        if not routes:
            return {
                "success": True,
                "has_faster_route": False,
                "best_route": {"summary": "Current route", "duration_mins": 14},
                "time_saved_mins": 0,
                "destination_address": destination_address
            }

        # Find best route (shortest duration)
        best_route = fastest_route(routes)

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
    Start navigation to the delivery on the in-app map.

    Platform: internal. The voice WebSocket emits `screen_navigate: map` and a `map_route`
    event built from this result, and the Flutter map draws the route itself.
    Trigger phrases: "navigate", "take me there", "get directions"

    Input:
    {
        "delivery_id": "uuid"
    }

    Expected output:
    {
        "success": true,
        "delivery_id": "uuid",
        "address": "22 Victoria Island Drive",
        "latitude": 6.4286,
        "longitude": 3.4108,
        "route": {
            "polyline": "<Google encoded overview polyline>",
            "summary": "Victoria Bridge",
            "distance_km": 3.2,
            "duration_mins": 11,
            "duration_text": "11 mins"
        },
        "message": "Route to 22 Victoria Island Drive is on your map: 11 mins via Victoria Bridge."
    }

    `route` is null when Directions returns nothing; the stop is still shown.
    """
    try:
        stop = resolve_stop(parameters.get("delivery_id"), context)
        address = stop["address"]

        route = fastest_route(await routes_to_stop(stop, context))
        if route:
            fields = route_fields(route)
            message = f"Route to {address} is on your map: {fields['duration_text']} via {fields['summary']}."
        else:
            fields = None
            message = f"{address} is on your map."

        return {
            "success": True,
            "delivery_id": stop["delivery_id"],
            "address": address,
            "latitude": stop["latitude"],
            "longitude": stop["longitude"],
            "route": fields,
            "message": message
        }
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }
