# PR-0207C-explorer-ordering-and-backfill-implementation

- Proposed title: `feat(workspace-tree): implement canonical ordering + legacy note_ref backfill`
- Status: In Progress (depends on PR-0207B)

## Goal

Implement the frozen semantics from `PR-0207B`:

1. parent-change-only move semantics (no same-parent reorder)
2. canonical explorer ordering policy
3. title-only explorer note rows (no preview text)
4. one-time legacy note -> `note_ref` backfill so old notes can move

## Scope

In scope:

- disable reorder-specific drag paths in explorer UI
- keep move-to-folder/root behavior
- align runtime ordering with contract freeze
- remove note preview text rendering from explorer rows
- materialize missing root-level `note_ref` rows for legacy notes
- add regression coverage for ordering and non-reorder move behavior

Out of scope:

- new major FFI API surface
- recursive drag UX redesign
- v3-level alias/title model changes

## Implementation Plan

1. Move semantics (Flutter):
   - remove same-parent reorder plan from drag controller
   - keep folder-target/root-lane move only
   - pass `targetOrder: null` for UI-originated moves
2. Ordering policy (Flutter projection):
   - root/folder branches render by frozen grouping/name rules
   - `Uncategorized` rows sort by note update time descending
3. Note row rendering policy (Flutter):
   - render note rows with title-only line
   - remove preview text projection dependency from explorer rows
4. Legacy note backfill (Core migration):
   - add one idempotent migration step to create missing root-level `note_ref`
     for active notes with no active workspace reference
   - guarantee no duplicate `note_ref` for same note in root
5. Compatibility:
   - keep existing `workspace_move_node` shape for v0.2 compatibility
6. Tests:
   - no-reorder drag rejection and move success
   - deterministic ordering assertions for root/folder/uncategorized
   - title-only row rendering assertions (no preview row text)
   - migration replay/backfill idempotence assertions

## Contract Impact

- no removal/rename of existing FFI function signatures
- semantics update only: `target_order` is compatibility-only in UI path
- docs synchronized with `PR-0207B`

## Planned File Changes

- [edit] `apps/lazynote_flutter/lib/features/notes/explorer_drag_controller.dart`
- [edit] `apps/lazynote_flutter/lib/features/notes/note_explorer.dart`
- [edit] `apps/lazynote_flutter/lib/features/notes/explorer_tree_item.dart`
- [edit] `apps/lazynote_flutter/lib/features/notes/explorer_tree_state.dart`
- [edit] `apps/lazynote_flutter/lib/features/notes/notes_controller.dart`
- [edit] `apps/lazynote_flutter/test/explorer_drag_controller_test.dart`
- [edit] `apps/lazynote_flutter/test/note_explorer_tree_test.dart`
- [edit] `apps/lazynote_flutter/test/notes_controller_workspace_tree_guards_test.dart`
- [add] `crates/lazynote_core/src/db/migrations/0009_workspace_note_ref_backfill.sql`
- [edit] `crates/lazynote_core/src/db/migrations/mod.rs`
- [edit] `crates/lazynote_core/tests/db_migrations.rs`

## Verification

- `cd crates && cargo test -p lazynote_core --test db_migrations`
- `cd crates && cargo test -p lazynote_core --test workspace_tree`
- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test test/explorer_drag_controller_test.dart test/note_explorer_tree_test.dart test/notes_controller_workspace_tree_guards_test.dart`

## Acceptance Criteria

- [ ] Explorer drag no longer supports same-parent reorder.
- [ ] Folder/root move remains functional and deterministic.
- [ ] Ordering behavior matches frozen contract across all branches.
- [ ] Explorer note rows are title-only and render no preview text.
- [ ] Legacy notes are materialized into workspace tree via idempotent backfill.
- [ ] Regression tests cover move semantics + ordering + migration.
