# PR-0205A-notes-ui-shell-alignment

- Proposed title: `feat(notes-ui): align notes shell with shared v0.2 visual language`
- Status: Planned

## Goal

Align Notes page shell style with the same visual language used by Task and Calendar UI:
single unified workspace shell, subtle split divider, consistent spacing, and state styling.

## References

- `docs/product/ui-standards/note-ui-dev-spec.md`
- `docs/product/ui-standards/note-ui.md`
- `docs/product/ui-standards/task-ui-dev-spec.md`
- `docs/product/ui-standards/calendar-ui-dev-spec.md`

## Scope (v0.2)

In scope:

- notes page two-pane shell alignment (`Header + Explorer + Divider + Editor`)
- shared style token alignment (container/divider/spacing/hover-selected emphasis)
- right pane composition alignment (`Tab strip + content area + optional capsule overlay slot`)
- UI-only state rendering alignment (loading/error/empty/success, save states)
- responsive baseline alignment (compact header and stable explorer width)

Out of scope:

- recursive explorer data behavior (handled by `PR-0205`)
- split-layout interactions (handled by `PR-0206`)
- drag-reorder/context actions (handled by `PR-0207`)
- any Rust/FFI/domain contract changes

## Step-by-Step

1. Align Notes shell layout grammar to `note-ui-dev-spec`.
2. Normalize explorer/editor visual tokens to shared v0.2 style language.
3. Add optional capsule overlay slot structure (UI-only; behavior can remain stubbed).
4. Add widget tests for shell composition and core visual states.

## Planned File Changes

- [edit] `apps/lazynote_flutter/lib/features/notes/notes_page.dart`
- [edit] `apps/lazynote_flutter/lib/features/notes/note_explorer.dart`
- [edit] `apps/lazynote_flutter/lib/features/entry/workbench_shell_layout.dart`
- [add] `apps/lazynote_flutter/test/notes_ui_shell_alignment_test.dart`
- [edit] `docs/releases/v0.2/prs/PR-0205-explorer-recursive-lazy-ui.md` (dependency note)

## Verification

- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test test/notes_ui_shell_alignment_test.dart`
- `cd apps/lazynote_flutter && flutter test`

## Acceptance Criteria

- [ ] Notes shell layout matches `note-ui-dev-spec` structure.
- [ ] Notes visual language is consistent with Task/Calendar shell style.
- [ ] Core UI states are distinguishable without business logic changes.
- [ ] Optional capsule overlay slot can be toggled without covering end-of-content lines.
