# PR-0207B-explorer-ordering-contract-freeze

- Proposed title: `docs(workspace-tree): freeze explorer ordering and move semantics`
- Status: Completed

## Goal

Freeze one stable ordering/move contract before any further code change so
workspace tree behavior is predictable and testable.

## Why This Follow-up

`PR-0207` delivered context actions + drag baseline, but review feedback shows
semantic ambiguity in three places:

1. Same-parent reorder is not product-critical and adds policy complexity.
2. Ordering policy is split across backend sort keys and Flutter projection.
3. Legacy notes without persisted `note_ref` cannot fully participate in move.

This PR is documentation-only and defines the exact v0.2 behavior boundary.

## Requirement Freeze (v0.2)

1. Explorer move semantics:
   - drag/drop is for changing parent folder only
   - same-parent reorder is not a supported user capability
   - `target_order` is treated as compatibility field and ignored by UI policy
2. Ordering semantics:
   - root level: synthetic `Uncategorized` first, then folders by name
   - normal folder children: `folder` group first, `note_ref` group second
   - within each group: name ascending (case-insensitive), stable id tie-break
   - `Uncategorized` note rows: `updated_at DESC`, then `atom_id ASC`
3. Note row rendering semantics:
   - all note rows are title-only
   - note preview text is not rendered in explorer rows
4. Legacy note behavior:
   - active notes must be materialized into workspace tree as real `note_ref`
   - each note appears exactly once in explorer projection
5. Contract compatibility:
   - no immediate FFI removal in this freeze PR
   - `workspace_move_node(..., target_order?)` remains shape-compatible

## Scope

In scope:

- update contract docs for ordering/move semantics
- freeze note-row display as title-only (no preview)
- define migration/backfill expectation for legacy notes
- define test matrix for follow-up implementation PR

Out of scope:

- runtime code changes
- schema/data migration implementation
- drag UX redesign

## Planned Doc Changes

- [x] `docs/api/ffi-contracts.md`
- [x] `docs/api/workspace-tree-contract.md`
- [x] `docs/architecture/data-model.md`
- [x] `docs/releases/v0.2/prs/PR-0207-explorer-context-actions-dnd-baseline.md`
- [x] `docs/releases/v0.2/README.md`

## Execution Notes (2026-02-22)

1. Contract docs now explicitly freeze parent-change-only move semantics.
2. Same-parent reorder is marked as compatibility/legacy behavior pending runtime removal in `PR-0207C`.
3. Explorer note-row contract is frozen to title-only (no preview text).
4. `sort_order` is documented as backend compatibility ordering key, not a UI reorder capability.

## Acceptance Criteria

- [x] Ordering contract is explicit and unambiguous (root/folder/uncategorized).
- [x] Move contract clearly states "parent change only, no same-parent reorder".
- [x] Note-row contract clearly states "title-only, no preview text".
- [x] Legacy-note backfill requirement is documented as mandatory follow-up.
- [x] Contract docs and release plan are synchronized.
