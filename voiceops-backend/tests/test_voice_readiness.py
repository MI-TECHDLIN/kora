"""
GET /health/ready and the classification of voice-session failures.

The readiness report must say which settings the voice path needs are present and whether the
upstream AssemblyAI session and the database work, and it must never carry a setting value.
"""
import asyncio
import json

import pytest
import websockets
from fastapi.testclient import TestClient
from websockets.datastructures import Headers
from websockets.http11 import Response

from app.config import settings
from app.main import app
from app.services import voice_readiness

client = TestClient(app)

API_KEY = "aai-secret-key-do-not-leak"
SUPABASE_URL = "https://secret-project.supabase.co"
SERVICE_KEY = "service-role-secret-do-not-leak"


class FakeUpstream:
    def __init__(self, reply=None):
        self.reply = reply or {"type": "session.ready", "session_id": "s-1"}
        self.sent = []
        self.closed = False

    async def send(self, text):
        self.sent.append(json.loads(text))

    async def recv(self):
        return json.dumps(self.reply)

    async def close(self):
        self.closed = True


class FakeQuery:
    def __init__(self, error=None):
        self.error = error

    def table(self, name):
        return self

    def select(self, *args):
        return self

    def limit(self, n):
        return self

    def execute(self):
        if self.error:
            raise self.error
        return object()


@pytest.fixture(autouse=True)
def configured(monkeypatch):
    voice_readiness.reset_readiness_cache()
    monkeypatch.setattr(settings, "assemblyai_api_key", API_KEY)
    monkeypatch.setattr(settings, "assemblyai_agent_id", None)
    monkeypatch.setattr(settings, "supabase_url", SUPABASE_URL)
    monkeypatch.setattr(settings, "supabase_service_key", SERVICE_KEY)
    monkeypatch.setattr("app.db.client.get_supabase_client", lambda: FakeQuery())
    yield
    voice_readiness.reset_readiness_cache()


def patch_connect(monkeypatch, result):
    """`websockets.connect` in the readiness module: return `result`, or raise it if an exception."""
    calls = []

    async def connect(url, **kwargs):
        calls.append((url, kwargs))
        if isinstance(result, BaseException):
            raise result
        return result

    monkeypatch.setattr(voice_readiness.websockets, "connect", connect)
    return calls


def invalid_status(code):
    return websockets.exceptions.InvalidStatus(Response(code, "Denied", Headers(), b""))


def test_ready_when_everything_works(monkeypatch):
    upstream = FakeUpstream()
    calls = patch_connect(monkeypatch, upstream)

    response = client.get("/health/ready")

    assert response.status_code == 200
    body = response.json()
    assert body["ready"] is True
    assert body["config"]["required"] == {
        "ASSEMBLYAI_API_KEY": True, "SUPABASE_URL": True, "SUPABASE_SERVICE_KEY": True,
    }
    assert body["checks"] == {"database": {"ok": True}, "assemblyai_session": {"ok": True}}
    # the probe opened one real-shaped session and ended it
    assert [m["type"] for m in upstream.sent] == ["session.update", "session.end"]
    assert upstream.closed
    assert calls[0][1]["additional_headers"] == {"Authorization": f"Bearer {API_KEY}"}


def test_report_never_contains_a_setting_value(monkeypatch):
    monkeypatch.setattr(settings, "assemblyai_agent_id", "agent-id-secret")
    patch_connect(monkeypatch, invalid_status(401))
    monkeypatch.setattr("app.db.client.get_supabase_client", lambda: FakeQuery(RuntimeError(SERVICE_KEY)))

    raw = client.get("/health/ready").text

    for secret in (API_KEY, SUPABASE_URL, SERVICE_KEY, "agent-id-secret"):
        assert secret not in raw


def test_every_leaf_of_the_config_report_is_a_boolean():
    report = voice_readiness.config_report()
    for group in report.values():
        assert all(isinstance(v, bool) for v in group.values())


def test_missing_settings_are_named_and_the_server_is_not_ready(monkeypatch):
    monkeypatch.setattr(settings, "assemblyai_api_key", None)
    monkeypatch.setattr(settings, "supabase_service_key", None)
    calls = patch_connect(monkeypatch, FakeUpstream())

    response = client.get("/health/ready")

    assert response.status_code == 503
    body = response.json()
    assert body["ready"] is False
    assert body["config"]["required"]["ASSEMBLYAI_API_KEY"] is False
    assert body["config"]["required"]["SUPABASE_SERVICE_KEY"] is False
    assert body["config"]["required"]["SUPABASE_URL"] is True
    assert body["checks"]["assemblyai_session"] == {"ok": False, "reason": "assemblyai_api_key_missing"}
    assert body["checks"]["database"] == {"ok": False, "reason": "not_configured"}
    assert calls == []  # no key, no connection attempt


@pytest.mark.parametrize("error, reason", [
    (invalid_status(401), "assemblyai_key_rejected"),
    (invalid_status(403), "assemblyai_key_rejected"),
    (invalid_status(502), "assemblyai_http_502"),
    (OSError("refused"), "assemblyai_unreachable_OSError"),
    (asyncio.TimeoutError(), "assemblyai_connect_timeout"),
])
def test_upstream_failures_get_a_specific_reason(monkeypatch, error, reason):
    patch_connect(monkeypatch, error)

    response = client.get("/health/ready")

    assert response.status_code == 503
    assert response.json()["checks"]["assemblyai_session"] == {"ok": False, "reason": reason}


def test_upstream_that_rejects_the_session_is_reported(monkeypatch):
    patch_connect(monkeypatch, FakeUpstream({"type": "session.error", "code": "invalid_agent", "message": "x"}))

    body = client.get("/health/ready").json()

    assert body["checks"]["assemblyai_session"] == {"ok": False, "reason": "session_rejected_invalid_agent"}


def test_upstream_that_never_answers_is_bounded(monkeypatch):
    class Silent(FakeUpstream):
        async def recv(self):
            await asyncio.sleep(30)

    monkeypatch.setattr(voice_readiness, "PROBE_TIMEOUT", 0.05)
    upstream = Silent()
    patch_connect(monkeypatch, upstream)

    body = client.get("/health/ready").json()

    assert body["checks"]["assemblyai_session"] == {"ok": False, "reason": "timeout"}
    assert upstream.closed


def test_database_failure_reports_the_error_class_and_code(monkeypatch):
    class APIError(Exception):
        code = "42P01"

    patch_connect(monkeypatch, FakeUpstream())
    monkeypatch.setattr("app.db.client.get_supabase_client", lambda: FakeQuery(APIError("relation missing")))

    body = client.get("/health/ready").json()

    assert body["ready"] is False
    assert body["checks"]["database"] == {"ok": False, "reason": "query_failed_APIError", "code": "42P01"}


def test_report_is_cached_briefly(monkeypatch):
    calls = patch_connect(monkeypatch, FakeUpstream())

    client.get("/health/ready")
    client.get("/health/ready")

    assert len(calls) == 1


def test_plain_health_stays_cheap_and_unchanged(monkeypatch):
    calls = patch_connect(monkeypatch, FakeUpstream())

    response = client.get("/health")

    assert response.status_code == 200 and response.json()["status"] == "ok"
    assert calls == []


@pytest.mark.parametrize("error, code, reason", [
    (voice_readiness.UpstreamNotConfigured("assemblyai_api_key_missing"), "voice_not_configured", "assemblyai_api_key_missing"),
    (invalid_status(401), "voice_not_configured", "assemblyai_key_rejected"),
    (invalid_status(503), "upstream_unavailable", "assemblyai_http_503"),
    (asyncio.TimeoutError(), "upstream_timeout", "assemblyai_connect_timeout"),
    (OSError("dns"), "upstream_unavailable", "assemblyai_unreachable_OSError"),
    (TypeError("unexpected keyword"), "upstream_unavailable", "assemblyai_connect_error_TypeError"),
])
def test_classify_upstream_failure(error, code, reason):
    got_code, got_reason, message = voice_readiness.classify_upstream_failure(error)
    assert (got_code, got_reason) == (code, reason)
    assert message and "dns" not in message


# ------------------------------------------------------------------------------ REST symptoms


def test_rest_call_on_a_server_without_supabase_config_is_503_not_401(monkeypatch, caplog):
    def unconfigured():
        raise ValueError("Supabase URL and service key must be set in environment variables")

    monkeypatch.setattr("app.dependencies.get_supabase_client", unconfigured)

    response = client.post("/v1/shift/start", headers={"Authorization": "Bearer any-token"})

    assert response.status_code == 503
    assert "not configured" in response.json()["detail"]
    assert "SUPABASE_SERVICE_KEY" in caplog.text


def test_shift_start_database_failure_is_logged_by_class_only(monkeypatch, caplog):
    from types import SimpleNamespace

    from app.api.routes import shift as shift_routes

    user = SimpleNamespace(user=SimpleNamespace(model_dump=lambda: {"id": "driver-1"}))
    monkeypatch.setattr("app.dependencies.get_supabase_client",
                        lambda: SimpleNamespace(auth=SimpleNamespace(get_user=lambda token: user)))

    async def no_dangling(driver_id):
        return None

    async def broken(driver_id):
        raise RuntimeError("relation shifts does not exist")

    monkeypatch.setattr(shift_routes, "get_active_shift_for_driver", no_dangling)
    monkeypatch.setattr(shift_routes, "create_shift", broken)

    response = client.post("/v1/shift/start", headers={"Authorization": "Bearer good"})

    assert response.status_code == 500
    assert "[start_shift] failed: RuntimeError" in caplog.text
    assert "relation shifts" not in caplog.text
