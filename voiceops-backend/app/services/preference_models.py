"""
Enhanced preference models with support for geographic areas, order types, and time-based rules.
"""
from typing import Dict, Any, List, Optional
from dataclasses import dataclass, field
from datetime import time
import json


@dataclass
class GeoZone:
    """Geographic zone defined by coordinates."""
    name: str
    center_lat: float
    center_lng: float
    radius_km: float
    zone_type: str  # "preferred" or "avoided"
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "center_lat": self.center_lat,
            "center_lng": self.center_lng,
            "radius_km": self.radius_km,
            "zone_type": self.zone_type
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'GeoZone':
        return cls(
            name=data.get("name", ""),
            center_lat=float(data.get("center_lat", 0.0)),
            center_lng=float(data.get("center_lng", 0.0)),
            radius_km=float(data.get("radius_km", 0.0)),
            zone_type=data.get("zone_type", "preferred")
        )


@dataclass
class OrderTypePreference:
    """Order type filtering preferences."""
    accepted_categories: List[str] = field(default_factory=list)
    max_weight_kg: Optional[float] = None
    max_dimensions: Optional[Dict[str, float]] = None
    min_order_value: Optional[float] = None
    priority_categories: List[str] = field(default_factory=list)
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "accepted_categories": self.accepted_categories,
            "max_weight_kg": self.max_weight_kg,
            "max_dimensions": self.max_dimensions,
            "min_order_value": self.min_order_value,
            "priority_categories": self.priority_categories
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'OrderTypePreference':
        return cls(
            accepted_categories=data.get("accepted_categories", []),
            max_weight_kg=data.get("max_weight_kg"),
            max_dimensions=data.get("max_dimensions"),
            min_order_value=data.get("min_order_value"),
            priority_categories=data.get("priority_categories", [])
        )


@dataclass
class TimeRange:
    """Time range for preference rules."""
    start_hour: int
    start_minute: int
    end_hour: int
    end_minute: int
    days_of_week: List[int] = field(default_factory=list)  # 0=Monday, 6=Sunday
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "start_hour": self.start_hour,
            "start_minute": self.start_minute,
            "end_hour": self.end_hour,
            "end_minute": self.end_minute,
            "days_of_week": self.days_of_week
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'TimeRange':
        return cls(
            start_hour=data.get("start_hour", 0),
            start_minute=data.get("start_minute", 0),
            end_hour=data.get("end_hour", 23),
            end_minute=data.get("end_minute", 59),
            days_of_week=data.get("days_of_week", [])
        )


@dataclass
class TimeBasedPreferences:
    """Time-based preference rules."""
    auto_accept_enabled_hours: List[TimeRange] = field(default_factory=list)
    disable_auto_accept_during_rush_hour: bool = False
    rush_hour_start: str = "17:00"  # 5 PM
    rush_hour_end: str = "19:00"    # 7 PM
    break_times: List[TimeRange] = field(default_factory=list)
    shift_start_preference: str = "any"  # "early", "late", "any"
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "auto_accept_enabled_hours": [tr.to_dict() for tr in self.auto_accept_enabled_hours],
            "disable_auto_accept_during_rush_hour": self.disable_auto_accept_during_rush_hour,
            "rush_hour_start": self.rush_hour_start,
            "rush_hour_end": self.rush_hour_end,
            "break_times": [tr.to_dict() for tr in self.break_times],
            "shift_start_preference": self.shift_start_preference
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'TimeBasedPreferences':
        return cls(
            auto_accept_enabled_hours=[
                TimeRange.from_dict(tr) for tr in data.get("auto_accept_enabled_hours", [])
            ],
            disable_auto_accept_during_rush_hour=data.get("disable_auto_accept_during_rush_hour", False),
            rush_hour_start=data.get("rush_hour_start", "17:00"),
            rush_hour_end=data.get("rush_hour_end", "19:00"),
            break_times=[
                TimeRange.from_dict(tr) for tr in data.get("break_times", [])
            ],
            shift_start_preference=data.get("shift_start_preference", "any")
        )


@dataclass
class EnhancedPreferences:
    """Complete enhanced preferences including geographic, order type, and time-based rules."""
    geographic_zones: List[GeoZone] = field(default_factory=list)
    order_type_prefs: OrderTypePreference = field(default_factory=OrderTypePreference)
    time_based_prefs: TimeBasedPreferences = field(default_factory=TimeBasedPreferences)
    pickup_radius_km: Optional[float] = None
    current_location_preference: str = "current"  # "home", "work", "current"
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "geographic_zones": [zone.to_dict() for zone in self.geographic_zones],
            "order_type_prefs": self.order_type_prefs.to_dict(),
            "time_based_prefs": self.time_based_prefs.to_dict(),
            "pickup_radius_km": self.pickup_radius_km,
            "current_location_preference": self.current_location_preference
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'EnhancedPreferences':
        return cls(
            geographic_zones=[
                GeoZone.from_dict(zone) for zone in data.get("geographic_zones", [])
            ],
            order_type_prefs=OrderTypePreference.from_dict(data.get("order_type_prefs", {})),
            time_based_prefs=TimeBasedPreferences.from_dict(data.get("time_based_prefs", {})),
            pickup_radius_km=data.get("pickup_radius_km"),
            current_location_preference=data.get("current_location_preference", "current")
        )


class PreferenceConflictResolver:
    """Resolves conflicts between preferences."""
    
    @staticmethod
    def resolve_auto_accept_conflicts(preferences: Dict[str, Any]) -> Dict[str, Any]:
        """
        Resolve conflicts between auto_accept and auto_decline preferences.
        Priority: auto_decline > auto_accept > manual
        """
        auto_accept = preferences.get("auto_accept_orders") == "true"
        auto_decline = preferences.get("auto_decline_orders") == "true"
        
        if auto_decline and auto_accept:
            # auto_decline takes priority
            preferences["auto_accept_orders"] = "false"
            preferences["conflict_resolved"] = "auto_decline_takes_priority"
        
        return preferences
    
    @staticmethod
    def resolve_distance_conflicts(preferences: Dict[str, Any]) -> Dict[str, Any]:
        """
        Resolve conflicts between different distance preferences.
        Priority: pickup_radius > max_order_distance
        """
        pickup_radius = preferences.get("pickup_radius_km")
        max_order_distance = preferences.get("max_order_distance_km")
        
        if pickup_radius and max_order_distance:
            try:
                pickup_radius_km = float(pickup_radius)
                max_order_distance_km = float(max_order_distance)
                
                if pickup_radius_km < max_order_distance_km:
                    # pickup_radius is more restrictive
                    preferences["effective_max_distance"] = str(pickup_radius_km)
                    preferences["conflict_resolved"] = "pickup_radius_takes_priority"
                else:
                    preferences["effective_max_distance"] = str(max_order_distance_km)
                    preferences["conflict_resolved"] = "max_order_distance_takes_priority"
            except (ValueError, TypeError):
                # If conversion fails, leave as-is
                pass
        
        return preferences
    
    @staticmethod
    def resolve_all_conflicts(preferences: Dict[str, Any]) -> Dict[str, Any]:
        """Resolve all preference conflicts in priority order."""
        preferences = PreferenceConflictResolver.resolve_auto_accept_conflicts(preferences)
        preferences = PreferenceConflictResolver.resolve_distance_conflicts(preferences)
        return preferences
