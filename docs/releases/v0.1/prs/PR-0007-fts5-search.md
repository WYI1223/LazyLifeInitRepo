# PR-0007-fts5-search

- Proposed title: `core(search): FTS5 full-text index + search_all()`
- Status: Completed

## Goal
Deliver type-to-results full-text search.

## Deliverables
- FTS5 index table
- trigger-based index update strategy
- search(query) summary output

## Planned File Changes
- [add] `crates/lazynote_core/src/search/mod.rs`
- [add] `crates/lazynote_core/src/search/fts.rs`
- [add] `crates/lazynote_core/src/db/migrations/0004_fts.sql`
- [edit] `crates/lazynote_core/src/db/migrations/mod.rs`
- [edit] `crates/lazynote_core/src/lib.rs`
- [add] `crates/lazynote_core/tests/search_fts.rs`

## Dependencies
- PR0005, PR0006

## Acceptance Criteria
- [x] Scope implemented
- [x] Basic verification/tests added
- [x] Documentation updated if behavior changes

## Notes
- Chosen index strategy: SQLite trigger-driven sync between `atoms` and `atoms_fts`.
- Added migration `0004_fts.sql`:
  - FTS5 virtual table `atoms_fts`
  - bootstrap import from existing non-deleted atoms
  - insert/update/delete triggers
- Added search module with:
  - `SearchQuery`
  - `SearchHit`
  - `search_all(conn, query)`
- `search_all` behavior:
  - blank query returns empty result
  - `limit = 0` returns empty result (explicit contract)
  - excludes soft-deleted atoms
  - supports optional `AtomType` filter and limit
  - default mode escapes user input terms for robust type-as-you-search behavior
  - optional `raw_fts_syntax = true` allows direct FTS expressions and maps syntax failures to `InvalidQuery`
- Added integration tests for:
  - create -> searchable
  - update -> index refreshed
  - soft delete -> excluded
  - type filter
  - limit handling
  - raw syntax error mapping
  - migration upgrade bootstrap from v3 -> v4 keeps old data searchable
- Kept PR core-only; FFI exposure can follow once search API contract stabilizes.
- Verification:
  - `cd crates && cargo fmt --all -- --check`
  - `cd crates && cargo clippy --all -- -D warnings`
  - `cd crates && cargo test --all`
