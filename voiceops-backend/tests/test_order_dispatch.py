"""
Tests for new-order dispatch: the MockAdapter order feed, nearest-driver offers, accept /
decline / timeout, the voice relay speaking an offer unprompted, and the Order Intake API.

Supabase is an in-memory table store that runs the real queries in app/db/queries.py.
AssemblyAI is test_voice_ws.py's scripted fake upstream.
"""
import asyncio
import os
import itertools
import json
import random
import re
import time
import uuid
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.agents.tool_registry import TOOL_EXECUTORS, execute_tool, get_tools
from app.api.routes.logistics import sign_body
from app.api.websocket import events, voice
from app.config import settings
from app.dispatch import order_dispatch
from app.dispatch.order_dispatch import OrderDispatcher
from app.integrations.logistics import DEMO_AREA_CENTER, IncomingOrder, MockAdapter, address_area
from app.main import app
from app.models.schemas import OrderCreatedEvent
from app.utils.geo import haversine_km
from tests.test_voice_ws import (  # noqa: F401  (backend / upstream are fixtures)
    AUTH, DRIVER_ID, SHIFT_ID, WS_PATH, backend, client, collect_until, connect_and_greet,
    finish_turn, is_event, next_frame, upstream,
)

# Drivers: the demo driver downtown, two more about 5 km out, and one off shift
REAL = {"driver_id": DRIVER_ID, "shift_id": SHIFT_ID, "name": "Emeka Okafor", "at": (30.2672, -97.7431)}
MARIA = {"driver_id": "d1000000-0000-4000-8000-000000000001", "shift_id": "51000000-0000-4000-8000-000000000001",
         "name": "Maria Gonzalez", "at": (30.2990, -97.7035)}
BEN = {"driver_id": "d1000000-0000-4000-8000-000000000002", "shift_id": "51000000-0000-4000-8000-000000000002",
       "name": "Ben Carter", "at": (30.2350, -97.7830)}
OFF_SHIFT = {"driver_id": "d1000000-0000-4000-8000-000000000003", "shift_id": "51000000-0000-4000-8000-000000000003",
             "name": "Olu Bello", "at": (30.2700, -97.7450)}


def make_order(external_id="MLX-TEST-1", at=(30.2713, -97.7455)):
    return IncomingOrder(source="mock-logistics", external_id=external_id, recipient_name="Priya Patel",
                         address="812 Lavaca St, Apt 3B, Austin, TX 78701", latitude=at[0], longitude=at[1],
                         recipient_phone="+15125550142", notes="Leave with the front desk.",
                         time_window="3:00 PM – 5:00 PM", package_count=2)


# ---------------------------------------------------------------------------- fakes


class FakeQuery:
    """Enough of the PostgREST query builder for app/db/queries.py."""

    def __init__(self, store, table):
        self.store, self.table = store, table
        self.op, self.payload, self.columns = "select", None, "*"
        self.filters, self.ordering, self.row_limit = [], None, None

    def select(self, columns="*"):
        self.op, self.columns = "select", columns
        return self

    def insert(self, row):
        self.op, self.payload = "insert", row
        return self

    def update(self, values):
        self.op, self.payload = "update", values
        return self

    def eq(self, column, value):
        self.filters.append(lambda r: r.get(column) == value)
        return self

    def is_(self, column, value):
        assert value == "null"
        self.filters.append(lambda r: r.get(column) is None)
        return self

    def in_(self, column, values):
        values = list(values)
        self.filters.append(lambda r: r.get(column) in values)
        return self

    def order(self, column, desc=False, nullsfirst=None):
        self.ordering = (column, desc)
        return self

    def limit(self, n):
        self.row_limit = n
        return self

    def execute(self):
        rows = self.store.tables.setdefault(self.table, [])
        if self.store.fail:
            raise RuntimeError("supabase down")
        if self.op == "insert":
            row = {"id": str(uuid.uuid4()), "created_at": next(self.store.clock), **self.payload}
            rows.append(row)
            return SimpleNamespace(data=[dict(row)])
        matched = [r for r in rows if all(f(r) for f in self.filters)]
        if self.op == "update":
            for r in matched:
                r.update(self.payload)
            return SimpleNamespace(data=[dict(r) for r in matched])
        if self.ordering:
            column, desc = self.ordering
            present = sorted((r for r in matched if r.get(column) is not None),
                             key=lambda r: r[column], reverse=desc)
            matched = present + [r for r in matched if r.get(column) is None]  # nulls last
        if self.row_limit is not None:
            matched = matched[:self.row_limit]
        out = [dict(r) for r in matched]
        if "drivers(name)" in self.columns:
            names = {d["id"]: d["name"] for d in self.store.tables.get("drivers", [])}
            for r in out:
                r["drivers"] = {"name": names[r["driver_id"]]} if r["driver_id"] in names else None
        return SimpleNamespace(data=out)


class FakeStore:
    def __init__(self):
        self.tables = {}
        self.clock = itertools.count(1)
        self.fail = False

    def table(self, name):
        return FakeQuery(self, name)

    def rows(self, name):
        return self.tables.setdefault(name, [])

    def add_driver(self, driver, ping=True, active=True, old_ping_at=None):
        self.rows("drivers").append({"id": driver["driver_id"], "name": driver["name"]})
        self.rows("shifts").append({"id": driver["shift_id"], "driver_id": driver["driver_id"],
                                    "status": "active" if active else "completed",
                                    "started_at": "2026-09-01T08:00:00+00:00"})
        if old_ping_at:
            self.rows("location_pings").append({"shift_id": driver["shift_id"], "latitude": old_ping_at[0],
                                                "longitude": old_ping_at[1], "pinged_at": "2026-09-01T09:00:00+00:00"})
        if ping:
            self.rows("location_pings").append({"shift_id": driver["shift_id"], "latitude": driver["at"][0],
                                                "longitude": driver["at"][1], "pinged_at": "2026-09-01T10:00:00+00:00"})

    def delivery(self, order_id):
        return next(r for r in self.rows("deliveries") if r["id"] == order_id)


class FakeHub:
    def __init__(self, live=None):
        self.live = dict(live or {})
        self.offers, self.closed = [], []

    def live_shifts(self):
        return dict(self.live)

    async def present_offer(self, shift_id, offer):
        self.offers.append((shift_id, offer))
        return 1 if shift_id in self.live else 0

    async def close_offer(self, shift_id, order_id, outcome):
        self.closed.append((shift_id, order_id, outcome))


def online(*drivers):
    """A hub where these drivers have an open voice socket."""
    return FakeHub(live={d["shift_id"]: d["driver_id"] for d in drivers})


@pytest.fixture
def store(monkeypatch):
    fake = FakeStore()
    monkeypatch.setattr("app.db.queries.get_supabase", lambda: fake)
    return fake


@pytest.fixture
def adapter():
    return MockAdapter(180, 420, rng=random.Random(3))


def dispatcher_with(adapter, hub, **kwargs):
    return OrderDispatcher(adapter, hub=hub, feed_enabled=False, **{"offer_window": 30, **kwargs})


def run(coro):
    return asyncio.run(coro)


# ---------------------------------------------------------------------------- deployment boundary


def test_production_uses_one_worker_for_process_local_dispatch_state():
    """The offer queue and voice-session hub cannot be split across Uvicorn workers."""
    procfile = (Path(__file__).parents[1] / "Procfile").read_text()
    assert re.search(r"(?:^|\s)--workers(?:=|\s+)1(?:\s|$)", procfile), (
        "OrderDispatcher._orders and the voice-session registry are process-local; "
        "multiple workers can retain competing copies of an open order."
    )


def test_offer_state_is_per_dispatcher_so_a_second_worker_cannot_accept_it(store, adapter):
    """Two dispatchers stand in for two uvicorn workers: each has its own offer queue."""
    store.add_driver(REAL)
    worker_a = dispatcher_with(adapter, online(REAL))
    worker_b = dispatcher_with(adapter, FakeHub())

    async def scenario():
        placed = await worker_a.ingest(make_order())
        on_b = await worker_b.accept(REAL["driver_id"], REAL["shift_id"], placed["order_id"])
        on_a = await worker_a.accept(REAL["driver_id"], REAL["shift_id"], placed["order_id"])
        await worker_a.stop()
        await worker_b.stop()
        return on_b, on_a

    on_b, on_a = run(scenario())
    assert on_b["success"] is False and "No order is waiting" in on_b["error"]
    assert on_a["success"] is True


# ---------------------------------------------------------------------------- mock order feed


def test_feed_interval_is_jittered_within_bounds():
    adapter = MockAdapter(180, 420, rng=random.Random(11))
    gaps = [adapter.next_interval() for _ in range(500)]
    assert all(180 <= g <= 420 for g in gaps)
    assert len(set(gaps)) == 500           # not a fixed timer
    assert min(gaps) < 200 and max(gaps) > 400  # spans the range


def test_feed_rejects_an_inverted_range():
    with pytest.raises(ValueError):
        MockAdapter(420, 180)


def test_feed_waits_before_the_first_order_and_between_every_order():
    log = []

    async def sleep(seconds):
        log.append(("sleep", seconds))
        if len([e for e in log if e[0] == "sleep"]) > 5:
            raise asyncio.CancelledError

    async def on_order(order):
        log.append(("order", order.external_id))

    adapter = MockAdapter(180, 420, rng=random.Random(5), sleep=sleep)
    with pytest.raises(asyncio.CancelledError):
        run(adapter.run_feed(on_order, lambda: True))

    assert log[0][0] == "sleep"  # never an order the moment the feed starts
    kinds = [kind for kind, _ in log]
    assert "order,order" not in ",".join(kinds)  # no two orders without a wait between
    assert kinds.count("order") == 5
    assert all(180 <= s <= 420 for kind, s in log if kind == "sleep")


def test_feed_makes_no_order_while_nobody_could_take_one():
    orders, sleeps = [], []

    async def sleep(seconds):
        sleeps.append(seconds)
        if len(sleeps) > 3:
            raise asyncio.CancelledError

    async def on_order(order):
        orders.append(order)

    with pytest.raises(asyncio.CancelledError):
        run(MockAdapter(1, 2, sleep=sleep).run_feed(on_order, lambda: False))
    assert orders == [] and len(sleeps) == 4


def test_feed_pauses_for_lapsed_offers_but_not_for_declines(store, adapter):
    store.add_driver(REAL)
    hub = FakeHub()
    dispatcher = dispatcher_with(adapter, hub, max_open_orders=2)

    async def scenario():
        assert dispatcher.should_generate() is False  # nobody online
        hub.live[REAL["shift_id"]] = REAL["driver_id"]
        assert dispatcher.should_generate() is True
        for n in range(3):  # the driver says no to every one: the feed keeps going
            await dispatcher.ingest(make_order(f"D{n}"))
            await dispatcher.decline(REAL["driver_id"])
        still_going = dispatcher.should_generate()
        dispatcher.offer_window = 0.01  # now they stop answering: two lapse and stay in play
        for n in range(2):
            await dispatcher.ingest(make_order(f"L{n}"))
            await asyncio.sleep(0.05)
        paused = dispatcher.should_generate()
        await dispatcher.stop()
        return still_going, paused

    assert run(scenario()) == (True, False)


def test_generated_order_is_an_order_intake_payload_in_the_demo_area(adapter):
    for _ in range(40):
        payload = adapter.build_order_event()
        order = IncomingOrder.from_event(OrderCreatedEvent.model_validate(json.loads(json.dumps(payload))))
        assert payload["event"] == "order.created" and payload["source"] == "mock-logistics"
        assert re.fullmatch(r"MLX-\d{8}-[A-Z0-9]{6}", order.external_id)
        assert haversine_km(*DEMO_AREA_CENTER, order.latitude, order.longitude) < 3.0
        assert "Austin, TX" in order.address and "Lagos" not in json.dumps(payload)
        assert re.fullmatch(r"\+151255501\d\d", order.recipient_phone)  # fictional 555-01xx
        assert re.fullmatch(r"\d{1,2}:\d\d [AP]M – \d{1,2}:\d\d [AP]M", order.time_window)
        assert not re.match(r"\d", order.area)


def test_address_area_drops_house_number_and_unit():
    assert address_area("1301 E 7th St, Apt 2, Austin, TX 78702") == "E 7th St, Austin"
    assert address_area("72 Rainey St, Austin, TX 78701") == "Rainey St, Austin"
    assert address_area("Suite 210, 501 Brazos St, Austin") == "Brazos St, Austin"


# ---------------------------------------------------------------------------- nearest driver


def test_order_goes_to_the_nearest_active_driver_by_latest_ping(store, adapter):
    store.add_driver(REAL)
    store.add_driver(MARIA, old_ping_at=(30.2713, -97.7455))  # used to be on top of the drop-off
    store.add_driver(BEN)
    store.add_driver(OFF_SHIFT, active=False)                  # nearest of all, but off shift
    hub = online(REAL, MARIA, BEN, OFF_SHIFT)
    dispatcher = dispatcher_with(adapter, hub)

    async def scenario():
        result = await dispatcher.ingest(make_order())
        await dispatcher.stop()
        return result

    result = run(scenario())
    assert result["status"] == "offered" and result["duplicate"] is False
    shift_id, offer = hub.offers[0]
    assert shift_id == REAL["shift_id"]
    assert offer["distance_km"] == pytest.approx(haversine_km(*REAL["at"], 30.2713, -97.7455), abs=0.01)
    row = store.delivery(result["order_id"])
    assert row["shift_id"] is None and row["status"] == "offered"
    assert (row["source"], row["external_id"], row["phone"]) == ("mock-logistics", "MLX-TEST-1", "+15125550142")


def test_ranking_is_straight_line_distance(store, adapter):
    for driver in (REAL, MARIA, BEN):
        store.add_driver(driver)
    dispatcher = dispatcher_with(adapter, online(REAL, MARIA, BEN))
    near_ben = make_order(at=(30.2400, -97.7800))
    ranked = run(dispatcher._candidates(near_ben, exclude=set()))
    assert [c.driver_id for c in ranked] == [BEN["driver_id"], REAL["driver_id"], MARIA["driver_id"]]
    assert ranked == sorted(ranked, key=lambda c: c.distance_km)


def test_online_driver_without_a_ping_stands_at_the_demo_centre(store, adapter):
    store.add_driver(REAL, ping=False)
    ranked = run(dispatcher_with(adapter, online(REAL))._candidates(make_order(), exclude=set()))
    assert [c.driver_id for c in ranked] == [REAL["driver_id"]]
    assert ranked[0].distance_km == pytest.approx(haversine_km(*DEMO_AREA_CENTER, 30.2713, -97.7455), abs=0.01)


def test_drivers_without_an_open_session_are_never_offered(store, adapter):
    """Captain's rule: the co-rider can only tell a driver whose voice session is open."""
    store.add_driver(REAL)
    store.add_driver(MARIA, old_ping_at=(30.2713, -97.7455))
    hub = online(REAL)
    dispatcher = dispatcher_with(adapter, hub)

    async def scenario():
        await dispatcher.ingest(make_order())
        declined = await dispatcher.decline(REAL["driver_id"])
        await dispatcher.stop()
        return declined

    declined = run(scenario())
    assert [shift for shift, _ in hub.offers] == [REAL["shift_id"]]  # never Maria, who is offline
    assert declined["passed_to"] is None and declined["status"] == "unassigned"
    assert run(dispatcher_with(adapter, FakeHub())._candidates(make_order(), set())) == []


def test_stale_pings_are_ignored_when_a_max_age_is_set(store, adapter):
    store.add_driver(MARIA)  # ping from 2026-09-01, long before "now"
    dispatcher = dispatcher_with(adapter, online(MARIA), ping_max_age_minutes=5)
    [maria] = run(dispatcher._candidates(make_order(), set()))
    assert maria.distance_km == pytest.approx(haversine_km(*DEMO_AREA_CENTER, 30.2713, -97.7455), abs=0.01)


def test_a_driver_holding_an_offer_gets_no_second_offer(store, adapter):
    store.add_driver(REAL)
    store.add_driver(MARIA)
    hub = online(REAL, MARIA)
    dispatcher = dispatcher_with(adapter, hub)

    async def scenario():
        await dispatcher.ingest(make_order("A"))
        await dispatcher.ingest(make_order("B"))
        await dispatcher.stop()

    run(scenario())
    assert [shift for shift, _ in hub.offers] == [REAL["shift_id"], MARIA["shift_id"]]


def test_order_intake_is_idempotent(store, adapter):
    store.add_driver(REAL)
    dispatcher = dispatcher_with(adapter, online(REAL))

    async def scenario():
        first = await dispatcher.ingest(make_order())
        again = await dispatcher.ingest(make_order())
        await dispatcher.stop()
        # A fresh process finds it in the database instead
        later = await dispatcher_with(adapter, online(REAL)).ingest(make_order())
        return first, again, later

    first, again, later = run(scenario())
    assert again == {**first, "duplicate": True}
    assert later["order_id"] == first["order_id"] and later["duplicate"] is True
    assert len(store.rows("deliveries")) == 1


def test_order_with_nobody_online_waits_unassigned(store, adapter):
    store.add_driver(REAL)  # on shift with a ping, but the app is closed
    hub = FakeHub()
    result = run(dispatcher_with(adapter, hub).ingest(make_order()))
    assert result["status"] == "unassigned" and hub.offers == []
    assert store.delivery(result["order_id"])["status"] == "unassigned"
    assert adapter.writebacks[-1]["unassigned"] == order_dispatch.NOBODY_FREE


def test_database_down_is_dispatch_unavailable(store, adapter):
    store.fail = True
    with pytest.raises(order_dispatch.DispatchUnavailable):
        run(dispatcher_with(adapter, FakeHub()).ingest(make_order()))


# ---------------------------------------------------------------------------- accept / decline / timeout


def test_accept_puts_the_order_on_the_drivers_shift_as_pending(store, adapter):
    store.add_driver(REAL)
    store.rows("deliveries").append({"id": "existing", "shift_id": REAL["shift_id"], "status": "pending",
                                     "sequence_order": 3})
    hub = online(REAL)
    dispatcher = dispatcher_with(adapter, hub)

    async def scenario():
        placed = await dispatcher.ingest(make_order())
        result = await dispatcher.accept(REAL["driver_id"], REAL["shift_id"])  # no order_id: the offered one
        await dispatcher.stop()
        return placed, result

    placed, result = run(scenario())
    assert result["success"] is True and result["sequence"] == 4 and result["status"] == "pending"
    assert result["order_id"] == result["delivery_id"] == placed["order_id"]
    row = store.delivery(placed["order_id"])
    assert (row["shift_id"], row["status"], row["sequence_order"]) == (REAL["shift_id"], "pending", 4)
    assert hub.closed == [(REAL["shift_id"], placed["order_id"], "accepted")]
    assert adapter.writebacks[-1] == {"external_id": "MLX-TEST-1", "delivery_id": placed["order_id"],
                                      "assigned_to": REAL["driver_id"]}
    assert dispatcher.next_order_for(REAL["driver_id"]) is None
    assert "phone" not in result and "+1512" not in json.dumps(result)


def _enable_auto_accept(monkeypatch, driver_id, max_order_distance_km=None):
    """Make `_maybe_auto_accept` see this driver as opted in, without touching Supabase."""
    from app.services import preference_service as preference_service_module
    from app.services.preference_models import EnhancedPreferences

    basic_prefs = {"auto_accept_orders": "true"}
    if max_order_distance_km is not None:
        basic_prefs["max_order_distance_km"] = max_order_distance_km

    async def fake_get_preferences(for_driver_id):
        return basic_prefs if for_driver_id == driver_id else {}

    async def fake_get_enhanced_preferences(for_driver_id):
        return EnhancedPreferences()

    monkeypatch.setattr(preference_service_module.preference_service, "get_preferences", fake_get_preferences)
    monkeypatch.setattr(preference_service_module.preference_service, "get_enhanced_preferences",
                        fake_get_enhanced_preferences)


def _fake_alert_service(monkeypatch):
    """Stand in for ProactiveAlertService so a test can see what `_maybe_auto_accept` would
    have told the driver, without a real Supabase table or voice socket."""
    import app.services.proactive_alert_service as alert_service_module

    calls = []

    class FakeAlertService:
        async def emit_voice_alert(self, **kwargs):
            calls.append(kwargs)
            return True

    monkeypatch.setattr(alert_service_module, "ProactiveAlertService", FakeAlertService)
    return calls


def test_auto_accept_takes_the_order_and_announces_it_unprompted(monkeypatch, store, adapter):
    """Captain's ask: never silent. The driver didn't ask, so the co-rider must say so out loud."""
    calls = _fake_alert_service(monkeypatch)
    store.add_driver(REAL)
    _enable_auto_accept(monkeypatch, REAL["driver_id"])
    hub = online(REAL)
    dispatcher = dispatcher_with(adapter, hub)

    async def scenario():
        placed = await dispatcher.ingest(make_order())
        await dispatcher.stop()
        return placed

    placed = run(scenario())
    row = store.delivery(placed["order_id"])
    assert (row["shift_id"], row["status"]) == (REAL["shift_id"], "pending")  # taken, not just offered
    assert hub.offers and hub.offers[0][0] == REAL["shift_id"]  # the offer was still shown...
    assert hub.closed == [(REAL["shift_id"], placed["order_id"], "accepted")]  # ...then closed at once

    [call] = calls
    assert call["driver_id"] == REAL["driver_id"] and call["shift_id"] == REAL["shift_id"]
    assert call["delivery_id"] == placed["order_id"]
    assert "812 Lavaca St" in call["message"]  # reuses accept()'s own message, not new wording
    assert "812 Lavaca St" in call["spoken_instructions"]
    assert "did not ask" in call["spoken_instructions"]  # told the agent this must be unprompted


def test_auto_accept_respects_the_drivers_max_distance_preference(monkeypatch, store, adapter):
    """A distance cap the driver set must actually be enforced, not silently ignored."""
    calls = _fake_alert_service(monkeypatch)
    store.add_driver(REAL)  # ~0.5 km from make_order()'s drop-off
    _enable_auto_accept(monkeypatch, REAL["driver_id"], max_order_distance_km="0.05")
    hub = online(REAL)
    dispatcher = dispatcher_with(adapter, hub)

    async def scenario():
        placed = await dispatcher.ingest(make_order())
        await dispatcher.stop()
        return placed

    placed = run(scenario())
    row = store.delivery(placed["order_id"])
    assert row["shift_id"] is None and row["status"] == "offered"  # too far: falls through to a manual offer
    assert calls == []


def test_auto_accepted_order_cannot_be_declined_back_to_the_pool(store, adapter):
    """
    Known gap (see PR description): decline_order only knows about orders still in the
    dispatcher's offer queue. Once accepted (auto or manual) the order becomes a plain
    delivery row and decline() can no longer find it, so it cannot be handed to another driver.
    """
    store.add_driver(REAL)
    hub = online(REAL)
    dispatcher = dispatcher_with(adapter, hub)

    async def scenario():
        placed = await dispatcher.ingest(make_order())
        accepted = await dispatcher.accept(REAL["driver_id"], REAL["shift_id"], placed["order_id"])
        declined = await dispatcher.decline(REAL["driver_id"], placed["order_id"])
        await dispatcher.stop()
        return accepted, declined

    accepted, declined = run(scenario())
    assert accepted["success"] is True
    assert declined == {"success": False, "error": "No order is offered to you right now."}


def test_accepted_delivery_cannot_go_straight_to_rescheduled(store, adapter):
    """
    Known gap (see PR description): the delivery state machine has no `pending` -> `rescheduled`
    transition, so a driver backing out of an auto-accepted stop must mark it `failed` first;
    there is no one-step "give this back" action for an already-accepted order.
    """
    from app.services.delivery_state_machine import assert_transition

    with pytest.raises(ValueError):
        assert_transition("pending", "rescheduled")
    assert_transition("pending", "failed")  # the actual path a driver has today
    assert_transition("failed", "rescheduled")


def test_accept_of_an_order_assigned_elsewhere_is_withdrawn(store, adapter):
    store.add_driver(REAL)
    hub = online(REAL)
    dispatcher = dispatcher_with(adapter, hub)

    async def scenario():
        placed = await dispatcher.ingest(make_order())
        store.delivery(placed["order_id"]).update(shift_id="another-shift", status="pending")
        result = await dispatcher.accept(REAL["driver_id"], REAL["shift_id"])
        await dispatcher.stop()
        return placed, result

    placed, result = run(scenario())
    assert result == {"success": False, "error": "Someone else already took that order."}
    assert hub.closed == [(REAL["shift_id"], placed["order_id"], "withdrawn")]
    assert store.delivery(placed["order_id"])["shift_id"] == "another-shift"


def test_only_the_offered_driver_can_accept(store, adapter):
    store.add_driver(REAL)
    store.add_driver(MARIA)
    dispatcher = dispatcher_with(adapter, online(REAL, MARIA))

    async def scenario():
        placed = await dispatcher.ingest(make_order())
        refused = await dispatcher.accept(MARIA["driver_id"], MARIA["shift_id"], placed["order_id"])
        nothing = await dispatcher.decline(MARIA["driver_id"])
        await dispatcher.stop()
        return placed, refused, nothing

    placed, refused, nothing = run(scenario())
    assert refused["success"] is False and "another driver" in refused["error"]
    assert nothing["success"] is False
    assert store.delivery(placed["order_id"])["shift_id"] is None


def test_accept_failure_logs_order_shift_and_reason(store, adapter, caplog):
    dispatcher = dispatcher_with(adapter, FakeHub())

    with caplog.at_level("WARNING", logger="app.dispatch.order_dispatch"):
        result = run(dispatcher.accept(REAL["driver_id"], REAL["shift_id"], "missing-order"))

    assert result["success"] is False
    assert (
        f"[Dispatch] accept_failed order_id=missing-order shift_id={REAL['shift_id']} "
        f"reason=no_matching_order pid={os.getpid()}"
    ) in caplog.messages


def test_decline_failure_logs_order_shift_and_reason(store, adapter, caplog):
    dispatcher = dispatcher_with(adapter, FakeHub())

    with caplog.at_level("WARNING", logger="app.dispatch.order_dispatch"):
        result = run(dispatcher.decline(
            REAL["driver_id"], "missing-order", shift_id=REAL["shift_id"]
        ))

    assert result["success"] is False
    assert (
        f"[Dispatch] decline_failed order_id=missing-order shift_id={REAL['shift_id']} "
        f"reason=no_matching_offer pid={os.getpid()}"
    ) in caplog.messages


def test_decline_cascades_to_the_next_nearest_then_parks(store, adapter):
    for driver in (REAL, MARIA, BEN):
        store.add_driver(driver)
    hub = online(REAL, MARIA, BEN)
    dispatcher = dispatcher_with(adapter, hub)

    async def scenario():
        placed = await dispatcher.ingest(make_order())
        first = await dispatcher.decline(REAL["driver_id"], reason="Too far")
        second = await dispatcher.decline(MARIA["driver_id"], placed["order_id"])
        last = await dispatcher.decline(BEN["driver_id"])
        after = await dispatcher.decline(BEN["driver_id"])
        await dispatcher.stop()
        return placed, first, second, last, after

    placed, first, second, last, after = run(scenario())
    order_id = placed["order_id"]
    # Lavaca St: Maria (5.1 km north-east) is nearer than Ben (5.4 km south-west)
    assert [shift for shift, _ in hub.offers] == [REAL["shift_id"], MARIA["shift_id"], BEN["shift_id"]]
    assert first["success"] and first["status"] == "offered"
    assert first["passed_to"] == {"driver_name": "Maria", "distance_km": 5.07}
    assert first["message"] == "Declined. Passed it to Maria, 5.1 km from the drop-off."
    assert second["passed_to"]["driver_name"] == "Ben"
    assert last["passed_to"] is None and last["status"] == "unassigned"
    assert "unassigned queue" in last["message"]
    assert after["success"] is False
    assert [outcome for _, _, outcome in hub.closed] == ["declined"] * 3
    row = store.delivery(order_id)
    assert row["shift_id"] is None and row["status"] == "unassigned"
    assert adapter.writebacks[-1]["unassigned"] == order_dispatch.EVERYONE_PASSED


def test_an_unanswered_offer_expires_to_the_next_driver(store, adapter):
    store.add_driver(REAL)
    store.add_driver(BEN)
    hub = online(REAL, BEN)
    dispatcher = dispatcher_with(adapter, hub, offer_window=0.05)

    async def scenario():
        placed = await dispatcher.ingest(make_order())
        await asyncio.sleep(0.03)
        assert hub.closed == []  # still inside the window
        await asyncio.sleep(0.05)
        offered_second = list(hub.offers)
        await asyncio.sleep(0.1)  # Ben lets it lapse too
        await dispatcher.stop()
        return placed, offered_second

    placed, offered_second = run(scenario())
    assert [shift for shift, _ in offered_second] == [REAL["shift_id"], BEN["shift_id"]]
    assert hub.closed == [(REAL["shift_id"], placed["order_id"], "expired"),
                          (BEN["shift_id"], placed["order_id"], "expired")]
    assert store.delivery(placed["order_id"])["status"] == "unassigned"


def test_accept_after_the_offer_expired_is_refused(store, adapter):
    store.add_driver(REAL)
    store.add_driver(BEN)
    dispatcher = dispatcher_with(adapter, online(REAL, BEN), offer_window=0.02)

    async def scenario():
        placed = await dispatcher.ingest(make_order())
        dispatcher.offer_window = 30  # Ben, next in line, holds his offer
        await asyncio.sleep(0.06)
        result = await dispatcher.accept(REAL["driver_id"], REAL["shift_id"], placed["order_id"])
        await dispatcher.stop()
        return result

    result = run(scenario())
    assert result["success"] is False


def test_unassigned_orders_are_offered_when_a_driver_comes_online(store, adapter):
    store.add_driver(REAL, ping=False)
    hub = FakeHub()
    dispatcher = dispatcher_with(adapter, hub)

    async def scenario():
        placed = await dispatcher.ingest(make_order())
        assert placed["status"] == "unassigned"
        hub.live[REAL["shift_id"]] = REAL["driver_id"]
        await dispatcher.driver_available(REAL["driver_id"], REAL["shift_id"])
        await dispatcher.stop()
        return placed

    placed = run(scenario())
    assert hub.offers[0][0] == REAL["shift_id"]
    assert store.delivery(placed["order_id"])["status"] == "offered"


def test_startup_reloads_open_orders_as_unassigned(store, adapter):
    store.rows("deliveries").extend([
        {"id": "o1", "shift_id": None, "status": "offered", "source": "mock-logistics", "external_id": "MLX-1",
         "recipient_name": "Priya Patel", "address": "72 Rainey St, Austin, TX 78701",
         "latitude": 30.259, "longitude": -97.7385, "created_at": 1},
        {"id": "o2", "shift_id": "s", "status": "pending", "latitude": 30.26, "longitude": -97.74, "created_at": 2},
    ])
    dispatcher = dispatcher_with(adapter, FakeHub())
    run(dispatcher.start())
    assert list(dispatcher._orders) == ["o1"]
    assert store.delivery("o1")["status"] == "unassigned"
    assert dispatcher.next_order_for("anyone")["external_id"] == "MLX-1"


# ---------------------------------------------------------------------------- tools


def test_order_tools_are_registered():
    tools = {t["name"]: t for t in get_tools()}
    for name in ("accept_order", "decline_order"):
        assert tools[name]["parameters"]["required"] == []
        assert "order_id" in tools[name]["parameters"]["properties"]
        assert name in TOOL_EXECUTORS
        assert events.step_for_tool(name) != f"Running {name.replace('_', ' ')}"
    assert set(tools) == set(TOOL_EXECUTORS)


def test_get_next_order_reads_the_live_queue(store, adapter, monkeypatch):
    store.add_driver(REAL)
    dispatcher = dispatcher_with(adapter, online(REAL))
    monkeypatch.setattr(order_dispatch, "_dispatcher", dispatcher)
    context = {"driver_id": REAL["driver_id"], "shift_id": REAL["shift_id"]}

    async def scenario():
        empty = await execute_tool("get_next_order", {}, context)
        placed = await dispatcher.ingest(make_order())
        offered = await execute_tool("get_next_order", {}, context)
        accepted = await execute_tool("accept_order", {"order_id": placed["order_id"]}, context)
        await dispatcher.stop()
        return empty, placed, offered, accepted

    empty, placed, offered, accepted = run(scenario())
    assert empty == {"success": True, "has_next": False, "message": "No new orders are waiting right now."}
    assert offered["has_next"] and offered["offered_to_you"] and offered["order_id"] == placed["order_id"]
    assert offered["external_id"] == "MLX-TEST-1" and offered["sequence_order"] is None
    assert 0 < offered["expires_in_s"] <= 30
    assert accepted["success"] and accepted["sequence"] == 1


def test_order_tools_need_a_driver_session():
    assert run(execute_tool("accept_order", {}, {}))["success"] is False
    assert run(execute_tool("decline_order", {}, {}))["success"] is False


def test_accept_tool_failure_logs_order_shift_and_reason(caplog):
    context = {"driver_id": REAL["driver_id"], "shift_id": REAL["shift_id"]}

    with caplog.at_level("WARNING", logger="app.agents.tools.delivery"):
        result = run(execute_tool("accept_order", {"order_id": "missing-order"}, context))

    assert result["success"] is False
    assert (
        f"[Tool:accept_order] accept_failed order_id=missing-order shift_id={REAL['shift_id']} "
        "reason=dispatcher_rejected detail='No order is waiting for you right now.'"
    ) in caplog.messages


# ---------------------------------------------------------------------------- voice relay


@pytest.fixture
def live_dispatch(store, adapter, monkeypatch):
    """The real voice hub over the in-memory store, with the demo driver on shift downtown."""
    store.add_driver(REAL)
    dispatcher = OrderDispatcher(adapter, feed_enabled=False, offer_window=30)
    monkeypatch.setattr(order_dispatch, "_dispatcher", dispatcher)
    monkeypatch.setattr(voice, "REPLY_GRACE", 0.2)
    monkeypatch.setattr(voice, "ANNOUNCE_POLL", 0.02)
    return dispatcher


class OtherDriverSession:
    """A second driver's open voice socket, as the relay's session registry sees it."""

    def __init__(self, driver):
        self.driver_id = driver["driver_id"]
        self.offers, self.closed = [], []

    async def present_offer(self, offer):
        self.offers.append(offer)

    async def close_offer(self, order_id, outcome):
        self.closed.append((order_id, outcome))


def second_driver_online(store, driver=MARIA):
    store.add_driver(driver)
    session = OtherDriverSession(driver)
    voice._sessions[driver["shift_id"]] = {session}
    return session


def reply_creates(upstream):
    return upstream.sent_of("reply.create")


def offer_and_announce(ws, upstream, dispatcher, order=None):
    seen_announcements = len(reply_creates(upstream))
    placed = ws.portal.call(dispatcher.ingest, order or make_order())
    offer = next(f for f in collect_until(ws, is_event("order_offer")) if is_event("order_offer")(f))
    deadline = time.monotonic() + 3
    while len(reply_creates(upstream)) <= seen_announcements and time.monotonic() < deadline:
        time.sleep(0.01)
    assert len(reply_creates(upstream)) > seen_announcements
    return placed, offer


def test_offer_is_shown_and_spoken_without_the_driver_asking(upstream, live_dispatch):
    with client.websocket_connect(WS_PATH, headers=AUTH) as ws:
        connect_and_greet(ws, upstream)
        placed, offer = offer_and_announce(ws, upstream, live_dispatch)
        ws.portal.call(live_dispatch.stop)

    assert offer["order_id"] == placed["order_id"]
    assert offer["area"] == "Lavaca St, Austin"
    assert (offer["latitude"], offer["longitude"]) == (30.271, -97.746)  # ~100 m, not the door
    assert offer["time_window"] == "3:00 PM – 5:00 PM" and 0 < offer["expires_in_s"] <= 30
    assert "812" not in json.dumps(offer) and "+1512" not in json.dumps(offer)
    assert "Priya" not in json.dumps(offer)

    [create] = reply_creates(upstream)
    assert placed["order_id"] in create["instructions"]
    assert "Lavaca St, Austin" in create["instructions"]
    assert "accept_order" in create["instructions"] and "decline_order" in create["instructions"]


def test_offer_waits_until_the_agent_and_driver_are_quiet(upstream, live_dispatch):
    with client.websocket_connect(WS_PATH, headers=AUTH) as ws:
        connect_and_greet(ws, upstream)
        upstream.push({"type": "reply.started", "reply_id": "r1"})
        time.sleep(0.1)
        ws.portal.call(live_dispatch.ingest, make_order())
        collect_until(ws, is_event("order_offer"))
        time.sleep(0.4)
        assert reply_creates(upstream) == []  # the agent is mid-reply

        # The driver barges in, which ends the agent's reply
        upstream.push({"type": "input.speech.started"},
                      {"type": "reply.done", "reply_id": "r1", "status": "interrupted"})
        time.sleep(0.4)
        assert reply_creates(upstream) == []  # now the driver is talking

        upstream.push({"type": "input.speech.stopped"})
        time.sleep(0.1)
        assert reply_creates(upstream) == []  # their turn gets its reply first
        upstream.wait_sent(lambda m: m["type"] == "reply.create")  # nothing came: speak up
        ws.portal.call(live_dispatch.stop)


def test_offer_on_connect_waits_for_the_greeting(upstream, live_dispatch, monkeypatch):
    monkeypatch.setattr(voice, "REPLY_GRACE", 2.0)
    with client.websocket_connect(WS_PATH, headers=AUTH) as ws:
        upstream.wait_sent(lambda m: m["type"] == "session.update")
        ws.portal.call(live_dispatch.ingest, make_order())
        collect_until(ws, is_event("order_offer"))
        time.sleep(0.3)
        assert reply_creates(upstream) == []  # the greeting is due first
        connect_and_greet(ws, upstream)
        upstream.wait_sent(lambda m: m["type"] == "reply.create")
        ws.portal.call(live_dispatch.stop)


def test_driver_accepts_the_offer_by_voice(upstream, live_dispatch, store):
    with client.websocket_connect(WS_PATH, headers=AUTH) as ws:
        connect_and_greet(ws, upstream)
        placed, _ = offer_and_announce(ws, upstream, live_dispatch)
        upstream.push({"type": "reply.started"}, {"type": "transcript.agent", "text": "New order on Lavaca."},
                      {"type": "reply.done", "status": "completed"})
        collect_until(ws, is_event("reply_done"))

        upstream.push({"type": "transcript.user", "text": "Yes, I'll take it"},
                      {"type": "tool.call", "call_id": "c1", "name": "accept_order", "arguments": {}})
        frames = collect_until(ws, is_event("task_step", step="Accepting the order", status="done"))
        result = finish_turn(ws, upstream, "c1")
        ws.portal.call(live_dispatch.stop)

    assert events.order_offer_closed(placed["order_id"], "accepted") in frames
    assert result["success"] is True and result["delivery_id"] == placed["order_id"]
    row = store.delivery(placed["order_id"])
    assert (row["shift_id"], row["status"]) == (SHIFT_ID, "pending")
    assert len(reply_creates(upstream)) == 1  # nothing more announced


def test_driver_accepts_second_offer_by_voice_after_finishing_first(upstream, live_dispatch, store):
    with client.websocket_connect(WS_PATH, headers=AUTH) as ws:
        connect_and_greet(ws, upstream)
        first, _ = offer_and_announce(ws, upstream, live_dispatch)
        upstream.push({"type": "reply.done", "status": "completed"},
                      {"type": "tool.call", "call_id": "c1", "name": "accept_order", "arguments": {}})
        first_result = finish_turn(ws, upstream, "c1")
        store.delivery(first["order_id"])["status"] = "delivered"

        second, _ = offer_and_announce(ws, upstream, live_dispatch, make_order("MLX-TEST-2"))
        upstream.push({"type": "reply.done", "status": "completed"},
                      {"type": "tool.call", "call_id": "c2", "name": "accept_order", "arguments": {}})
        second_result = finish_turn(ws, upstream, "c2")
        ws.portal.call(live_dispatch.stop)

    assert first_result["success"] is True
    assert second_result["success"] is True and second_result["delivery_id"] == second["order_id"]
    assert store.delivery(second["order_id"])["sequence_order"] == 2


def test_accepted_order_can_be_navigated_to(upstream, live_dispatch, backend):
    with client.websocket_connect(WS_PATH, headers=AUTH) as ws:
        connect_and_greet(ws, upstream)
        placed, _ = offer_and_announce(ws, upstream, live_dispatch)
        upstream.push({"type": "reply.done", "status": "completed"},
                      {"type": "tool.call", "call_id": "c1", "name": "accept_order", "arguments": {}})
        finish_turn(ws, upstream, "c1")
        upstream.push({"type": "reply.done", "status": "completed"},
                      {"type": "tool.call", "call_id": "c2", "name": "start_navigation",
                       "arguments": {"delivery_id": placed["order_id"]}})
        frames = collect_until(ws, is_event("map_route"))
        ws.portal.call(live_dispatch.stop)
    assert frames[-1]["stops"][0]["address"] == "812 Lavaca St, Apt 3B, Austin, TX 78701"


def test_driver_declines_and_the_order_moves_to_the_next_driver(upstream, live_dispatch, store):
    maria = second_driver_online(store)
    with client.websocket_connect(WS_PATH, headers=AUTH) as ws:
        connect_and_greet(ws, upstream)
        placed, _ = offer_and_announce(ws, upstream, live_dispatch)
        upstream.push({"type": "reply.done", "status": "completed"},
                      {"type": "transcript.user", "text": "No, pass"},
                      {"type": "tool.call", "call_id": "c1", "name": "decline_order", "arguments": {}})
        frames = collect_until(ws, is_event("task_step", step="Passing the order on", status="done"))
        result = finish_turn(ws, upstream, "c1")
        ws.portal.call(live_dispatch.stop)

    assert events.order_offer_closed(placed["order_id"], "declined") in frames
    assert result["passed_to"]["driver_name"] == "Maria"
    row = store.delivery(placed["order_id"])
    assert row["shift_id"] is None and row["status"] == "offered"
    assert live_dispatch._orders[placed["order_id"]].offered_to.driver_id == MARIA["driver_id"]
    assert [o["order_id"] for o in maria.offers] == [placed["order_id"]]


def test_driver_accepts_the_offer_by_tap(upstream, live_dispatch, store):
    with client.websocket_connect(WS_PATH, headers=AUTH) as ws:
        connect_and_greet(ws, upstream)
        placed, _ = offer_and_announce(ws, upstream, live_dispatch)
        upstream.push({"type": "reply.done", "status": "completed"})
        collect_until(ws, is_event("reply_done"))

        ws.send_json({"event": "accept_order", "order_id": placed["order_id"]})
        frames = collect_until(ws, is_event("task_step", step="Accepting the order", status="done"))
        # The co-rider asked about it, so it hears the tap settled it
        [confirm] = upstream.wait_sent(lambda m: m["type"] == "reply.create" and "tapping" in m["instructions"])
        ws.portal.call(live_dispatch.stop)

    assert events.order_offer_closed(placed["order_id"], "accepted") in frames
    assert not any(is_event("error")(f) for f in frames)
    row = store.delivery(placed["order_id"])
    assert (row["shift_id"], row["status"]) == (SHIFT_ID, "pending")
    assert "accepted" in confirm["instructions"] and "812 Lavaca St" in confirm["instructions"]
    assert upstream.sent_of("tool.result") == []  # FastAPI ran the handler; no LLM tool call


def test_driver_accepts_second_offer_by_tap_after_finishing_first(upstream, live_dispatch, store):
    with client.websocket_connect(WS_PATH, headers=AUTH) as ws:
        connect_and_greet(ws, upstream)
        first, _ = offer_and_announce(ws, upstream, live_dispatch)
        upstream.push({"type": "reply.done", "status": "completed"},
                      {"type": "tool.call", "call_id": "c1", "name": "accept_order", "arguments": {}})
        first_result = finish_turn(ws, upstream, "c1")
        store.delivery(first["order_id"])["status"] = "delivered"

        second, _ = offer_and_announce(ws, upstream, live_dispatch, make_order("MLX-TEST-2"))
        upstream.push({"type": "reply.done", "status": "completed"})
        collect_until(ws, is_event("reply_done"))
        ws.send_json({"event": "accept_order", "order_id": second["order_id"]})
        frames = collect_until(ws, is_event("task_step", step="Accepting the order", status="done"))
        upstream.wait_sent(lambda m: m["type"] == "reply.create" and "accepted" in m["instructions"])
        ws.portal.call(live_dispatch.stop)

    assert first_result["success"] is True
    assert events.order_offer_closed(second["order_id"], "accepted") in frames
    assert store.delivery(second["order_id"])["sequence_order"] == 2
    assert upstream.sent_of("tool.result") == [
        m for m in upstream.sent_of("tool.result") if m["call_id"] == "c1"
    ]


def test_driver_declines_the_offer_by_tap_and_it_moves_on(upstream, live_dispatch, store):
    maria = second_driver_online(store)
    with client.websocket_connect(WS_PATH, headers=AUTH) as ws:
        connect_and_greet(ws, upstream)
        placed, _ = offer_and_announce(ws, upstream, live_dispatch)
        upstream.push({"type": "reply.done", "status": "completed"})
        collect_until(ws, is_event("reply_done"))

        ws.send_json({"event": "decline_order", "order_id": placed["order_id"]})
        frames = collect_until(ws, is_event("task_step", step="Passing the order on", status="done"))
        upstream.wait_sent(lambda m: m["type"] == "reply.create" and "declined" in m["instructions"])
        ws.portal.call(live_dispatch.stop)

    assert events.order_offer_closed(placed["order_id"], "declined") in frames
    assert [o["order_id"] for o in maria.offers] == [placed["order_id"]]
    assert upstream.sent_of("tool.result") == []


def test_tap_on_an_offer_not_yet_spoken_says_nothing(upstream, live_dispatch, monkeypatch):
    monkeypatch.setattr(voice, "REPLY_GRACE", 1.0)
    with client.websocket_connect(WS_PATH, headers=AUTH) as ws:
        upstream.wait_sent(lambda m: m["type"] == "session.update")
        placed = ws.portal.call(live_dispatch.ingest, make_order())
        collect_until(ws, is_event("order_offer"))  # the greeting is due, so it waits unspoken
        ws.send_json({"event": "accept_order", "order_id": placed["order_id"]})
        frames = collect_until(ws, is_event("task_step", step="Accepting the order", status="done"))
        connect_and_greet(ws, upstream)
        time.sleep(0.3)
        ws.portal.call(live_dispatch.stop)

    assert events.order_offer_closed(placed["order_id"], "accepted") in frames
    assert reply_creates(upstream) == []  # neither the offer nor the tap is announced


def test_tap_on_an_order_taken_elsewhere_closes_it_without_an_error(upstream, live_dispatch, store):
    with client.websocket_connect(WS_PATH, headers=AUTH) as ws:
        connect_and_greet(ws, upstream)
        placed, _ = offer_and_announce(ws, upstream, live_dispatch)
        store.delivery(placed["order_id"]).update(shift_id="another-shift", status="pending")

        ws.send_json({"event": "accept_order", "order_id": placed["order_id"]})
        frames = collect_until(ws, is_event("task_step", step="Accepting the order", status="done"))
        ws.portal.call(live_dispatch.stop)

    assert events.order_offer_closed(placed["order_id"], "withdrawn") in frames
    assert not any(is_event("error")(f) for f in frames)  # the card's closed note says why


def test_failed_tap_reports_an_error_and_keeps_the_offer_open(upstream, live_dispatch, store):
    with client.websocket_connect(WS_PATH, headers=AUTH) as ws:
        connect_and_greet(ws, upstream)
        placed, _ = offer_and_announce(ws, upstream, live_dispatch)
        store.fail = True
        ws.send_json({"event": "accept_order", "order_id": placed["order_id"]})
        frames = collect_until(ws, is_event("error"))
        still_offered_to = live_dispatch._orders[placed["order_id"]].offered_to  # before the socket closes
        store.fail = False
        ws.portal.call(live_dispatch.stop)

    assert frames[-1] == events.error("internal", "Couldn't reach the order system. Try accepting again.")
    assert not any(is_event("order_offer_closed")(f) for f in frames)
    assert still_offered_to.driver_id == REAL["driver_id"]


def test_offer_moves_on_when_its_driver_disconnects(upstream, live_dispatch, store):
    maria = second_driver_online(store)
    with client.websocket_connect(WS_PATH, headers=AUTH) as ws:
        connect_and_greet(ws, upstream)
        placed, _ = offer_and_announce(ws, upstream, live_dispatch)
        portal = ws.portal
        ws.close()
        deadline = time.monotonic() + 3
        while not maria.offers and time.monotonic() < deadline:
            time.sleep(0.02)
        portal.call(live_dispatch.stop)
    assert [o["order_id"] for o in maria.offers] == [placed["order_id"]]
    assert live_dispatch._orders[placed["order_id"]].passed_over == set()  # leaving isn't declining


def test_expired_offer_closes_the_card_and_the_agent_says_so(upstream, live_dispatch):
    live_dispatch.offer_window = 0.5
    with client.websocket_connect(WS_PATH, headers=AUTH) as ws:
        connect_and_greet(ws, upstream)
        placed, _ = offer_and_announce(ws, upstream, live_dispatch)
        upstream.push({"type": "reply.done", "status": "completed"})
        frames = collect_until(ws, is_event("order_offer_closed"), timeout=3.0)
        upstream.wait_sent(lambda m: m["type"] == "reply.create" and "timed out" in m["instructions"])
        ws.portal.call(live_dispatch.stop)
    assert frames[-1] == events.order_offer_closed(placed["order_id"], "expired")


def test_offer_that_expires_before_it_was_spoken_is_never_announced(upstream, live_dispatch):
    live_dispatch.offer_window = 0.3
    with client.websocket_connect(WS_PATH, headers=AUTH) as ws:
        connect_and_greet(ws, upstream)
        upstream.push({"type": "reply.started"})  # a long reply holds the floor
        time.sleep(0.1)
        ws.portal.call(live_dispatch.ingest, make_order())
        collect_until(ws, is_event("order_offer_closed"), timeout=3.0)
        upstream.push({"type": "reply.done", "status": "completed"})
        time.sleep(0.5)
        ws.portal.call(live_dispatch.stop)
    assert reply_creates(upstream) == []


def test_connecting_driver_is_offered_the_waiting_queue(upstream, live_dispatch, store):
    store.rows("location_pings").clear()  # nobody placeable until the socket opens
    placed = run(live_dispatch.ingest(make_order()))
    assert placed["status"] == "unassigned"
    with client.websocket_connect(WS_PATH, headers=AUTH) as ws:
        frames = collect_until(ws, is_event("order_offer"))
        ws.portal.call(live_dispatch.stop)
    assert frames[-1]["order_id"] == placed["order_id"]


def test_offer_events_follow_the_contract_vocabulary():
    with pytest.raises(ValueError):
        events.order_offer_closed("o1", "cancelled")


# ---------------------------------------------------------------------------- Order Intake API

SECRET = "test-webhook-secret"


def post_order(payload, secret=SECRET, signature=None):
    body = json.dumps(payload).encode()
    headers = {"Content-Type": "application/json"}
    if secret is not None or signature is not None:
        headers["X-VoiceOps-Signature"] = signature or sign_body(body, secret)
    return client.post("/v1/logistics/orders", content=body, headers=headers)


@pytest.fixture
def intake(store, adapter, monkeypatch):
    monkeypatch.setattr(settings, "logistics_webhook_secret", SECRET)
    dispatcher = dispatcher_with(adapter, online(REAL))
    monkeypatch.setattr(order_dispatch, "_dispatcher", dispatcher)
    return dispatcher


def test_order_intake_route_is_mounted():
    assert "/v1/logistics/orders" in {getattr(route, "path", None) for route in app.routes}


def test_order_intake_is_off_without_a_secret(monkeypatch, adapter):
    monkeypatch.setattr(settings, "logistics_webhook_secret", None)
    assert post_order(adapter.build_order_event()).status_code == 503


def test_order_intake_rejects_a_bad_signature(intake, adapter):
    payload = adapter.build_order_event()
    assert post_order(payload, secret=None).status_code == 401
    assert post_order(payload, secret="wrong-secret").status_code == 401
    assert post_order(payload, signature="sha256=deadbeef").status_code == 401


def test_order_intake_accepts_a_signed_order(intake, store, adapter):
    store.add_driver(REAL)
    payload = adapter.build_order_event()
    response = post_order(payload)
    assert response.status_code == 202
    body = response.json()
    assert body["external_id"] == payload["external_id"]
    assert body["status"] == "offered" and body["duplicate"] is False
    row = store.delivery(body["order_id"])
    assert row["address"] == payload["order"]["dropoff"]["address"] and row["shift_id"] is None

    again = post_order(payload)
    assert again.status_code == 202 and again.json()["duplicate"] is True
    assert len(store.rows("deliveries")) == 1


def test_order_intake_validates_the_payload(intake, adapter):
    payload = adapter.build_order_event()
    del payload["order"]["dropoff"]["latitude"]
    assert post_order(payload).status_code == 422
    assert post_order({**adapter.build_order_event(), "event": "order.cancelled"}).status_code == 422


def test_order_intake_reports_a_database_outage(intake, store, adapter):
    store.fail = True
    assert post_order(adapter.build_order_event()).status_code == 503


# ---------------------------------------------------------------------------- app startup


def test_app_startup_runs_the_order_feed_end_to_end(store, monkeypatch):
    """Lifespan starts the dispatcher; the feed's orders reach a driver through the database."""
    store.add_driver(REAL)
    hub = FakeHub(live={REAL["shift_id"]: REAL["driver_id"]})
    dispatcher = OrderDispatcher(MockAdapter(0.01, 0.02), hub=hub, feed_enabled=True,
                                 offer_window=30, max_open_orders=2)
    monkeypatch.setattr(order_dispatch, "_dispatcher", None)
    monkeypatch.setattr(order_dispatch, "OrderDispatcher", lambda adapter: dispatcher)

    with TestClient(app):
        deadline = time.monotonic() + 3
        while len(store.rows("deliveries")) < 2 and time.monotonic() < deadline:
            time.sleep(0.02)
        time.sleep(0.1)
        rows = list(store.rows("deliveries"))

    # The feed stops at max_open_orders; the one driver holds one offer, the other order waits
    assert len(rows) == 2
    assert sorted(r["status"] for r in rows) == ["offered", "unassigned"]
    assert all(r["source"] == "mock-logistics" and r["shift_id"] is None for r in rows)
    assert hub.offers[0][0] == REAL["shift_id"]
    assert dispatcher.adapter._feed is None  # shutdown stopped it


def test_mock_adapter_nearby_coordinate_generation():
    from app.integrations.logistics.mock_adapter import generate_nearby_coordinate
    from app.utils.geo import haversine_km

    center = (31.47477, 73.16320)
    for _ in range(20):
        lat, lng = generate_nearby_coordinate(center[0], center[1], min_dist_km=0.5, max_dist_km=2.5)
        dist = haversine_km(center[0], center[1], lat, lng)
        assert 0.49 <= dist <= 2.51


def test_mock_adapter_build_order_with_custom_center():
    from app.integrations.logistics.mock_adapter import MockAdapter
    from app.utils.geo import haversine_km

    adapter = MockAdapter(10, 20)
    center = (51.5074, -0.1278)  # London
    event = adapter.build_order_event(center=center, address="Baker Street, London")
    order = event["order"]
    assert "Baker Street" in order["dropoff"]["address"]
    dist = haversine_km(center[0], center[1], order["dropoff"]["latitude"], order["dropoff"]["longitude"])
    assert 0.49 <= dist <= 2.51
