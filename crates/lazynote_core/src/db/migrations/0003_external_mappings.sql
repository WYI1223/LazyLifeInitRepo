-- Migration: 0003_external_mappings.sql
-- Purpose: create provider mapping table for external sync identifiers.
-- Invariants:
-- - (provider, external_id) must be unique.
-- - each atom has at most one mapping per provider.
-- - mappings must reference existing atoms.
-- Backward compatibility:
-- - additive schema update on top of 0002_tags.sql.

CREATE TABLE external_mappings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    provider TEXT NOT NULL,
    external_id TEXT NOT NULL,
    atom_uuid TEXT NOT NULL,
    external_version TEXT NULL,
    last_synced_at INTEGER NULL,
    created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now') * 1000),
    updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now') * 1000),
    UNIQUE (provider, external_id),
    UNIQUE (provider, atom_uuid),
    FOREIGN KEY (atom_uuid) REFERENCES atoms(uuid) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_external_mappings_atom_uuid
    ON external_mappings(atom_uuid);
