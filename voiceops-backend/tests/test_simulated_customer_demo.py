"""
Tests for simulated customer call demo feature.
Tests scenarios, pinned scenario, flag off leaves behaviour unchanged, no network or Twilio.
"""
import asyncio
import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from app.agents.tools.communication import call_customer, _simulated_customer_call
from app.config import settings


def test_simulated_customer_call_scenarios():
    """Test all four simulated customer scenarios."""
    scenarios = ["home", "neighbour", "gate_code", "reschedule"]

    for scenario in scenarios:
        with patch.object(settings, 'demo_simulated_customer', True):
            with patch.object(settings, 'demo_simulated_customer_scenario', scenario):
                context = {"eta_minutes": 6}
                result = asyncio.run(_simulated_customer_call("Tunde", context, None))

                assert result["success"] is True
                assert result["call_sid"].startswith("demo-")
                assert result["call_sid"].startswith(f"demo-{scenario}")
                assert result["customer_name"] == "Tunde"
                assert result["status"] == "initiated"

                # Check outcome is stored in context
                assert "simulated_customer_outcome" in context
                assert "Tunde" in context["simulated_customer_outcome"]


def test_simulated_customer_call_random_scenario():
    """Test random scenario selection when not pinned."""
    with patch.object(settings, 'demo_simulated_customer', True):
        with patch.object(settings, 'demo_simulated_customer_scenario', None):
            context = {"eta_minutes": 10}
            result = asyncio.run(_simulated_customer_call("Maria", context, None))

            assert result["success"] is True
            assert result["call_sid"].startswith("demo-")
            assert result["customer_name"] == "Maria"
            assert "simulated_customer_outcome" in context


def test_simulated_customer_call_invalid_scenario():
    """Test fallback to random when scenario name is invalid."""
    with patch.object(settings, 'demo_simulated_customer', True):
        with patch.object(settings, 'demo_simulated_customer_scenario', "invalid_scenario"):
            context = {"eta_minutes": 5}
            result = asyncio.run(_simulated_customer_call("John", context, None))

            assert result["success"] is True
            assert result["call_sid"].startswith("demo-")
            assert "simulated_customer_outcome" in context


def test_simulated_customer_call_eta_fallback():
    """Test ETA fallback to 10 minutes when not in context."""
    with patch.object(settings, 'demo_simulated_customer', True):
        with patch.object(settings, 'demo_simulated_customer_scenario', "home"):
            context = {}  # No eta_minutes
            result = asyncio.run(_simulated_customer_call("Alice", context, None))

            assert result["success"] is True
            assert "10 minutes" in context["simulated_customer_outcome"]


def test_simulated_customer_call_invalid_eta():
    """Test ETA fallback when context has invalid eta value."""
    with patch.object(settings, 'demo_simulated_customer', True):
        with patch.object(settings, 'demo_simulated_customer_scenario', "home"):
            context = {"eta_minutes": "invalid"}  # Invalid ETA
            result = asyncio.run(_simulated_customer_call("Bob", context, None))

            assert result["success"] is True
            assert "10 minutes" in context["simulated_customer_outcome"]


def test_call_customer_with_demo_flag_off():
    """Test that call_customer uses Twilio when demo flag is off."""
    with patch.object(settings, 'demo_simulated_customer', False):
        with patch('app.agents.tools.communication.make_call') as mock_make_call:
            with patch('app.agents.tools.communication._log_customer_interaction') as mock_log:
                mock_make_call.return_value = {
                    "success": True,
                    "call_sid": "CA123456789",
                    "customer_name": "Customer"
                }

                context = {
                    "current_delivery": {
                        "id": "delivery-123",
                        "customer_phone": "+1234567890",
                        "recipient_name": "Test Customer"
                    }
                }

                result = asyncio.run(call_customer({"delivery_id": "delivery-123"}, context))

                assert result["success"] is True
                assert result["call_sid"] == "CA123456789"
                mock_make_call.assert_called_once()
                mock_log.assert_called_once()


def test_call_customer_with_demo_flag_on():
    """Test that call_customer uses simulated call when demo flag is on."""
    with patch.object(settings, 'demo_simulated_customer', True):
        with patch('app.agents.tools.communication.make_call') as mock_make_call:
            context = {
                "current_delivery": {
                    "id": "delivery-123",
                    "customer_phone": "+1234567890",
                    "recipient_name": "Test Customer"
                }
            }

            result = asyncio.run(call_customer({"delivery_id": "delivery-123"}, context))

            assert result["success"] is True
            assert result["call_sid"].startswith("demo-")
            # make_call should NOT be called when demo is on
            mock_make_call.assert_not_called()


def test_simulated_customer_outcome_content():
    """Test that outcome content includes customer name and ETA."""
    with patch.object(settings, 'demo_simulated_customer', True):
        with patch.object(settings, 'demo_simulated_customer_scenario', "home"):
            context = {"eta_minutes": 8}
            result = asyncio.run(_simulated_customer_call("Sarah", context, None))

            outcome = context["simulated_customer_outcome"]
            assert "Sarah" in outcome
            assert "8 minutes" in outcome
            assert "home" in outcome.lower()


def test_simulated_customer_all_scenarios_unique():
    """Test that each scenario produces unique outcome content."""
    scenario_keywords = {
        "home": ["home", "answer the door"],
        "neighbour": ["neighbour"],
        "gate_code": ["2468", "gate code"],
        "reschedule": ["4 to 6 PM", "reschedule"]
    }

    for scenario, keywords in scenario_keywords.items():
        with patch.object(settings, 'demo_simulated_customer', True):
            with patch.object(settings, 'demo_simulated_customer_scenario', scenario):
                context = {"eta_minutes": 5}
                asyncio.run(_simulated_customer_call("Customer", context, None))

                outcome = context["simulated_customer_outcome"]
                for keyword in keywords:
                    assert keyword in outcome, f"Keyword '{keyword}' not found in scenario '{scenario}' outcome: {outcome}"


def test_simulated_customer_no_network_calls():
    """Test that simulated customer does not make any network calls."""
    with patch.object(settings, 'demo_simulated_customer', True):
        with patch('app.agents.tools.communication.make_call') as mock_make_call:
            with patch('app.integrations.twilio_client.make_call') as mock_twilio:
                context = {
                    "current_delivery": {
                        "id": "delivery-123",
                        "customer_phone": "+1234567890",
                        "recipient_name": "Test Customer"
                    }
                }

                result = asyncio.run(call_customer({"delivery_id": "delivery-123"}, context))

                assert result["success"] is True
                assert result["call_sid"].startswith("demo-")
                # Neither make_call should be called
                mock_make_call.assert_not_called()
                mock_twilio.assert_not_called()
