"""
Automated tests for FastAPI + asyncio parallel tool dispatch.
Verifies that:
1. ToolOrchestrator executes multiple tools concurrently via asyncio.gather().
2. Wall-clock execution latency stays well under 500ms SLA.
3. Partial tool failures do not crash the batch.
4. FastAPI endpoints (/v1/tools/execute-parallel and /v1/tools/benchmark) function correctly.
"""
import pytest
import asyncio
from app.agents.orchestrator import ToolOrchestrator
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

@pytest.fixture
def test_context():
    return {
        "driver_id": "10ed22c4-c1c0-4d37-8683-dbb8f510e4c6",
        "shift_id": "093375a3-06ab-4584-8331-f5df775f150b",
        "session_id": "test-session-123",
        "latitude": 6.4541,
        "longitude": 3.3947
    }


def test_parallel_execution_under_500ms(test_context):
    """Verify that multiple tools executed with asyncio.gather() complete under 500ms."""
    tools = [
        {"name": "update_delivery_status", "arguments": {"status": "delivered", "notes": "Left at door"}, "call_id": "call_1"},
        {"name": "get_next_delivery", "arguments": {}, "call_id": "call_2"},
        {"name": "get_shift_summary", "arguments": {}, "call_id": "call_3"},
        {"name": "get_next_order", "arguments": {}, "call_id": "call_4"},
        {"name": "log_exception", "arguments": {"reason": "gate_locked", "resolution": "reschedule"}, "call_id": "call_5"}
    ]

    result = asyncio.run(ToolOrchestrator.execute_parallel(tools, test_context))

    assert result["tool_count"] == 5
    assert len(result["results"]) == 5
    assert result["under_500ms"] is True
    assert result["total_duration_ms"] < 500.0

    # Ensure all call IDs match
    returned_call_ids = [r["call_id"] for r in result["results"]]
    assert returned_call_ids == ["call_1", "call_2", "call_3", "call_4", "call_5"]


def test_parallel_handles_partial_failure(test_context):
    """Verify that invalid tools do not crash the concurrent gather batch."""
    tools = [
        {"name": "get_next_delivery", "arguments": {}, "call_id": "valid_1"},
        {"name": "non_existent_tool_xyz", "arguments": {}, "call_id": "invalid_1"},
        {"name": "get_shift_summary", "arguments": {}, "call_id": "valid_2"}
    ]

    result = asyncio.run(ToolOrchestrator.execute_parallel(tools, test_context))

    assert result["tool_count"] == 3
    assert len(result["results"]) == 3

    # Check results
    res_map = {r["call_id"]: r for r in result["results"]}
    assert res_map["valid_1"]["is_error"] is False
    assert res_map["invalid_1"]["is_error"] is True
    assert res_map["valid_2"]["is_error"] is False


def test_api_execute_parallel_endpoint(test_context):
    """Test the POST /v1/tools/execute-parallel FastAPI REST endpoint."""
    payload = {
        "tools": [
            {"name": "update_delivery_status", "arguments": {"status": "delivered"}, "call_id": "t1"},
            {"name": "get_next_delivery", "arguments": {}, "call_id": "t2"},
            {"name": "get_shift_summary", "arguments": {}, "call_id": "t3"}
        ],
        "context": test_context
    }

    response = client.post("/v1/tools/execute-parallel", json=payload)
    assert response.status_code == 200

    data = response.json()
    assert data["tool_count"] == 3
    assert data["under_500ms"] is True
    assert data["total_duration_ms"] < 500.0
    assert len(data["results"]) == 3


def test_api_benchmark_endpoint(test_context):
    """Test the POST /v1/tools/benchmark FastAPI REST endpoint."""
    payload = {
        "tools": [
            {"name": "get_next_delivery", "arguments": {}, "call_id": "b1"},
            {"name": "get_shift_summary", "arguments": {}, "call_id": "b2"}
        ],
        "context": test_context
    }

    response = client.post("/v1/tools/benchmark", json=payload)
    assert response.status_code == 200

    data = response.json()
    assert data["tool_count"] == 2
    assert "sequential_ms" in data
    assert "parallel_asyncio_gather_ms" in data
    assert "speedup_factor" in data
    assert data["under_500ms"] is True
