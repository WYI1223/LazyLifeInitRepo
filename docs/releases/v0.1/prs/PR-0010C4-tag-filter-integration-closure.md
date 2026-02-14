# PR-0010C4-tag-filter-integration-closure

- Proposed title: `feat(notes-ui): single-tag filter and integration closure`
- Status: Implemented

## Goal

Complete the v0.1 Notes UI flow by landing single-tag filtering and full integration-level regression coverage.

## Scope (v0.1)

In scope:

- single-select tag filter UI with chip-toggle clear behavior
- `tags_list` and `notes_list(tag)` wiring
- list/detail coherence across filter transitions
- regression tests for primary and failure paths
- doc closure for PR-0010C implementation behavior

Out of scope:

- multi-tag boolean filter builder
- tag hierarchy and advanced scoring behaviors

## UI Requirements

1. Filter is single-select in v0.1.
2. Tapping the selected tag chip clears filter and restores unfiltered list.
3. Active filter state is visible.
4. When tags overflow, filter area supports click-to-expand downward and collapse.
5. Filter failures are explicit and recoverable.

## Locked Decisions (Applied)

1. Filter control location: Explorer header top region (between header and list).
2. Tag ordering: alphabetical.
3. Filter persistence: disabled in v0.1 (reset on restart).
4. Contextual create under active filter: new note auto-applies current tag.
5. Ghost state on tag removal:
   - list updates immediately
   - editor keeps current note open
6. Frontend validation: blank tag input is silently ignored.

## Landed Notes

1. Added reusable tag filter component:
   - `apps/lazynote_flutter/lib/features/tags/tag_filter.dart`
2. Wired `tags_list` and `notes_list(tag)` through `NotesController`:
   - added `selectedTag`, `availableTags`, `tagsLoading`, `tagsErrorMessage`
   - added `applyTagFilter`, `clearTagFilter`, `retryTagLoad`
   - removed explicit `Clear` button and unified apply/clear on tag chip toggle
3. Added immediate tag mutation path (`note_set_tags`) for active note:
   - `setActiveNoteTags`, `addTagToActiveNote`, `removeTagFromActiveNote`
4. Implemented contextual create auto-tag:
   - when filter is active, `createNote()` calls `note_set_tags` with current tag
5. Implemented ghost-state consistency:
   - if active note no longer matches selected filter after tag edit, explorer list refreshes
   - content area remains open on the active editor
6. Added explicit filter failure and recovery paths:
   - tag catalog failure (`tags_list`) shows retryable error in filter area
   - filtered list failure (`notes_list(tag)`) is retryable via existing list retry action
7. Fixed filtered-list coherence for tab activation:
   - activating an open tab whose note does not match current filter no longer inserts that note into explorer filtered list
8. Fixed orphan tag lifecycle:
   - `note_set_tags` now prunes unused tags in core repository
   - tags removed from the last referencing note disappear from filter list after refresh
9. Added overflow handling in filter area:
   - collapsed mode shows first N tags and a `+N more` affordance
   - expanded mode renders full tag chip set with collapse action

## Known Behavior and Deferred Items

1. Contextual create under active filter is currently non-transactional:
   - implementation uses `note_create` then `note_set_tags`
   - if `note_set_tags` fails after create succeeds, new note already exists in backend
   - UI keeps create success path and shows warning message
2. Note delete is out of scope for C4/v0.1:
   - no delete affordance is shipped in current Notes UI

## Step-by-Step

1. Add reusable `tag_filter.dart` component. `Done`
2. Load available tags via `tags_list`. `Done`
3. Apply and clear `notes_list(tag)` filtering. `Done`
4. Preserve selected note behavior when filter changes. `Done`
5. Add end-to-end widget tests for filter + create/edit/save interactions. `Done`
6. Sync PR docs with implemented behavior and known non-goals. `Done`
7. Add overflow expand/collapse interaction for large tag sets. `Done`

## File Changes

- [add] `apps/lazynote_flutter/lib/features/tags/tag_filter.dart`
- [edit] `apps/lazynote_flutter/lib/features/notes/notes_controller.dart`
- [edit] `apps/lazynote_flutter/lib/features/notes/note_explorer.dart`
- [edit] `apps/lazynote_flutter/lib/features/notes/note_content_area.dart`
- [add] `apps/lazynote_flutter/test/notes_page_c4_test.dart`
- [edit] `docs/releases/v0.1/prs/PR-0010C-notes-tags-ui.md`

## Verification

- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test test/notes_page_c4_test.dart`
- `cd apps/lazynote_flutter && flutter test`

## Acceptance Criteria

- [x] Single-tag filter apply and clear work correctly.
- [x] Filter transitions keep list/detail state coherent.
- [x] Regression tests cover filter success/error and recovery.
- [x] PR-0010C docs are synchronized with shipped behavior.
- [x] Tag filter remains usable when tag count exceeds one-row capacity.
