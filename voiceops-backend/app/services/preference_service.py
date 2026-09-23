"""
Driver Preferences Service

Manages driver behavioral preferences stored in Supabase.
Drivers can customize their co-rider's behavior through voice commands.
"""
import logging
from typing import Any, Dict, Optional
from supabase import create_client, Client

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


# Global instance
preference_service = PreferenceService()

def initialize_preference_service(supabase_url: str, supabase_key: str):
    """Initialize the preference service with Supabase credentials."""
    global preference_service
    preference_service = PreferenceService(supabase_url, supabase_key)
