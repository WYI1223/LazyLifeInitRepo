-- Migration: 0001_init.sql
-- Purpose: create the canonical atoms table for note/task/event projections.
-- Invariants:
-- - atoms.uuid is a stable ID and primary key.
-- - atoms.is_deleted is a soft-delete marker (0 or 1).
-- - event_end must be >= event_start when both are present.
-- Backward compatibility:
-- - baseline schema for v0.1; follow-up migrations should be additive.

CREATE TABLE IF NOT EXISTS atoms (
    uuid TEXT PRIMARY KEY NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('note', 'task', 'event')),
    content TEXT NOT NULL,
    task_status TEXT NULL CHECK (
        task_status IS NULL OR task_status IN ('todo', 'in_progress', 'done', 'cancelled')
    ),
    event_start INTEGER NULL,
    event_end INTEGER NULL,
    hlc_timestamp TEXT NULL,
    is_deleted INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1)),
    created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now') * 1000),
    updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now') * 1000),
    CHECK (
        event_start IS NULL
        OR event_end IS NULL
        OR event_end >= event_start
    )
);

CREATE INDEX IF NOT EXISTS idx_atoms_type ON atoms(type);
CREATE INDEX IF NOT EXISTS idx_atoms_is_deleted ON atoms(is_deleted);
CREATE INDEX IF NOT EXISTS idx_atoms_updated_at ON atoms(updated_at);
