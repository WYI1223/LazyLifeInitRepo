# PR-0009A-entry-ffi-surface

- Proposed title: `feat(ffi): add entry use-case surface for search and command actions`
- Status: Draft

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

- [ ] API contract is documented and stable.
- [ ] Core logic and tests pass.
- [ ] No storage internals leaked via FFI.
