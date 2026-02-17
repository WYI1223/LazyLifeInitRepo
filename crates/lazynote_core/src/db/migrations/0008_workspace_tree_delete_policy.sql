-- Migration: 0008_workspace_tree_delete_policy.sql
-- Purpose: switch workspace tree delete semantics from strict blocking (A)
--          to hybrid behavior (note delete allowed, read-time filtering).
-- Invariants:
-- - Existing workspace schema shape remains unchanged.
-- - note_ref creation/update still requires active note target (from 0007).
-- - Atom delete/type-change is no longer blocked by workspace references.
-- Backward compatibility:
-- - Drops only policy triggers introduced by 0007; data remains untouched.

DROP TRIGGER IF EXISTS atoms_block_note_demote_when_referenced;
DROP TRIGGER IF EXISTS atoms_block_note_delete_when_referenced;
