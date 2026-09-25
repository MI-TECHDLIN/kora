"""
Unit tests for Milestone 1 & 2 services:
- Delivery State Machine
- Location Intelligence Service (Haversine & ETA)
- Context Builder
"""
import pytest
from app.services.delivery_state_machine import (
    validate_transition,
    assert_transition,
    is_terminal,
    get_allowed_transitions,
)
from app.services.location_service import (
    haversine_distance,
    LocationIntelligenceService,
)


def test_delivery_state_machine_valid_transitions():
    assert validate_transition("pending", "en_route") is True
    assert validate_transition("pending", "arrived") is True
    assert validate_transition("pending", "delivered") is True
    assert validate_transition("pending", "failed") is True
    assert validate_transition("en_route", "arrived") is True
    assert validate_transition("arrived", "delivered") is True
    assert validate_transition("failed", "rescheduled") is True
    assert validate_transition("rescheduled", "en_route") is True


def test_delivery_state_machine_terminal_state():
    assert is_terminal("delivered") is True
    assert is_terminal("pending") is False
    assert validate_transition("delivered", "pending") is False
    assert validate_transition("delivered", "en_route") is False

    with pytest.raises(ValueError):
        assert_transition("delivered", "en_route")


def test_haversine_distance_calculation():
    # South Congress to north downtown Austin (~3.5 km)
    lat1, lng1 = 30.2490, -97.7497
    lat2, lng2 = 30.2800, -97.7428

    dist = haversine_distance(lat1, lng1, lat2, lng2)
    assert 3000 < dist < 4500  # meters

    # Zero distance between identical points
    assert haversine_distance(lat1, lng1, lat1, lng1) == 0.0


def test_compute_eta():
    lat1, lng1 = 30.2490, -97.7497
    lat2, lng2 = 30.2800, -97.7428

    eta = LocationIntelligenceService.compute_eta(lat1, lng1, lat2, lng2, speed_kmh=30.0)
    assert isinstance(eta, int)
    assert eta >= 1


def test_eta_service_minutes():
    from app.services.eta_service import eta_service
    mins = eta_service.compute_eta_minutes((30.2490, -97.7497), (30.2800, -97.7428), current_speed_kmh=40.0)
    assert isinstance(mins, int)
    assert mins >= 1


def test_alert_service_cooldown():
    import asyncio
    from app.services.proactive_alert_service import ProactiveAlertService

    service = ProactiveAlertService()
    driver_id = "test-driver-cooldown-001"
    risk_type = "LATE_DELIVERY"

    # First alert should succeed
    allowed1 = asyncio.run(service.should_alert(driver_id, risk_type, cooldown_minutes=15))
    assert allowed1 is True

    # Immediate second alert for same driver and risk should be suppressed by cooldown
    allowed2 = asyncio.run(service.should_alert(driver_id, risk_type, cooldown_minutes=15))
    assert allowed2 is False

    # Different risk type should be allowed
    allowed3 = asyncio.run(service.should_alert(driver_id, "EXCESSIVE_IDLE", cooldown_minutes=15))
    assert allowed3 is True


def test_exception_workflow():
    import asyncio
    from app.services.exception_workflow import exception_workflow_service

    context = {
        "driver_id": "test-driver-123",
        "driver_name": "Morgan Driver",
        "shift_id": "test-shift-123",
        "current_delivery": {
            "id": "del-mock-999",
            "recipient_name": "Marcus",
            "address": "812 Lavaca St",
            "customer_phone": "+15125550100",
        }
    }

    result = asyncio.run(exception_workflow_service.handle_customer_unavailable(
        delivery_id="del-mock-999",
        driver_id="test-driver-123",
        context=context
    ))

    assert result.get("success") is True
    assert result.get("workflow") == "customer_unavailable"
    assert "guidance" in result


def test_routing_service_calculation():
    import asyncio
    from app.services.routing_service import routing_service

    # Calculate a route between two downtown Austin coordinates.
    route = asyncio.run(routing_service.calculate_route(
        origin=(30.2490, -97.7497),
        destination=(30.2800, -97.7428),
    ))

    assert route.get("success") is True
    assert "distance_km" in route
    assert "duration_mins" in route
    assert route["distance_km"] > 0


def test_tool_safety_gate():
    import asyncio
    from app.agents.tool_safety import tool_safety_gate

    context = {
        "driver_id": "test-driver-123",
        "is_demo": True,
        "current_delivery": {"id": "del-demo-123", "status": "pending"}
    }

    # Allowed valid check
    allowed, reason = asyncio.run(tool_safety_gate.check(
        tool_name="get_next_delivery",
        parameters={},
        context=context
    ))
    assert allowed is True
    assert reason == ""


def test_dispatcher_agent_risk_evaluation():
    import asyncio
    from app.agents.dispatcher_agent import dispatcher_agent

    mock_snapshot = {
        "active_drivers_count": 2,
        "open_deliveries_count": 50,  # High ratio > 15
        "alerts": [
            {
                "id": "alert-1",
                "driver_id": "drv-1",
                "message": "Assault threat",
                "severity": "critical",
                "is_critical": True
            }
        ]
    }

    recommendations = asyncio.run(dispatcher_agent.evaluate_fleet_risk(mock_snapshot))
    assert len(recommendations) >= 1
    types = [r["type"] for r in recommendations]
    assert "CRITICAL_INCIDENT" in types
    assert "FLEET_OVERLOAD" in types


def test_memory_agent_worthiness():
    from app.agents.memory_agent import memory_agent

    # Worth storing: high confidence and meaningful text
    assert memory_agent._is_worth_storing("Gate code is 9876. Security guard named John.", confidence=0.85) is True

    # Noise: low confidence
    assert memory_agent._is_worth_storing("Gate code is 9876", confidence=0.4) is False

    # Noise: too short
    assert memory_agent._is_worth_storing("ok", confidence=0.9) is False


def test_event_bus_pub_sub():
    import asyncio
    from app.services.event_bus import EventBus, Events

    received_events = []

    def handle_test_event(payload):
        received_events.append(payload)

    EventBus.subscribe("TEST_EVENT", handle_test_event)

    asyncio.run(EventBus.publish("TEST_EVENT", {"data": 42}))
    assert len(received_events) == 1
    assert received_events[0]["data"] == 42


def test_customer_agent_sandboxing():
    import asyncio
    from app.agents.customer_agent import customer_agent

    # Forbidden action
    res_forbidden = asyncio.run(customer_agent.handle_request(
        action="issue_refund",
        delivery_id="del-123",
        payload={"amount": 500}
    ))
    assert res_forbidden["success"] is False
    assert "forbidden" in res_forbidden["error"].lower()


def test_optimization_service_greedy():
    import asyncio
    from app.services.optimization_service import optimization_service

    origin = (30.2672, -97.7431)  # Downtown Austin
    deliveries = [
        {"id": "far", "dropoff_latitude": 30.2490, "dropoff_longitude": -97.7497, "address": "S Congress Ave"},
        {"id": "near", "dropoff_latitude": 30.2673, "dropoff_longitude": -97.7419, "address": "Brazos St"},
        {"id": "mid", "dropoff_latitude": 30.2713, "dropoff_longitude": -97.7455, "address": "Lavaca St"},
    ]

    optimized = asyncio.run(optimization_service.optimize_route(
        driver_id="drv-1",
        shift_id="shift-1",
        deliveries=deliveries,
        origin=origin,
    ))

    assert len(optimized) == 3
    # Nearest stop should be visited first
    assert optimized[0]["id"] == "near"
    assert optimized[0]["sequence_order"] == 1
    assert optimized[1]["id"] == "mid"
    assert optimized[1]["sequence_order"] == 2
    assert optimized[2]["id"] == "far"
    assert optimized[2]["sequence_order"] == 3


def test_tool_orchestrator_trace_id():
    import asyncio
    from app.agents.orchestrator import ToolOrchestrator

    context = {
        "driver_id": "test-trace-driver",
        "is_demo": True,
        "current_delivery": {"id": "del-trace-1", "status": "pending"}
    }

    result = asyncio.run(ToolOrchestrator.execute_single_tool(
        tool_name="get_next_delivery",
        parameters={},
        context=context
    ))

    assert "trace_id" in result
    assert len(result["trace_id"]) > 0
    assert result["tool_name"] == "get_next_delivery"

