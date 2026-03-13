-- ============================================================
-- PostgreSQL init script for Home Assistant
-- Runs automatically on first container start
-- ============================================================

-- Ensure the database uses UTF-8 encoding (already set by POSTGRES_DB env)
-- Grant full privileges to the HA user
ALTER DATABASE homeassistant SET timezone TO 'UTC';

-- Create ltree extension (used by Home Assistant recorder)
CREATE EXTENSION IF NOT EXISTS ltree;
