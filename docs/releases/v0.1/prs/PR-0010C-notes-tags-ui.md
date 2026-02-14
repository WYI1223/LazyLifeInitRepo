# PR-0010C-notes-tags-ui

- Proposed title: `feat(notes-ui): notes list/editor and tag filter integration`
- Status: Planned

## Goal

Build the first usable Notes UI on top of PR-0010B contracts:

- list notes
- edit note content
- filter by one tag

## Scope (v0.1)

In scope:

- Notes page replaces current Notes placeholder route
- list panel + editor panel baseline layout
- create note, select note, edit/save note
- single-tag filter selector and clear action
- loading/error/empty states

Out of scope:

- markdown preview renderer
- editor formatting toolbar
- multi-tag boolean filter builder

## UX Requirements (Locked)

1. Keep Workbench as current host shell; Notes page is feature content in left pane.
2. Notes list is ordered by recency from backend contract.
3. Selecting a note opens it in editor without route churn.
4. Tag filter is single-select in v0.1:
   - selecting one tag applies filter
   - clear returns to full list
5. Failure states must be explicit and recoverable (retry/manual refresh).

## Step-by-Step

1. Add notes controller for list/detail/filter state.
2. Wire FFI invokers from PR-0010B APIs into controller.
3. Implement notes list view (loading/empty/error/success states).
4. Implement note editor view (content edit + save action).
5. Implement tag filter UI (chip/dropdown style, single-select).
6. Ensure save/refresh updates list and detail consistently.
7. Add widget tests for:
   - load + render
   - select + edit + save
   - single-tag filter apply/clear
   - error and retry path
8. Run quality gates.

## Planned File Changes

- [add] `apps/lazynote_flutter/lib/features/notes/notes_page.dart`
- [add] `apps/lazynote_flutter/lib/features/notes/note_editor.dart`
- [add] `apps/lazynote_flutter/lib/features/notes/notes_controller.dart`
- [add] `apps/lazynote_flutter/lib/features/tags/tag_filter.dart`
- [edit] `apps/lazynote_flutter/lib/features/entry/entry_shell_page.dart` (Notes section wiring)
- [add] `apps/lazynote_flutter/test/notes_flow_test.dart`

## Dependencies

- PR-0010B (core + FFI contracts ready)
- PR-0008 shell routing baseline
- PR-0010A visual shell contract

## Quality Gates

- `flutter analyze`
- `flutter test`
- plus existing Rust gates in full pipeline

## Acceptance Criteria

- [ ] Notes placeholder is replaced by functional notes list/editor UI.
- [ ] Single-tag filter works and can be cleared.
- [ ] Save path updates UI state consistently.
- [ ] Flutter tests cover primary and failure flows.
