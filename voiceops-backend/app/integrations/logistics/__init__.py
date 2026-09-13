"""Logistics platforms behind one interface (`LogisticsAdapter`). See base.py."""
from typing import Optional

from app.config import settings
from app.integrations.logistics.base import IncomingOrder, LogisticsAdapter, address_area
from app.integrations.logistics.mock_adapter import DEMO_AREA_CENTER, MockAdapter

_adapter: Optional[LogisticsAdapter] = None


def get_logistics_adapter() -> LogisticsAdapter:
    """
    The configured platform. Only `MockAdapter` exists so far; an Onfleet adapter slots in here
    behind the same interface when it is built.
    """
    global _adapter
    if _adapter is None:
        _adapter = MockAdapter(settings.order_feed_min_interval_seconds,
                               settings.order_feed_max_interval_seconds)
    return _adapter


__all__ = ["DEMO_AREA_CENTER", "IncomingOrder", "LogisticsAdapter", "MockAdapter",
           "address_area", "get_logistics_adapter"]
