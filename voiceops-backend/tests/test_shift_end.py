"""
Tests for the shift-end trigger fix (audit report §2.2): nothing in the app used to call
POST /v1/shift/{shift_id}/end, so the LeMUR post-shift pipeline was dead code and
GET /v1/shift/{shift_id}/report looped on "processing" forever. Covers:

- the new `end_shift` voice tool actually invokes the pipeline
- a dangling shift (app killed, never explicitly ended) is auto-closed when a new one starts
- get_shift_summary no longer fabricates stats for a genuinely empty shift
"""
import asyncio
from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.dependencies import get_current_driver
from app.agents.tool_registry import execute_tool, get_tools, TOOL_EXECUTORS
from app.api.routes import shift as shift_routes

client = TestClient(app)

DRIVER_ID = "driver-1"
SHIFT_ID = "shift-1"
DANGLING_SHIFT_ID = "shift-dangling"


class _FakeTable:
    """Stands in for `get_supabase().table(...).update(...).eq(...).execute()`."""

    def table(self, name):
        return self

    def update(self, data):
        return self

    def eq(self, key, value):
        return self

    def execute(self):
        return None


@pytest.fixture(autouse=True)
def driver_auth():
    app.dependency_overrides[get_current_driver] = lambda: {
        "id": DRIVER_ID,
        "full_name": "Test Driver",
        "email": "driver@example.com",
    }
    yield
    app.dependency_overrides.pop(get_current_driver, None)


def test_end_shift_tool_is_registered_and_distinct_from_end_conversation():
    tool_names = {t["name"] for t in get_tools()}
    assert "end_shift" in tool_names
    assert "end_conversation" in tool_names
    assert "end_shift" in TOOL_EXECUTORS
    # Every declared tool has an executor and vice versa (mirrors the WS session-config check).
    assert tool_names == set(TOOL_EXECUTORS)


def test_end_shift_tool_invokes_the_intelligence_pipeline(monkeypatch):
    calls = {"status": [], "n8n": [], "intelligence": []}

    async def fake_update_shift_status(shift_id, status):
        calls["status"].append((shift_id, status))
        return {"id": shift_id, "status": status}

    async def fake_get_shift_by_id(shift_id):
        return {
            "id": shift_id,
            "driver_id": DRIVER_ID,
            "status": "active",
            "started_at": datetime.now(timezone.utc).isoformat(),
        }

    async def fake_get_shift_stats(shift_id):
        return {"total": 3, "delivered": 2, "failed": 1, "remaining": 0}

    async def fake_get_shift_voice_sessions(shift_id):
        return []

    def fake_trigger_n8n(**kwargs):
        calls["n8n"].append(kwargs)

    async def fake_run_shift_intelligence(shift_id, driver_id=None):
        calls["intelligence"].append((shift_id, driver_id))
        return {"analysis": {"executive_summary": "Solid shift."}}

    async def fake_stream_summary(shift_id, text):
        return 0

    monkeypatch.setattr(shift_routes, "update_shift_status", fake_update_shift_status)
    monkeypatch.setattr(shift_routes, "get_shift_by_id", fake_get_shift_by_id)
    monkeypatch.setattr(shift_routes, "get_shift_stats", fake_get_shift_stats)
    monkeypatch.setattr(shift_routes, "get_shift_voice_sessions", fake_get_shift_voice_sessions)
    monkeypatch.setattr(shift_routes, "trigger_post_shift_report_background", fake_trigger_n8n)
    monkeypatch.setattr(shift_routes, "run_shift_intelligence", fake_run_shift_intelligence)
    monkeypatch.setattr(shift_routes, "stream_summary", fake_stream_summary)
    monkeypatch.setattr(shift_routes, "get_supabase", lambda: _FakeTable())

    context = {"driver_id": DRIVER_ID, "driver_name": "Test Driver", "shift_id": SHIFT_ID}

    async def run():
        result = await execute_tool("end_shift", {}, context)
        # The pipeline runs as a fire-and-forget asyncio task; give the loop a beat
        # to run it before the loop (and the task with it) goes away.
        await asyncio.sleep(0.05)
        return result

    result = asyncio.run(run())

    assert result["success"] is True
    assert result["shift_id"] == SHIFT_ID
    assert result["status"] == "completed"
    assert calls["status"] == [(SHIFT_ID, "completed")]
    assert calls["n8n"], "the n8n post-shift webhook was never triggered"
    assert calls["intelligence"] == [(SHIFT_ID, DRIVER_ID)], (
        "end_shift must invoke the LeMUR pipeline (run_shift_intelligence)"
    )


def test_end_shift_tool_requires_an_active_shift():
    result = asyncio.run(execute_tool("end_shift", {}, {"driver_id": DRIVER_ID, "shift_id": None}))
    assert result["success"] is False


def test_start_shift_auto_closes_a_dangling_previous_shift(monkeypatch):
    calls = {"status": [], "created": []}

    async def fake_get_active_shift_for_driver(driver_id):
        return {"id": DANGLING_SHIFT_ID, "driver_id": driver_id, "status": "active"}

    async def fake_end_shift_core(shift_id, driver_id, driver_name):
        calls["status"].append(shift_id)
        return {"shift_id": shift_id, "status": "completed", "shift_duration_min": 42}

    async def fake_run_shift_intelligence_and_stream(shift_id, driver_id):
        return {}

    async def fake_create_shift(driver_id):
        calls["created"].append(driver_id)
        return {"id": SHIFT_ID, "status": "active"}

    monkeypatch.setattr(shift_routes, "get_active_shift_for_driver", fake_get_active_shift_for_driver)
    monkeypatch.setattr(shift_routes, "end_shift_core", fake_end_shift_core)
    monkeypatch.setattr(shift_routes, "run_shift_intelligence_and_stream", fake_run_shift_intelligence_and_stream)
    monkeypatch.setattr(shift_routes, "create_shift", fake_create_shift)

    response = client.post("/v1/shift/start", headers={"Authorization": "Bearer good"})

    assert response.status_code == 200
    assert response.json()["shift_id"] == SHIFT_ID
    assert calls["status"] == [DANGLING_SHIFT_ID], "the dangling shift was not closed"
    assert calls["created"] == [DRIVER_ID]


def test_start_shift_with_no_dangling_shift_only_creates_the_new_one(monkeypatch):
    calls = {"status": [], "created": []}

    async def fake_get_active_shift_for_driver(driver_id):
        return None

    async def fake_end_shift_core(shift_id, driver_id, driver_name):
        calls["status"].append(shift_id)
        return {}

    async def fake_create_shift(driver_id):
        calls["created"].append(driver_id)
        return {"id": SHIFT_ID, "status": "active"}

    monkeypatch.setattr(shift_routes, "get_active_shift_for_driver", fake_get_active_shift_for_driver)
    monkeypatch.setattr(shift_routes, "end_shift_core", fake_end_shift_core)
    monkeypatch.setattr(shift_routes, "create_shift", fake_create_shift)

    response = client.post("/v1/shift/start", headers={"Authorization": "Bearer good"})

    assert response.status_code == 200
    assert calls["status"] == []
    assert calls["created"] == [DRIVER_ID]


def test_get_shift_summary_reports_real_zeros_for_an_empty_shift(monkeypatch):
    async def fake_get_shift_stats(shift_id):
        return {"total": 0, "delivered": 0, "failed": 0, "success_rate": 0}

    monkeypatch.setattr("app.db.queries.get_shift_stats", fake_get_shift_stats)

    context = {"driver_id": DRIVER_ID, "shift_id": SHIFT_ID}
    result = asyncio.run(execute_tool("get_shift_summary", {}, context))

    assert result["success"] is True
    assert result["total"] == 0
    assert result["delivered"] == 0
    assert result["message"] == "0 of 0 complete. 0 remaining."


def test_get_shift_summary_still_reports_real_nonzero_stats(monkeypatch):
    async def fake_get_shift_stats(shift_id):
        return {
            "total": 5,
            "delivered": 3,
            "failed": 1,
            "remaining": 1,
            "pending": 1,
            "en_route": 0,
            "success_rate": 60,
        }

    monkeypatch.setattr("app.db.queries.get_shift_stats", fake_get_shift_stats)

    context = {"driver_id": DRIVER_ID, "shift_id": SHIFT_ID}
    result = asyncio.run(execute_tool("get_shift_summary", {}, context))

    assert result["total"] == 5
    assert result["delivered"] == 3
    assert result["failed"] == 1
