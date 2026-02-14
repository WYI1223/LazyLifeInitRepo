# PR-0010C3-note-autosave-switch-flush

- Proposed title: `feat(notes-ui): debounced autosave and switch flush consistency`
- Status: Implemented

## Goal

Implement non-blocking save behavior with deterministic consistency during note switching.

## Locked Product Decisions

1. Save strategy is `1.5s` debounced auto-save.
2. Switching notes forces pending save flush.
3. No unsaved-changes modal in switch path.

## Scope (v0.1)

In scope:

- debounced `note_update` write path
- dirty/saving/error state signals
- forced flush before note selection switch commits
- stale async write-back guard

Out of scope:

- offline queue / long-term sync semantics
- collaborative editing conflict resolution

## Confirmed Decisions

1. Switch guard is blocking: flush failure must stop note switch.
2. Autosave boundary:
   - note body: `1.5s` debounce
   - tags/metadata: immediate save path (to be wired in C4/metadata surfaces)
3. Save status location is editor top-right status widget.
4. Desktop lifecycle must run best-effort flush on close (C3.3).
5. Retry always saves latest in-memory draft.

## Stage Progress

### C3.1 Landed

1. Added `NoteSaveState` state machine (`clean/dirty/saving/error`) in `NotesController`.
2. Added debounced autosave pipeline (`note_update`) with configurable debounce duration (default `1.5s`).
3. Added save status widget in content top-right:
   - dirty: unsaved indicator
   - saving: spinner
   - clean(success): temporary saved badge
   - error: red failure status
4. Added C3.1 widget tests for transition and failure paths.

### C3.2 Landed

1. Added blocking switch guard in note selection path:
   - `selectNote` now calls `flushPendingSave()` before switching away.
   - flush failure returns `false` and stops selection transition.
2. Added explicit blocking failure banner above editor body:
   - message: `Save failed. Retry or back up content.`
3. Added C3.2 widget tests:
   - flush failure blocks switch and keeps active note unchanged
   - flush success allows switching to target note

### C3.3 Landed

1. Added save retry path:
   - UI retry button in save-error state.
   - Retry always persists latest in-memory draft.
2. Added desktop lifecycle best-effort flush:
   - flush triggered on app lifecycle `inactive/paused/detached`.
3. Added desktop close guard via `window_manager`.
4. Hardened save concurrency:
   - removed infinite retry loop risk on failed autosave.
   - in-flight + queued follow-up save behavior prevents stale callback overwrite.
5. Added C3.3 tests:
   - retry saves latest draft
   - stale save completion cannot overwrite newer draft
   - paused lifecycle triggers best-effort flush

### C3.3 Post-Landing Fixes (Bugfix Sync)

1. Fixed slow desktop close experience.
   - Symptom: closing app felt slow even when there was no unsaved draft.
   - Root cause: close interception was always enabled (`setPreventClose(true)`), so every close went through async intercept + forced destroy path.
   - Solution:
     - switch to dynamic interception: only enable `preventClose` when `hasPendingSaveWork == true`
     - add fast close path for clean state (`setPreventClose(false)` then `windowManager.close()`, fallback `destroy()`)
     - shorten close flush timeout from `900ms` to `450ms` for best-effort behavior
2. Fixed save-error UI overlap in top-right action row.
   - Symptom: full backend error text (for example `[db_error] ...`) pushed or covered `refresh/share/star/more`.
   - Root cause: status widget rendered full error payload inline in the top-right compact action region.
   - Solution:
     - top-right status now renders stable short label `Save failed` only
     - full backend message is shown in dedicated red error banner above editor body
     - status icon keeps tooltip with full message for hover diagnostics
3. Fixed corrupted switch-block error copy.
   - Symptom: non-UTF8 garbled text displayed in switch-block failure banner.
   - Solution: replaced with clear English text `Save failed. Retry or back up content.`
4. Fixed autosave retry storm risk.
   - Symptom: persistent save failures could spawn repeated retries.
   - Root cause: queue drain condition retried on dirty state rather than true queued intent.
   - Solution: queue follow-up save only when explicit queued signal exists.
5. Fixed tab-close data loss gaps.
   - Symptom: closing active last tab or tab-pruning actions could bypass flush and drop unsaved draft.
   - Root cause: `closeOpenNote` / `closeOtherOpenNotes` / `closeOpenNotesToRight` changed tab state directly without enforcing flush guard.
   - Solution:
     - all three close helpers now return `bool` and enforce flush-before-close semantics when active dirty draft is involved
     - close operation is blocked on flush failure, preserving current tab/draft state
6. Fixed window-close pending-save blind spot.
   - Symptom: close interception only checked active note, so non-active pending work could be missed.
   - Root cause: `hasPendingSaveWork` only evaluated active note dirty/in-flight status.
   - Solution: `hasPendingSaveWork` now scans active note plus all open tabs for dirty/in-flight saves.
7. Fixed top action bar clipping and interaction inconsistency in narrow windows.
   - Symptom: right-side action cluster could clip in narrow width; long/short UI "..." behavior diverged.
   - Root cause: fixed action set in compact space and mixed interaction models.
   - Solution:
     - narrow width collapses secondary actions into one overflow menu
     - wide width keeps direct `Share` and `Star`, and uses matching dropdown-based `...` action for consistency
     - save error detail remains in banner; top status stays compact to protect action layout

## Incident Notes

1. During C3 test iteration there was local machine slowdown with many lingering test workers.
2. Stabilization actions:
   - removed infinite retry trigger in save queue logic
   - reran targeted and full Flutter test suites to confirm no hanging test processes remain
3. Current result:
   - no `flutter_test` or `flutter_tester` lingering processes after test completion
   - close behavior is fast when no pending save exists

## Step-by-Step

1. Add debounce timer path for editor text mutations (`1.5s`).
2. Add explicit persistence states in controller:
   - clean
   - dirty
   - saving
   - save_error
3. Implement `flushPendingSave()` and call it in note-switch workflow.
4. Add request-id or equivalent ordering guard to drop stale save completion callbacks.
5. Add recovery path for save failure with retry.

## Planned File Changes

- [edit] `apps/lazynote_flutter/lib/features/notes/notes_controller.dart`
- [edit] `apps/lazynote_flutter/lib/features/notes/notes_page.dart`
- [edit] `apps/lazynote_flutter/lib/features/notes/note_editor.dart`
- [add] `apps/lazynote_flutter/test/notes_page_c3_test.dart`

## Verification

- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test test/notes_page_c1_test.dart`
- `cd apps/lazynote_flutter && flutter test test/notes_page_c2_test.dart`
- `cd apps/lazynote_flutter && flutter test test/notes_page_c3_test.dart`
- `cd apps/lazynote_flutter && flutter test test/notes_controller_tabs_test.dart`
- `cd apps/lazynote_flutter && flutter test`

## Manual Verification (Windows)

1. Clean-close path:
   - open notes page
   - make no edits (or wait until saved)
   - click window close
   - expected: window closes immediately without dialog lag
2. Dirty-close path (save succeeds):
   - type in editor and close quickly
   - expected: best-effort flush runs, then window closes
3. Dirty-close path (save fails):
   - simulate DB write failure
   - click close
   - expected: unsaved-content dialog appears with `Keep editing` / `Retry save`
4. Save error rendering:
   - trigger save failure
   - expected:
     - top-right keeps short `Save failed` status and buttons remain visible
     - full error text appears in red banner above editor body
5. Switch guard:
   - edit note A
   - force save failure
   - click note B
   - expected: switch blocked, stay on note A, banner shows save failure guidance
6. Tab close guard:
   - edit active note and click tab close `x`
   - expected:
     - save success: close proceeds
     - save failure: close blocked, tab and draft remain
7. Close Others / Close Right guard:
   - make active note dirty, then trigger tab context close actions
   - expected:
     - actions that would prune active tab must flush first
     - flush failure blocks action and preserves tab set
8. Responsive top actions:
   - resize window from wide to narrow
   - expected:
     - narrow: compact overflow menu appears
     - wide: direct `Share`/`Star` + dropdown `...` remains visible
     - no right-side clipping/half-hidden button

## Acceptance Criteria

- [x] Typing pauses trigger one debounced save after `1.5s`.
- [x] Switching note flushes pending save before switching selected note.
- [x] Save failure does not lose in-memory edits and provides retry path.
- [x] Stale save completion cannot overwrite newer editor state.
- [x] Close path is fast when no pending save work exists.
- [x] Save-error UI does not overlap top-right action buttons.
- [x] Tab close actions respect flush guard and block on flush failure.
- [x] Window close interception covers pending save work across all open tabs.
- [x] Top action bar remains usable in narrow and wide layouts without clipping.
