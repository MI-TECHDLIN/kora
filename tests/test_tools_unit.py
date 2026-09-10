"""
Unit tests for tool execution and registry.
"""
import asyncio
import pytest
from app.agents.tool_registry import execute_tool, get_tools


@pytest.fixture
def mock_context():
    return {
        "driver_id": "test-driver-123",
        "driver_name": "Test Driver",
        "shift_id": "test-shift-456",
        "current_delivery": {
            "id": "mock-delivery-789",
            "recipient_name": "Amara Johnson",
            "address": "14 Broad Street, Lagos Island",
            "customer_phone": "+2348012345678"
        },
        "session_id": "test-session-000"
    }


def test_tool_definitions():
    """Verify tool definitions are registered."""
    tools = get_tools()
    assert isinstance(tools, list)
    assert len(tools) == 10
    tool_names = [t["name"] for t in tools]
    assert "call_customer" in tool_names
    assert "notify_customer" in tool_names
    assert "get_next_delivery" in tool_names


def test_get_next_delivery(mock_context):
    result = asyncio.run(execute_tool("get_next_delivery", {}, mock_context))
    assert result.get("success") is True


def test_update_delivery_status(mock_context):
    result = asyncio.run(execute_tool(
        "update_delivery_status",
        {"status": "delivered", "notes": "Signed"},
        mock_context
    ))
    assert result.get("success") is True


def test_call_customer(mock_context):
    result = asyncio.run(execute_tool(
        "call_customer",
        {"delivery_id": "del-123", "message": "On my way"},
        mock_context
    ))
    assert result.get("success") is True
    assert "customer_name" in result


def test_notify_customer(mock_context):
    result = asyncio.run(execute_tool(
        "notify_customer",
        {"delivery_id": "del-123", "message_type": "nearby"},
        mock_context
    ))
    assert result.get("success") is True
    assert result.get("status") == "delivered"


def test_unknown_tool(mock_context):
    result = asyncio.run(execute_tool("nonexistent_tool", {}, mock_context))
    assert result.get("success") is False
    assert "not found" in result.get("error").lower()
