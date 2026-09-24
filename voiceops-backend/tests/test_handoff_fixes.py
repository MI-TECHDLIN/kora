"""
Unit tests covering the 6 design handoffs:
1. Honest sentiment scoring and dynamic location matching in LeMUR fallback.
2. Proactive dwell check-in geofence gating and driver-facing question.
3. Contract-compliant PROACTIVE_ALERT event structure and voice socket bridge.
4. Shift report duration and source indicator.
"""
import asyncio
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch, MagicMock
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.main import app
from app.config import Settings
from app.dependencies import get_current_driver
from app.api import ownership
from app.api.routes import deliveries as delivery_routes
from app.api.routes import pod as pod_routes
from app.api.routes import shift as shift_routes
from app.api.routes import tools as tool_routes
from app.api.routes import voice_agent as voice_agent_routes
from app.agents import tool_safety
from app.services.risk_engine import RiskEngine, RiskType, RiskSeverity
from app.services import proactive_alert_service as alert_service_module
from app.intelligence.lemur_pipeline import LemurIntelligencePipeline
from app.api.websocket import events
from app.api.websocket.voice import present_proactive_alert, _sessions, VoiceSession


DRIVER_A = "10000000-0000-4000-8000-000000000001"
DRIVER_B = "20000000-0000-4000-8000-000000000002"
SHIFT_A = "30000000-0000-4000-8000-000000000003"
SHIFT_B = "40000000-0000-4000-8000-000000000004"
DELIVERY_A = "50000000-0000-4000-8000-000000000005"


@pytest.fixture
def driver_b_client():
    app.dependency_overrides[get_current_driver] = lambda: {
        "id": DRIVER_B,
        "email": "driver-b@example.com",
    }
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.pop(get_current_driver, None)


@pytest.fixture
def driver_a_client():
    app.dependency_overrides[get_current_driver] = lambda: {
        "id": DRIVER_A,
        "email": "driver-a@example.com",
    }
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.pop(get_current_driver, None)


def _foreign_delivery(monkeypatch):
    async def get_delivery(delivery_id):
        return {"id": delivery_id, "shift_id": SHIFT_A, "status": "pending"}

    async def get_shift(shift_id):
        return {"id": shift_id, "driver_id": DRIVER_A, "status": "active"}

    monkeypatch.setattr(ownership, "get_delivery_by_id", get_delivery)
    monkeypatch.setattr(ownership, "get_shift_by_id", get_shift)


def test_driver_cannot_update_another_drivers_delivery(monkeypatch, driver_b_client):
    _foreign_delivery(monkeypatch)

    response = driver_b_client.put(
        f"/v1/deliveries/{DELIVERY_A}/status",
        json={"status": "delivered"},
    )

    assert response.status_code == 404
    assert response.json() == {"detail": "Delivery not found"}


def test_driver_cannot_upload_or_read_another_drivers_pod(monkeypatch, driver_b_client):
    _foreign_delivery(monkeypatch)

    upload = driver_b_client.post(
        f"/v1/deliveries/{DELIVERY_A}/pod",
        data={"latitude": "30.2672", "longitude": "-97.7431"},
    )
    read = driver_b_client.get(f"/v1/deliveries/{DELIVERY_A}/pod")

    assert upload.status_code == 404
    assert upload.json() == {"detail": "Delivery not found"}
    assert read.status_code == 404
    assert read.json() == {"detail": "Delivery not found"}


def test_driver_cannot_read_stats_or_analyze_another_drivers_shift(
    monkeypatch, driver_b_client
):
    async def get_shift(shift_id):
        return {"id": shift_id, "driver_id": DRIVER_A, "status": "completed"}

    monkeypatch.setattr(ownership, "get_shift_by_id", get_shift)

    stats = driver_b_client.get(f"/v1/shift/{SHIFT_A}/stats")
    analysis = driver_b_client.post(f"/v1/shift/{SHIFT_A}/analyze-lemur")

    assert stats.status_code == 404
    assert stats.json() == {"detail": "Shift not found"}
    assert analysis.status_code == 404
    assert analysis.json() == {"detail": "Shift not found"}


@pytest.mark.parametrize("path", ["/v1/tools/execute-parallel", "/v1/tools/benchmark"])
def test_tool_routes_require_authentication(path):
    app.dependency_overrides.pop(get_current_driver, None)
    response = TestClient(app).post(
        path,
        json={"tools": [{"name": "unknown", "arguments": {}}], "context": {}},
    )
    assert response.status_code == 401


def test_tool_route_ignores_caller_supplied_identity(monkeypatch, driver_a_client):
    seen = {}

    async def active_shift(driver_id):
        assert driver_id == DRIVER_A
        return {"id": SHIFT_A, "driver_id": DRIVER_A, "status": "active"}

    async def next_delivery(shift_id, driver_id):
        assert (shift_id, driver_id) == (SHIFT_A, DRIVER_A)
        return {"id": DELIVERY_A, "shift_id": SHIFT_A, "status": "pending"}

    async def execute(tool_calls, context):
        seen.update(context)
        return {
            "tool_count": 1,
            "total_duration_ms": 1.0,
            "sequential_sum_ms": 1.0,
            "time_saved_ms": 0.0,
            "under_500ms": True,
            "results": [],
        }

    monkeypatch.setattr(tool_routes, "get_active_shift_for_driver", active_shift)
    monkeypatch.setattr(tool_routes, "get_next_pending_delivery", next_delivery)
    monkeypatch.setattr(tool_routes.ToolOrchestrator, "execute_parallel", execute)

    response = driver_a_client.post(
        "/v1/tools/execute-parallel",
        json={
            "tools": [{"name": "unknown", "arguments": {}}],
            "context": {
                "driver_id": DRIVER_B,
                "driver_name": "Imposter",
                "shift_id": SHIFT_B,
                "session_id": "foreign-session",
                "is_demo": True,
                "current_delivery": {"id": "foreign-delivery"},
                "offered_order": {"id": "foreign-order"},
                "latitude": 30.2672,
            },
        },
    )

    assert response.status_code == 200
    assert seen["driver_id"] == DRIVER_A
    assert seen["shift_id"] == SHIFT_A
    assert seen["is_demo"] is False
    assert seen["current_delivery"]["id"] == DELIVERY_A
    assert seen["latitude"] == 30.2672
    assert "session_id" not in seen
    assert "offered_order" not in seen


def test_tool_benchmark_is_off_by_default(monkeypatch, driver_a_client):
    monkeypatch.setattr(tool_routes.settings, "tools_benchmark_enabled", False)
    response = driver_a_client.post(
        "/v1/tools/benchmark",
        json={"tools": [{"name": "unknown", "arguments": {}}], "context": {}},
    )
    assert response.status_code == 404


def test_legacy_driver_websocket_is_not_mounted():
    paths = {
        route.path
        for route in app.routes
        if route.__class__.__name__ == "APIWebSocketRoute"
    }

    assert paths == {"/ws/voice/{shift_id}"}


def test_mock_id_setting_defaults_on_outside_production_and_off_in_production():
    development = Settings(_env_file=None, environment="development")
    production = Settings(_env_file=None, environment="production")

    assert development.allow_mock_delivery_ids is True
    assert development.mock_delivery_ids_enabled is True
    assert production.mock_delivery_ids_enabled is False


@pytest.mark.parametrize(
    ("environment", "enabled"),
    [("development", False), ("staging", True), ("production", True)],
)
def test_voice_agent_harness_is_hidden_unless_both_gates_are_on(
    monkeypatch, environment, enabled
):
    monkeypatch.setattr(voice_agent_routes.settings, "environment", environment)
    monkeypatch.setattr(voice_agent_routes.settings, "voice_agent_harness_enabled", enabled)

    response = TestClient(app).post(
        "/v1/voice-agent",
        json={"audio": "AAA=", "sample_rate": 24000, "session_id": "test-session"},
    )

    assert response.status_code == 404
    assert response.json() == {"detail": "Not found"}


def test_voice_agent_harness_runs_when_both_gates_are_on(monkeypatch):
    monkeypatch.setattr(voice_agent_routes.settings, "environment", "development")
    monkeypatch.setattr(voice_agent_routes.settings, "voice_agent_harness_enabled", True)
    monkeypatch.setattr(voice_agent_routes, "save_wav", MagicMock())
    monkeypatch.setattr(
        voice_agent_routes,
        "handle_assemblyai_session",
        AsyncMock(return_value=(b"response", ["driver text"], ["agent text"])),
    )

    response = TestClient(app).post(
        "/v1/voice-agent",
        json={"audio": "AAA=", "sample_rate": 24000, "session_id": "test-session"},
    )

    assert response.status_code == 200
    assert response.json()["session_id"] == "test-session"
    assert response.json()["user_transcript"] == "driver text"
    assert response.json()["agent_transcript"] == "agent text"


def test_tool_delivery_argument_is_checked_through_its_shift(monkeypatch):
    async def get_delivery(delivery_id):
        return {"id": delivery_id, "shift_id": SHIFT_A}

    async def get_shift(shift_id):
        return {"id": shift_id, "driver_id": DRIVER_A}

    monkeypatch.setattr(tool_safety, "get_delivery_by_id", get_delivery)
    monkeypatch.setattr(tool_safety, "get_shift_by_id", get_shift)

    allowed, reason = asyncio.run(tool_safety.tool_safety_gate.check(
        "update_delivery_status",
        {"delivery_id": DELIVERY_A, "status": "delivered"},
        {"driver_id": DRIVER_B, "shift_id": SHIFT_B},
    ))

    assert allowed is False
    assert "belongs to another driver" in reason


def test_non_uuid_mock_delivery_paths_keep_demo_behavior(monkeypatch, driver_a_client):
    calls = []

    async def mark(delivery_id, status, failure_reason=None, notes=None):
        calls.append((delivery_id, status))
        return {"id": delivery_id, "status": status}

    async def event(**kwargs):
        return {}

    async def notify(shift_id, driver_id):
        return None

    class FakePodTable:
        def insert(self, data):
            return self

        def execute(self):
            return SimpleNamespace(data=[{"id": "mock-pod"}])

    class FakePodDb:
        def table(self, name):
            return FakePodTable()

    monkeypatch.setattr(ownership.settings, "environment", "development")
    monkeypatch.setattr(ownership.settings, "allow_mock_delivery_ids", True)
    monkeypatch.setattr(delivery_routes, "mark_delivery_status", mark)
    monkeypatch.setattr(delivery_routes, "create_delivery_event", event)
    monkeypatch.setattr(delivery_routes, "notify_queue_changed", notify)
    monkeypatch.setattr(pod_routes, "get_supabase", lambda: FakePodDb())

    status_response = driver_a_client.put(
        "/v1/deliveries/mock-delivery-123/status",
        json={"status": "delivered"},
    )
    upload_response = driver_a_client.post(
        "/v1/deliveries/mock-delivery-123/pod",
        data={"latitude": "30.2672", "longitude": "-97.7431"},
    )
    read_response = driver_a_client.get("/v1/deliveries/mock-delivery-123/pod")

    assert status_response.status_code == 200
    assert status_response.json()["status"] == "delivered"
    assert upload_response.status_code == 200
    assert upload_response.json()["pod_id"] == "mock-pod"
    assert read_response.status_code == 200
    assert read_response.json() == {"pod": None}
    assert calls == [("mock-delivery-123", "delivered")]


def test_non_uuid_mock_delivery_paths_are_blocked_in_production(monkeypatch, driver_a_client):
    monkeypatch.setattr(ownership.settings, "environment", "production")
    monkeypatch.setattr(ownership.settings, "allow_mock_delivery_ids", True)

    status_response = driver_a_client.put(
        "/v1/deliveries/mock-delivery-123/status",
        json={"status": "delivered"},
    )
    upload_response = driver_a_client.post(
        "/v1/deliveries/mock-delivery-123/pod",
        data={"latitude": "30.2672", "longitude": "-97.7431"},
    )
    read_response = driver_a_client.get("/v1/deliveries/mock-delivery-123/pod")

    assert status_response.status_code == 404
    assert upload_response.status_code == 404
    assert read_response.status_code == 404

    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(ownership.require_owned_shift(
            "demo-shift-001", DRIVER_A, allow_mock_id=True
        ))
    assert exc_info.value.status_code == 404


def test_proactive_alert_service_uses_authenticated_voice_socket(monkeypatch):
    present = AsyncMock(return_value=1)
    monkeypatch.setattr("app.api.websocket.voice.present_proactive_alert", present)
    monkeypatch.setattr(
        alert_service_module,
        "get_supabase",
        MagicMock(side_effect=RuntimeError("database unavailable")),
    )

    sent = asyncio.run(alert_service_module.alert_service.emit_voice_alert(
        driver_id=DRIVER_A,
        message="Traffic ahead.",
        risk_type="ROUTE_DEVIATION",
        shift_id=SHIFT_A,
        spoken_instructions="Tell the driver about the traffic delay.",
    ))

    assert sent is True
    present.assert_awaited_once()


def test_lemur_fallback_honest_sentiment():
    """Verify fallback sentiment has estimated prefix and dynamic route extraction."""
    pipeline = LemurIntelligencePipeline()
    shift_stats = {"total": 10, "delivered": 8, "failed": 1, "success_rate": 80.0}
    deliveries = [
        {"id": "del-1", "address": "812 Lavaca St, Austin, TX"},
        {"id": "del-2", "address": "1200 Congress Ave, Austin, TX"},
    ]
    # Transcript mentions Lavaca St and an incident, but NOT Lagos
    transcript = (
        "Driver: Next stop.\n"
        "Kora: Stop 1 is Lavaca St.\n"
        "Driver: There is a lot of traffic on Lavaca St and the gate is locked.\n"
    )
    result = pipeline._fallback_nlp_analysis(transcript, shift_stats, deliveries=deliveries)

    assert result["lemur_source"] == "voiceops_speech_intelligence_engine"
    assert result["is_estimated"] is True
    assert "(Estimated while AI analysis was unavailable)" in result["executive_summary"]
    assert "Overall sentiment estimated at" in result["executive_summary"]
    assert any("Lavaca St" in issue for issue in result["route_issues"])
    # Ensure no hardcoded Lagos locations appear
    for issue in result["route_issues"]:
        assert "Lagos" not in issue
        assert "Marina" not in issue


def test_idle_time_gated_outside_geofence():
    """Verify idle time is NOT flagged when driver is far from stop (e.g. in traffic)."""
    async def _run():
        risk_engine = RiskEngine()
        driver_id = "00000000-0000-0000-0000-000000000001"
        shift_id = "00000000-0000-0000-0000-000000000002"
        # Driver stationary at (30.2600, -97.7400)
        location_update = {"latitude": 30.2600, "longitude": -97.7400, "speed": 0.5}
        
        # Stop is at (30.2800, -97.7400), over 2 km away
        delivery = {
            "id": "00000000-0000-0000-0000-000000000003",
            "dropoff_latitude": 30.2800,
            "dropoff_longitude": -97.7400,
            "status": "pending",
            "attempt_count": 0,
            "recipient_name": "Alice",
            "address": "200 University Ave",
        }
        with patch("app.services.risk_engine.get_next_pending_delivery", new=AsyncMock(return_value=delivery)):
            result = await risk_engine._check_idle_time(driver_id, shift_id, location_update)
            # Should be None because driver is not within 100m geofence
            assert result is None

    asyncio.run(_run())


def test_idle_time_flagged_inside_geofence_with_driver_question():
    """Verify idle time flags a driver question when stationary within 100m of stop."""
    async def _run():
        risk_engine = RiskEngine()
        driver_id = "00000000-0000-0000-0000-000000000001"
        shift_id = "00000000-0000-0000-0000-000000000002"
        # Driver stationary within 20m of dropoff
        location_update = {"latitude": 30.2713, "longitude": -97.7455, "speed": 0.0}
        delivery = {
            "id": "00000000-0000-0000-0000-000000000003",
            "dropoff_latitude": 30.2714,
            "dropoff_longitude": -97.7456,
            "status": "pending",
            "attempt_count": 1,
            "recipient_name": "Sarah",
            "address": "812 Lavaca St",
        }
        mock_pings = [
            {"speed": 0.0, "pinged_at": "2026-09-19T10:05:00Z"},
            {"speed": 0.2, "pinged_at": "2026-09-19T10:04:45Z"},
            {"speed": 0.1, "pinged_at": "2026-09-19T10:04:30Z"},
            {"speed": 0.0, "pinged_at": "2026-09-19T10:04:15Z"},
            {"speed": 0.0, "pinged_at": "2026-09-19T10:04:00Z"},
            {"speed": 0.0, "pinged_at": "2026-09-19T10:03:45Z"},
        ]
        with patch("app.services.risk_engine.get_next_pending_delivery", new=AsyncMock(return_value=delivery)), \
             patch("app.services.risk_engine.get_recent_location_pings", new=AsyncMock(return_value=mock_pings)):
            result = await risk_engine._check_idle_time(driver_id, shift_id, location_update)
            assert result is not None
            assert result.risk_type == RiskType.EXCESSIVE_IDLE
            assert result.delivery_id == delivery["id"]
            assert result.evidence["at_stop"] is True
            assert result.evidence["prior_failures"] == 1
            # Check wording addresses driver directly and mentions prior failure
            assert "prior failed attempt" in result.recommended_action
            assert "stuck at a gate" in result.recommended_action

    asyncio.run(_run())


def test_proactive_alert_event_structure():
    """Verify events.proactive_alert matches docs/contracts/interface.md."""
    event = events.proactive_alert(
        severity="HIGH",
        risk_type="ROUTE_DEVIATION",
        message="Traffic ahead adds 8 minutes. Want me to reroute?",
        delivery_id="del-123",
        route_suggestion={"eta_minutes": 12, "current_eta_minutes": 20, "geometry": "xyz"},
    )
    assert event["event"] == "PROACTIVE_ALERT"
    assert event["severity"] == "HIGH"
    assert event["risk_type"] == "ROUTE_DEVIATION"
    assert event["delivery_id"] == "del-123"
    assert event["route_suggestion"]["eta_minutes"] == 12


def test_present_proactive_alert_bridge():
    """Verify present_proactive_alert emits to voice socket and queues announcement."""
    async def _run():
        driver_id = "driver-abc"
        shift_id = "shift-xyz"
        mock_session = MagicMock()
        mock_session.driver_id = driver_id
        mock_session.shift_id = shift_id
        mock_session.emit = AsyncMock()
        mock_session._announce = MagicMock()

        _sessions[shift_id] = {mock_session}
        try:
            alert_payload = {
                "event": "PROACTIVE_ALERT",
                "severity": "HIGH",
                "risk_type": "ROUTE_DEVIATION",
                "message": "Traffic ahead.",
            }
            instructions = "Tell the driver about the traffic delay."
            sent_count = await present_proactive_alert(
                driver_id=driver_id,
                alert_payload=alert_payload,
                spoken_instructions=instructions,
                shift_id=shift_id,
            )
            assert sent_count == 1
            mock_session.emit.assert_awaited_once_with(alert_payload)
            mock_session._announce.assert_called_once_with("risk:ROUTE_DEVIATION", instructions)
        finally:
            _sessions.pop(shift_id, None)

    asyncio.run(_run())
