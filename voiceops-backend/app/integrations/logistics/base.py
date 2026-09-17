"""
LogisticsAdapter: the one boundary between VoiceOps and a logistics platform (AGENTS.md
"Logistics Layer"). Tool handlers and the order dispatcher talk to an adapter, never to a
platform API directly.

Inbound, a platform hands VoiceOps new orders, either by POSTing the Order Intake API
(`POST /v1/logistics/orders`, an `OrderCreatedEvent`) or through the adapter's own feed.
Outbound, the dispatcher reports back who took an order, or that nobody did.
"""
import re
from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime
from typing import Awaitable, Callable, Optional, Tuple

from app.models.schemas import OrderCreatedEvent

_UNIT = re.compile(r"^(apt|apartment|unit|suite|ste|fl|floor|#)\b\.?\s*\S*$|^#\S+$", re.IGNORECASE)
_HOUSE_NUMBER = re.compile(r"^\d+[A-Za-z]?(-\d+)?\s+")


def _clock(moment: datetime) -> str:
    return f"{moment.hour % 12 or 12}:{moment.minute:02d} {'AM' if moment.hour < 12 else 'PM'}"


def format_time_window(start: datetime, end: datetime) -> str:
    """'3:00 PM – 5:00 PM', each end in its own UTC offset (the local time the platform sent)."""
    return f"{_clock(start)} – {_clock(end)}"


def address_area(address: str) -> str:
    """
    The street and city of an address, without the house number or unit: what a driver sees
    of an order before it is theirs. '1301 E 7th St, Apt 2, Austin, TX 78702' → 'E 7th St, Austin'.
    """
    parts = [p.strip() for p in (address or "").split(",") if p.strip() and not _UNIT.match(p.strip())]
    if not parts:
        return ""
    street = _HOUSE_NUMBER.sub("", parts[0])
    return f"{street}, {parts[1]}" if len(parts) > 1 else street


@dataclass(frozen=True)
class IncomingOrder:
    """A new order from a logistics platform, before any driver has it."""
    source: str
    external_id: str
    recipient_name: str
    address: str
    latitude: float
    longitude: float
    recipient_phone: Optional[str] = None
    notes: Optional[str] = None
    time_window: Optional[str] = None  # display text, as deliveries.time_window stores it
    package_count: Optional[int] = None

    @property
    def area(self) -> str:
        return address_area(self.address)

    @classmethod
    def from_event(cls, event: OrderCreatedEvent) -> "IncomingOrder":
        order = event.order
        window = order.time_window
        return cls(
            source=event.source,
            external_id=event.external_id,
            recipient_name=order.recipient.name,
            recipient_phone=order.recipient.phone,
            address=order.dropoff.address,
            latitude=order.dropoff.latitude,
            longitude=order.dropoff.longitude,
            notes=order.notes,
            time_window=format_time_window(window.start, window.end) if window else None,
            package_count=order.package_count,
        )

    @classmethod
    def from_delivery_row(cls, row: dict) -> "IncomingOrder":
        """Rebuild an order from its `deliveries` row (restart recovery)."""
        return cls(
            source=row.get("source") or "unknown",
            external_id=row.get("external_id") or row["id"],
            recipient_name=row.get("recipient_name") or "Customer",
            recipient_phone=row.get("phone"),
            address=row.get("address") or "",
            latitude=float(row["latitude"]),
            longitude=float(row["longitude"]),
            notes=row.get("notes"),
            time_window=row.get("time_window"),
        )


OrderHandler = Callable[[IncomingOrder], Awaitable[object]]


class LogisticsAdapter(ABC):
    """
    One logistics platform. `MockAdapter` is the demo backend; an Onfleet adapter will sit
    behind the same interface. Changing this class means changing `MockAdapter` in the same
    change (AGENTS.md "What NOT to Do").
    """

    #: Platform name, stored as `deliveries.source`
    name: str

    @abstractmethod
    async def start_order_feed(
        self,
        on_order: OrderHandler,
        should_generate: Callable[[], bool],
        get_location: Optional[Callable[[], Awaitable[Optional[Tuple[float, float]]]]] = None,
    ) -> None:
        """
        Start delivering new orders to `on_order`. `should_generate()` is false while nobody
        could take an order, and a feed that creates orders itself skips them then.
        `get_location()` optionally supplies the (latitude, longitude) of online drivers
        around which to generate mock drop-offs.
        A platform that only pushes through the Order Intake API makes this a no-op.
        """

    @abstractmethod
    async def stop_order_feed(self) -> None:
        """Stop the feed. Safe to call when it never started."""

    @abstractmethod
    async def order_assigned(self, order: IncomingOrder, delivery_id: str, driver_id: str) -> None:
        """A driver accepted the order: tell the platform who has it."""

    @abstractmethod
    async def order_unassigned(self, order: IncomingOrder, delivery_id: str, reason: str) -> None:
        """No driver took the order: it waits in the unassigned queue."""
