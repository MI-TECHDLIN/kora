"""Order Queue snapshots, synchronization paths, targets, and voice behavior."""
import asyncio
from datetime import datetime, timezone
from types import SimpleNamespace

import pytest

from app.agents.tools import delivery as delivery_tools
from app.agents.tools import preferences as preference_tools
from app.api.routes import deliveries as delivery_routes
from app.api.routes import pod as pod_routes
from app.api.websocket import voice
from app.dispatch import order_dispatch
from app.dispatch.order_dispatch import Candidate, OpenOrder, OrderDispatcher
from app.integrations.logistics import IncomingOrder
from app.services import location_service as location_module
from app.services import order_queue_service
from app.services.preference_service import (
    MAX_DAILY_DELIVERY_TARGET,
    normalize_preference_value,
)

DRIVER_ID = "10ed22c4-c1c0-4d37-8683-dbb8f510e4c6"
SHIFT_ID = "093375a3-06ab-4584-8331-f5df775f150b"
DELIVERY_ID = "f2000000-0000-4000-8000-000000000001"


def run(coro):
    return asyncio.run(coro)


def delivery(sequence, status, delivery_id=None, **extra):
    return {
        "id": delivery_id or f"delivery-{sequence}",
        "sequence_order": sequence,
        "status": status,
        "recipient_name": f"Customer {sequence}",
        "address": f"{sequence} Main St",
        "time_window": None,
        **extra,
    }


def test_empty_queue_snapshot_has_zero_counts_and_no_target(monkeypatch):
    async def no_deliveries(shift_id):
        return []

    async def no_preference(driver_id, key):
        return None

    monkeypatch.setattr(order_queue_service, "get_shift_deliveries", no_deliveries)
    monkeypatch.setattr(order_queue_service.preference_service, "get_preference", no_preference)

    snapshot = run(order_queue_service.build_queue_snapshot(SHIFT_ID, DRIVER_ID))

    assert snapshot == {
        "shift_id": SHIFT_ID,
        "target": None,
        "counts": {
            "total": 0,
            "completed": 0,
            "active": 0,
            "pending": 0,
            "failed": 0,
            "rescheduled": 0,
        },
        "orders": [],
    }


def test_mixed_snapshot_selects_lowest_pending_as_active_and_includes_target(monkeypatch):
    rows = [
        delivery(5, "pending", eta_minutes=19),
        delivery(1, "delivered"),
        delivery(4, "rescheduled"),
        delivery(2, "pending", time_window="9:00 AM – 10:00 AM"),
        delivery(3, "failed"),
    ]

    async def get_deliveries(shift_id):
        return rows

    async def get_preference(driver_id, key):
        return "15"

    monkeypatch.setattr(order_queue_service, "get_shift_deliveries", get_deliveries)
    monkeypatch.setattr(order_queue_service.preference_service, "get_preference", get_preference)

    snapshot = run(order_queue_service.build_queue_snapshot(SHIFT_ID, DRIVER_ID))

    assert snapshot["target"] == 15
    assert snapshot["counts"] == {
        "total": 5,
        "completed": 1,
        "active": 1,
        "pending": 1,
        "failed": 1,
        "rescheduled": 1,
    }
    assert [order["sequence"] for order in snapshot["orders"]] == [1, 2, 3, 4, 5]
    assert [order["state"] for order in snapshot["orders"]] == [
        "completed", "active", "failed", "rescheduled", "pending"
    ]
    assert snapshot["orders"][-1]["eta_minutes"] == 19


@pytest.mark.parametrize("value", [1, "15", 15.0, MAX_DAILY_DELIVERY_TARGET])
def test_daily_target_accepts_positive_whole_numbers(value):
    assert normalize_preference_value("daily_delivery_target", value) == str(int(value))


@pytest.mark.parametrize("value", [0, -1, True, "1.5", MAX_DAILY_DELIVERY_TARGET + 1])
def test_daily_target_rejects_invalid_values(value):
    with pytest.raises(ValueError, match="whole number"):
        normalize_preference_value("daily_delivery_target", value)


def test_rest_and_websocket_use_the_same_snapshot_object(monkeypatch):
    snapshot = {"shift_id": SHIFT_ID, "target": None, "counts": {}, "orders": []}
    seen = []

    async def build(shift_id, driver_id):
        return snapshot

    async def broadcast(shift_id, payload):
        seen.append(payload)

    async def no_ack(payload, driver_id):
        return False

    monkeypatch.setattr(order_queue_service, "build_queue_snapshot", build)
    monkeypatch.setattr(order_queue_service, "_acknowledge_target_once", no_ack)
    monkeypatch.setattr(voice, "broadcast_queue_update", broadcast)

    result = run(order_queue_service.publish_queue_update(SHIFT_ID, DRIVER_ID))

    assert result is snapshot
    assert seen == [snapshot]


class FixedDateTime(datetime):
    current = datetime(2026, 9, 24, tzinfo=timezone.utc)

    @classmethod
    def now(cls, tz=None):
        return cls.current if tz is not None else cls.current.replace(tzinfo=None)


def test_target_change_does_not_repeat_acknowledgement_on_same_day(monkeypatch):
    stored = {}
    announcements = []
    snapshot = {
        "shift_id": SHIFT_ID,
        "target": 2,
        "counts": {"completed": 2},
        "orders": [],
    }

    async def get_preference(driver_id, key):
        return stored.get(key)

    async def set_marker(driver_id, marker):
        stored["_daily_delivery_target_acknowledged"] = marker
        return True

    async def announce(driver_id, shift_id, target):
        announcements.append((driver_id, shift_id, target))
        return 1

    monkeypatch.setattr(order_queue_service.preference_service, "get_preference", get_preference)
    monkeypatch.setattr(order_queue_service.preference_service, "set_target_acknowledged", set_marker)
    monkeypatch.setattr(voice, "announce_target_reached", announce)
    monkeypatch.setattr(order_queue_service, "datetime", FixedDateTime)

    assert run(order_queue_service._acknowledge_target_once(snapshot, DRIVER_ID)) is True
    snapshot["target"] = 5
    snapshot["counts"]["completed"] = 5
    assert run(order_queue_service._acknowledge_target_once(snapshot, DRIVER_ID)) is False
    assert announcements == [(DRIVER_ID, SHIFT_ID, 2)]


def test_target_reached_is_announced_again_on_a_new_utc_day(monkeypatch):
    stored = {}
    announcements = []
    snapshot = {
        "shift_id": SHIFT_ID,
        "target": 2,
        "counts": {"completed": 2},
        "orders": [],
    }

    async def get_preference(driver_id, key):
        return stored.get(key)

    async def set_marker(driver_id, marker):
        stored["_daily_delivery_target_acknowledged"] = marker
        return True

    async def announce(driver_id, shift_id, target):
        announcements.append((driver_id, shift_id, target))
        return 1

    monkeypatch.setattr(order_queue_service.preference_service, "get_preference", get_preference)
    monkeypatch.setattr(order_queue_service.preference_service, "set_target_acknowledged", set_marker)
    monkeypatch.setattr(voice, "announce_target_reached", announce)
    monkeypatch.setattr(order_queue_service, "datetime", FixedDateTime)

    FixedDateTime.current = datetime(2026, 9, 24, tzinfo=timezone.utc)
    assert run(order_queue_service._acknowledge_target_once(snapshot, DRIVER_ID)) is True
    FixedDateTime.current = datetime(2026, 9, 25, tzinfo=timezone.utc)
    assert run(order_queue_service._acknowledge_target_once(snapshot, DRIVER_ID)) is True
    assert announcements == [
        (DRIVER_ID, SHIFT_ID, 2),
        (DRIVER_ID, SHIFT_ID, 2),
    ]


def test_concurrent_target_updates_announce_once(monkeypatch):
    stored = {}
    announcements = []
    snapshot = {
        "shift_id": SHIFT_ID,
        "target": 2,
        "counts": {"completed": 2},
        "orders": [],
    }

    async def get_preference(driver_id, key):
        await asyncio.sleep(0)
        return stored.get(key)

    async def set_marker(driver_id, marker):
        await asyncio.sleep(0)
        stored["_daily_delivery_target_acknowledged"] = marker
        return True

    async def announce(driver_id, shift_id, target):
        announcements.append((driver_id, shift_id, target))
        return 1

    async def race():
        return await asyncio.gather(
            order_queue_service._acknowledge_target_once(snapshot, DRIVER_ID),
            order_queue_service._acknowledge_target_once(snapshot, DRIVER_ID),
        )

    monkeypatch.setattr(order_queue_service.preference_service, "get_preference", get_preference)
    monkeypatch.setattr(order_queue_service.preference_service, "set_target_acknowledged", set_marker)
    monkeypatch.setattr(voice, "announce_target_reached", announce)
    monkeypatch.setattr(order_queue_service, "datetime", FixedDateTime)
    FixedDateTime.current = datetime(2026, 9, 24, tzinfo=timezone.utc)

    assert run(race()) == [True, False]
    assert announcements == [(DRIVER_ID, SHIFT_ID, 2)]


def test_status_rest_route_emits_queue_update(monkeypatch):
    notifications = []
    row = delivery(1, "pending", delivery_id=DELIVERY_ID, shift_id=SHIFT_ID)

    async def get_delivery(delivery_id):
        return row

    async def mark(delivery_id, status, failure_reason, notes):
        return {**row, "status": status}

    async def event(**kwargs):
        return {}

    async def notify(shift_id, driver_id):
        notifications.append((shift_id, driver_id))

    monkeypatch.setattr(delivery_routes, "get_delivery_by_id", get_delivery)
    monkeypatch.setattr(delivery_routes, "mark_delivery_status", mark)
    monkeypatch.setattr(delivery_routes, "create_delivery_event", event)
    monkeypatch.setattr(delivery_routes, "notify_queue_changed", notify)

    request = delivery_routes.DeliveryStatusUpdate(status="delivered")
    result = run(delivery_routes.update_delivery_status_endpoint(
        DELIVERY_ID, request, {"id": DRIVER_ID}
    ))

    assert result["status"] == "delivered"
    assert notifications == [(SHIFT_ID, DRIVER_ID)]


def test_voice_completion_targets_current_lowest_pending_and_emits(monkeypatch):
    notifications = []
    marked = []
    active = delivery(2, "pending", delivery_id=DELIVERY_ID, shift_id=SHIFT_ID)

    async def next_pending(shift_id, driver_id):
        return active

    async def mark(delivery_id, status, failure_reason, notes):
        marked.append((delivery_id, status))
        return {**active, "status": status}

    async def event(**kwargs):
        return {}

    async def attempts(delivery_id):
        return {}

    async def notify(shift_id, driver_id):
        notifications.append((shift_id, driver_id))

    monkeypatch.setattr("app.db.queries.get_next_pending_delivery", next_pending)
    monkeypatch.setattr("app.db.queries.mark_delivery_status", mark)
    monkeypatch.setattr("app.db.queries.create_delivery_event", event)
    monkeypatch.setattr("app.db.queries.increment_delivery_attempts", attempts)
    monkeypatch.setattr(order_queue_service, "notify_queue_changed", notify)

    result = run(delivery_tools.update_delivery_status(
        {"status": "delivered"},
        {
            "driver_id": DRIVER_ID,
            "shift_id": SHIFT_ID,
            "current_delivery": {"id": "stale-delivery", "status": "pending"},
        },
    ))

    assert result["success"] is True
    assert marked == [(DELIVERY_ID, "delivered")]
    assert notifications == [(SHIFT_ID, DRIVER_ID)]


def test_target_voice_tool_emits_queue_update(monkeypatch):
    notifications = []

    async def save(driver_id, key, value):
        return True

    async def notify(driver_id, shift_id=None):
        notifications.append((driver_id, shift_id))

    monkeypatch.setattr(preference_tools.preference_service, "set_preference", save)
    monkeypatch.setattr(order_queue_service, "notify_active_queue_changed", notify)

    result = run(preference_tools.set_preference(
        {"key": "daily_delivery_target", "value": "15"},
        {"driver_id": DRIVER_ID, "shift_id": SHIFT_ID},
    ))

    assert result["success"] is True
    assert notifications == [(DRIVER_ID, SHIFT_ID)]


class _Adapter:
    async def order_assigned(self, order, delivery_id, driver_id):
        return None

    async def stop_order_feed(self):
        return None


class _Hub:
    def live_shifts(self):
        return {}

    async def close_offer(self, shift_id, order_id, outcome):
        return None


def test_order_acceptance_including_auto_accept_emits_queue_update(monkeypatch):
    notifications = []
    dispatcher = OrderDispatcher(_Adapter(), hub=_Hub(), feed_enabled=False)
    order = IncomingOrder(
        source="mock",
        external_id="order-1",
        recipient_name="Priya",
        address="1 Main St",
        latitude=30.0,
        longitude=-97.0,
    )
    candidate = Candidate(DRIVER_ID, SHIFT_ID, "Driver", 1.0)
    dispatcher._orders[DELIVERY_ID] = OpenOrder(
        DELIVERY_ID, order, "offered", offered_to=candidate
    )

    async def db(query, *args):
        return {"id": DELIVERY_ID, "sequence_order": 3, "status": "pending"}

    async def notify(shift_id, driver_id):
        notifications.append((shift_id, driver_id))

    monkeypatch.setattr(order_dispatch, "_db", db)
    monkeypatch.setattr(order_dispatch, "notify_queue_changed", notify)

    async def scenario():
        result = await dispatcher.accept(DRIVER_ID, SHIFT_ID, DELIVERY_ID)
        await asyncio.sleep(0)
        await dispatcher.stop()
        return result

    result = run(scenario())

    assert result["success"] is True
    assert notifications == [(SHIFT_ID, DRIVER_ID)]


def test_pod_and_geofence_status_paths_emit_queue_updates(monkeypatch):
    notifications = []
    row = delivery(
        1,
        "pending",
        delivery_id=DELIVERY_ID,
        shift_id=SHIFT_ID,
        latitude=30.0,
        longitude=-97.0,
    )

    async def get_delivery(delivery_id):
        return row

    async def next_pending(shift_id, driver_id):
        return row

    async def mark(*args, **kwargs):
        return {**row, "status": args[1]}

    async def event(**kwargs):
        return {}

    async def notify(shift_id, driver_id):
        notifications.append((shift_id, driver_id))

    class PodTable:
        def insert(self, data):
            return self

        def execute(self):
            return SimpleNamespace(data=[{"id": "pod-1"}])

    class PodDb:
        def table(self, name):
            return PodTable()

    monkeypatch.setattr(pod_routes, "get_delivery_by_id", get_delivery)
    monkeypatch.setattr(pod_routes, "mark_delivery_status", mark)
    monkeypatch.setattr(pod_routes, "create_delivery_event", event)
    monkeypatch.setattr(pod_routes, "get_supabase", lambda: PodDb())
    monkeypatch.setattr(pod_routes, "notify_queue_changed", notify)

    run(pod_routes.upload_proof_of_delivery(
        DELIVERY_ID, 30.0, -97.0, None, None, None, {"id": DRIVER_ID}
    ))

    monkeypatch.setattr("app.db.queries.get_next_pending_delivery", next_pending)
    monkeypatch.setattr("app.db.queries.mark_delivery_status", mark)
    monkeypatch.setattr("app.db.queries.create_delivery_event", event)
    monkeypatch.setattr(order_queue_service, "notify_queue_changed", notify)

    events = run(location_module.location_service.process_location_update(
        DRIVER_ID, SHIFT_ID, 30.0, -97.0, speed=2.0
    ))

    assert "DRIVER_ARRIVED" in events
    assert notifications == [(SHIFT_ID, DRIVER_ID), (SHIFT_ID, DRIVER_ID)]
