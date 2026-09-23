"""
Vehicle modes and the per-mode time-to-destination calculation.

Every ETA the driver hears (voice tools), sees (the route card) or gets pushed
(proactive alerts, order offers, customer ETA texts) comes from
`duration_for_mode`, so the three surfaces cannot drift apart.

HONEST LIMITATION: the public OSRM demo server only serves the `driving`
profile, and the traffic API is queried as `car`. Walking and cycling routes
therefore still follow driving-network roads (no footpaths, no one-way
exemptions, no bike lanes), so their *distance* is approximate. Only the
duration is derived per mode, from that distance and the average speeds below.
Follow-up: self-host OSRM with real `foot`/`bicycle` profiles and route with
those instead of deriving; the tuning block below then becomes a fallback.
"""
import logging
import re
import time
from enum import Enum
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)


class VehicleMode(str, Enum):
    """The values stored in `drivers.vehicle_type` and sent by the app."""

    CAR = "car"
    MOTORBIKE = "motorbike"
    BICYCLE = "bicycle"
    WALKING = "walking"


# ---------------------------------------------------------------------------
# Tuning block: change these to retune ETAs (captain / Maria). Nothing else in
# the backend hardcodes a per-mode speed.
# ---------------------------------------------------------------------------

# Average door-to-door speeds in km/h. Cover stops, crossings and hills.
WALKING_SPEED_KMH = 5.0
BICYCLE_SPEED_KMH = 15.0

# A motorbike filters through traffic, so it is a little quicker than a car on
# the same route but never slower: driving duration x this factor (must be <= 1).
MOTORBIKE_DURATION_FACTOR = 0.85

# Used when a driver has no vehicle set, or one we do not recognise.
DEFAULT_VEHICLE_MODE = VehicleMode.CAR

# Values that mean "the driver has not chosen a vehicle" (the profile route
# returns "vehicle" as its placeholder). These fall back to the default quietly.
_UNSET_VALUES = {"", "vehicle", "not set", "none", "unknown"}

_WALKING_TOKENS = {"foot", "feet", "pedestrian", "hiking"}
_MOTORBIKE_TOKENS = {"scooter", "okada", "moped", "boda"}
_BICYCLE_TOKENS = {"bike", "bicycle", "cycle", "cycling", "cyclist", "ebike"}
_CAR_TOKENS = {
    "car", "sedan", "suv", "van", "truck", "lorry", "pickup", "taxi", "hatchback",
    "minivan",
}


def parse_vehicle_mode(value: Any) -> Optional[VehicleMode]:
    """
    Map free text ("Walking", "on foot", "Okada", "sedan") to a mode.
    Returns None when the text is blank or not recognised: callers decide what
    to do with that (`resolve_vehicle_mode` defaults to car, loudly).
    """
    if isinstance(value, VehicleMode):
        return value
    tokens = re.findall(r"[a-z]+", str(value or "").lower())
    if not tokens:
        return None
    # Order matters: "motorbike" contains "bike", so motorbike is checked first.
    if any(t.startswith("walk") or t in _WALKING_TOKENS for t in tokens):
        return VehicleMode.WALKING
    if any(t.startswith("motor") or t in _MOTORBIKE_TOKENS for t in tokens):
        return VehicleMode.MOTORBIKE
    if any(t.startswith(("bicycl", "cycl")) or t in _BICYCLE_TOKENS for t in tokens):
        return VehicleMode.BICYCLE
    if any(t in _CAR_TOKENS for t in tokens):
        return VehicleMode.CAR
    return None


def resolve_vehicle_mode(value: Any) -> VehicleMode:
    """
    The mode to compute an ETA with. Unset -> the default; unrecognised text ->
    the default too, but logged so a new vehicle type is noticed, not hidden.
    """
    mode = parse_vehicle_mode(value)
    if mode is not None:
        return mode
    if str(value or "").strip().lower() not in _UNSET_VALUES:
        logger.warning(
            "[VehicleMode] Unrecognised vehicle_type %r; computing ETAs as %s",
            value,
            DEFAULT_VEHICLE_MODE.value,
        )
    return DEFAULT_VEHICLE_MODE


def duration_for_mode(mode: VehicleMode, distance_m: float, driving_duration_s: float) -> int:
    """
    Seconds to cover a route for `mode`.

    `driving_duration_s` is the OSRM (or traffic-aware) car duration for the
    same route. Car keeps it; motorbike scales it; walking and cycling are
    distance / average speed and ignore traffic.
    """
    if mode == VehicleMode.WALKING:
        return round(distance_m / (WALKING_SPEED_KMH / 3.6))
    if mode == VehicleMode.BICYCLE:
        return round(distance_m / (BICYCLE_SPEED_KMH / 3.6))
    if mode == VehicleMode.MOTORBIKE:
        return round(driving_duration_s * min(MOTORBIKE_DURATION_FACTOR, 1.0))
    return round(driving_duration_s)


def apply_mode_to_routes(routes: List[Dict[str, Any]], vehicle_type: Any) -> List[Dict[str, Any]]:
    """
    Re-time OSRM route dicts (`distance` m, `duration` s) for the driver's mode.
    Keeps the driving time as `driving_duration`, tags `vehicle_mode`, and
    returns the routes fastest-first for that mode.
    """
    mode = resolve_vehicle_mode(vehicle_type)
    timed = [
        {
            **route,
            "driving_duration": route["duration"],
            "duration": duration_for_mode(mode, route["distance"], route["duration"]),
            "vehicle_mode": mode.value,
        }
        for route in routes
    ]
    return sorted(timed, key=lambda route: route["duration"])


def straight_line_speed_kmh(mode: VehicleMode, driving_speed_kmh: float) -> float:
    """
    Effective speed for the offline (haversine) fallback, where there is no
    driving duration to scale. `driving_speed_kmh` is what a car would average.
    """
    if mode == VehicleMode.WALKING:
        return WALKING_SPEED_KMH
    if mode == VehicleMode.BICYCLE:
        return BICYCLE_SPEED_KMH
    if mode == VehicleMode.MOTORBIKE:
        return driving_speed_kmh / min(MOTORBIKE_DURATION_FACTOR, 1.0)
    return driving_speed_kmh


# ---------------------------------------------------------------------------
# Looking up a driver's mode
# ---------------------------------------------------------------------------

_DRIVER_MODE_TTL_SECONDS = 60.0
_driver_mode_cache: Dict[str, Tuple[float, VehicleMode]] = {}


def invalidate_driver_vehicle_mode(driver_id: str) -> None:
    """Forget the cached mode, e.g. right after the driver changes vehicle."""
    _driver_mode_cache.pop(str(driver_id), None)


async def get_driver_vehicle_mode(driver_id: Optional[str], fallback: Any = None) -> VehicleMode:
    """
    The driver's current mode from `drivers.vehicle_type`, cached briefly because
    location pings call this every few seconds. When there is no driver row or the
    lookup fails, `fallback` (e.g. the vehicle_type the voice session loaded) is
    used, then the default mode. Never raises.
    """
    if not driver_id:
        return resolve_vehicle_mode(fallback)
    key = str(driver_id)
    cached = _driver_mode_cache.get(key)
    now = time.monotonic()
    if cached and now - cached[0] < _DRIVER_MODE_TTL_SECONDS:
        return cached[1]
    try:
        from app.db.queries import get_driver_by_id

        driver = await get_driver_by_id(key)
    except Exception as e:
        logger.warning("[VehicleMode] Could not load vehicle for driver %s: %s", key, e)
        return resolve_vehicle_mode(fallback)
    if driver is None:
        return resolve_vehicle_mode(fallback)
    mode = resolve_vehicle_mode(driver.get("vehicle_type"))
    _driver_mode_cache[key] = (now, mode)
    return mode
