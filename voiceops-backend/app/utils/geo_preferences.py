"""
Geographic utility functions for preference-based order acceptance.
"""
from typing import List, Tuple, Optional
from app.services.preference_models import GeoZone
from app.utils.geo import haversine_km


def is_point_in_zone(lat: float, lon: float, zone: GeoZone) -> bool:
    """
    Check if a point is within a geographic zone.
    
    Args:
        lat, lon: Point coordinates
        zone: GeoZone to check against
    
    Returns:
        True if point is within the zone radius
    """
    distance = haversine_km(lat, lon, zone.center_lat, zone.center_lng)
    return distance <= zone.radius_km


def check_zone_conflict(lat: float, lon: float, zones: List[GeoZone]) -> Tuple[bool, Optional[str]]:
    """
    Check if a point conflicts with any geographic zones.
    
    Args:
        lat, lon: Point coordinates
        zones: List of GeoZone objects
    
    Returns:
        Tuple of (has_conflict, conflict_reason)
    """
    for zone in zones:
        if is_point_in_zone(lat, lon, zone):
            if zone.zone_type == "avoided":
                return True, f"Order is in avoided zone: {zone.name}"
            elif zone.zone_type == "preferred":
                return False, f"Order is in preferred zone: {zone.name}"
    
    return False, None


def find_nearest_zone(lat: float, lon: float, zones: List[GeoZone]) -> Optional[GeoZone]:
    """
    Find the nearest geographic zone to a point.
    
    Args:
        lat, lon: Point coordinates
        zones: List of GeoZone objects
    
    Returns:
        Nearest GeoZone or None if no zones exist
    """
    if not zones:
        return None
    
    nearest_zone = None
    min_distance = float('inf')
    
    for zone in zones:
        distance = haversine_km(lat, lon, zone.center_lat, zone.center_lng)
        if distance < min_distance:
            min_distance = distance
            nearest_zone = zone
    
    return nearest_zone


def calculate_zone_bonus(lat: float, lon: float, zones: List[GeoZone]) -> float:
    """
    Calculate a bonus score based on zone preferences.
    
    Args:
        lat, lon: Point coordinates
        zones: List of GeoZone objects
    
    Returns:
        Bonus score (positive for preferred zones, negative for avoided)
    """
    bonus = 0.0
    
    for zone in zones:
        if is_point_in_zone(lat, lon, zone):
            if zone.zone_type == "preferred":
                bonus += 10.0  # Strong preference bonus
            elif zone.zone_type == "avoided":
                bonus -= 20.0  # Strong avoidance penalty
    
    return bonus


def is_order_acceptable_by_location(
    order_lat: float,
    order_lon: float,
    driver_lat: float,
    driver_lon: float,
    max_distance_km: Optional[float] = None,
    pickup_radius_km: Optional[float] = None,
    zones: List[GeoZone] = None
) -> Tuple[bool, str]:
    """
    Comprehensive location-based order acceptance check.
    
    Args:
        order_lat, order_lon: Order pickup location
        driver_lat, driver_lon: Driver's current location
        max_distance_km: Maximum acceptable distance
        pickup_radius_km: Specific pickup radius preference
        zones: Geographic zones to check
    
    Returns:
        Tuple of (acceptable, reason)
    """
    zones = zones or []
    
    # Check avoided zones first (highest priority)
    has_conflict, conflict_reason = check_zone_conflict(order_lat, order_lon, zones)
    if has_conflict:
        return False, conflict_reason or "Order is in an avoided zone"
    
    # Check distance constraints
    effective_max_distance = pickup_radius_km if pickup_radius_km else max_distance_km
    if effective_max_distance:
        distance = haversine_km(driver_lat, driver_lon, order_lat, order_lon)
        if distance > effective_max_distance:
            return False, f"Order distance ({distance:.1f} km) exceeds maximum ({effective_max_distance} km)"
    
    # Check preferred zones (positive factor)
    if zones:
        nearest_zone = find_nearest_zone(order_lat, order_lon, zones)
        if nearest_zone and nearest_zone.zone_type == "preferred":
            return True, f"Order is in preferred zone: {nearest_zone.name}"
    
    return True, "Order meets all location criteria"