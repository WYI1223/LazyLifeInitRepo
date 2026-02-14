# PR-0010D-notes-tags-hardening

- Proposed title: `chore(notes): hardening, regression tests, docs closure`
- Status: In Progress

## Goal

Close PR-0010 with reliability hardening, regression protection, and doc closure.

## Scope (v0.1)

In scope:

- error-path polish for notes/tags operations
- consistency checks for list/editor/filter state transitions
- regression tests (core + ffi + flutter critical paths)
- release/docs/governance synchronization

Out of scope:

- performance optimization beyond baseline stability
- new feature expansion beyond PR-0010B/C scope

## Hardening Focus

1. Prevent stale async response from overwriting newer UI state.
2. Prevent duplicate submit/create due to rapid repeated actions.
3. Ensure UI can recover from backend errors without app restart.
4. Validate contract/doc alignment for any API shape change.

## Residual Risks (Non-blocking)

1. Contextual create under active tag filter is still a two-step call:
   - step 1: `note_create`
   - step 2: `note_set_tags`
   If step 1 succeeds but step 2 fails, backend already contains the new note.
   Current v0.1 behavior keeps the create success path and shows a warning
   (`SnackBar`): note is visible in unfiltered list but not in current filtered
   list when tag apply fails.

## Explicit v0.1 Non-goal Addendum

- Note delete flow is not implemented in PR-0010 scope.
  - no delete action in Explorer/Tab/UI
  - no dedicated delete contract path in current Notes UI flow

## Step-by-Step

1. Review known risk points from 0010B/0010C implementation.
2. Add/adjust guards for:
   - overlapping requests
   - stale response application
   - duplicate actions
3. Add regression tests for:
   - stale response ordering
   - retry after failure
   - filter + edit interaction stability
4. Update docs:
   - `docs/releases/v0.1/prs/PR-0010-notes-tags.md`
   - `docs/releases/v0.1/README.md`
   - `docs/api/*` and `docs/governance/API_COMPATIBILITY.md` (if contract changed)
5. Run full quality gates and mark PR-0010 complete.

## Landed in D1-D2

1. Tag mutation ordering hardening:
   - serialized per-note tag writes in controller queue
   - guarded manual reload paths (`loadNotes` / `retryLoad`) to await pending tag writes
2. Filter safety hardening:
   - auto-clear stale selected filter when selected tag disappears from available tags
3. Contextual create failure UX hardening:
   - non-transactional create+tag behavior explicitly surfaced as warning instead of silent mismatch
4. Regression tests added:
   - orphan note recovery visibility after clearing filter
   - manual reload vs tag-write queue concurrency
   - retry reload vs tag-write queue concurrency

## Planned File Changes

- [edit] notes/tags controller and UI files from PR-0010C
- [edit] Rust/FFI contracts/tests from PR-0010B if needed
- [edit] release/api/governance docs for closure
- [add/edit] regression tests under Flutter and Rust test suites

## Dependencies

- PR-0010B
- PR-0010C

## Quality Gates

- `cargo fmt --all -- --check`
- `cargo clippy --all -- -D warnings`
- `cargo test --all`
- `flutter analyze`
- `flutter test`

## Acceptance Criteria

- [ ] No known high/medium note/tag flow regressions remain open.
- [ ] Regression tests cover key async/order/error cases.
- [ ] Docs and API compatibility records are synchronized.
- [ ] PR-0010 umbrella is updated to completed state.
