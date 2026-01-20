-- Palantir Registry Schema
-- Run this in your Neon SQL console to set up the database

-- Users table: Roblox users who have registered assets
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    roblox_user_id BIGINT UNIQUE NOT NULL,
    roblox_username TEXT,
    discord_user_id BIGINT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Assets table: Individual mesh registrations
CREATE TABLE IF NOT EXISTS assets (
    id SERIAL PRIMARY KEY,
    asset_id BIGINT UNIQUE NOT NULL,          -- Roblox asset ID (MeshId)
    owner_id BIGINT NOT NULL REFERENCES users(roblox_user_id),
    name TEXT,
    asset_type TEXT DEFAULT 'mesh',            -- 'mesh' or 'texture'
    size_x REAL,
    size_y REAL,
    size_z REAL,
    material TEXT,
    texture_id BIGINT,
    registered_at TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT valid_asset_type CHECK (asset_type IN ('mesh', 'texture'))
);

-- Models table: Model bundles containing multiple meshes
CREATE TABLE IF NOT EXISTS models (
    id SERIAL PRIMARY KEY,
    owner_id BIGINT NOT NULL REFERENCES users(roblox_user_id),
    name TEXT NOT NULL,
    mesh_count INT DEFAULT 0,
    fingerprint TEXT,                          -- Hash for quick identification
    registered_at TIMESTAMPTZ DEFAULT NOW()
);

-- Model-Asset junction: Links models to their meshes
CREATE TABLE IF NOT EXISTS model_assets (
    id SERIAL PRIMARY KEY,
    model_id INT NOT NULL REFERENCES models(id) ON DELETE CASCADE,
    asset_id BIGINT NOT NULL,                  -- Roblox asset ID
    name TEXT,
    path TEXT,                                 -- Hierarchy path within model
    size_x REAL,
    size_y REAL,
    size_z REAL,
    material TEXT,
    texture_id BIGINT
);

-- Scan history: Track when assets are scanned/detected
CREATE TABLE IF NOT EXISTS scan_logs (
    id SERIAL PRIMARY KEY,
    scanner_user_id BIGINT NOT NULL,           -- Who ran the scan
    scanned_model_name TEXT,
    asset_ids BIGINT[],                        -- Array of asset IDs found
    flagged_assets BIGINT[],                   -- Assets belonging to others
    scanned_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_assets_owner ON assets(owner_id);
CREATE INDEX IF NOT EXISTS idx_assets_asset_id ON assets(asset_id);
CREATE INDEX IF NOT EXISTS idx_models_owner ON models(owner_id);
CREATE INDEX IF NOT EXISTS idx_model_assets_model ON model_assets(model_id);
CREATE INDEX IF NOT EXISTS idx_model_assets_asset ON model_assets(asset_id);
CREATE INDEX IF NOT EXISTS idx_scan_logs_scanner ON scan_logs(scanner_user_id);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for users table
DROP TRIGGER IF EXISTS users_updated_at ON users;
CREATE TRIGGER users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();
