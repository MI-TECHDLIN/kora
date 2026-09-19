-- Order dispatch (2026-09-13). Idempotent: safe to run on an existing database.
-- A logistics platform's new order is a `deliveries` row with shift_id NULL and
-- status 'offered' (waiting on one driver's answer) or 'unassigned' (nobody took
-- it yet) until a driver accepts it, which sets shift_id and status 'pending'.
-- The existing RLS policy on `deliveries` already hides these rows from drivers:
-- they belong to no shift until accepted.
ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS source VARCHAR(100);      -- sending platform
ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS external_id VARCHAR(100); -- the platform's order id
CREATE UNIQUE INDEX IF NOT EXISTS idx_deliveries_source_external_id ON deliveries(source, external_id);
CREATE INDEX IF NOT EXISTS idx_deliveries_open_orders ON deliveries(status) WHERE shift_id IS NULL;
