"""
Voice tools for managing driver preferences.

Drivers can customize their co-rider's behavior through voice commands like:
- "Always accept orders"
- "Never call customers"
- "Tell me my preferences"
"""
import logging
from typing import Any, Dict, Optional
from app.services.preference_service import preference_service

logger = logging.getLogger(__name__)


async def get_preferences(parameters: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Get all the driver's current preferences.
    
    Driver says: "Tell me my preferences" or "What are my settings?"
    
    Returns a dictionary of all preferences and their values.
    """
    driver_id = context.get("driver_id")
    
    if not driver_id:
        return {
            "success": False,
            "error": "Driver ID not found in context"
        }
    
    try:
        preferences = await preference_service.get_preferences(driver_id)
        
        # Format the response in a friendly way
        if not preferences:
            return {
                "success": True,
                "message": "You don't have any custom preferences set. Your co-rider will use default behavior.",
                "preferences": {}
            }
        
        # Convert to friendly descriptions
        friendly_descriptions = {
            "auto_accept_orders": "Automatically accept orders" if preferences.get("auto_accept_orders") == "true" else "Don't automatically accept orders",
            "auto_decline_orders": "Automatically decline orders" if preferences.get("auto_decline_orders") == "true" else "Don't automatically decline orders",
            "max_order_distance_km": f"Only accept orders within {preferences.get('max_order_distance_km')} km" if preferences.get("max_order_distance_km") else None,
            "avoid_highways": "Avoid highways" if preferences.get("avoid_highways") == "true" else "No highway restrictions",
            "prefer_residential": "Prefer residential areas" if preferences.get("prefer_residential") == "true" else "No residential preference",
            "always_call_before_delivery": "Always call customers before delivery" if preferences.get("always_call_before_delivery") == "true" else "No automatic customer calls",
            "never_call_customer": "Never call customers" if preferences.get("never_call_customer") == "true" else "Can call customers",
            "always_send_sms": "Always send SMS on delivery" if preferences.get("always_send_sms") == "true" else "No automatic SMS",
            "max_deliveries_per_shift": f"End shift after {preferences.get('max_deliveries_per_shift')} deliveries" if preferences.get("max_deliveries_per_shift") else None,
            "auto_announce_next_stop": "Auto-announce next stop" if preferences.get("auto_announce_next_stop") == "true" else "No auto-announcement",
            "proactive_traffic_alerts": "Show proactive traffic alerts" if preferences.get("proactive_traffic_alerts") == "true" else "No proactive alerts",
            "daily_delivery_target": f"Today's delivery target is {preferences.get('daily_delivery_target')}" if preferences.get("daily_delivery_target") else None,
        }
        
        # Filter out None values
        active_preferences = {k: v for k, v in friendly_descriptions.items() if v is not None}
        
        return {
            "success": True,
            "message": f"You have {len(active_preferences)} preferences set:",
            "preferences": active_preferences
        }
    except Exception as e:
        logger.error(f"[Preference Tool] Error getting preferences: {e}")
        return {
            "success": False,
            "error": f"Failed to retrieve preferences: {str(e)}"
        }


async def set_preference(parameters: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Set a specific preference by key and value.
    
    Driver says: "Always accept orders" → Sets auto_accept_orders to true
    Driver says: "Never call customers" → Sets never_call_customer to true
    """
    driver_id = context.get("driver_id")
    key = parameters.get("key")
    value = parameters.get("value")
    
    if not driver_id:
        return {
            "success": False,
            "error": "Driver ID not found in context"
        }
    
    if not key or value is None:
        return {
            "success": False,
            "error": "Please specify both a preference and value"
        }
    
    try:
        success = await preference_service.set_preference(driver_id, key, value)
        if success:
            if key == "daily_delivery_target":
                from app.services.order_queue_service import notify_active_queue_changed
                await notify_active_queue_changed(driver_id, context.get("shift_id"))
            return {
                "success": True,
                "message": f"Preference set: {key} = {value}"
            }
        else:
            return {
                "success": False,
                "error": "Failed to save preference"
            }
    except Exception as e:
        logger.error(f"[Preference Tool] Error setting preference: {e}")
        return {
            "success": False,
            "error": f"Failed to set preference: {str(e)}"
        }


async def clear_preference(parameters: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Clear a specific preference.
    
    Driver says: "Clear my order preference" or "Stop auto-accepting orders"
    """
    driver_id = context.get("driver_id")
    key = parameters.get("key")
    
    if not driver_id:
        return {
            "success": False,
            "error": "Driver ID not found in context"
        }
    
    if not key:
        return {
            "success": False,
            "error": "Please specify which preference to clear"
        }
    
    try:
        success = await preference_service.clear_preference(driver_id, key)
        if success:
            if key == "daily_delivery_target":
                from app.services.order_queue_service import notify_active_queue_changed
                await notify_active_queue_changed(driver_id, context.get("shift_id"))
            return {
                "success": True,
                "message": f"Preference cleared: {key}"
            }
        else:
            return {
                "success": False,
                "error": "Failed to clear preference"
            }
    except Exception as e:
        logger.error(f"[Preference Tool] Error clearing preference: {e}")
        return {
            "success": False,
            "error": f"Failed to clear preference: {str(e)}"
        }


async def reset_preferences(parameters: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Reset all preferences to defaults.
    
    Driver says: "Reset my preferences" or "Clear all my settings"
    """
    driver_id = context.get("driver_id")
    
    if not driver_id:
        return {
            "success": False,
            "error": "Driver ID not found in context"
        }
    
    try:
        success = await preference_service.reset_preferences(driver_id)
        if success:
            from app.services.order_queue_service import notify_active_queue_changed
            await notify_active_queue_changed(driver_id, context.get("shift_id"))
            return {
                "success": True,
                "message": "All preferences have been reset to defaults. Your co-rider will use standard behavior."
            }
        else:
            return {
                "success": False,
                "error": "Failed to reset preferences"
            }
    except Exception as e:
        logger.error(f"[Preference Tool] Error resetting preferences: {e}")
        return {
            "success": False,
            "error": f"Failed to reset preferences: {str(e)}"
        }
