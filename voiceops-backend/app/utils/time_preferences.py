"""
Time-based preference utilities for order acceptance.
"""
from datetime import datetime, time
from typing import List, Optional
from app.services.preference_models import TimeRange, TimeBasedPreferences


def is_time_in_range(current_time: time, time_range: TimeRange) -> bool:
    """
    Check if current time falls within a time range.
    
    Args:
        current_time: Current time to check
        time_range: TimeRange to check against
    
    Returns:
        True if current time is within the range
    """
    start = time(time_range.start_hour, time_range.start_minute)
    end = time(time_range.end_hour, time_range.end_minute)
    
    if start <= end:
        return start <= current_time <= end
    else:
        # Handle ranges that cross midnight (e.g., 22:00 to 02:00)
        return current_time >= start or current_time <= end


def is_day_in_range(current_day: int, days_of_week: List[int]) -> bool:
    """
    Check if current day is in the allowed days list.
    
    Args:
        current_day: Current day (0=Monday, 6=Sunday)
        days_of_week: List of allowed days
    
    Returns:
        True if current day is in the list (or if list is empty for all days)
    """
    if not days_of_week:
        return True  # Empty list means all days are allowed
    return current_day in days_of_week


def is_auto_accept_enabled(current_time: Optional[datetime] = None, 
                          time_prefs: Optional[TimeBasedPreferences] = None) -> Tuple[bool, str]:
    """
    Check if auto-accept is currently enabled based on time-based preferences.
    
    Args:
        current_time: Current datetime (defaults to now)
        time_prefs: TimeBasedPreferences to check
    
    Returns:
        Tuple of (enabled, reason)
    """
    if not time_prefs:
        return True, "No time-based restrictions"
    
    if current_time is None:
        current_time = datetime.now()
    
    current_time_obj = current_time.time()
    current_day = current_time.weekday()  # 0=Monday, 6=Sunday
    
    # Check if currently in rush hour and auto-accept is disabled during rush hour
    if time_prefs.disable_auto_accept_during_rush_hour:
        rush_start = _parse_time(time_prefs.rush_hour_start)
        rush_end = _parse_time(time_prefs.rush_hour_end)
        
        if is_time_in_range(current_time_obj, TimeRange(
            rush_start.hour, rush_start.minute,
            rush_end.hour, rush_end.minute
        )):
            return False, "Auto-accept disabled during rush hour"
    
    # Check if currently in a break time
    for break_time in time_prefs.break_times:
        if is_time_in_range(current_time_obj, break_time):
            if is_day_in_range(current_day, break_time.days_of_week):
                return False, "Auto-accept disabled during break time"
    
    # Check if current time is within enabled hours
    if time_prefs.auto_accept_enabled_hours:
        is_in_enabled_hours = False
        for enabled_range in time_prefs.auto_accept_enabled_hours:
            if is_time_in_range(current_time_obj, enabled_range):
                if is_day_in_range(current_day, enabled_range.days_of_week):
                    is_in_enabled_hours = True
                    break
        
        if not is_in_enabled_hours:
            return False, "Auto-accept disabled outside configured hours"
    
    return True, "Auto-accept is currently enabled"


def _parse_time(time_str: str) -> time:
    """Parse time string in HH:MM format."""
    try:
        hours, minutes = map(int, time_str.split(':'))
        return time(hours, minutes)
    except (ValueError, AttributeError):
        return time(0, 0)  # Default to midnight


def should_accept_order_by_time(
    order_time: Optional[datetime] = None,
    time_prefs: Optional[TimeBasedPreferences] = None
) -> Tuple[bool, str]:
    """
    Check if an order should be accepted based on time-based preferences.
    
    Args:
        order_time: Time when order was offered (defaults to now)
        time_prefs: TimeBasedPreferences to check
    
    Returns:
        Tuple of (should_accept, reason)
    """
    if not time_prefs:
        return True, "No time-based restrictions"
    
    if order_time is None:
        order_time = datetime.now()
    
    return _check_time_constraints(order_time, time_prefs)


def get_shift_start_preference(time_prefs: Optional[TimeBasedPreferences] = None) -> str:
    """
    Get the shift start preference.
    
    Args:
        time_prefs: TimeBasedPreferences to check
    
    Returns:
        Shift start preference string
    """
    if not time_prefs:
        return "any"
    return time_prefs.shift_start_preference


def _check_time_constraints(current_time: datetime, time_prefs: TimeBasedPreferences) -> Tuple[bool, str]:
    """
    Internal function to check time-based constraints without recursion.
    
    Args:
        current_time: Current datetime
        time_prefs: TimeBasedPreferences to check
    
    Returns:
        Tuple of (enabled, reason)
    """
    current_time_obj = current_time.time()
    current_day = current_time.weekday()  # 0=Monday, 6=Sunday
    
    # Check if currently in rush hour and auto-accept is disabled during rush hour
    if time_prefs.disable_auto_accept_during_rush_hour:
        rush_start = _parse_time(time_prefs.rush_hour_start)
        rush_end = _parse_time(time_prefs.rush_hour_end)
        
        if is_time_in_range(current_time_obj, TimeRange(
            rush_start.hour, rush_start.minute,
            rush_end.hour, rush_end.minute
        )):
            return False, "Auto-accept disabled during rush hour"
    
    # Check if currently in a break time
    for break_time in time_prefs.break_times:
        if is_time_in_range(current_time_obj, break_time):
            if is_day_in_range(current_day, break_time.days_of_week):
                return False, "Auto-accept disabled during break time"
    
    # Check if current time is within enabled hours
    if time_prefs.auto_accept_enabled_hours:
        is_in_enabled_hours = False
        for enabled_range in time_prefs.auto_accept_enabled_hours:
            if is_time_in_range(current_time_obj, enabled_range):
                if is_day_in_range(current_day, enabled_range.days_of_week):
                    is_in_enabled_hours = True
                    break
        
        if not is_in_enabled_hours:
            return False, "Auto-accept disabled outside configured hours"
    
    return True, "Auto-accept is currently enabled"


def is_auto_accept_enabled(current_time: Optional[datetime] = None, 
                          time_prefs: Optional[TimeBasedPreferences] = None) -> Tuple[bool, str]:
    """
    Check if auto-accept is currently enabled based on time-based preferences.
    
    Args:
        current_time: Current datetime (defaults to now)
        time_prefs: TimeBasedPreferences to check
    
    Returns:
        Tuple of (enabled, reason)
    """
    if not time_prefs:
        return True, "No time-based restrictions"
    
    if current_time is None:
        current_time = datetime.now()
    
    return _check_time_constraints(current_time, time_prefs)