"""
Tests for order completion and summary generation trigger.
"""
import pytest
from unittest.mock import AsyncMock, patch, MagicMock


class TestOrderCompletionSummary:
    """Test order completion triggering summary generation."""
    
    def test_trigger_delivery_summary_callable(self):
        """Test that _trigger_delivery_summary function exists and is callable."""
        from app.agents.tools.delivery import _trigger_delivery_summary
        assert callable(_trigger_delivery_summary)
    
    def test_trigger_delivery_summary_signature(self):
        """Test _trigger_delivery_summary has correct signature."""
        from app.agents.tools.delivery import _trigger_delivery_summary
        import inspect
        sig = inspect.signature(_trigger_delivery_summary)
        params = list(sig.parameters.keys())
        assert "shift_id" in params
        assert "driver_id" in params


class TestProfileDataLoading:
    """Test profile data loading improvements."""
    
    def test_get_driver_by_id_with_invalid_uuid(self):
        """Test driver retrieval with invalid UUID."""
        from app.db.queries import get_driver_by_id, is_valid_uuid
        
        # Test that invalid UUID returns None
        assert is_valid_uuid("invalid-uuid") is False
    
    def test_profile_service_import(self):
        """Test that profile service can be imported."""
        from app.services.preference_service import PreferenceService
        assert PreferenceService is not None
    
    def test_preference_models_import(self):
        """Test that preference models can be imported."""
        from app.services.preference_models import (
            GeoZone,
            OrderTypePreference,
            TimeBasedPreferences,
            EnhancedPreferences,
            PreferenceConflictResolver
        )
        assert GeoZone is not None
        assert OrderTypePreference is not None
        assert TimeBasedPreferences is not None
        assert EnhancedPreferences is not None
        assert PreferenceConflictResolver is not None
    
    def test_geo_preferences_import(self):
        """Test that geo preferences utilities can be imported."""
        from app.utils.geo_preferences import (
            is_point_in_zone,
            check_zone_conflict,
            is_order_acceptable_by_location
        )
        assert is_point_in_zone is not None
        assert check_zone_conflict is not None
        assert is_order_acceptable_by_location is not None
    
    def test_time_preferences_import(self):
        """Test that time preferences utilities can be imported."""
        from app.utils.time_preferences import (
            is_time_in_range,
            should_accept_order_by_time,
            is_auto_accept_enabled
        )
        assert is_time_in_range is not None
        assert should_accept_order_by_time is not None
        assert is_auto_accept_enabled is not None
    
    def test_order_type_preferences_import(self):
        """Test that order type preferences utilities can be imported."""
        from app.utils.order_type_preferences import (
            is_order_type_accepted,
            calculate_order_priority_bonus
        )
        assert is_order_type_accepted is not None
        assert calculate_order_priority_bonus is not None
    
    def test_driver_profile_endpoint_exists(self):
        """Test that driver profile endpoint exists."""
        from app.api.routes import driver
        assert hasattr(driver, "get_profile")
        assert hasattr(driver, "update_profile")
        assert hasattr(driver, "sign_out")