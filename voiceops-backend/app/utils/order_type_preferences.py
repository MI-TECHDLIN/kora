"""
Order type preference utilities for order acceptance.
"""
from typing import List, Optional, Dict, Any, Tuple
from app.services.preference_models import OrderTypePreference


def is_order_type_accepted(
    order_category: str,
    order_weight_kg: Optional[float] = None,
    order_dimensions: Optional[Dict[str, float]] = None,
    order_value: Optional[float] = None,
    type_prefs: Optional[OrderTypePreference] = None
) -> Tuple[bool, str]:
    """
    Check if an order should be accepted based on order type preferences.
    
    Args:
        order_category: Category of the order (e.g., "food", "packages")
        order_weight_kg: Weight of the order in kg
        order_dimensions: Dimensions of the order (length, width, height)
        order_value: Value of the order
        type_prefs: OrderTypePreference to check
    
    Returns:
        Tuple of (accepted, reason)
    """
    if not type_prefs:
        return True, "No order type restrictions"
    
    # Check if category is in accepted list
    if type_prefs.accepted_categories:
        if order_category not in type_prefs.accepted_categories:
            return False, f"Order category '{order_category}' not in accepted categories"
    
    # Check weight constraints
    if type_prefs.max_weight_kg and order_weight_kg:
        if order_weight_kg > type_prefs.max_weight_kg:
            return False, f"Order weight ({order_weight_kg} kg) exceeds maximum ({type_prefs.max_weight_kg} kg)"
    
    # Check dimension constraints
    if type_prefs.max_dimensions and order_dimensions:
        for dim, value in order_dimensions.items():
            max_dim = type_prefs.max_dimensions.get(dim)
            if max_dim and value > max_dim:
                return False, f"Order {dim} ({value} cm) exceeds maximum ({max_dim} cm)"
    
    # Check minimum order value
    if type_prefs.min_order_value and order_value:
        if order_value < type_prefs.min_order_value:
            return False, f"Order value (${order_value}) below minimum (${type_prefs.min_order_value})"
    
    # Check if category is in priority list (for informational purposes)
    if type_prefs.priority_categories and order_category in type_prefs.priority_categories:
        return True, f"Order category '{order_category}' is prioritized"
    
    return True, "Order meets all type criteria"


def calculate_order_priority_bonus(
    order_category: str,
    type_prefs: Optional[OrderTypePreference] = None
) -> float:
    """
    Calculate priority bonus based on order type preferences.
    
    Args:
        order_category: Category of the order
        type_prefs: OrderTypePreference to check
    
    Returns:
        Priority bonus score
    """
    if not type_prefs:
        return 0.0
    
    bonus = 0.0
    
    if order_category in type_prefs.priority_categories:
        bonus += 5.0  # Priority category bonus
    
    if order_category in type_prefs.accepted_categories:
        bonus += 2.0  # Accepted category bonus
    
    return bonus


def get_recommended_order_categories(type_prefs: Optional[OrderTypePreference] = None) -> List[str]:
    """
    Get recommended order categories based on preferences.
    
    Args:
        type_prefs: OrderTypePreference to check
    
    Returns:
        List of recommended categories
    """
    if not type_prefs:
        return ["food", "packages", "groceries", "documents"]  # Default recommendations
    
    if type_prefs.priority_categories:
        return type_prefs.priority_categories
    
    if type_prefs.accepted_categories:
        return type_prefs.accepted_categories
    
    return ["food", "packages", "groceries", "documents"]  # Fallback