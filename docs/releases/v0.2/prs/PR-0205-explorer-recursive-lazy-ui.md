# PR-0205-explorer-recursive-lazy-ui

- Proposed title: `feat(notes-explorer): recursive explorer with lazy folder loading`
- Status: Planned

## Goal

Replace flat explorer behavior with a recursive tree interaction model driven by core hierarchy APIs.

## References

- `docs/product/ui-standards/note-ui-dev-spec.md`
- `docs/product/ui-standards/note-ui.md`
- `docs/product/ui-standards/task-ui-dev-spec.md`
- `docs/product/ui-standards/calendar-ui-dev-spec.md`
- `docs/api/workspace-tree-contract.md`
- `docs/api/ffi-contracts.md`

## Dependency

- `PR-0205A-notes-ui-shell-alignment` should land first (or provide equivalent shell alignment),
  so this PR can focus only on explorer behavior.
- Note explorer visual style must follow the same shell token language used by
  Notes/Task/Calendar surfaces (container, divider, spacing, row state emphasis).

## Scope (v0.2)

In scope:

- recursive folder rendering
- lazy load children on expand
- single-click preview open in active pane
- double-click pinned open in active pane
- hover-first minimalist explorer actions
- explorer-level loading/error/empty states for lazy children

Out of scope:

- notes page shell visual alignment (handled by `PR-0205A`)
- full drag edge split behavior
- advanced tree virtualization
- workspace provider contract changes

## Interaction Rules

1. Expand folder:
   - request children only when expanded first time
2. Single click note:
   - open as preview tab in active pane
3. Double click note:
   - convert/open as pinned tab

## Step-by-Step

1. Build recursive tree item components.
2. Integrate lazy children query with loading/error states.
3. Wire preview/pinned open semantics through existing controller/provider contracts (no API shape change).
4. Add widget tests for expand/collapse and open behavior.

## Planned File Changes

- [edit] `apps/lazynote_flutter/lib/features/notes/note_explorer.dart`
- [add] `apps/lazynote_flutter/lib/features/notes/explorer_tree_item.dart`
- [add] `apps/lazynote_flutter/lib/features/notes/explorer_tree_state.dart`
- [add] `apps/lazynote_flutter/test/note_explorer_tree_test.dart`

## Verification

- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test test/note_explorer_tree_test.dart`
- `cd apps/lazynote_flutter && flutter test`

## Acceptance Criteria

- [ ] Explorer renders nested folders recursively.
- [ ] Child nodes load lazily on expansion.
- [ ] Single-click preview and double-click pinned semantics work in active pane.
- [ ] Error/empty/loading states are visible and recoverable.
- [ ] Explorer states (default/hover/selected/loading/error) remain visually consistent with the shared UI style system.
