"""
Deterministic reasoning formatter for task_step events.
Generates optional 'reasoning' field based on tool result fields and status.
Follows the contract: reasoning appears on both active and done status,
text is deterministically derived from returned fields, max 140 characters.
"""
from typing import Any, Dict, Optional


def format_reasoning(tool_name: str, result: Dict[str, Any], status: str = "done") -> Optional[str]:
    """
    Generate deterministic reasoning text for a tool.
    For active status: generates real-time reasoning about what the agent is doing.
    For done status: generates result-based reasoning from tool output.
    Returns None if the tool has no reasoning template or required fields are missing.
    """
    if status == "active":
        return _format_active_reasoning(tool_name)
    
    if not result.get("success"):
        return None

    formatters = {
        "get_next_delivery": _format_get_next_delivery,
        "log_exception": _format_log_exception,
        "get_best_route": _format_get_best_route,
        "start_navigation": _format_start_navigation,
        "call_customer": _format_call_customer,
        "notify_customer": _format_notify_customer,
        "get_next_order": _format_get_next_order,
        "accept_order": _format_accept_order,
        "decline_order": _format_decline_order,
        "get_shift_summary": _format_get_shift_summary,
    }

    formatter = formatters.get(tool_name)
    if formatter:
        reasoning = formatter(result)
        if reasoning and len(reasoning) <= 140:
            return reasoning
    return None


def _format_active_reasoning(tool_name: str) -> Optional[str]:
    """
    Generate real-time reasoning for active status explaining what the agent is doing.
    This helps users understand the agent's actions in real-time.
    """
    active_reasonings = {
        "get_next_delivery": "Finding your next delivery stop from the route.",
        "update_delivery_status": "Updating the delivery status in the system.",
        "log_exception": "Recording the delivery exception details.",
        "get_best_route": "Checking traffic and calculating the fastest route.",
        "start_navigation": "Setting up navigation to the delivery location.",
        "call_customer": "Initiating a call to the customer.",
        "notify_customer": "Sending an SMS notification to the customer.",
        "get_next_order": "Checking the order queue for new assignments.",
        "accept_order": "Adding the new order to your delivery route.",
        "decline_order": "Passing the order to the next available driver.",
        "get_shift_summary": "Calculating your shift statistics and progress.",
        "alert_dispatcher": "Notifying the dispatcher about your situation.",
        "show_screen": "Opening the requested screen in the app.",
    }
    
    reasoning = active_reasonings.get(tool_name)
    if reasoning and len(reasoning) <= 140:
        return reasoning
    return None


def _format_get_next_delivery(result: Dict[str, Any]) -> Optional[str]:
    """Format reasoning for get_next_delivery."""
    has_next = result.get("has_next")
    sequence = result.get("sequence")
    time_window = result.get("time_window")

    if has_next is False:
        return "There are no remaining deliveries in this shift."

    if sequence is not None:
        if time_window:
            line = f"Stop {sequence} is next, with a {time_window} delivery window."
        else:
            line = f"Stop {sequence} is next in your run."
        return line if len(line) <= 140 else None

    return None


def _format_log_exception(result: Dict[str, Any]) -> Optional[str]:
    """Format reasoning for log_exception."""
    reason = result.get("reason")
    resolution = result.get("resolution")

    if reason and resolution:
        # Map enum tokens to plain labels
        reason_labels = {
            "customer_not_home": "customer not home",
            "gate_code_required": "gate code required",
            "package_damaged": "package damaged",
            "wrong_address": "wrong address",
            "customer_refused": "customer refused",
        }
        resolution_labels = {
            "left_with_neighbour": "left with neighbour",
            "rescheduled": "rescheduled",
            "returned_to_sender": "returned to sender",
            "left_at_door": "left at door",
        }

        reason_label = reason_labels.get(reason, reason)
        resolution_label = resolution_labels.get(resolution, resolution)

        line = f"Recorded {reason_label}; next step is {resolution_label}."
        return line if len(line) <= 140 else None

    return None


def _format_get_best_route(result: Dict[str, Any]) -> Optional[str]:
    """Format reasoning for get_best_route."""
    has_faster_route = result.get("has_faster_route")
    time_saved_mins = result.get("time_saved_mins")
    best_route = result.get("best_route", {})

    if has_faster_route and time_saved_mins and time_saved_mins > 0:
        line = f"This route saves about {time_saved_mins} min versus the alternative."
        return line if len(line) <= 140 else None

    duration_mins = best_route.get("duration_mins")
    if duration_mins:
        line = f"The fastest available route is about {duration_mins} min."
        return line if len(line) <= 140 else None

    return None


def _format_start_navigation(result: Dict[str, Any]) -> Optional[str]:
    """Format reasoning for start_navigation."""
    route = result.get("route", {})
    distance_km = route.get("distance_km")
    duration_mins = route.get("duration_mins")

    if distance_km is not None and duration_mins is not None:
        line = f"This route is {distance_km} km and about {duration_mins} min."
        return line if len(line) <= 140 else None

    return None


def _format_call_customer(result: Dict[str, Any]) -> Optional[str]:
    """Format reasoning for call_customer."""
    call_sid = result.get("call_sid")
    if call_sid:
        return "The call request was created for this stop."
    return None


def _format_notify_customer(result: Dict[str, Any]) -> Optional[str]:
    """Format reasoning for notify_customer."""
    status = result.get("status")
    # Allowlist of successful statuses
    successful_statuses = {"sent", "delivered", "queued"}
    if status in successful_statuses:
        line = f"The customer update is {status}."
        return line if len(line) <= 140 else None
    return None


def _format_get_next_order(result: Dict[str, Any]) -> Optional[str]:
    """Format reasoning for get_next_order."""
    has_next = result.get("has_next")
    offered_to_you = result.get("offered_to_you")
    distance_km = result.get("distance_km")

    if has_next is False:
        return "No new orders are waiting right now."

    if offered_to_you and distance_km is not None:
        line = f"This offer is {distance_km} km from your current position."
        return line if len(line) <= 140 else None

    if not offered_to_you and distance_km is not None:
        line = f"The nearest waiting order is {distance_km} km away."
        return line if len(line) <= 140 else None

    return None


def _format_accept_order(result: Dict[str, Any]) -> Optional[str]:
    """Format reasoning for accept_order."""
    sequence = result.get("sequence")
    time_window = result.get("time_window")

    if sequence is not None:
        if time_window:
            line = f"The order was added as stop {sequence}. Its window is {time_window}."
            if len(line) <= 140:
                return line
        # Fallback without time window
        line = f"The order was added as stop {sequence}."
        return line if len(line) <= 140 else None

    return None


def _format_decline_order(result: Dict[str, Any]) -> Optional[str]:
    """Format reasoning for decline_order."""
    passed_to = result.get("passed_to")

    if passed_to is None:
        return "No other driver is free, so the order returned to the queue."

    if passed_to and isinstance(passed_to, dict):
        distance_km = passed_to.get("distance_km")
        if distance_km is not None:
            line = f"The next driver is {distance_km} km from the drop-off."
            return line if len(line) <= 140 else None

    return None


def _format_get_shift_summary(result: Dict[str, Any]) -> Optional[str]:
    """Format reasoning for get_shift_summary."""
    delivered = result.get("delivered")
    total = result.get("total")
    remaining = result.get("remaining")
    failed = result.get("failed")

    if delivered is not None and total is not None and remaining is not None:
        line = f"You have completed {delivered} of {total}; {remaining} remain."
        if failed and failed > 0:
            line_with_failed = f"{line} {failed} failed."
            if len(line_with_failed) <= 140:
                return line_with_failed
        return line if len(line) <= 140 else None

    return None
