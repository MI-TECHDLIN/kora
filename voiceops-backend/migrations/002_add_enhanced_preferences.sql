-- Database migration for enhanced driver preferences
-- Add columns for geographic zones, order types, and time-based preferences to driver_preferences table

-- Add new columns for enhanced preferences (using JSON for complex data)
ALTER TABLE driver_preferences 
ADD COLUMN IF NOT EXISTS geographic_zones JSONB DEFAULT '[]'::jsonb,
ADD COLUMN IF NOT EXISTS order_type_prefs JSONB DEFAULT '{}'::jsonb,
ADD COLUMN IF NOT EXISTS time_based_prefs JSONB DEFAULT '{}'::jsonb,
ADD COLUMN IF NOT EXISTS pickup_radius_km FLOAT,
ADD COLUMN IF NOT EXISTS current_location_preference VARCHAR(50) DEFAULT 'current';

-- Add comments to new columns
COMMENT ON COLUMN driver_preferences.geographic_zones IS 'JSON array of geographic zones (preferred/avoided areas with center coordinates and radius)';
COMMENT ON COLUMN driver_preferences.order_type_prefs IS 'JSON object with order type preferences (categories, weight, dimensions, priority)';
COMMENT ON COLUMN driver_preferences.time_based_prefs IS 'JSON object with time-based preference rules (hours, rush hour, breaks)';
COMMENT ON COLUMN driver_preferences.pickup_radius_km IS 'Specific pickup radius preference (different from max_order_distance_km)';
COMMENT ON COLUMN driver_preferences.current_location_preference IS 'Location preference: home, work, or current';

-- Add index for driver_id if not exists
CREATE INDEX IF NOT EXISTS idx_driver_preferences_driver_id ON driver_preferences(driver_id);

-- Add index for preference_key if not exists
CREATE INDEX IF NOT EXISTS idx_driver_preferences_key ON driver_preferences(preference_key);
