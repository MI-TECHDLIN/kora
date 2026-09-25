"""
MockAdapter: a stand-in logistics platform for the demo (and the fallback when no real
platform is connected).

Its order feed behaves like a real platform's webhook: every random interval in
[order_feed_min_interval_seconds, order_feed_max_interval_seconds] (3-7 minutes by default,
re-drawn each time, never a fixed timer) it builds an Order Intake API payload for a
plausible drop-off in downtown Austin, the demo's home area, validates it with the same
model `POST /v1/logistics/orders` uses, and hands the order to the dispatcher.

Each order is placed near the position `get_location()` reports, which the dispatcher
draws from an online driver's own fresh GPS ping (or the explicit DEMO_AREA_LAT/LNG override).
While no such position exists the feed holds and re-checks every `location_retry_seconds`, so
the first ping is what releases the next order. It never falls back to another driver's ping.
"""
import asyncio
import logging
import math
import random
import string
from collections import deque
from datetime import datetime, timedelta, timezone, tzinfo
from typing import Awaitable, Callable, Deque, Dict, Optional, Tuple

import httpx

from app.config import settings
from app.integrations.logistics.base import IncomingOrder, LogisticsAdapter, OrderHandler
from app.models.schemas import OrderCreatedEvent

logger = logging.getLogger(__name__)

SOURCE = "mock-logistics"

# Downtown Austin, TX: default fallback centre (MapScreen.fallbackCenter)
DEMO_AREA_CENTER = (30.2672, -97.7431)

# Drop-offs within ~2.5 km of the demo centre: (street address, latitude, longitude)
DROPOFFS = (
    ("812 Lavaca St, Austin, TX 78701", 30.2713, -97.7455),
    ("604 W 6th St, Austin, TX 78701", 30.2698, -97.7485),
    ("501 Brazos St, Austin, TX 78701", 30.2673, -97.7419),
    ("215 E 11th St, Austin, TX 78701", 30.2720, -97.7400),
    ("1705 Guadalupe St, Austin, TX 78701", 30.2800, -97.7428),
    ("908 W 5th St, Austin, TX 78703", 30.2703, -97.7538),
    ("72 Rainey St, Austin, TX 78701", 30.2590, -97.7385),
    ("1301 E 7th St, Austin, TX 78702", 30.2658, -97.7302),
    ("1103 E 12th St, Austin, TX 78702", 30.2716, -97.7285),
    ("1210 Barton Springs Rd, Austin, TX 78704", 30.2612, -97.7580),
    ("1600 S Congress Ave, Austin, TX 78704", 30.2490, -97.7497),
    ("300 Bowie St, Austin, TX 78703", 30.2675, -97.7525),
)
UNITS = ("", "", "", "Apt 3B", "Suite 210", "Unit 14", "Apt 707")
FIRST_NAMES = ("Jordan", "Priya", "Marcus", "Elena", "Tyler", "Aisha", "Diego", "Hannah",
               "Kevin", "Sofia", "Andre", "Megan", "Luis", "Grace")
LAST_NAMES = ("Lee", "Patel", "Brooks", "Ramirez", "Nguyen", "Carter", "Morales", "Kim",
              "Walker", "Hughes", "Santos", "Foster")
NOTES = (
    None,
    "Leave with the front desk.",
    "Call on arrival, the buzzer is broken.",
    "Fragile: glassware.",
    "Gate code 4412.",
    "Side entrance by the garage.",
    "Customer asked for no-contact drop-off.",
)
CATEGORIES = ("food", "packages", "documents", "furniture", "groceries")


def _local_tz() -> tzinfo:
    try:
        from zoneinfo import ZoneInfo
        return ZoneInfo("America/Chicago")
    except Exception:  # no tz database on the host: Austin is on CDT for most of the year
        return timezone(timedelta(hours=-5), "CDT")


def generate_nearby_coordinate(
    center_lat: float,
    center_lng: float,
    min_dist_km: float = 0.5,
    max_dist_km: float = 2.5,
    rng: Optional[random.Random] = None,
) -> Tuple[float, float]:
    """Generate a random coordinate between min_dist_km and max_dist_km from center."""
    r = rng or random.Random()
    dist_km = r.uniform(min_dist_km, max_dist_km)
    angle_rad = r.uniform(0, 2 * math.pi)

    delta_lat = (dist_km * math.cos(angle_rad)) / 111.0
    cos_lat = math.cos(math.radians(center_lat))
    if abs(cos_lat) < 1e-6:
        cos_lat = 1.0
    delta_lng = (dist_km * math.sin(angle_rad)) / (111.0 * cos_lat)

    return round(center_lat + delta_lat, 6), round(center_lng + delta_lng, 6)


_GEOCODE_CACHE: Dict[Tuple[float, float], str] = {}


async def reverse_geocode_async(lat: float, lng: float) -> Optional[str]:
    """Reverse geocode (lat, lng) to a real street/area address via TomTom or Nominatim."""
    cache_key = (round(lat, 3), round(lng, 3))
    if cache_key in _GEOCODE_CACHE:
        return _GEOCODE_CACHE[cache_key]

    tomtom_fallback: Optional[str] = None
    if settings.tomtom_api_key:
        url = f"https://api.tomtom.com/search/2/reverseGeocode/{lat},{lng}.json"
        params = {"key": settings.tomtom_api_key}
        try:
            async with httpx.AsyncClient(timeout=4.0) as client:
                resp = await client.get(url, params=params)
                if resp.status_code == 200:
                    data = resp.json()
                    addresses = data.get("addresses", [])
                    if addresses:
                        addr = addresses[0].get("address", {})
                        street = addr.get("streetName") or addr.get("street")
                        muni = addr.get("municipality") or addr.get("countrySubdivision")
                        freeform = addr.get("freeformAddress")
                        if street and muni:
                            result = f"{street}, {muni}"
                            _GEOCODE_CACHE[cache_key] = result
                            return result
                        if street:
                            _GEOCODE_CACHE[cache_key] = street
                            return street
                        tomtom_fallback = freeform or muni
        except Exception as e:
            logger.debug(f"[MockAdapter] TomTom reverse geocode failed for ({lat}, {lng}): {e}")

    try:
        url = "https://nominatim.openstreetmap.org/reverse"
        headers = {"User-Agent": "VoiceOps-Logistics/1.0"}
        params = {"format": "json", "lat": lat, "lon": lng, "zoom": 18, "addressdetails": 1, "accept-language": "en"}
        async with httpx.AsyncClient(timeout=4.0) as client:
            resp = await client.get(url, params=params, headers=headers)
            if resp.status_code == 200:
                data = resp.json()
                addr = data.get("address", {})
                road = (
                    addr.get("road")
                    or addr.get("suburb")
                    or addr.get("neighbourhood")
                    or addr.get("village")
                    or addr.get("pedestrian")
                )
                city = (
                    addr.get("city")
                    or addr.get("town")
                    or addr.get("district")
                    or addr.get("state")
                )
                if road and city:
                    result = f"{road}, {city}"
                    _GEOCODE_CACHE[cache_key] = result
                    return result
                if road:
                    _GEOCODE_CACHE[cache_key] = road
                    return road
                if data.get("display_name"):
                    parts = [p.strip() for p in data["display_name"].split(",") if p.strip()]
                    result = ", ".join(parts[:2]) if len(parts) >= 2 else parts[0]
                    _GEOCODE_CACHE[cache_key] = result
                    return result
    except Exception as e:
        logger.debug(f"[MockAdapter] Nominatim reverse geocode failed for ({lat}, {lng}): {e}")

    if tomtom_fallback:
        _GEOCODE_CACHE[cache_key] = tomtom_fallback
        return tomtom_fallback

    return None


class MockAdapter(LogisticsAdapter):
    name = SOURCE

    def __init__(
        self,
        min_interval: float,
        max_interval: float,
        rng: Optional[random.Random] = None,
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
        location_retry_seconds: Optional[float] = None,
    ):
        if not 0 < min_interval <= max_interval:
            raise ValueError("MockAdapter needs 0 < min_interval <= max_interval")
        self.min_interval = min_interval
        self.max_interval = max_interval
        self._rng = rng or random.Random()
        self._sleep = sleep
        self.location_retry_seconds = (settings.order_feed_location_retry_seconds
                                       if location_retry_seconds is None else location_retry_seconds)
        self._feed: Optional[asyncio.Task] = None
        # What the platform was told, newest last (the demo and tests read it)
        self.writebacks: Deque[dict] = deque(maxlen=50)

    # ------------------------------------------------------------------ order feed

    def next_interval(self) -> float:
        """Seconds until the next order: uniform in [min_interval, max_interval], drawn fresh."""
        return self._rng.uniform(self.min_interval, self.max_interval)

    def build_order_event(
        self,
        now: Optional[datetime] = None,
        center: Optional[Tuple[float, float]] = None,
        drop_coord: Optional[Tuple[float, float]] = None,
        address: Optional[str] = None,
    ) -> dict:
        """
        One Order Intake API payload (`OrderCreatedEvent`) for a drop-off.
        If drop_coord/center are provided, generates a drop-off near that location.
        Otherwise falls back to the default demo drop-offs in Austin, TX.
        """
        rng = self._rng
        unit = rng.choice(UNITS)

        if drop_coord is not None:
            latitude, longitude = drop_coord
            if address:
                order_address = f"{address}, {unit}" if unit and unit not in address else address
            else:
                order_address = f"{rng.randint(10, 999)} Local Route, Near {latitude:.3f}, {longitude:.3f}"
            offset_hours = int(round(longitude / 15.0))
            now = (now or datetime.now(timezone.utc)).astimezone(timezone(timedelta(hours=offset_hours)))
        elif center is not None:
            latitude, longitude = generate_nearby_coordinate(center[0], center[1], rng=rng)
            if address:
                order_address = f"{address}, {unit}" if unit and unit not in address else address
            else:
                order_address = f"{rng.randint(10, 999)} Local Route, Near {latitude:.3f}, {longitude:.3f}"
            offset_hours = int(round(longitude / 15.0))
            now = (now or datetime.now(timezone.utc)).astimezone(timezone(timedelta(hours=offset_hours)))
        else:
            now = (now or datetime.now(timezone.utc)).astimezone(_local_tz())
            street, latitude, longitude = rng.choice(DROPOFFS)
            order_address = street.replace(", Austin", f", {unit}, Austin", 1) if unit else street

        # Window opens at the next half hour plus 30 minutes, and lasts 2 hours
        start = now.replace(second=0, microsecond=0) + timedelta(minutes=30 - now.minute % 30 + 30)
        end = start + timedelta(hours=2)

        suffix = "".join(rng.choices(string.ascii_uppercase + string.digits, k=6))
        order = {
            "recipient": {
                "name": f"{rng.choice(FIRST_NAMES)} {rng.choice(LAST_NAMES)}",
                # 555-0100..0199 is reserved for fiction: no real customer gets called
                "phone": f"+1512555{rng.randint(100, 199):04d}",
            },
            "dropoff": {"address": order_address, "latitude": latitude, "longitude": longitude},
            "time_window": {"start": start.isoformat(), "end": end.isoformat()},
            "package_count": rng.randint(1, 3),
            "category": rng.choice(CATEGORIES),
            "weight_kg": round(rng.uniform(0.5, 50.0), 1),
            "dimensions": {
                "length": round(rng.uniform(10, 100), 1),
                "width": round(rng.uniform(10, 80), 1),
                "height": round(rng.uniform(5, 50), 1),
            },
            "value": round(rng.uniform(5.0, 200.0), 2),
        }
        note = rng.choice(NOTES)
        if note:
            order["notes"] = note
        return {
            "event": "order.created",
            "source": SOURCE,
            "external_id": f"MLX-{now:%Y%m%d}-{suffix}",
            "created_at": now.isoformat(),
            "order": order,
        }

    def next_order(
        self,
        center: Optional[Tuple[float, float]] = None,
        address: Optional[str] = None,
    ) -> IncomingOrder:
        """A generated order, parsed exactly as the Order Intake API parses a platform's POST."""
        return IncomingOrder.from_event(
            OrderCreatedEvent.model_validate(self.build_order_event(center=center, address=address))
        )

    async def next_order_async(
        self,
        center: Optional[Tuple[float, float]] = None,
    ) -> IncomingOrder:
        """Asynchronously build next order, reverse-geocoding if a center location is provided."""
        # If no center or center is downtown Austin demo area, use curated DROPOFFS with 0 network delay
        is_austin = (
            center is None
            or (abs(center[0] - 30.2672) < 0.1 and abs(center[1] - -97.7431) < 0.1)
        )

        drop_coord = None
        geo_address = None
        if center is not None and not is_austin:
            drop_coord = generate_nearby_coordinate(center[0], center[1], rng=self._rng)
            geo_address = await reverse_geocode_async(drop_coord[0], drop_coord[1])

        event = self.build_order_event(center=center if not is_austin else None, drop_coord=drop_coord, address=geo_address)
        return IncomingOrder.from_event(OrderCreatedEvent.model_validate(event))

    async def _locate(
        self,
        get_location: Optional[Callable[[], Awaitable[Optional[Tuple[float, float]]]]],
    ) -> Tuple[bool, Optional[Tuple[float, float]]]:
        """
        (ready, centre) for the next order. With a `get_location` source, ready means it named a
        position; a source with nothing to say (no driver located yet) means hold. Without one
        there is no driver context: the explicit demo area if set, else the curated Austin drop-offs.
        """
        if get_location is None:
            if settings.demo_area_lat is not None and settings.demo_area_lng is not None:
                return True, (float(settings.demo_area_lat), float(settings.demo_area_lng))
            return True, None
        try:
            center = await get_location()
        except Exception as e:
            logger.debug(f"[MockAdapter] get_location failed: {e}")
            center = None
        return center is not None, center

    async def run_feed(
        self,
        on_order: OrderHandler,
        should_generate: Callable[[], bool],
        get_location: Optional[Callable[[], Awaitable[Optional[Tuple[float, float]]]]] = None,
    ) -> None:
        """
        Wait a fresh random interval, then emit one order (unless nobody could take it). Forever.
        If nobody's position is known yet the order is held, not placed elsewhere, and retried
        every `location_retry_seconds` until one is (or nobody is left to take it).
        """
        while True:
            await self._sleep(self.next_interval())
            while should_generate():
                ready, center = await self._locate(get_location)
                if not ready:
                    logger.info("[MockAdapter] Holding the next order: no online driver's location is known yet")
                    await self._sleep(self.location_retry_seconds)
                    continue
                order = await self.next_order_async(center=center)
                try:
                    await on_order(order)
                except Exception:
                    logger.exception(f"[MockAdapter] Dispatching {order.external_id} failed")
                break

    async def start_order_feed(
        self,
        on_order: OrderHandler,
        should_generate: Callable[[], bool],
        get_location: Optional[Callable[[], Awaitable[Optional[Tuple[float, float]]]]] = None,
    ) -> None:
        if self._feed is None or self._feed.done():
            self._feed = asyncio.create_task(self.run_feed(on_order, should_generate, get_location))

    async def stop_order_feed(self) -> None:
        if self._feed is not None:
            self._feed.cancel()
            await asyncio.gather(self._feed, return_exceptions=True)
            self._feed = None

    # ------------------------------------------------------------------ write-backs

    async def order_assigned(self, order: IncomingOrder, delivery_id: str, driver_id: str) -> None:
        self.writebacks.append({"external_id": order.external_id, "delivery_id": delivery_id,
                                "assigned_to": driver_id})
        logger.info(f"[MockAdapter] {order.external_id} assigned to driver {driver_id}")

    async def order_unassigned(self, order: IncomingOrder, delivery_id: str, reason: str) -> None:
        self.writebacks.append({"external_id": order.external_id, "delivery_id": delivery_id,
                                "unassigned": reason})
        logger.info(f"[MockAdapter] {order.external_id} unassigned: {reason}")
