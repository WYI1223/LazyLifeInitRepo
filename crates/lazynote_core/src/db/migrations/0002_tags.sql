-- Migration: 0002_tags.sql
-- Purpose: create tags and atom_tags join table for many-to-many relationships.
-- Invariants:
-- - tags.name is unique (case-insensitive).
-- - atom_tags pairs are unique by (atom_uuid, tag_id).
-- - atom_tags rows must reference existing atoms and tags.
-- Backward compatibility:
-- - additive schema update on top of 0001_init.sql.

CREATE TABLE IF NOT EXISTS tags (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL COLLATE NOCASE UNIQUE,
    created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now') * 1000)
);

CREATE TABLE IF NOT EXISTS atom_tags (
    atom_uuid TEXT NOT NULL,
    tag_id INTEGER NOT NULL,
    created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now') * 1000),
    PRIMARY KEY (atom_uuid, tag_id),
    FOREIGN KEY (atom_uuid) REFERENCES atoms(uuid) ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_atom_tags_tag_id ON atom_tags(tag_id);
