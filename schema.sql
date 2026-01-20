-- Palantir Registry Schema
-- Run this in your Neon SQL console to set up the database

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Owners use secret keys for admin operations
CREATE TABLE IF NOT EXISTS owners (
    id SERIAL PRIMARY KEY,
    display_name TEXT,
    owner_key TEXT UNIQUE NOT NULL,
    roblox_user_id BIGINT,
    roblox_group_id BIGINT,
    discord_user_id BIGINT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS models (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id INT REFERENCES owners(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    roblox_asset_id BIGINT,
    mesh_count INT DEFAULT 0,
    fingerprint TEXT,
    registered_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS whitelist (
    id SERIAL PRIMARY KEY,
    model_id UUID REFERENCES models(id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL,
    note TEXT,
    added_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(model_id, user_id)
);

CREATE TABLE IF NOT EXISTS model_meshes (
    id SERIAL PRIMARY KEY,
    model_id UUID REFERENCES models(id) ON DELETE CASCADE,
    mesh_asset_id BIGINT NOT NULL,
    mesh_name TEXT,
    UNIQUE(model_id, mesh_asset_id)
);

CREATE TABLE IF NOT EXISTS usage_logs (
    id SERIAL PRIMARY KEY,
    model_id UUID REFERENCES models(id),
    actor_user_id BIGINT NOT NULL,
    place_id BIGINT,
    server_job_id TEXT,
    mesh_ids BIGINT[],
    meta JSONB,
    allowed BOOLEAN,
    reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_models_owner ON models(owner_id);
CREATE INDEX IF NOT EXISTS idx_whitelist_model ON whitelist(model_id);
CREATE INDEX IF NOT EXISTS idx_whitelist_user ON whitelist(user_id);
CREATE INDEX IF NOT EXISTS idx_model_meshes_model ON model_meshes(model_id);
CREATE INDEX IF NOT EXISTS idx_usage_logs_model ON usage_logs(model_id);
CREATE INDEX IF NOT EXISTS idx_usage_logs_actor ON usage_logs(actor_user_id);
