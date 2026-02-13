# PR-0009A-entry-ffi-surface

- Proposed title: `feat(ffi): add entry use-case surface for search and command actions`
- Status: Completed

## Goal

Provide a stable FFI use-case surface required by the single-entry router.

## Scope

In scope:

- Add entry-oriented FFI APIs (use-case level, no SQL internals).
- Define request/response contracts for search and command actions.
- Wire core calls to existing model/repo/service/search layers.

Out of scope:

- Flutter parser and UI rendering.
- Final command UX behavior.

## API Contract (v0.1 baseline)

1. `entry_search(text, limit)`:
   - default `limit = 10`
   - routes to core `search_all`
2. `entry_create_note(content)`
3. `entry_create_task(content)`:
   - sets `task_status = todo`
4. `entry_schedule(title, start_epoch_ms, end_epoch_ms?)`:
   - `end_epoch_ms = null` means point schedule
   - non-null means range schedule

All FFI exports must include `FFI contract` rustdoc sections.

## Planned File Changes

- [edit] `crates/lazynote_ffi/src/api.rs`
- [edit] `crates/lazynote_ffi/src/lib.rs`
- [edit] `crates/lazynote_core/src/lib.rs` (if new re-exports are needed)
- [add/edit] core service/repo files as needed for entry actions
- [add] Rust tests for FFI/core entry APIs

## Step-by-Step

1. Define DTOs and error mapping strategy for entry APIs.
2. Implement FFI wrappers at use-case level.
3. Enforce `limit <= 10` default behavior for entry search path.
4. Implement task default status as `todo`.
5. Implement schedule point/range semantics.
6. Add unit/integration tests.
7. Run quality gates.

## Verification

- `cd crates && cargo fmt --all -- --check`
- `cd crates && cargo clippy --all -- -D warnings`
- `cd crates && cargo test --all`

## Acceptance Criteria

- [x] API contract is documented and stable.
- [x] Core logic and tests pass.
- [x] No storage internals leaked via FFI.

## Progress Notes

Phase 1 (completed):

- Added core service entry helpers:
  - `create_note`
  - `create_task` (default `todo`)
  - `schedule_event` (point/range shape)
- Added FFI DTO envelopes and `entry_*` API signatures.
- Added phase-1 scaffold behavior for `entry_*` APIs with explicit not-ready messages.
- Added tests for limit normalization and scaffold response behavior.
- Passed first-round gates:
  - `cargo fmt --all -- --check`
  - `cargo clippy -p lazynote_core -p lazynote_ffi -- -D warnings`
  - `cargo test -p lazynote_core -p lazynote_ffi`

Phase 2 (completed):

- `entry_search` now executes real core `search_all` with default limit normalization.
- `entry_create_note`, `entry_create_task`, and `entry_schedule` now execute real core service operations.
- FFI now resolves a real SQLite path (`LAZYNOTE_DB_PATH` override, temp-file default) and opens migrated DB per call.
- Added tests for:
  - search hit retrieval after create
  - task default `todo` persistence
  - schedule point success
  - schedule reversed range rejection
- Regenerated FRB bindings and verified Flutter side checks/tests.
