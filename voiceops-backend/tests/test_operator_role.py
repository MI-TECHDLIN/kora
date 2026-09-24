"""
Tests for operator-role gating on fleet and location routes.

A driver token (no role claim) must receive 403 on every route gated by
get_current_operator.  A token with app_metadata.role == "operator" must get the
normal response (200).

These tests run offline: Supabase auth is replaced by a fake that reads the token
value, and DB calls return minimal stubs so the route bodies do not blow up.
"""
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

DRIVER_TOKEN = "driver-token"
OPERATOR_TOKEN = "operator-token"
DRIVER_HEADERS = {"Authorization": f"Bearer {DRIVER_TOKEN}"}
OPERATOR_HEADERS = {"Authorization": f"Bearer {OPERATOR_TOKEN}"}


class FakeAuth:
    def get_user(self, token: str):
        if token == DRIVER_TOKEN:
            user = {"id": "d-driver-001", "app_metadata": {}, "user_metadata": {"name": "Test Driver"}}
        elif token == OPERATOR_TOKEN:
            user = {"id": "d-operator-001", "app_metadata": {"role": "operator"}, "user_metadata": {"name": "Test Operator"}}
        else:
            raise Exception("invalid token")
        return SimpleNamespace(user=SimpleNamespace(model_dump=lambda: user))


class _FakeQuery:
    def __init__(self, name):
        self._name = name
    def select(self, *a, **kw):
        return self
    def eq(self, *a, **kw):
        return self
    def order(self, *a, **kw):
        return self
    def limit(self, *a, **kw):
        return self
    def execute(self):
        return SimpleNamespace(data=[])


class FakeSupabase:
    auth = FakeAuth()
    def table(self, name):
        return _FakeQuery(name)


@pytest.fixture(autouse=True)
def stub_supabase(monkeypatch):
    fake = FakeSupabase()
    monkeypatch.setattr("app.dependencies.get_supabase_client", lambda: fake)
    monkeypatch.setattr("app.db.queries.get_supabase", lambda: fake)
    from app.agents import dispatcher_agent as _da
    async def _snapshot():
        return {"active_drivers_count": 0, "active_shifts_count": 0, "open_deliveries_count": 0, "unresolved_alerts_count": 0, "timestamp": "2026-09-24T00:00:00Z"}
    async def _risk(snapshot):
        return []
    monkeypatch.setattr(_da.dispatcher_agent, "get_fleet_snapshot", _snapshot)
    monkeypatch.setattr(_da.dispatcher_agent, "evaluate_fleet_risk", _risk)


class TestFleetDriverRole:
    def test_overview_rejects_driver(self):
        assert client.get("/v1/fleet/overview", headers=DRIVER_HEADERS).status_code == 403
    def test_overview_allows_operator(self):
        assert client.get("/v1/fleet/overview", headers=OPERATOR_HEADERS).status_code == 200
    def test_drivers_list_rejects_driver(self):
        assert client.get("/v1/fleet/drivers", headers=DRIVER_HEADERS).status_code == 403
    def test_drivers_list_allows_operator(self):
        assert client.get("/v1/fleet/drivers", headers=OPERATOR_HEADERS).status_code == 200
    def test_incidents_rejects_driver(self):
        assert client.get("/v1/fleet/incidents", headers=DRIVER_HEADERS).status_code == 403
    def test_incidents_allows_operator(self):
        assert client.get("/v1/fleet/incidents", headers=OPERATOR_HEADERS).status_code == 200
    def test_analytics_rejects_driver(self):
        assert client.get("/v1/fleet/analytics", headers=DRIVER_HEADERS).status_code == 403
    def test_analytics_allows_operator(self):
        assert client.get("/v1/fleet/analytics", headers=OPERATOR_HEADERS).status_code == 200
    def test_unauthenticated_fleet_is_401(self):
        assert client.get("/v1/fleet/drivers").status_code == 401


class TestFleetDriversPhoneNotExposed:
    def test_phone_absent_from_drivers_response(self, monkeypatch):
        class _PhoneQuery(_FakeQuery):
            def execute(self):
                return SimpleNamespace(data=[{"id": "d1", "name": "Test Driver", "phone": "+15125551234", "status": "active"}])
        class _PhoneSupa(FakeSupabase):
            def table(self, name):
                return _PhoneQuery(name)
        monkeypatch.setattr("app.db.queries.get_supabase", lambda: _PhoneSupa())
        r = client.get("/v1/fleet/drivers", headers=OPERATOR_HEADERS)
        assert r.status_code == 200
        for driver in r.json().get("drivers", []):
            assert "phone" not in driver


DRIVER_UUID = "d0000000-0000-4000-8000-000000000001"


class TestLocationDriverRole:
    def test_location_rejects_driver(self, monkeypatch):
        monkeypatch.setattr("app.api.routes.locations.is_valid_uuid", lambda uid: True)
        async def _mock_driver(driver_id):
            return {"id": driver_id, "name": "Emeka"}
        monkeypatch.setattr("app.api.routes.locations.get_driver_by_id", _mock_driver)
        assert client.get(f"/v1/drivers/{DRIVER_UUID}/location", headers=DRIVER_HEADERS).status_code == 403

    def test_location_allows_operator(self, monkeypatch):
        monkeypatch.setattr("app.api.routes.locations.is_valid_uuid", lambda uid: True)
        async def _mock_driver(driver_id):
            return {"id": driver_id, "name": "Emeka"}
        monkeypatch.setattr("app.api.routes.locations.get_driver_by_id", _mock_driver)
        assert client.get(f"/v1/drivers/{DRIVER_UUID}/location", headers=OPERATOR_HEADERS).status_code == 200

    def test_history_rejects_driver(self, monkeypatch):
        monkeypatch.setattr("app.api.routes.locations.is_valid_uuid", lambda uid: True)
        async def _mock_pings(driver_id, limit=50):
            return []
        monkeypatch.setattr("app.api.routes.locations.get_recent_location_pings", _mock_pings)
        assert client.get(f"/v1/drivers/{DRIVER_UUID}/history", headers=DRIVER_HEADERS).status_code == 403

    def test_history_allows_operator(self, monkeypatch):
        monkeypatch.setattr("app.api.routes.locations.is_valid_uuid", lambda uid: True)
        async def _mock_pings(driver_id, limit=50):
            return []
        monkeypatch.setattr("app.api.routes.locations.get_recent_location_pings", _mock_pings)
        assert client.get(f"/v1/drivers/{DRIVER_UUID}/history", headers=OPERATOR_HEADERS).status_code == 200


class TestOnboardAuth:
    def test_onboard_without_token_is_401(self, monkeypatch):
        monkeypatch.setattr("app.integrations.n8n_client.trigger_driver_onboarding_background", lambda **kw: None)
        assert client.post("/v1/driver/onboard", json={}).status_code == 401
    def test_onboard_with_driver_token_succeeds(self, monkeypatch):
        monkeypatch.setattr("app.integrations.n8n_client.trigger_driver_onboarding_background", lambda **kw: None)
        r = client.post("/v1/driver/onboard", json={}, headers=DRIVER_HEADERS)
        assert r.status_code == 200
        assert r.json()["status"] == "success"
        assert "phone" not in r.json()
