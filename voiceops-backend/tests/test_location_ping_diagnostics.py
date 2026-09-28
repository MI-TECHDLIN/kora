"""Location-ping acceptance, rejection, and value-free health diagnostics."""

import asyncio
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi.testclient import TestClient

from app.api.routes import locations
from app.dependencies import get_current_driver
from app.dispatch import order_dispatch
from app.dispatch.ping_diagnostics import ping_diagnostics, reset_ping_diagnostics
from app.db import queries
from app.main import app
from app.services import risk_engine


DRIVER_ID = "10000000-0000-4000-8000-000000000001"
OTHER_DRIVER_ID = "20000000-0000-4000-8000-000000000002"
SHIFT_ID = "30000000-0000-4000-8000-000000000003"
PING = {"latitude": 30.2672, "longitude": -97.7431}


@pytest.fixture(autouse=True)
def reset_diagnostics():
    reset_ping_diagnostics()
    yield
    reset_ping_diagnostics()


@pytest.fixture
def client():
    app.dependency_overrides[get_current_driver] = lambda: {"id": DRIVER_ID}
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.pop(get_current_driver, None)


def test_missing_auth_and_bad_payload_are_counted_before_the_route(client):
    app.dependency_overrides.pop(get_current_driver, None)
    unauthenticated = client.post("/v1/locations/ping", json=PING)
    app.dependency_overrides[get_current_driver] = lambda: {"id": DRIVER_ID}
    invalid = client.post("/v1/locations/ping", json={"latitude": 999, "longitude": 0})

    diag = ping_diagnostics()
    assert unauthenticated.status_code == 401
    assert invalid.status_code == 422
    assert diag["ping_received"] == 2
    assert diag["ping_rejected"] == 2
    assert diag["ping_rejections"]["no_auth"] == 1
    assert diag["ping_rejections"]["bad_payload"] == 1


@pytest.mark.parametrize(
    ("shift", "status_code", "reason"),
    [
        (None, 404, "shift_not_found"),
        ({"id": SHIFT_ID, "driver_id": OTHER_DRIVER_ID, "status": "active"}, 404, "not_owner"),
        ({"id": SHIFT_ID, "driver_id": DRIVER_ID, "status": "completed"}, 409, "shift_not_active"),
    ],
)
def test_unusable_shift_is_rejected_with_a_value_free_reason(
    monkeypatch, client, shift, status_code, reason,
):
    monkeypatch.setattr(locations, "get_shift_by_id", AsyncMock(return_value=shift))
    save = AsyncMock()
    monkeypatch.setattr(locations, "save_location_ping", save)

    response = client.post("/v1/locations/ping", json={**PING, "shift_id": SHIFT_ID})

    assert response.status_code == status_code
    assert ping_diagnostics()["ping_rejections"][reason] == 1
    save.assert_not_awaited()


def test_omitted_shift_id_resolves_the_drivers_active_shift_and_is_accepted(monkeypatch, client):
    monkeypatch.setattr(
        locations,
        "get_active_shift_for_driver",
        AsyncMock(return_value={"id": SHIFT_ID, "driver_id": DRIVER_ID, "status": "active"}),
    )
    save = AsyncMock(return_value={"id": "ping-row"})
    monkeypatch.setattr(locations, "save_location_ping", save)
    monkeypatch.setattr(locations, "update_driver_location", AsyncMock(return_value={}))
    monkeypatch.setattr(
        locations.location_service, "process_location_update", AsyncMock(return_value=[]),
    )
    monkeypatch.setattr(risk_engine.risk_engine, "evaluate", AsyncMock(return_value=[]))
    monkeypatch.setattr(
        "app.db.queries.get_next_pending_delivery", AsyncMock(return_value=None),
    )
    ping_hook = SimpleNamespace(location_ping=lambda driver_id: None)
    monkeypatch.setattr(order_dispatch, "get_order_dispatcher", lambda: ping_hook)

    response = client.post("/v1/locations/ping", json=PING)

    assert response.status_code == 200
    assert response.json()["success"] is True
    assert save.await_args.kwargs["shift_id"] == SHIFT_ID
    diag = ping_diagnostics()
    assert diag["ping_received"] == 1
    assert diag["ping_accepted"] == 1
    assert diag["ping_rejected"] == 0
    assert diag["last_ping_received_at"] is not None
    assert diag["last_ping_accepted_at"] is not None
    assert diag["last_accepted_ping_shift_active"] is True


def test_insert_failure_is_rejected_and_counted_by_exception_class(monkeypatch, client, caplog):
    monkeypatch.setattr(
        locations,
        "get_shift_by_id",
        AsyncMock(return_value={"id": SHIFT_ID, "driver_id": DRIVER_ID, "status": "active"}),
    )
    monkeypatch.setattr(
        locations, "save_location_ping", AsyncMock(side_effect=RuntimeError("database details")),
    )

    response = client.post("/v1/locations/ping", json={**PING, "shift_id": SHIFT_ID})

    assert response.status_code == 503
    diag = ping_diagnostics()
    assert diag["ping_accepted"] == 0
    assert diag["ping_rejections"]["storage_error"] == 1
    assert diag["ping_storage_error_types"] == {"RuntimeError": 1}
    assert "error_type=RuntimeError" in caplog.text
    assert "database details" not in caplog.text


def test_location_insert_uses_schema_columns_and_database_timestamp(monkeypatch):
    inserted = []

    class Query:
        def insert(self, row):
            inserted.append(row)
            return self

        def execute(self):
            return SimpleNamespace(data=[{"id": "ping-row", **inserted[-1]}])

    class Supabase:
        def table(self, name):
            assert name == "location_pings"
            return Query()

    monkeypatch.setattr(queries, "get_supabase", lambda: Supabase())

    result = asyncio.run(queries.save_location_ping(
        DRIVER_ID, SHIFT_ID, PING["latitude"], PING["longitude"],
        speed=20, heading=90, accuracy=5,
    ))

    assert result["id"] == "ping-row"
    assert inserted == [{
        "driver_id": DRIVER_ID,
        "shift_id": SHIFT_ID,
        "latitude": PING["latitude"],
        "longitude": PING["longitude"],
    }]
