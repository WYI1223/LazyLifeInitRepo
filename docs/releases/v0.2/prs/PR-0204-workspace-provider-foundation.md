# PR-0204-workspace-provider-foundation

- Proposed title: `feat(notes-ui): workspace provider and state hoisting foundation`
- Status: In Progress (M1+M2 landed; UI wiring pending)

## Goal

Introduce a centralized workspace runtime state so notes/tabs/panes share one source of truth.

## Scope (v0.2)

In scope:

- `WorkspaceProvider` as top-level runtime owner
- active pane state (`activePaneId`)
- opened tabs per pane
- shared note buffer registry
- save coordinator hooks (debounce + flush)

Out of scope:

- recursive split layout tree (v0.3)
- drag-to-split interactions (v0.3)

## State Model Baseline

Required state slices:

1. `layoutState` (single pane initially, split-ready shape)
2. `activePaneId`
3. `openTabsByPane`
4. `buffersByNoteId`
5. `saveStateByNoteId` (`clean | dirty | saving | save_error`)

Design rule:

- visual widgets consume provider selectors
- editor components remain layout-agnostic and reusable

## Design Constraints from Engineering Review

The following bugs found in v0.1 `NotesController` (review-02 §1.1–1.3) must be
addressed by design in `WorkspaceProvider`, not patched onto the old controller:

**R02-1.1 — Draft buffer coherence on pane/tab switch**

`activeDraftContent` in v0.1 uses a three-branch fallback that can return stale server
content after a tab switch (local draft map is correct, but the active-id pointer lags in
some `_loadNotes` paths).  In the new design, `buffersByNoteId` must be the single
authoritative source for draft reads.  When active pane or tab changes, derive content
directly from `buffersByNoteId[activeNoteId]` — no secondary "active content" field.

**R02-1.2 — Save flush must have a bounded retry limit**

The v0.1 `flushPendingSave` uses an unbounded `while (true)` loop.  If the FFI save fails
AND the user keeps typing (version counter increments), the loop never exits, blocking tab
close indefinitely.  The new save coordinator must cap flush retries (suggested: 5) and
transition to `save_error` state after exhausting retries.

**R02-1.3 — Tag mutations must not fire after tab close**

The v0.1 Promise-chain tag mutation queue does not guard against the target note being
closed mid-flight.  The new `WorkspaceProvider` tag dispatch must check that the note is
still present in `openTabsByPane` before issuing the FFI call.

## Step-by-Step

1. Add provider and models in `features/workspace/`.
2. Migrate existing `notes_controller` responsibilities into provider-managed state.
3. Keep current Notes UI behavior intact while swapping state ownership.
4. Add tests for buffer/saving state coherence across tab activation.

## Execution Plan (M1-M3)

### M1. Provider Skeleton + Guardrail Tests

1. Add `workspace_models.dart` and `workspace_provider.dart` with:
- `layoutState`
- `activePaneId`
- `openTabsByPane`
- `buffersByNoteId`
- `saveStateByNoteId`
2. Land save coordinator hook with bounded flush retries (`<= 5`).
3. Land tag mutation queue guard: note must still be open before dispatch.
4. Add `workspace_provider_test.dart` for R02-1.1/1.2/1.3.

Status:
- M1 model/provider skeleton: completed
- M1 guardrail tests: completed

### M2. NotesController Bridge

1. Introduce adapter layer from `NotesController` to `WorkspaceProvider`.
2. Preserve existing Notes behavior while moving ownership to provider.
3. Add bridge-focused tests for tab/draft/save consistency.

Status:
- M2 controller bridge: completed
- M2 bridge tests: completed

### M3. UI Wiring Baseline

1. Wire `notes_page`/`entry_shell_page` to provider selectors.
2. Keep split/explorer visual behavior unchanged (no recursive split in v0.2).
3. Run full regression suite before PR-0205 handoff.

## Planned File Changes

- [add] `apps/lazynote_flutter/lib/features/workspace/workspace_provider.dart`
- [add] `apps/lazynote_flutter/lib/features/workspace/workspace_models.dart`
- [edit] `apps/lazynote_flutter/lib/features/notes/notes_controller.dart`
- [edit] `apps/lazynote_flutter/lib/features/notes/notes_page.dart`
- [edit] `apps/lazynote_flutter/lib/features/entry/entry_shell_page.dart`
- [add] `apps/lazynote_flutter/test/workspace_provider_test.dart`
- [add] `apps/lazynote_flutter/test/notes_controller_workspace_bridge_test.dart`

## Verification

- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test test/workspace_provider_test.dart`
- `cd apps/lazynote_flutter && flutter test test/notes_controller_workspace_bridge_test.dart`
- `cd apps/lazynote_flutter && flutter test`

## Acceptance Criteria

- [ ] Notes buffers are provider-owned and reusable by future pane layouts.
- [x] Active pane and tab state are explicit and test-covered.
- [x] Existing v0.1 note flows still pass.
- [x] NotesController bridge keeps tab/draft/save snapshots synchronized with
      `WorkspaceProvider` in regression tests.
- [x] (R02-1.1) Active draft content is always derived from `buffersByNoteId`; no stale
      content appears after tab/pane switch in widget tests.
- [x] (R02-1.2) Save flush coordinator has a bounded retry count (≤ 5) and transitions to
      `save_error` on exhaustion; test covers the save-failure + in-progress-typing case.
- [x] (R02-1.3) Tag mutation dispatch checks note presence in open tabs before FFI call;
      test covers close-then-tag-queue scenario.
