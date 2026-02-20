# PR-0206-split-layout-v1

- Proposed title: `feat(workspace-ui): limited split layout v1 with min-size guard`
- Status: In Review (post-review remediation landed)

## Goal

Introduce pane splitting baseline while keeping implementation risk controlled.

## Scope (v0.2)

In scope:

- horizontal/vertical split commands
- limited pane count (for example up to 4 panes)
- active pane focus and tab routing
- strict min-size guard (`200px`) for pane geometry safety

Out of scope:

- fully recursive split tree
- drag tab to edge split zones

## Milestones (M1-M4)

### M1. Workspace split model and provider guardrails

Deliverables:

- add split direction/result contracts in workspace model
- add split state (`paneFractions`) for non-recursive root layout
- add provider split command with deterministic rejection codes:
  - max pane count
  - direction lock (no mixed orientation in v0.2 root model)
  - min-size guard (`200px`)
- add provider regression tests

Exit criteria:

- `workspace_provider_test.dart` covers split success + guardrails
- `flutter analyze` and provider tests pass

M1 implementation note:

- `WorkspaceLayoutState` now carries `splitDirection` + `paneFractions`.
- `WorkspaceProvider.splitActivePane(...)` is landed with guardrails and stable
  `WorkspaceSplitResult`.
- active pane routing keeps note-open behavior deterministic after split.

### M2. Notes shell split commands and feedback

Deliverables:

- expose split commands in Notes UI (horizontal/vertical)
- wire command results to user-visible feedback (blocked/rejected reasons)
- keep active pane indication explicit

M2 implementation note:

- `NotesPage` header now provides explicit split command buttons
  (horizontal/vertical).
- split command results are mapped to visible SnackBar feedback for:
  - success
  - min-size blocked
  - direction locked
  - max pane reached
  - pane missing
- active pane indicator is rendered in header (`Pane X/Y`).
- widget regressions added in `test/workspace_split_v1_test.dart`.

### M3. Active-pane tab/editor routing

Deliverables:

- route open/activate actions to active pane consistently
- validate tab strip/editor target updates under split interactions

M3 implementation note:

- `NotesController` now exposes pane commands (`splitActivePane`,
  `switchActivePane`, `activateNextPane`) and adopts active pane state for
  editor routing.
- controller/workspace bridge preserves pane-local tab topology during sync
  instead of collapsing all tabs into one pane.
- split mode tab projection is active-pane scoped (no fallback to global tab
  union for empty pane).
- Notes header provides explicit next-pane focus command.
- regressions added for pane-local tab routing and next-pane switch behavior:
  - `test/notes_controller_workspace_bridge_test.dart`
  - `test/workspace_split_v1_test.dart`

### M4. Hardening and closure

Deliverables:

- expand widget tests for split command UX
- sync release docs and acceptance checklists

M4 implementation note:

- added split UX hardening regression for single-pane next-pane no-op feedback.
- reran split/provider/controller/widget regression suite after M3 bridge
  adjustments.
- synced contracts and release docs:
  - `docs/api/ffi-contracts.md`
  - `docs/api/error-codes.md`
  - `docs/releases/v0.2/README.md`
  - this PR document (`PR-0206`)

## Post-Review Remediation Plan (R1-R3)

The first M1-M4 baseline is landed. A focused post-review remediation pass is
required before final closure.

### R1. Prevent split-mode active-state divergence on detail failure (High)

Problem:

- `selectNote` can temporarily diverge `NotesController` selected note and
  `WorkspaceProvider` active note in split mode when detail loading fails.

Fix plan:

- enforce active-pane note alignment at select stage (before async detail
  result), not only after detail success.
- keep failure handling non-destructive: detail failure should not roll back
  active pane selection or create controller/workspace fork.
- keep existing error surfacing (`loadError`/snackbar path) intact.

Regression tests:

- add split-mode test where target note selection triggers detail failure.
- assert controller selected note and workspace active note remain consistent.

### R2. Route `Ctrl+Tab` by active pane tab strip semantics (Medium)

Problem:

- split UI renders active-pane tabs, but `Ctrl+Tab` still cycles global open
  notes, causing cross-pane jumps.

Fix plan:

- add pane-local next/previous tab navigation methods in `NotesController`.
- wire `NotesPage` keyboard shortcut handlers to pane-local methods.
- keep global behavior only for non-split/single-pane fallback.

Regression tests:

- add split test with two panes and disjoint tab sets.
- assert `Ctrl+Tab`/`Ctrl+Shift+Tab` only cycles inside active pane tabs.

### R3. Harden `WorkspaceLayoutState` immutability contract (Low)

Problem:

- `@immutable` state currently stores mutable `List` references that may be
  modified externally.

Fix plan:

- apply defensive copy + unmodifiable wrapping for list fields in constructor
  and `copyWith`.
- ensure provider snapshots are never mutated from outside.

Regression tests:

- add model/provider test to verify input list mutation does not affect stored
  layout state.

### R1-R3 Exit Criteria

- [x] R1 behavior landed + regression test added.
- [x] R2 behavior landed + keyboard routing regression test added.
- [x] R3 immutability hardening landed + regression test added.
- [x] `flutter analyze` and split-related tests pass.
- [x] PR docs and release plan are re-synced to final status.

## Layout Constraints

1. Any pane width/height must remain `>= 200px`.
2. Split command is rejected when constraint would be violated.
3. Rejection must provide visible feedback to user.

## Step-by-Step

1. Add split-capable layout model in workspace state.
2. Add split actions (menu/button/shortcut).
3. Add min-size validation before applying split.
4. Ensure notes open in active pane only.
5. Add widget tests for split success/failure and active-pane behavior.

## Planned File Changes

- [edit] `apps/lazynote_flutter/lib/features/workspace/workspace_models.dart`
- [edit] `apps/lazynote_flutter/lib/features/workspace/workspace_provider.dart`
- [edit] `apps/lazynote_flutter/test/workspace_provider_test.dart`
- [edit] `apps/lazynote_flutter/lib/features/notes/notes_controller.dart`
- [edit] `apps/lazynote_flutter/lib/features/notes/notes_page.dart`
- [add] `apps/lazynote_flutter/test/workspace_split_v1_test.dart`
- [edit] `apps/lazynote_flutter/test/notes_controller_workspace_bridge_test.dart`
- [edit] `docs/api/ffi-contracts.md`
- [edit] `docs/api/error-codes.md`
- [edit] `docs/releases/v0.2/README.md`

## Verification

- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test test/workspace_provider_test.dart`
- `cd apps/lazynote_flutter && flutter test test/workspace_split_v1_test.dart`
- `cd apps/lazynote_flutter && flutter test`

## QA Summary (2026-02-20)

Execution result:

- split command paths, pane focus switching, and pane-local tab routing
  passed QA.
- keyboard routing (`Ctrl+Tab`, `Ctrl+Shift+Tab`) passed pane-local behavior
  verification.
- R1/R2/R3 post-review regressions are covered and passing.

Observed limitations (accepted for v0.2 split baseline):

- on narrower window widths, additional split attempts are rejected by the
  `200px` min-size guard after the first split.
- split-pane remove/merge (unsplit) action is not implemented in `PR-0206`.

Conclusion:

- QA passed with accepted limitations.
- limitations are non-blocking for `PR-0206` scope and should be tracked as
  follow-up UX enhancements (e.g. explicit unsplit/merge command).

## Acceptance Criteria

- [x] M1 model/provider guardrails are landed and regression-covered.
- [x] M2 split command entry and rejection feedback are landed and regression-covered.
- [x] Users can split panes via explicit commands.
- [x] Active pane is clearly represented and used for open actions.
- [x] Min-size guard blocks invalid splits with UI feedback.
- [x] M4 hardening and closure are completed with synced docs/contracts.
