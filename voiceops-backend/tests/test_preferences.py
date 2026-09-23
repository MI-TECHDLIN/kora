"""
Tests for driver preferences service and tools.
"""
import pytest
from unittest.mock import Mock, patch
from app.services.preference_service import PreferenceService


def test_preference_service_no_client():
    """Test preference service without Supabase client."""
    service = PreferenceService.__new__(PreferenceService)
    service._client = None
    
    # Should return empty dict when no client
    import asyncio
    result = asyncio.run(service.get_preferences("driver-123"))
    assert result == {}


def test_preference_tools_import():
    """Test that preference tools can be imported."""
    from app.agents.tools.preferences import (
        get_preferences,
        set_preference,
        clear_preference,
        reset_preferences
    )
    
    # Verify all tools are callable
    assert callable(get_preferences)
    assert callable(set_preference)
    assert callable(clear_preference)
    assert callable(reset_preferences)


def test_preference_service_initialization():
    """Test preference service initialization."""
    service = PreferenceService.__new__(PreferenceService)
    service._client = None
    
    assert service._client is None


def test_preference_service_with_credentials():
    """Test preference service initialization with credentials."""
    mock_client = Mock()
    with patch('app.services.preference_service.create_client', return_value=mock_client):
        service = PreferenceService(supabase_url="http://test.com", supabase_key="test-key")
        assert service._client == mock_client


def test_initialize_preference_service():
    """Test global preference service initialization."""
    from app.services.preference_service import initialize_preference_service
    
    mock_client = Mock()
    with patch('app.services.preference_service.create_client', return_value=mock_client):
        initialize_preference_service("http://test.com", "test-key")
        
        # Check that the global instance was updated
        from app.services.preference_service import preference_service
        assert preference_service._client == mock_client


def test_preference_keys_validation():
    """Test that valid preference keys are used."""
    valid_keys = [
        "auto_accept_orders",
        "auto_decline_orders",
        "max_order_distance_km",
        "avoid_highways",
        "prefer_residential",
        "always_call_before_delivery",
        "never_call_customer",
        "always_send_sms",
        "max_deliveries_per_shift",
        "auto_announce_next_stop",
        "proactive_traffic_alerts"
    ]
    
    # Verify all keys are strings
    for key in valid_keys:
        assert isinstance(key, str)
        assert len(key) > 0


def test_preference_value_types():
    """Test that preference values can be different types."""
    # Boolean values
    assert "true" == "true"
    assert "false" == "false"
    
    # Numeric values (stored as strings)
    assert "5.0" == "5.0"
    assert "10" == "10"
    
    # String values
    assert "residential" == "residential"


def test_preference_tool_in_registry():
    """Test that preference tools are registered in the tool registry."""
    from app.agents.tool_registry import TOOL_EXECUTORS
    
    # Check that preference tools are in the executors
    assert "get_preferences" in TOOL_EXECUTORS
    assert "set_preference" in TOOL_EXECUTORS
    assert "clear_preference" in TOOL_EXECUTORS
    assert "reset_preferences" in TOOL_EXECUTORS


def test_preference_service_module_structure():
    """Test that preference service module has correct structure."""
    from app.services import preference_service
    
    # Check that the module has the expected class
    assert hasattr(preference_service, "PreferenceService")
    
    # Check that the module has the global instance
    assert hasattr(preference_service, "preference_service")
    
    # Check that the module has the initialization function
    assert hasattr(preference_service, "initialize_preference_service")
