-- Migration: 0009_workspace_note_ref_backfill.sql
-- Purpose: materialize legacy active notes into workspace tree as root note_ref
--          rows when they currently have no active workspace reference.
-- Invariants:
-- - Only `atoms.type='note' AND is_deleted=0` rows are candidates.
-- - Existing active note_ref rows are preserved; no duplicates are added.
-- - New note_ref rows are created at root level (`parent_uuid IS NULL`).
-- - Migration is idempotent when replayed.

WITH missing_notes AS (
    SELECT
        a.uuid AS atom_uuid,
        ROW_NUMBER() OVER (ORDER BY a.updated_at DESC, a.uuid ASC) AS row_num
    FROM atoms a
    WHERE a.type = 'note'
      AND a.is_deleted = 0
      AND NOT EXISTS (
          SELECT 1
          FROM workspace_nodes n
          WHERE n.kind = 'note_ref'
            AND n.atom_uuid = a.uuid
            AND n.is_deleted = 0
      )
),
base_sort AS (
    SELECT COALESCE(MAX(sort_order), -1) AS base_order
    FROM workspace_nodes
    WHERE parent_uuid IS NULL
      AND is_deleted = 0
)
INSERT INTO workspace_nodes (
    node_uuid,
    kind,
    parent_uuid,
    atom_uuid,
    display_name,
    sort_order,
    is_deleted,
    created_at,
    updated_at
)
SELECT
    lower(
        hex(randomblob(4)) || '-' ||
        hex(randomblob(2)) || '-4' ||
        substr(hex(randomblob(2)), 2) || '-' ||
        substr('89ab', (abs(random()) % 4) + 1, 1) ||
        substr(hex(randomblob(2)), 2) || '-' ||
        hex(randomblob(6))
    ) AS node_uuid,
    'note_ref' AS kind,
    NULL AS parent_uuid,
    m.atom_uuid,
    'Untitled note' AS display_name,
    (b.base_order + m.row_num) AS sort_order,
    0 AS is_deleted,
    (strftime('%s', 'now') * 1000) AS created_at,
    (strftime('%s', 'now') * 1000) AS updated_at
FROM missing_notes m
CROSS JOIN base_sort b;
