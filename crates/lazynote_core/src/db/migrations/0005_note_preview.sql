-- Migration: 0005_note_preview.sql
-- Purpose: add note preview projection columns for markdown-based notes.
-- Invariants:
-- - preview_text stores sanitized summary text, max 100 chars from hook logic.
-- - preview_image stores first markdown image path when present.
-- - both fields are nullable and derived from `content`, never source-of-truth.
-- Backward compatibility:
-- - additive columns on top of existing atoms schema.

ALTER TABLE atoms
ADD COLUMN preview_text TEXT NULL;

ALTER TABLE atoms
ADD COLUMN preview_image TEXT NULL;
