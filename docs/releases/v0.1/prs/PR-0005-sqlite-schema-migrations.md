# PR-0005-sqlite-schema-migrations

- Proposed title: `core(db): sqlite schema + migrations + open_db()`
- Status: Completed

## Goal
Make SQLite the canonical local storage with migrations.

## Deliverables
- atoms/tags/atom_tags/external_mappings
- migration versioning
- open_db() bootstrap

## Planned File Changes
- [add] `crates/lazynote_core/src/db/mod.rs`
- [add] `crates/lazynote_core/src/db/open.rs`
- [add] `crates/lazynote_core/src/db/migrations/mod.rs`
- [add] `crates/lazynote_core/src/db/migrations/0001_init.sql`
- [add] `crates/lazynote_core/src/db/migrations/0002_tags.sql`
- [add] `crates/lazynote_core/src/db/migrations/0003_external_mappings.sql`
- [edit] `crates/lazynote_core/Cargo.toml`
- [add] `crates/lazynote_core/tests/db_migrations.rs`

## Dependencies
- PR0004

## Acceptance Criteria
- [x] Scope implemented
- [x] Basic verification/tests added
- [x] Documentation updated if behavior changes

## Notes
- Added SQLite bootstrap module with `open_db()` and `open_db_in_memory()`.
- Added migration registry driven by `PRAGMA user_version`.
- Added migration registry guards to enforce strictly increasing/unique versions.
- Added v0.1 baseline migrations:
  - `0001_init.sql` for `atoms`
  - `0002_tags.sql` for `tags` + `atom_tags`
  - `0003_external_mappings.sql` for external provider mapping
- Removed `CREATE TABLE IF NOT EXISTS` from core migrations to fail fast on schema drift.
- Added migration tests for:
  - first open applies all migrations
  - opening same DB twice is idempotent
  - opening DB newer than supported schema returns explicit error
  - schema drift does not silently advance `user_version`
  - key constraints (`CHECK` / `FOREIGN KEY CASCADE` / `UNIQUE`) are enforced
- Verification:
  - `cd crates && cargo fmt --all -- --check`
  - `cd crates && cargo clippy --all -- -D warnings`
  - `cd crates && cargo test --all`
