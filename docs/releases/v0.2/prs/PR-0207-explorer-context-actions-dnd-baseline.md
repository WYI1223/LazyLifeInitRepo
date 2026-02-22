# PR-0207-explorer-context-actions-dnd-baseline

- Proposed title: `feat(notes-ui): explorer context actions and baseline drag reorder`
- Status: Completed

## Goal

Add practical file-manager interactions to explorer tree for daily notes operations.

## Background

- `PR-0205` delivered recursive lazy tree baseline.
- `PR-0205B` froze explorer/tab open-intent ownership.
- `PR-0206`/`PR-0206B` stabilized pane/layout behavior.
- `PR-0207A` closes v0.2 note-row title/rename semantic alignment after M1.
- `PR-0207` now fills explorer operation baseline (context actions first, drag later).

## Requirement Freeze (confirmed 2026-02-20)

1. Synthetic root `__uncategorized__` is not renameable/movable/deletable.
2. `New note` in folder uses create-note + create-note-ref, then auto-open.
3. `Move` in M1 uses minimal dialog (pick target parent) rather than drag UX.
4. Right-click on blank explorer area exposes create actions.
5. Explorer refresh must preserve expand/collapse state (no forced re-expand/reset).
6. `note_ref` rename is frozen in v0.2; rename entry is folder-only.
7. Explorer note row title uses Atom title projection (including draft-aware projection), not independent `note_ref` alias editing.
8. `dissolve` display mapping follows hybrid policy: note refs return to synthetic `Uncategorized`, while child folders are promoted to root.
9. `Uncategorized` projection must not duplicate notes that already appear via
   workspace folder references.
10. Folder row right-click must be row-wide and deterministic:
   - right-click on icon/text/row whitespace opens folder row menu
   - row menu has priority; blank-area menu must not pop on the same gesture

## Scope (v0.2)

In scope:

- right-click menu:
  - new note
  - new folder
  - rename (folder-only in v0.2)
  - move
- baseline drag-reorder (same parent first, cross-parent second; post-M1)
- visual hover action affordances

Out of scope:

- multi-select batch operations
- advanced undo/redo stack for tree operations
- recursive split-aware drag orchestration
- advanced move tree-picker UX (search, breadcrumb, keyboard nav)

## M1 Boundary (start implementation against this)

M1 only lands context actions and deterministic refresh behavior:

- context menu action model + action dispatch
- create note / create folder / rename(folder) / move dialogs (minimal UX)
- strict synthetic-root guardrails
- expansion-state preservation during tree reload
- regression tests for action success/failure paths

M1 explicitly does **not** include drag reorder implementation.

## M2 Boundary (drag baseline, start implementation against this)

M2 only lands deterministic drag/move baseline behavior:

- same-parent reorder via drag
- cross-parent move via drag
- clear drop indicator and invalid-target rejection
- branch refresh consistency after move
- regression tests for drag success/failure paths

M2 frozen rules:

1. synthetic root `__uncategorized__` is not draggable and not a drop target row.
2. drop-to-root is only allowed via blank area/root lane (maps to `new_parent_id = null`).
3. folder-before-note projection must stay stable after drag:
   - drag reorder is only allowed within same `kind` group under one parent.
   - cross-kind reorder in one parent is rejected in UI.
4. note_ref alias rename policy stays unchanged (still frozen in v0.2).
5. no optimistic local reorder persistence without backend success.
6. on successful move:
   - refresh source parent branch
   - refresh target parent branch
   - preserve expand/collapse state
7. on failed move:
   - keep tree state unchanged
   - show explicit recoverable feedback
8. M2 keeps existing FFI contract shape (no new Rust API).

## Step-by-Step

1. Freeze action boundary and menu matrix:
   - node row menu (`folder`, `note_ref`, synthetic root)
   - blank-area menu
2. Implement action handlers with guardrails:
   - reject rename/move/delete for synthetic root
   - map synthetic-root create-parent semantics to root (`null`) path
3. Implement M1 dialogs:
   - create folder
   - create note (name optional policy consistent with existing note create flow)
   - rename (folder-only)
   - move (target parent picker, no drag)
4. Wire operations through existing controller/FFI flows:
   - use existing workspace APIs only
   - no new Rust contract shape
5. Preserve visual state:
   - keep expanded folder set and active selection stable after refresh
6. Add M1 regressions:
   - action visibility matrix
   - create/rename/move success + recoverable failure
   - expansion-state preservation assertions

## Step-by-Step (M2)

1. Freeze drag/drop target matrix and rejection rules.
   - row drag source: `folder` / `note_ref` (except synthetic root)
   - row drop target: same-kind sibling lane or folder container lane
   - blank-area drop target: root lane (`new_parent_id = null`)
2. Add drag controller and target-order projection.
   - compute target parent and target order from visible tree projection
   - keep same-kind ordering invariant
3. Wire drag move execution through `workspace_move_node`.
   - no FFI shape changes
   - no new error-code namespace
4. Preserve UI consistency.
   - refresh source + target branches on success
   - preserve expansion state and active selection
5. Add M2 regressions.
   - same-parent reorder success
   - cross-parent move success
   - invalid drop rejection
   - failure path with no stale UI reorder

## Contract Impact

- No Rust FFI API add/remove/rename in M1.
- No new stable error-code namespace in M1.
- M1 consumes existing contracts:
  - `workspace_list_children`
  - `workspace_create_folder`
  - `workspace_create_note_ref`
  - `workspace_rename_node` (folder nodes only in v0.2 UI policy)
  - `workspace_move_node`
  - existing note create/open contracts
- UI-local guard policy is documented in `docs/api/ffi-contracts.md` under PR-0207 section.

## Implementation Notes (M1 landed)

- added explorer context menu model in
  `apps/lazynote_flutter/lib/features/notes/explorer_context_menu.dart`
- `NoteExplorer` now supports:
  - right-click blank-area create menu
  - folder/note row context actions (new note/new folder/move/delete; rename kept for folder rows)
  - right-click dispatch dedup (row menu has priority over blank-area menu)
  - row-wide folder context-menu hit target (icon/text/whitespace all map to row menu)
  - synthetic root guardrails (`__uncategorized__` cannot rename/move/delete)
  - root-parent normalization for synthetic root create/move
  - deterministic branch refresh after mutations:
    - child-folder delete refreshes affected parent branch immediately
    - child-folder rename refreshes affected parent branch immediately
    - no stale/ghost child row remains in explorer cache
  - synthetic `Uncategorized` note rows project live title from controller draft
- `NotesController` now exposes M1 workspace mutation APIs:
  - `createWorkspaceNoteInFolder`
  - `renameWorkspaceNode`
  - `moveWorkspaceNode`
- `NotesPage` wires explorer context callbacks to controller actions.
- default first-party slot chain is fully wired (not fallback-only):
  - `notes_on_create_note_in_folder_requested`
  - `notes_on_rename_node_requested`
  - `notes_on_move_node_requested`
- M1 regression tests added:
  - `apps/lazynote_flutter/test/explorer_context_actions_test.dart`
  - `apps/lazynote_flutter/test/notes_controller_workspace_tree_guards_test.dart`
  - `apps/lazynote_flutter/test/notes_page_explorer_slot_wiring_test.dart`
  - `apps/lazynote_flutter/test/note_explorer_tree_test.dart` (rename/delete child branch refresh)

## Implementation Notes (M2 landed)

- added drag decision helper:
  - `apps/lazynote_flutter/lib/features/notes/explorer_drag_controller.dart`
- `NoteExplorer` now supports baseline drag/drop:
  - draggable folder/note_ref rows (synthetic root and non-stable ids excluded)
  - row drop semantics:
    - same-parent + same-kind => reorder with `targetOrder`
    - cross-parent drop onto folder => move into folder (append)
  - root-lane drop (`new_parent_id = null`) during active drag
  - explicit drop highlight for reorder vs move-into-folder
  - mutation success path refreshes source/target branches while preserving expand state
- move callback contract upgraded for M2:
  - `onMoveNodeRequested(nodeId, newParentNodeId, {targetOrder})`
  - context-menu move continues to call with `targetOrder = null`
- M2 regression tests added:
  - `apps/lazynote_flutter/test/explorer_drag_controller_test.dart`
  - existing M1 suites remain green (`explorer_context_actions_test.dart`, `note_explorer_tree_test.dart`, `notes_page_explorer_slot_wiring_test.dart`)

## Planned File Changes

- [edit] `apps/lazynote_flutter/lib/features/notes/note_explorer.dart`
- [add] `apps/lazynote_flutter/lib/features/notes/explorer_context_menu.dart`
- [edit] `apps/lazynote_flutter/lib/features/notes/notes_controller.dart`
- [edit] `apps/lazynote_flutter/lib/features/workspace/workspace_provider.dart`
- [add] `apps/lazynote_flutter/test/explorer_context_actions_test.dart`
- [edit] `docs/api/ffi-contracts.md`
- [edit] `docs/releases/v0.2/README.md`

M2 expected additions:

- [add] `apps/lazynote_flutter/lib/features/notes/explorer_drag_controller.dart`
- [edit] `apps/lazynote_flutter/test/explorer_context_actions_test.dart` (drag cases)
- [edit] `apps/lazynote_flutter/lib/features/notes/note_explorer.dart` (drop indicator + drag dispatch)
- [edit] `apps/lazynote_flutter/lib/features/notes/explorer_tree_state.dart` (target-order projection helper)

## Verification

- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test test/explorer_context_actions_test.dart`
- `cd apps/lazynote_flutter && flutter test`

Verification replay (2026-02-20):

- `flutter analyze` passed.
- `flutter test test/explorer_context_actions_test.dart test/notes_controller_workspace_tree_guards_test.dart test/note_explorer_tree_test.dart test/note_explorer_workspace_delete_test.dart` passed.
- `flutter test` passed.

## Acceptance Criteria (M1)

- [x] Context menu supports create/folder-rename/move actions end-to-end.
- [x] Synthetic root guardrails are enforced (`__uncategorized__` non-movable/non-renameable).
- [x] Blank-area menu supports create actions.
- [x] Create/move/rename refresh keeps explorer expand/collapse state stable.
- [x] M1 lands without FFI contract shape drift.
- [x] Failure paths are explicit and recoverable.

## Follow-up (M2+)

- M2: drag reorder baseline (same-parent then cross-parent) with clear drop indicators. (landed)
- M3: hardening/docs closure (error/retry UX, edge-case regression expansion). (landed)
- M4 transition lane (in progress):
  - `PR-0207B` contract freeze for ordering + move semantics
  - `PR-0207C` implementation (no-reorder move + title-only explorer note rows + legacy note_ref backfill)
  - `PR-0207D` closure replay (docs sync + migration/QA evidence + obsolete reorder cleanup)
- transition note:
  - PR-0207 M2 same-parent reorder behavior is treated as legacy baseline.
  - PR-0207B/0207C replace it with parent-change-only move semantics.

## Acceptance Criteria (M2)

- [x] Drag reorder works within same parent and same-kind group.
- [x] Drag move works across parents and keeps projection invariants.
- [x] Invalid drop targets are clearly rejected (no hidden side effects).
- [x] Source/target branches refresh deterministically after successful drop.
- [x] Expansion-state preservation remains stable.
- [x] M2 lands without FFI contract shape drift.

## M3 Closure (landed)

- synchronized M2 move callback contract across UI slot wiring and docs:
  - `onMoveNodeRequested(nodeId, newParentNodeId, {targetOrder})`
- finalized docs alignment:
  - PR status, README execution checklist, and FFI contract notes are consistent
- expanded regression guardrail set:
  - added drag decision unit coverage (`explorer_drag_controller_test.dart`)
  - retained M1/M2 integration suites as release guard

## Acceptance Criteria (M3)

- [x] PR status/docs/contract index are synchronized.
- [x] Drag policy edge cases are regression-covered (same-kind reorder, cross-parent move, invalid drop).
- [x] No additional FFI shape drift introduced by closure work.

## Verification replay (2026-02-21)

- `cd apps/lazynote_flutter && flutter analyze` passed.
- `cd apps/lazynote_flutter && flutter test test/explorer_drag_controller_test.dart test/explorer_context_actions_test.dart test/note_explorer_tree_test.dart test/notes_page_explorer_slot_wiring_test.dart test/notes_controller_workspace_tree_guards_test.dart` passed.
- `cd apps/lazynote_flutter && flutter test` passed.
