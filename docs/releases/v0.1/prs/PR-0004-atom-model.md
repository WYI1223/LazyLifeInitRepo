# PR-0004-atom-model

- Proposed title: `core(model): define Atom model + IDs + soft delete`
- Status: Completed

## Goal
Implement the unified Atom domain model.

## Deliverables
- Atom fields in Rust domain model
- serialization/deserialization baseline
- reserved fields for later CRDT support

## Planned File Changes
- [add] `crates/lazynote_core/src/model/mod.rs`
- [add] `crates/lazynote_core/src/model/atom.rs`
- [edit] `crates/lazynote_core/src/lib.rs`
- [add] `crates/lazynote_core/tests/atom_model.rs`

## Dependencies
- PR0003

## Acceptance Criteria
- [x] Scope implemented
- [x] Basic verification/tests added
- [x] Documentation updated if behavior changes

## Notes
- Added `Atom`, `AtomType`, `TaskStatus`, and `AtomId` in `lazynote_core`.
- Added soft-delete helpers (`soft_delete`, `restore`, `is_active`).
- Added validation baseline (`validate`) for nil UUID and event time window invariants.
- Added serialization baseline via `serde` and integration test coverage in `tests/atom_model.rs`, including invalid deserialization rejection.
- Reserved `hlc_timestamp` field for later CRDT/HLC work.
- Verification:
  - `cd crates && cargo fmt --all -- --check`
  - `cd crates && cargo clippy --all -- -D warnings`
  - `cd crates && cargo test --all`
