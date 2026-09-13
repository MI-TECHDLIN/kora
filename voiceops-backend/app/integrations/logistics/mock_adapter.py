"""
MockAdapter: a stand-in logistics platform for the demo (and the fallback when no real
platform is connected).

Its order feed behaves like a real platform's webhook: every random interval in
[order_feed_min_interval_seconds, order_feed_max_interval_seconds] (3-7 minutes by default,
re-drawn each time, never a fixed timer) it builds an Order Intake API payload for a
plausible drop-off in downtown Austin, the demo's home area, validates it with the same
model `POST /v1/logistics/orders` uses, and hands the order to the dispatcher.
"""
import asyncio
import logging
import random
import string
from collections import deque
from datetime import datetime, timedelta, timezone, tzinfo
from typing import Awaitable, Callable, Deque, Optional

from app.integrations.logistics.base import IncomingOrder, LogisticsAdapter, OrderHandler
from app.models.schemas import OrderCreatedEvent

logger = logging.getLogger(__name__)

SOURCE = "mock-logistics"

# Downtown Austin, TX: the frontend map's fallback centre (MapScreen.fallbackCenter)
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


def _local_tz() -> tzinfo:
    try:
        from zoneinfo import ZoneInfo
        return ZoneInfo("America/Chicago")
    except Exception:  # no tz database on the host: Austin is on CDT for most of the year
        return timezone(timedelta(hours=-5), "CDT")


class MockAdapter(LogisticsAdapter):
    name = SOURCE

    def __init__(
        self,
        min_interval: float,
        max_interval: float,
        rng: Optional[random.Random] = None,
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
    ):
        if not 0 < min_interval <= max_interval:
            raise ValueError("MockAdapter needs 0 < min_interval <= max_interval")
        self.min_interval = min_interval
        self.max_interval = max_interval
        self._rng = rng or random.Random()
        self._sleep = sleep
        self._feed: Optional[asyncio.Task] = None
        # What the platform was told, newest last (the demo and tests read it)
        self.writebacks: Deque[dict] = deque(maxlen=50)

    # ------------------------------------------------------------------ order feed

    def next_interval(self) -> float:
        """Seconds until the next order: uniform in [min_interval, max_interval], drawn fresh."""
        return self._rng.uniform(self.min_interval, self.max_interval)

    def build_order_event(self, now: Optional[datetime] = None) -> dict:
        """One Order Intake API payload (`OrderCreatedEvent`) for a random demo drop-off."""
        rng = self._rng
        now = (now or datetime.now(timezone.utc)).astimezone(_local_tz())
        street, latitude, longitude = rng.choice(DROPOFFS)
        unit = rng.choice(UNITS)
        address = street.replace(", Austin", f", {unit}, Austin", 1) if unit else street

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
            "dropoff": {"address": address, "latitude": latitude, "longitude": longitude},
            "time_window": {"start": start.isoformat(), "end": end.isoformat()},
            "package_count": rng.randint(1, 3),
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

    def next_order(self) -> IncomingOrder:
        """A generated order, parsed exactly as the Order Intake API parses a platform's POST."""
        return IncomingOrder.from_event(OrderCreatedEvent.model_validate(self.build_order_event()))

    async def run_feed(self, on_order: OrderHandler, should_generate: Callable[[], bool]) -> None:
        """Wait a fresh random interval, then emit one order (unless nobody could take it). Forever."""
        while True:
            await self._sleep(self.next_interval())
            if not should_generate():
                continue
            order = self.next_order()
            try:
                await on_order(order)
            except Exception:
                logger.exception(f"[MockAdapter] Dispatching {order.external_id} failed")

    async def start_order_feed(self, on_order: OrderHandler, should_generate: Callable[[], bool]) -> None:
        if self._feed is None or self._feed.done():
            self._feed = asyncio.create_task(self.run_feed(on_order, should_generate))

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
