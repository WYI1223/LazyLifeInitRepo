# PR-0205B-explorer-tab-open-intent-migration

- Proposed title: `refactor(notes-tab): move preview/pinned semantics ownership from explorer to tab model`
- Status: Planned

## Goal

Make preview/pinned semantics a tab-model concern and keep explorer behavior as
pure open-intent emission.

## Background

- `PR-0205` established recursive lazy explorer and open intent callbacks.
- VSCode-like single/double-click semantics should be owned by top tab model
  (single click activate, double click pin/solidify), not hardcoded in explorer.
- `PR-0304` defines long-term preview/pinned model ownership; this PR provides
  a v0.2 transition path to avoid behavior drift.

## Scope (v0.2 transition)

In scope:

- explorer emits one open intent (`open(noteId)`) without semantic branching.
- tab strip / tab state model accepts interaction semantics ownership.
- document ownership boundary: explorer = intent source, tab model = semantic
  decision.
- regression tests for single/double behavior at tab layer.

Out of scope:

- introducing new Rust FFI APIs.
- cross-pane preview/pinned persistence policy expansion (full lane in `PR-0304`).

## Dependency and Start Gate

- Upstream baseline required:
  - `PR-0205` explorer recursive/lazy behavior stable (completed)
  - `PR-0205A` shell alignment completed
- Downstream relation:
  - `PR-0206` should start after `PR-0205B` reaches API/interaction freeze.
- Start gate for execution:
  - all existing notes page tests pass on `main`
  - no open blocker on explorer create/delete stability

## Design Rules

1. Explorer responsibilities:
   - emit one open intent only (`open(noteId)`)
   - no preview/pinned semantic branching
2. Tab model responsibilities:
   - owns preview lifecycle and pinned promotion rules
   - resolves single/double interactions deterministically
3. NotesController responsibilities:
   - expose stable commands consumed by tab model
   - avoid embedding source-specific semantic branching

## Milestones (M1-M4)

### M1. Contract freeze (intent boundary)

Deliverables:

- freeze explorer callback contract as single open intent
- update docs/contracts to remove ambiguity

Exit criteria:

- docs explicitly state explorer != semantic owner
- no runtime dependency on explorer double-click path

### M2. Tab model behavior landing

Deliverables:

- implement tab-level single/double interaction policy
- wire tab manager to explicit preview->pinned transitions

Exit criteria:

- deterministic behavior in unit/widget tests
- no regression in `notes_page_c1..c4`

### M3. Controller clean-up and compatibility shim

Deliverables:

- keep compatibility shim for legacy callers if needed
- remove dead or redundant explorer-side semantic branches

Exit criteria:

- analyze/test pass with no new warnings
- internal API surface remains minimal

### M4. Docs and closure

Deliverables:

- sync `PR-0205`, `PR-0304`, `ffi-contracts.md`, `v0.2 README`
- record `PR-0206` start condition satisfied

Exit criteria:

- no doc/contract drift in review

## Contract Impact

- FFI/API shape delta: none.
- UI contract delta:
  - `PR-0205` no longer claims explorer-level double-click semantics as shipped
    behavior.
  - ownership moved to tab model lane (`PR-0304`).

## Planned File Changes

- [edit] `apps/lazynote_flutter/lib/features/notes/notes_page.dart`
- [edit] `apps/lazynote_flutter/lib/features/notes/note_tab_manager.dart`
- [edit] `apps/lazynote_flutter/lib/features/notes/notes_controller.dart`
- [edit] `docs/releases/v0.2/prs/PR-0205-explorer-recursive-lazy-ui.md`
- [edit] `docs/releases/v0.3/prs/PR-0304-tab-preview-pinned-model.md`
- [edit] `docs/api/ffi-contracts.md`
- [add] `apps/lazynote_flutter/test/tab_open_intent_migration_test.dart` (if existing tab tests are insufficient)

## Verification

- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test test/notes_controller_tabs_test.dart`
- `cd apps/lazynote_flutter && flutter test test/note_explorer_tree_test.dart`
- `cd apps/lazynote_flutter && flutter test test/notes_page_c1_test.dart test/notes_page_c2_test.dart test/notes_page_c3_test.dart test/notes_page_c4_test.dart`

## Acceptance Criteria

- [ ] Explorer no longer carries runtime semantic ownership for preview/pinned.
- [ ] Top tab model owns single/double click semantic decisions.
- [ ] Contract docs explicitly reflect ownership boundary and no longer drift.
- [ ] `PR-0206` can start without reopening explorer/tab semantic boundary decisions.
