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
    assert len(tools) == 14
    tool_names = [t["name"] for t in tools]
    assert "call_customer" in tool_names
    assert "notify_customer" in tool_names
    assert "get_next_delivery" in tool_names
    assert "end_conversation" in tool_names


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


def test_alert_dispatcher(mock_context):
    result = asyncio.run(execute_tool(
        "alert_dispatcher",
        {"delivery_id": "del-123", "message": "Customer is aggressive", "priority": "urgent"},
        mock_context
    ))
    assert result.get("success") is True
    assert result.get("priority") == "urgent"


def test_unknown_tool(mock_context):
    result = asyncio.run(execute_tool("nonexistent_tool", {}, mock_context))
    assert result.get("success") is False
    assert "not found" in result.get("error").lower()


def test_start_navigation_is_in_app_not_a_deep_link(mock_context, monkeypatch):
    """start_navigation returns route data for the in-app map, never an external maps URL."""
    from app.agents.tools import navigation

    async def get_directions(origin_lat, origin_lng, dest_lat, dest_lng):
        return [{"summary": "Victoria Bridge", "distance": 3200, "duration": 660,
                 "polyline": "_p~iF~ps|U_ulLnnqC_mqNvxq`@"}]

    monkeypatch.setattr(navigation, "get_directions", get_directions)
    context = dict(mock_context, latitude=6.46, longitude=3.40)
    context["current_delivery"] = dict(mock_context["current_delivery"], latitude=6.4541, longitude=3.3947)
    result = asyncio.run(execute_tool("start_navigation", {"delivery_id": "mock-delivery-789"}, context))
    assert result.get("success") is True
    assert "navigation_url" not in result and "action" not in result
    assert result["delivery_id"] == "mock-delivery-789"
    assert (result["latitude"], result["longitude"]) == (6.4541, 3.3947)
    assert set(result["route"]) == {"polyline", "summary", "distance_km", "duration_mins", "duration_text"}
    assert result["route"]["polyline"]


def test_encode_polyline_matches_google_reference():
    from app.integrations.google_maps import encode_polyline
    # Worked example from Google's encoded polyline algorithm documentation
    points = [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)]
    assert encode_polyline(points) == "_p~iF~ps|U_ulLnnqC_mqNvxq`@"


def test_show_screen(mock_context):
    result = asyncio.run(execute_tool("show_screen", {"screen": "settings"}, mock_context))
    assert result == {"success": True, "screen": "settings", "message": "Opening your profile and settings."}
    bad = asyncio.run(execute_tool("show_screen", {"screen": "vehicle"}, mock_context))
    assert bad["success"] is False and "error" in bad
