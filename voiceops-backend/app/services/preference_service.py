"""
Driver Preferences Service

Manages driver behavioral preferences stored in Supabase.
Drivers can customize their co-rider's behavior through voice commands.
"""
import logging
from typing import Any, Dict, Optional
from supabase import create_client, Client
from app.services.preference_models import (
    EnhancedPreferences,
    GeoZone,
    OrderTypePreference,
    TimeBasedPreferences,
    PreferenceConflictResolver
)

logger = logging.getLogger(__name__)


class PreferenceService:
    """Service for managing driver preferences."""
    
    def __init__(self, supabase_url: Optional[str] = None, supabase_key: Optional[str] = None):
        """Initialize the preference service with Supabase client."""
        self._client: Optional[Client] = None
        if supabase_url and supabase_key:
            self._client = create_client(supabase_url, supabase_key)
        else:
            logger.warning("[PreferenceService] Supabase credentials not provided. Preferences will be in-memory only.")
    
    async def get_preferences(self, driver_id: str) -> Dict[str, Any]:
        """
        Get all preferences for a driver.
        
        Args:
            driver_id: The driver's UUID
            
        Returns:
            Dictionary of preference_key -> preference_value
        """
        if not self._client:
            logger.warning("[PreferenceService] No Supabase client, returning empty preferences")
            return {}
        
        try:
            response = self._client.table('driver_preferences').select('*').eq('driver_id', driver_id).execute()
            preferences = {}
            for row in response.data:
                preferences[row['preference_key']] = row['preference_value']
            logger.info(f"[PreferenceService] Retrieved {len(preferences)} preferences for driver {driver_id}")
            return preferences
        except Exception as e:
            logger.error(f"[PreferenceService] Error fetching preferences for driver {driver_id}: {e}")
            return {}
    
    async def get_preference(self, driver_id: str, key: str) -> Optional[Any]:
        """
        Get a specific preference for a driver.
        
        Args:
            driver_id: The driver's UUID
            key: The preference key
            
        Returns:
            The preference value, or None if not set
        """
        if not self._client:
            return None
        
        try:
            response = self._client.table('driver_preferences').select('*').eq('driver_id', driver_id).eq('preference_key', key).execute()
            if response.data:
                return response.data[0]['preference_value']
            return None
        except Exception as e:
            logger.error(f"[PreferenceService] Error fetching preference {key} for driver {driver_id}: {e}")
            return None
    
    async def set_preference(self, driver_id: str, key: str, value: Any) -> bool:
        """
        Set a preference for a driver.
        
        Args:
            driver_id: The driver's UUID
            key: The preference key
            value: The preference value (will be JSON stringified if not string)
            
        Returns:
            True if successful, False otherwise
        """
        if not self._client:
            logger.warning("[PreferenceService] No Supabase client, preference not saved")
            return False
        
        try:
            # Convert value to string for storage
            if not isinstance(value, str):
                import json
                value_str = json.dumps(value)
            else:
                value_str = value
            
            # Upsert the preference
            response = self._client.table('driver_preferences').upsert(
                {
                    'driver_id': driver_id,
                    'preference_key': key,
                    'preference_value': value_str
                }
            ).execute()
            
            logger.info(f"[PreferenceService] Set preference {key}={value_str} for driver {driver_id}")
            return True
        except Exception as e:
            logger.error(f"[PreferenceService] Error setting preference {key} for driver {driver_id}: {e}")
            return False
    
    async def clear_preference(self, driver_id: str, key: str) -> bool:
        """
        Clear a preference for a driver.
        
        Args:
            driver_id: The driver's UUID
            key: The preference key to clear
            
        Returns:
            True if successful, False otherwise
        """
        if not self._client:
            return False
        
        try:
            response = self._client.table('driver_preferences').delete().eq('driver_id', driver_id).eq('preference_key', key).execute()
            logger.info(f"[PreferenceService] Cleared preference {key} for driver {driver_id}")
            return True
        except Exception as e:
            logger.error(f"[PreferenceService] Error clearing preference {key} for driver {driver_id}: {e}")
            return False
    
    async def reset_preferences(self, driver_id: str) -> bool:
        """
        Reset all preferences for a driver to defaults (delete all).
        
        Args:
            driver_id: The driver's UUID
            
        Returns:
            True if successful, False otherwise
        """
        if not self._client:
            return False
        
        try:
            response = self._client.table('driver_preferences').delete().eq('driver_id', driver_id).execute()
            logger.info(f"[PreferenceService] Reset all preferences for driver {driver_id}")
            return True
        except Exception as e:
            logger.error(f"[PreferenceService] Error resetting preferences for driver {driver_id}: {e}")
            return False
    
    async def get_enhanced_preferences(self, driver_id: str) -> EnhancedPreferences:
        """
        Get enhanced preferences including geographic zones, order types, and time-based rules.
        
        Args:
            driver_id: The driver's UUID
            
        Returns:
            EnhancedPreferences object with all complex preferences
        """
        import json
        preferences = await self.get_preferences(driver_id)
        
        # Parse complex preferences from JSON strings
        geographic_data = preferences.get("geographic_zones", "[]")
        order_type_data = preferences.get("order_type_prefs", "{}")
        time_based_data = preferences.get("time_based_prefs", "{}")
        
        try:
            geographic_zones = [GeoZone.from_dict(zone) for zone in json.loads(geographic_data)]
        except (json.JSONDecodeError, ValueError):
            geographic_zones = []
        
        try:
            order_type_prefs = OrderTypePreference.from_dict(json.loads(order_type_data))
        except (json.JSONDecodeError, ValueError):
            order_type_prefs = OrderTypePreference()
        
        try:
            time_based_prefs = TimeBasedPreferences.from_dict(json.loads(time_based_data))
        except (json.JSONDecodeError, ValueError):
            time_based_prefs = TimeBasedPreferences()
        
        return EnhancedPreferences(
            geographic_zones=geographic_zones,
            order_type_prefs=order_type_prefs,
            time_based_prefs=time_based_prefs,
            pickup_radius_km=preferences.get("pickup_radius_km"),
            current_location_preference=preferences.get("current_location_preference", "current")
        )
    
    async def set_geographic_zone(self, driver_id: str, zone: GeoZone) -> bool:
        """
        Add or update a geographic zone preference.
        
        Args:
            driver_id: The driver's UUID
            zone: GeoZone object to save
            
        Returns:
            True if successful, False otherwise
        """
        enhanced_prefs = await self.get_enhanced_preferences(driver_id)
        
        # Update or add the zone
        zone_found = False
        for i, existing_zone in enumerate(enhanced_prefs.geographic_zones):
            if existing_zone.name == zone.name:
                enhanced_prefs.geographic_zones[i] = zone
                zone_found = True
                break
        
        if not zone_found:
            enhanced_prefs.geographic_zones.append(zone)
        
        import json
        return await self.set_preference(
            driver_id, 
            "geographic_zones", 
            json.dumps([z.to_dict() for z in enhanced_prefs.geographic_zones])
        )
    
    async def remove_geographic_zone(self, driver_id: str, zone_name: str) -> bool:
        """
        Remove a geographic zone preference.
        
        Args:
            driver_id: The driver's UUID
            zone_name: Name of the zone to remove
            
        Returns:
            True if successful, False otherwise
        """
        enhanced_prefs = await self.get_enhanced_preferences(driver_id)
        enhanced_prefs.geographic_zones = [
            zone for zone in enhanced_prefs.geographic_zones if zone.name != zone_name
        ]
        
        import json
        return await self.set_preference(
            driver_id,
            "geographic_zones",
            json.dumps([z.to_dict() for z in enhanced_prefs.geographic_zones])
        )
    
    async def set_order_type_preferences(self, driver_id: str, prefs: OrderTypePreference) -> bool:
        """
        Set order type filtering preferences.
        
        Args:
            driver_id: The driver's UUID
            prefs: OrderTypePreference object
            
        Returns:
            True if successful, False otherwise
        """
        import json
        return await self.set_preference(
            driver_id,
            "order_type_prefs",
            json.dumps(prefs.to_dict())
        )
    
    async def set_time_based_preferences(self, driver_id: str, prefs: TimeBasedPreferences) -> bool:
        """
        Set time-based preference rules.
        
        Args:
            driver_id: The driver's UUID
            prefs: TimeBasedPreferences object
            
        Returns:
            True if successful, False otherwise
        """
        import json
        return await self.set_preference(
            driver_id,
            "time_based_prefs",
            json.dumps(prefs.to_dict())
        )
    
    async def resolve_preference_conflicts(self, driver_id: str) -> Dict[str, Any]:
        """
        Resolve conflicts between preferences and return the resolved set.
        
        Args:
            driver_id: The driver's UUID
            
        Returns:
            Dictionary of resolved preferences
        """
        preferences = await self.get_preferences(driver_id)
        return PreferenceConflictResolver.resolve_all_conflicts(preferences)


# Global instance
preference_service = PreferenceService()

def initialize_preference_service(supabase_url: str, supabase_key: str):
    """Initialize the preference service with Supabase credentials."""
    global preference_service
    preference_service = PreferenceService(supabase_url, supabase_key)
