-- Database migration for driver preferences feature
-- Create the driver_preferences table to store driver behavioral settings

CREATE TABLE IF NOT EXISTS driver_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
    preference_key VARCHAR(100) NOT NULL,
    preference_value TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(driver_id, preference_key)
);

-- Create index for faster lookups by driver_id
CREATE INDEX IF NOT EXISTS idx_driver_preferences_driver_id ON driver_preferences(driver_id);

-- Create index for faster lookups by preference_key
CREATE INDEX IF NOT EXISTS idx_driver_preferences_key ON driver_preferences(preference_key);

-- Add comment to the table
COMMENT ON TABLE driver_preferences IS 'Stores driver behavioral preferences for voice agent customization';

-- Add comments to columns
COMMENT ON COLUMN driver_preferences.driver_id IS 'Reference to the driver who owns these preferences';
COMMENT ON COLUMN driver_preferences.preference_key IS 'The preference key (e.g., auto_accept_orders, avoid_highways)';
COMMENT ON COLUMN driver_preferences.preference_value IS 'The preference value (stored as string, JSON for complex values)';
COMMENT ON COLUMN driver_preferences.created_at IS 'When the preference was first set';
COMMENT ON COLUMN driver_preferences.updated_at IS 'When the preference was last updated';
