# PR-0006-core-crud

- Proposed title: `core(repo): Atom CRUD + basic queries`
- Status: Completed

## Goal
Provide stable core CRUD operations.

## Planning Baseline (Confirmed)

- PR0005 is already merged and synced to `origin/main`.
- DB migration drift safeguards are already in place.
- Atom validation exists (`Atom::validate`) and must be enforced at write boundaries.

## Deliverables
- create/update/get/list/soft_delete
- repository interface and tests

## Scope

### In scope

- Core repository trait and SQLite-backed implementation for Atom CRUD.
- Service layer wrapping repository with use-case-friendly methods.
- Query filters for `type` and soft-delete visibility.
- Integration tests against real SQLite database.

### Out of scope (this PR)

- FFI API expansion for CRUD (defer to next PR after core contract stabilizes).
- FTS search and ranking (PR0007).
- UI wiring (PR0008+).

## Planned File Changes
- [add] `crates/lazynote_core/src/repo/mod.rs`
- [add] `crates/lazynote_core/src/repo/atom_repo.rs`
- [add] `crates/lazynote_core/src/service/mod.rs`
- [add] `crates/lazynote_core/src/service/atom_service.rs`
- [edit] `crates/lazynote_core/src/lib.rs`
- [add] `crates/lazynote_core/tests/atom_crud.rs`

## Dependencies
- PR0005

## API Contract (Proposed for this PR)

- `create_atom(atom)`:
  - validates atom (`atom.validate()`), inserts row, returns created atom id
- `update_atom(atom)`:
  - validates atom, updates mutable columns by id, refreshes `updated_at`
  - returns explicit not-found error when id does not exist
- `get_atom(id, include_deleted)`:
  - returns `Option<Atom>`
- `list_atoms(query)`:
  - supports `kind` filter + `include_deleted` + pagination (`limit/offset`)
  - default behavior excludes deleted records
- `soft_delete_atom(id)`:
  - sets `is_deleted = 1` when active
  - already-deleted record returns success without changing `updated_at`

## Error Model (Proposed)

- Repository error enum includes:
  - validation errors (`AtomValidationError`)
  - DB errors (`DbError`/`rusqlite`)
  - semantic errors (`NotFound`)
- Service layer should avoid leaking raw SQL strings to callers.

## Step-by-Step Execution Plan

1. Add repo module skeleton and core traits.
2. Add SQLite repo implementation using `rusqlite`.
3. Add service module as use-case entry points.
4. Wire modules through `lazynote_core/src/lib.rs`.
5. Add integration tests (`tests/atom_crud.rs`) for happy/negative paths.
6. Run quality gates and fix all warnings.
7. Update this PR doc status/checklist/notes.

## Test Matrix (Must Pass)

- Create + get roundtrip
- Update existing atom
- Update not-found returns `NotFound`
- List excludes deleted by default
- List includes deleted when requested
- Soft delete is idempotent
- Validation failure blocks create/update
- Query filters by `AtomType`
- Pagination path: `limit + offset`
- Pagination path: offset-only (`LIMIT -1 OFFSET`)

## Acceptance Criteria
- [x] Scope implemented
- [x] Basic verification/tests added
- [x] Documentation updated if behavior changes

## Notes
- Implemented `AtomRepository` + `SqliteAtomRepository` with:
  - `create_atom`
  - `update_atom`
  - `get_atom`
  - `list_atoms` (type filter + include deleted + pagination)
  - `soft_delete_atom`
- Added `AtomService` as use-case wrapper over repository.
- Enforced `Atom::validate()` on repository write paths.
- Repository construction now uses `try_new` guard to reject uninitialized/non-migrated connections.
- Repository constructor guard now validates required `atoms` schema columns to prevent forged `user_version` bypass.
- Kept PR core-only (no FFI CRUD exposure yet).
- Added integration tests in `tests/atom_crud.rs` for:
  - create/get roundtrip
  - update success + not-found
  - list default vs include-deleted behavior
  - soft delete idempotency
  - validation failure on create/update
  - type filter query
  - pagination branches (`limit + offset`, offset-only)
  - connection guard branches (`MissingRequiredTable`, `MissingRequiredColumn`)
  - service wrapper smoke flow
- Verification:
  - `cd crates && cargo fmt --all -- --check`
  - `cd crates && cargo clippy --all -- -D warnings`
  - `cd crates && cargo test --all`
