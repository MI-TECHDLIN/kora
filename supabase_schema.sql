-- VoiceOps Supabase Schema
-- Run this in Supabase SQL Editor

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Drivers table
CREATE TABLE drivers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    phone VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(255),
    vehicle_type VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Platform connections table
CREATE TABLE platform_connections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id UUID REFERENCES drivers(id) ON DELETE CASCADE,
    platform VARCHAR(100) NOT NULL,
    connect_code VARCHAR(10),
    credentials JSONB,
    status VARCHAR(20) DEFAULT 'active',
    connected_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(driver_id, platform)
);

-- Shifts table
CREATE TABLE shifts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id UUID REFERENCES drivers(id) ON DELETE CASCADE,
    status VARCHAR(20) DEFAULT 'active',
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    ended_at TIMESTAMP WITH TIME ZONE
);

-- Deliveries table
CREATE TABLE deliveries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shift_id UUID REFERENCES shifts(id) ON DELETE CASCADE,
    recipient_name VARCHAR(255) NOT NULL,
    address TEXT NOT NULL,
    phone VARCHAR(20),
    status VARCHAR(20) DEFAULT 'pending',
    notes TEXT,
    time_window VARCHAR(100),
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    sequence_order INTEGER,
    failure_reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Voice sessions table
CREATE TABLE voice_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shift_id UUID REFERENCES shifts(id) ON DELETE CASCADE,
    driver_id UUID REFERENCES drivers(id) ON DELETE CASCADE,
    delivery_id UUID REFERENCES deliveries(id) ON DELETE SET NULL,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    ended_at TIMESTAMP WITH TIME ZONE,
    driver_transcript TEXT,
    agent_transcript TEXT,
    tool_calls JSONB,
    tool_results JSONB
);

-- Location pings table
CREATE TABLE location_pings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id UUID REFERENCES drivers(id) ON DELETE CASCADE,
    shift_id UUID REFERENCES shifts(id) ON DELETE CASCADE,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    pinged_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Intelligence reports table
CREATE TABLE intelligence_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shift_id UUID REFERENCES shifts(id) ON DELETE CASCADE,
    total_deliveries INTEGER,
    delivered_count INTEGER,
    failed_count INTEGER,
    success_rate DECIMAL(5, 2),
    failure_patterns JSONB,
    route_issues JSONB,
    sentiment_score DECIMAL(3, 2),
    recommendations TEXT,
    generated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Operator codes table (for platform connection)
CREATE TABLE operator_codes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(10) UNIQUE NOT NULL,
    company_name VARCHAR(255) NOT NULL,
    platform VARCHAR(100) NOT NULL,
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_deliveries_shift_id ON deliveries(shift_id);
CREATE INDEX idx_deliveries_status ON deliveries(status);
CREATE INDEX idx_voice_sessions_shift_id ON voice_sessions(shift_id);
CREATE INDEX idx_location_pings_driver_id ON location_pings(driver_id);
CREATE INDEX idx_location_pings_shift_id ON location_pings(shift_id);
CREATE INDEX idx_shifts_driver_id ON shifts(driver_id);
CREATE INDEX idx_platform_connections_driver_id ON platform_connections(driver_id);

-- Enable Row Level Security
ALTER TABLE drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE location_pings ENABLE ROW LEVEL SECURITY;
ALTER TABLE intelligence_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE operator_codes ENABLE ROW LEVEL SECURITY;

-- RLS Policies (basic - customize for production)
CREATE POLICY "Users can view own driver profile" ON drivers
    FOR SELECT USING (auth.uid()::text = id::text);

CREATE POLICY "Users can update own driver profile" ON drivers
    FOR UPDATE USING (auth.uid()::text = id::text);

CREATE POLICY "Users can view own platform connections" ON platform_connections
    FOR SELECT USING (auth.uid()::text = driver_id::text);

CREATE POLICY "Users can view own shifts" ON shifts
    FOR SELECT USING (auth.uid()::text = driver_id::text);

CREATE POLICY "Users can view own deliveries" ON deliveries
    FOR SELECT USING (
        shift_id IN (SELECT id FROM shifts WHERE driver_id = auth.uid()::text)
    );

CREATE POLICY "Users can view own voice sessions" ON voice_sessions
    FOR SELECT USING (auth.uid()::text = driver_id::text);

CREATE POLICY "Users can insert own location pings" ON location_pings
    FOR INSERT WITH CHECK (auth.uid()::text = driver_id::text);

CREATE POLICY "Users can view own location pings" ON location_pings
    FOR SELECT USING (auth.uid()::text = driver_id::text);

CREATE POLICY "Users can view own intelligence reports" ON intelligence_reports
    FOR SELECT USING (
        shift_id IN (SELECT id FROM shifts WHERE driver_id = auth.uid()::text)
    );

-- Operator codes are public read
CREATE POLICY "Anyone can view operator codes" ON operator_codes
    FOR SELECT USING (true);

-- Dispatcher alerts table (used by n8n escalation workflow and voice agent)
CREATE TABLE IF NOT EXISTS dispatcher_alerts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id TEXT,
    driver_name VARCHAR(255),
    alert_type VARCHAR(100) NOT NULL,
    message TEXT NOT NULL,
    severity VARCHAR(50) DEFAULT 'normal',
    location TEXT,
    shift_id TEXT,
    is_critical BOOLEAN DEFAULT FALSE,
    resolved BOOLEAN DEFAULT FALSE,
    resolved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for dispatcher alerts
CREATE INDEX IF NOT EXISTS idx_dispatcher_alerts_created_at ON dispatcher_alerts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_dispatcher_alerts_severity ON dispatcher_alerts(severity);
CREATE INDEX IF NOT EXISTS idx_dispatcher_alerts_driver_id ON dispatcher_alerts(driver_id);
CREATE INDEX IF NOT EXISTS idx_dispatcher_alerts_is_critical ON dispatcher_alerts(is_critical);

-- Enable Row Level Security
ALTER TABLE dispatcher_alerts ENABLE ROW LEVEL SECURITY;

-- Allow service role (used by n8n webhook and backend) full access
CREATE POLICY "Service role full access on dispatcher_alerts" ON dispatcher_alerts
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Allow authenticated users to view their alerts
CREATE POLICY "Drivers can view their own alerts" ON dispatcher_alerts
    FOR SELECT
    TO authenticated
    USING (auth.uid()::text = driver_id);
