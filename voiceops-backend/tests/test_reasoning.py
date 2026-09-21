"""
Tests for task-step reasoning feature.
Tests deterministic reasoning formatting, event builders, and relay integration.
"""
import pytest
from app.api.websocket import events
from app.api.websocket import reasoning as reasoning_formatter


def test_task_step_with_reasoning():
    """Test task_step event builder includes reasoning field."""
    result = events.task_step("Checking delivery route", "done", "This route saves about 7 min versus the alternative.")
    assert result["event"] == "task_step"
    assert result["step"] == "Checking delivery route"
    assert result["status"] == "done"
    assert result["reasoning"] == "This route saves about 7 min versus the alternative."


def test_task_step_without_reasoning():
    """Test task_step event builder omits reasoning when not provided."""
    result = events.task_step("Checking delivery route", "done")
    assert result["event"] == "task_step"
    assert result["step"] == "Checking delivery route"
    assert result["status"] == "done"
    assert "reasoning" not in result


def test_task_step_active_no_reasoning():
    """Test task_step with active status never includes reasoning."""
    result = events.task_step("Checking delivery route", "active", "Some reasoning")
    assert result["event"] == "task_step"
    assert result["step"] == "Checking delivery route"
    assert result["status"] == "active"
    assert "reasoning" not in result


def test_task_step_reasoning_length_limit():
    """Test task_step rejects reasoning over 140 characters."""
    long_reasoning = "This is a very long reasoning string that exceeds the 140 character limit and should be rejected by the event builder to ensure compliance with the interface contract."
    with pytest.raises(ValueError, match="exceeds 140 character limit"):
        events.task_step("Checking delivery route", "done", long_reasoning)


def test_task_step_reasoning_exactly_140_chars():
    """Test task_step accepts reasoning exactly at 140 character limit."""
    reasoning = "X" * 140
    assert len(reasoning) == 140
    result = events.task_step("Checking delivery route", "done", reasoning)
    assert result["reasoning"] == reasoning


def test_format_reasoning_get_next_delivery_with_sequence_and_window():
    """Test get_next_delivery reasoning with sequence and time window."""
    result = {
        "success": True,
        "has_next": True,
        "sequence": 4,
        "time_window": "2:00 PM - 4:00 PM"
    }
    formatted = reasoning_formatter.format_reasoning("get_next_delivery", result)
    assert formatted == "Stop 4 is next, with a 2:00 PM - 4:00 PM delivery window."
    assert len(formatted) <= 140


def test_format_reasoning_get_next_delivery_with_sequence_only():
    """Test get_next_delivery reasoning with sequence only."""
    result = {
        "success": True,
        "has_next": True,
        "sequence": 4
    }
    formatted = reasoning_formatter.format_reasoning("get_next_delivery", result)
    assert formatted == "Stop 4 is next in your run."
    assert len(formatted) <= 140


def test_format_reasoning_get_next_delivery_no_remaining():
    """Test get_next_delivery reasoning when no deliveries remain."""
    result = {
        "success": True,
        "has_next": False
    }
    formatted = reasoning_formatter.format_reasoning("get_next_delivery", result)
    assert formatted == "There are no remaining deliveries in this shift."
    assert len(formatted) <= 140


def test_format_reasoning_get_next_delivery_missing_sequence():
    """Test get_next_delivery reasoning returns None when sequence missing."""
    result = {
        "success": True,
        "has_next": True
    }
    formatted = reasoning_formatter.format_reasoning("get_next_delivery", result)
    assert formatted is None


def test_format_reasoning_log_exception_with_both_fields():
    """Test log_exception reasoning with reason and resolution."""
    result = {
        "success": True,
        "reason": "customer_not_home",
        "resolution": "left_with_neighbour"
    }
    formatted = reasoning_formatter.format_reasoning("log_exception", result)
    assert formatted == "Recorded customer not home; next step is left with neighbour."
    assert len(formatted) <= 140


def test_format_reasoning_log_exception_missing_fields():
    """Test log_exception reasoning returns None when fields missing."""
    result = {
        "success": True,
        "reason": "customer_not_home"
    }
    formatted = reasoning_formatter.format_reasoning("log_exception", result)
    assert formatted is None


def test_format_reasoning_get_best_route_with_savings():
    """Test get_best_route reasoning with time savings."""
    result = {
        "success": True,
        "has_faster_route": True,
        "time_saved_mins": 7,
        "best_route": {"duration_mins": 11}
    }
    formatted = reasoning_formatter.format_reasoning("get_best_route", result)
    assert formatted == "This route saves about 7 min versus the alternative."
    assert len(formatted) <= 140


def test_format_reasoning_get_best_route_duration_only():
    """Test get_best_route reasoning with duration only."""
    result = {
        "success": True,
        "has_faster_route": False,
        "best_route": {"duration_mins": 11}
    }
    formatted = reasoning_formatter.format_reasoning("get_best_route", result)
    assert formatted == "The fastest available route is about 11 min."
    assert len(formatted) <= 140


def test_format_reasoning_get_best_route_no_route():
    """Test get_best_route reasoning returns None when no route data."""
    result = {
        "success": True,
        "has_faster_route": False
    }
    formatted = reasoning_formatter.format_reasoning("get_best_route", result)
    assert formatted is None


def test_format_reasoning_start_navigation_with_both_fields():
    """Test start_navigation reasoning with distance and duration."""
    result = {
        "success": True,
        "route": {
            "distance_km": 3.2,
            "duration_mins": 11
        }
    }
    formatted = reasoning_formatter.format_reasoning("start_navigation", result)
    assert formatted == "This route is 3.2 km and about 11 min."
    assert len(formatted) <= 140


def test_format_reasoning_start_navigation_missing_fields():
    """Test start_navigation reasoning returns None when fields missing."""
    result = {
        "success": True,
        "route": {"distance_km": 3.2}
    }
    formatted = reasoning_formatter.format_reasoning("start_navigation", result)
    assert formatted is None


def test_format_reasoning_call_customer_with_call_sid():
    """Test call_customer reasoning with call ID."""
    result = {
        "success": True,
        "call_sid": "CA123456789"
    }
    formatted = reasoning_formatter.format_reasoning("call_customer", result)
    assert formatted == "The call request was created for this stop."
    assert len(formatted) <= 140


def test_format_reasoning_call_customer_no_call_sid():
    """Test call_customer reasoning returns None when no call ID."""
    result = {
        "success": True
    }
    formatted = reasoning_formatter.format_reasoning("call_customer", result)
    assert formatted is None


def test_format_reasoning_notify_customer_successful():
    """Test notify_customer reasoning with successful status."""
    result = {
        "success": True,
        "status": "sent"
    }
    formatted = reasoning_formatter.format_reasoning("notify_customer", result)
    assert formatted == "The customer update is sent."
    assert len(formatted) <= 140


def test_format_reasoning_notify_customer_unsuccessful_status():
    """Test notify_customer reasoning returns None for unsuccessful status."""
    result = {
        "success": True,
        "status": "failed"
    }
    formatted = reasoning_formatter.format_reasoning("notify_customer", result)
    assert formatted is None


def test_format_reasoning_get_next_order_offered():
    """Test get_next_order reasoning when order is offered."""
    result = {
        "success": True,
        "has_next": True,
        "offered_to_you": True,
        "distance_km": 0.51
    }
    formatted = reasoning_formatter.format_reasoning("get_next_order", result)
    assert formatted == "This offer is 0.51 km from your current position."
    assert len(formatted) <= 140


def test_format_reasoning_get_next_order_unassigned():
    """Test get_next_order reasoning when order is unassigned."""
    result = {
        "success": True,
        "has_next": True,
        "offered_to_you": False,
        "distance_km": 1.2
    }
    formatted = reasoning_formatter.format_reasoning("get_next_order", result)
    assert formatted == "The nearest waiting order is 1.2 km away."
    assert len(formatted) <= 140


def test_format_reasoning_get_next_order_no_orders():
    """Test get_next_order reasoning when no orders waiting."""
    result = {
        "success": True,
        "has_next": False
    }
    formatted = reasoning_formatter.format_reasoning("get_next_order", result)
    assert formatted == "No new orders are waiting right now."
    assert len(formatted) <= 140


def test_format_reasoning_accept_order_with_window():
    """Test accept_order reasoning with time window."""
    result = {
        "success": True,
        "sequence": 5,
        "time_window": "3:00 PM - 5:00 PM"
    }
    formatted = reasoning_formatter.format_reasoning("accept_order", result)
    assert formatted == "The order was added as stop 5. Its window is 3:00 PM - 5:00 PM."
    assert len(formatted) <= 140


def test_format_reasoning_accept_order_without_window():
    """Test accept_order reasoning without time window."""
    result = {
        "success": True,
        "sequence": 5
    }
    formatted = reasoning_formatter.format_reasoning("accept_order", result)
    assert formatted == "The order was added as stop 5."
    assert len(formatted) <= 140


def test_format_reasoning_decline_order_with_next_driver():
    """Test decline_order reasoning with next driver distance."""
    result = {
        "success": True,
        "passed_to": {"distance_km": 2.3}
    }
    formatted = reasoning_formatter.format_reasoning("decline_order", result)
    assert formatted == "The next driver is 2.3 km from the drop-off."
    assert len(formatted) <= 140


def test_format_reasoning_decline_order_no_next_driver():
    """Test decline_order reasoning when no next driver available."""
    result = {
        "success": True,
        "passed_to": None
    }
    formatted = reasoning_formatter.format_reasoning("decline_order", result)
    assert formatted == "No other driver is free, so the order returned to the queue."
    assert len(formatted) <= 140


def test_format_reasoning_get_shift_summary_with_failures():
    """Test get_shift_summary reasoning with failures."""
    result = {
        "success": True,
        "delivered": 14,
        "total": 22,
        "remaining": 6,
        "failed": 2
    }
    formatted = reasoning_formatter.format_reasoning("get_shift_summary", result)
    assert formatted == "You have completed 14 of 22; 6 remain. 2 failed."
    assert len(formatted) <= 140


def test_format_reasoning_get_shift_summary_without_failures():
    """Test get_shift_summary reasoning without failures."""
    result = {
        "success": True,
        "delivered": 14,
        "total": 22,
        "remaining": 6,
        "failed": 0
    }
    formatted = reasoning_formatter.format_reasoning("get_shift_summary", result)
    assert formatted == "You have completed 14 of 22; 6 remain."
    assert len(formatted) <= 140


def test_format_reasoning_failed_tool():
    """Test reasoning returns None for failed tool results."""
    result = {
        "success": False,
        "error": "Something went wrong"
    }
    formatted = reasoning_formatter.format_reasoning("get_next_delivery", result)
    assert formatted is None


def test_format_reasoning_unknown_tool():
    """Test reasoning returns None for unknown tools."""
    result = {
        "success": True,
        "some_field": "value"
    }
    formatted = reasoning_formatter.format_reasoning("unknown_tool", result)
    assert formatted is None


def test_format_reasoning_tools_without_templates():
    """Test reasoning returns None for tools without templates."""
    # update_delivery_status, alert_dispatcher, show_screen, end_conversation have no reasoning
    for tool_name in ["update_delivery_status", "alert_dispatcher", "show_screen", "end_conversation"]:
        result = {"success": True, "status": "completed"}
        formatted = reasoning_formatter.format_reasoning(tool_name, result)
        assert formatted is None


def test_format_reasoning_length_exceeds_limit():
    """Test reasoning returns None when formatted text exceeds 140 chars."""
    result = {
        "success": True,
        "sequence": 1234567890,
        "time_window": "This is an extremely long time window description that would cause the formatted reasoning text to exceed the 140 character limit set by the interface contract"
    }
    formatted = reasoning_formatter.format_reasoning("get_next_delivery", result)
    assert formatted is None


def test_reasoning_provenance_from_result_fields():
    """Test reasoning is derived only from result fields, not from context or other sources."""
    result = {
        "success": True,
        "has_faster_route": True,
        "time_saved_mins": 7
    }
    # Call with empty context to prove it doesn't use context
    formatted = reasoning_formatter.format_reasoning("get_best_route", result)
    assert formatted == "This route saves about 7 min versus the alternative."
    assert "7" in formatted  # Proves it came from result field


def test_reasoning_no_pii_leakage():
    """Test reasoning doesn't include PII even if present in result."""
    result = {
        "success": True,
        "call_sid": "CA123456789",
        "customer_phone": "+1234567890",  # PII that should not appear
        "customer_name": "John Doe"  # PII that should not appear
    }
    formatted = reasoning_formatter.format_reasoning("call_customer", result)
    assert formatted == "The call request was created for this stop."
    assert "+1234567890" not in formatted
    assert "John Doe" not in formatted
