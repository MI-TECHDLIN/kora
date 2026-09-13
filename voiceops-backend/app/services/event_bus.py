"""
VoiceOps Internal Event Bus
Asynchronous in-process Pub/Sub event bus for decoupling core delivery events,
analytics, proactive notifications, and memory storage.
"""
import asyncio
import logging
from typing import Callable, Dict, List, Any

logger = logging.getLogger(__name__)


class Events:
    DRIVER_STARTED_SHIFT = "DriverStartedShift"
    DRIVER_LOCATION_UPDATED = "DriverLocationUpdated"
    DRIVER_ARRIVED = "DriverArrived"
    DELIVERY_COMPLETED = "DeliveryCompleted"
    DELIVERY_FAILED = "DeliveryFailed"
    CUSTOMER_CONTACTED = "CustomerContacted"
    DELIVERY_AT_RISK = "DeliveryAtRisk"
    DISPATCHER_ALERT = "DispatcherAlertCreated"


class EventBus:
    _subscribers: Dict[str, List[Callable]] = {}

    @classmethod
    def subscribe(cls, event_type: str, handler: Callable):
        """Register a subscriber handler for a specific event type."""
        cls._subscribers.setdefault(event_type, []).append(handler)

    @classmethod
    def unsubscribe(cls, event_type: str, handler: Callable):
        """Remove a subscriber handler."""
        if event_type in cls._subscribers and handler in cls._subscribers[event_type]:
            cls._subscribers[event_type].remove(handler)

    @classmethod
    async def publish(cls, event_type: str, payload: Dict[str, Any]):
        """
        Publish an event to all subscribers concurrently in the background.
        Errors in subscribers do not bubble up to the publisher.
        """
        handlers = cls._subscribers.get(event_type, [])
        if not handlers:
            return

        import inspect
        tasks = []
        for handler in handlers:
            try:
                if inspect.iscoroutinefunction(handler):
                    tasks.append(handler(payload))
                else:
                    handler(payload)
            except Exception as e:
                logger.error(f"[EventBus] Synchronous handler error for {event_type}: {e}")

        if tasks:
            results = await asyncio.gather(*tasks, return_exceptions=True)
            for res in results:
                if isinstance(res, Exception):
                    logger.error(f"[EventBus] Async subscriber error for {event_type}: {res}")
