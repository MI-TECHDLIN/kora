"""
Tests for enhanced preference system including geographic zones, order types, and time-based rules.
"""
import pytest
from app.services.preference_models import (
    GeoZone,
    OrderTypePreference,
    TimeRange,
    TimeBasedPreferences,
    EnhancedPreferences,
    PreferenceConflictResolver
)
from app.utils.geo_preferences import (
    is_point_in_zone,
    check_zone_conflict,
    is_order_acceptable_by_location,
    calculate_zone_bonus
)
from app.utils.time_preferences import (
    is_time_in_range,
    should_accept_order_by_time,
    is_auto_accept_enabled
)
from app.utils.order_type_preferences import (
    is_order_type_accepted,
    calculate_order_priority_bonus
)
from datetime import datetime, time


class TestPreferenceModels:
    """Test preference data models."""
    
    def test_geo_zone_creation(self):
        """Test creating a geographic zone."""
        zone = GeoZone(
            name="Downtown Austin",
            center_lat=30.2672,
            center_lng=-97.7431,
            radius_km=5.0,
            zone_type="preferred"
        )
        
        assert zone.name == "Downtown Austin"
        assert zone.center_lat == 30.2672
        assert zone.center_lng == -97.7431
        assert zone.radius_km == 5.0
        assert zone.zone_type == "preferred"
    
    def test_geo_zone_serialization(self):
        """Test GeoZone to_dict and from_dict."""
        zone = GeoZone(
            name="Test Zone",
            center_lat=30.0,
            center_lng=-97.0,
            radius_km=3.0,
            zone_type="avoided"
        )
        
        zone_dict = zone.to_dict()
        restored_zone = GeoZone.from_dict(zone_dict)
        
        assert restored_zone.name == zone.name
        assert restored_zone.center_lat == zone.center_lat
        assert restored_zone.center_lng == zone.center_lng
        assert restored_zone.radius_km == zone.radius_km
        assert restored_zone.zone_type == zone.zone_type
    
    def test_order_type_preference(self):
        """Test order type preference model."""
        prefs = OrderTypePreference(
            accepted_categories=["food", "packages"],
            max_weight_kg=50.0,
            max_dimensions={"length": 100, "width": 50, "height": 30},
            min_order_value=10.0,
            priority_categories=["food"]
        )
        
        assert "food" in prefs.accepted_categories
        assert prefs.max_weight_kg == 50.0
        assert prefs.min_order_value == 10.0
        assert "food" in prefs.priority_categories
    
    def test_time_range(self):
        """Test time range model."""
        time_range = TimeRange(
            start_hour=9,
            start_minute=0,
            end_hour=17,
            end_minute=0,
            days_of_week=[0, 1, 2, 3, 4]  # Monday to Friday
        )
        
        assert time_range.start_hour == 9
        assert time_range.end_hour == 17
        assert len(time_range.days_of_week) == 5
    
    def test_time_based_preferences(self):
        """Test time-based preferences model."""
        prefs = TimeBasedPreferences(
            disable_auto_accept_during_rush_hour=True,
            rush_hour_start="17:00",
            rush_hour_end="19:00"
        )
        
        assert prefs.disable_auto_accept_during_rush_hour is True
        assert prefs.rush_hour_start == "17:00"
        assert prefs.rush_hour_end == "19:00"
    
    def test_enhanced_preferences(self):
        """Test complete enhanced preferences model."""
        zone = GeoZone("Home", 30.0, -97.0, 2.0, "preferred")
        order_prefs = OrderTypePreference(accepted_categories=["food"])
        time_prefs = TimeBasedPreferences()
        
        enhanced = EnhancedPreferences(
            geographic_zones=[zone],
            order_type_prefs=order_prefs,
            time_based_prefs=time_prefs,
            pickup_radius_km=3.0
        )
        
        assert len(enhanced.geographic_zones) == 1
        assert enhanced.pickup_radius_km == 3.0


class TestPreferenceConflictResolver:
    """Test preference conflict resolution."""
    
    def test_auto_accept_vs_auto_decline(self):
        """Test that auto_decline takes priority over auto_accept."""
        preferences = {
            "auto_accept_orders": "true",
            "auto_decline_orders": "true"
        }
        
        resolved = PreferenceConflictResolver.resolve_auto_accept_conflicts(preferences)
        
        assert resolved["auto_accept_orders"] == "false"
        assert resolved["auto_decline_orders"] == "true"
        assert "conflict_resolved" in resolved
    
    def test_distance_conflict_resolution(self):
        """Test distance preference conflict resolution."""
        preferences = {
            "max_order_distance_km": "10.0",
            "pickup_radius_km": "5.0"
        }
        
        resolved = PreferenceConflictResolver.resolve_distance_conflicts(preferences)
        
        assert "effective_max_distance" in resolved
        assert resolved["effective_max_distance"] == "5.0"
        assert "conflict_resolved" in resolved
    
    def test_all_conflicts_resolution(self):
        """Test comprehensive conflict resolution."""
        preferences = {
            "auto_accept_orders": "true",
            "auto_decline_orders": "true",
            "max_order_distance_km": "10.0",
            "pickup_radius_km": "3.0"
        }
        
        resolved = PreferenceConflictResolver.resolve_all_conflicts(preferences)
        
        assert resolved["auto_accept_orders"] == "false"
        assert "effective_max_distance" in resolved


class TestGeographicPreferences:
    """Test geographic preference utilities."""
    
    def test_point_in_zone(self):
        """Test checking if a point is within a zone."""
        zone = GeoZone(
            name="Test Zone",
            center_lat=30.2672,
            center_lng=-97.7431,
            radius_km=5.0,
            zone_type="preferred"
        )
        
        # Point at center should be in zone
        assert is_point_in_zone(30.2672, -97.7431, zone) is True
        
        # Point far away should not be in zone
        assert is_point_in_zone(35.0, -100.0, zone) is False
    
    def test_zone_conflict_detection(self):
        """Test zone conflict detection."""
        preferred_zone = GeoZone("Preferred", 30.0, -97.0, 5.0, "preferred")
        avoided_zone = GeoZone("Avoided", 30.1, -97.1, 2.0, "avoided")
        
        # Point in avoided zone should return conflict
        has_conflict, reason = check_zone_conflict(30.1, -97.1, [avoided_zone])
        assert has_conflict is True
        assert "avoided" in reason.lower()
        
        # Point in preferred zone should not return conflict
        has_conflict, reason = check_zone_conflict(30.0, -97.0, [preferred_zone])
        assert has_conflict is False
        assert "preferred" in reason.lower()
    
    def test_order_acceptable_by_location(self):
        """Test comprehensive location-based order acceptance."""
        preferred_zone = GeoZone("Downtown", 30.2672, -97.7431, 5.0, "preferred")
        avoided_zone = GeoZone("Highway", 30.3, -97.8, 2.0, "avoided")
        
        # Order in preferred zone should be acceptable
        acceptable, reason = is_order_acceptable_by_location(
            30.2672, -97.7431, 30.0, -97.0,
            zones=[preferred_zone]
        )
        assert acceptable is True
        assert "preferred" in reason.lower()
        
        # Order in avoided zone should not be acceptable
        acceptable, reason = is_order_acceptable_by_location(
            30.3, -97.8, 30.0, -97.0,
            zones=[avoided_zone]
        )
        assert acceptable is False
        assert "avoided" in reason.lower()
        
        # Order within max distance should be acceptable
        acceptable, reason = is_order_acceptable_by_location(
            30.1, -97.1, 30.0, -97.0,
            max_distance_km=15.0
        )
        assert acceptable is True
        
        # Order beyond max distance should not be acceptable
        acceptable, reason = is_order_acceptable_by_location(
            35.0, -100.0, 30.0, -97.0,
            max_distance_km=5.0
        )
        assert acceptable is False
        assert "exceeds" in reason.lower()
    
    def test_zone_bonus_calculation(self):
        """Test zone bonus calculation."""
        preferred_zone = GeoZone("Preferred", 30.0, -97.0, 5.0, "preferred")
        avoided_zone = GeoZone("Avoided", 30.1, -97.1, 2.0, "avoided")
        
        # Point in preferred zone should get positive bonus
        bonus = calculate_zone_bonus(30.0, -97.0, [preferred_zone])
        assert bonus > 0
        
        # Point in avoided zone should get negative bonus
        bonus = calculate_zone_bonus(30.1, -97.1, [avoided_zone])
        assert bonus < 0
        
        # Point in no zone should get zero bonus
        bonus = calculate_zone_bonus(35.0, -100.0, [])
        assert bonus == 0.0


class TestTimeBasedPreferences:
    """Test time-based preference utilities."""
    
    def test_time_in_range(self):
        """Test checking if time is within range."""
        time_range = TimeRange(9, 0, 17, 0)
        
        # Time within range
        assert is_time_in_range(time(12, 0), time_range) is True
        
        # Time before range
        assert is_time_in_range(time(8, 0), time_range) is False
        
        # Time after range
        assert is_time_in_range(time(18, 0), time_range) is False
    
    def test_auto_accept_enabled_function_no_restrictions(self):
        """Test auto-accept function with no time restrictions."""
        enabled, reason = is_auto_accept_enabled()
        assert enabled is True
        assert "no time-based restrictions" in reason.lower()
    
    def test_auto_accept_enabled_function_during_rush_hour(self):
        """Test auto-accept function disabled during rush hour."""
        time_prefs = TimeBasedPreferences(
            disable_auto_accept_during_rush_hour=True,
            rush_hour_start="17:00",
            rush_hour_end="19:00"
        )
        
        # During rush hour
        enabled, reason = is_auto_accept_enabled(
            current_time=datetime(2026, 9, 23, 18, 0),
            time_prefs=time_prefs
        )
        assert enabled is False
        assert "rush hour" in reason.lower()
        
        # Outside rush hour
        enabled, reason = is_auto_accept_enabled(
            current_time=datetime(2026, 9, 23, 10, 0),
            time_prefs=time_prefs
        )
        assert enabled is True
    
    def test_should_accept_order_by_time(self):
        """Test order acceptance based on time."""
        time_prefs = TimeBasedPreferences(
            disable_auto_accept_during_rush_hour=True
        )
        
        # During rush hour
        should_accept, reason = should_accept_order_by_time(
            order_time=datetime(2026, 9, 23, 18, 0),
            time_prefs=time_prefs
        )
        assert should_accept is False
        
        # Outside rush hour
        should_accept, reason = should_accept_order_by_time(
            order_time=datetime(2026, 9, 23, 10, 0),
            time_prefs=time_prefs
        )
        assert should_accept is True
        """Test order acceptance based on time."""
        time_prefs = TimeBasedPreferences(
            disable_auto_accept_during_rush_hour=True
        )
        
        # During rush hour
        should_accept, reason = should_accept_order_by_time(
            order_time=datetime(2026, 9, 23, 18, 0),
            time_prefs=time_prefs
        )
        assert should_accept is False
        
        # Outside rush hour
        should_accept, reason = should_accept_order_by_time(
            order_time=datetime(2026, 9, 23, 10, 0),
            time_prefs=time_prefs
        )
        assert should_accept is True


class TestOrderTypePreferences:
    """Test order type preference utilities."""
    
    def test_order_type_accepted(self):
        """Test order type acceptance based on preferences."""
        prefs = OrderTypePreference(
            accepted_categories=["food", "packages"],
            max_weight_kg=50.0
        )
        
        # Accepted category
        accepted, reason = is_order_type_accepted("food", type_prefs=prefs)
        assert accepted is True
        
        # Rejected category
        accepted, reason = is_order_type_accepted("furniture", type_prefs=prefs)
        assert accepted is False
        assert "category" in reason.lower()
        
        # Weight constraint
        accepted, reason = is_order_type_accepted("food", order_weight_kg=60.0, type_prefs=prefs)
        assert accepted is False
        assert "weight" in reason.lower()
    
    def test_order_priority_bonus(self):
        """Test order priority bonus calculation."""
        prefs = OrderTypePreference(
            priority_categories=["food"],
            accepted_categories=["food", "packages"]
        )
        
        # Priority category should get higher bonus
        bonus = calculate_order_priority_bonus("food", prefs)
        assert bonus > 5.0  # Priority bonus
        
        # Accepted but not priority should get lower bonus
        bonus = calculate_order_priority_bonus("packages", prefs)
        assert bonus > 0 and bonus < 5.0
        
        # Neither priority nor accepted should get zero bonus
        bonus = calculate_order_priority_bonus("furniture", prefs)
        assert bonus == 0.0