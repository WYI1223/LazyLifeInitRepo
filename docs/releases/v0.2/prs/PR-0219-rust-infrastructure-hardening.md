# PR-0219-rust-infrastructure-hardening

- Proposed title: `fix(core/ffi): Rust infrastructure hardening (safety, WAL, observability)`
- Status: Planned
- Source: review-01 issues 1–5, 7, 9, 10 + review-02 issues 4.1, 4.2

## Goal

Resolve all HIGH and MEDIUM findings from the architecture/engineering reviews before v0.2
feature work builds on top of the existing Rust infrastructure.  All changes are small,
targeted, and limited to Rust crates — no FFI surface additions, no `gen_bindings.ps1` run
needed.

## Rationale for a Pre-Feature PR

Two HIGH-risk findings were identified in review-01:

- **R01-2**: `resolve_entry_db_path` silently falls back to `%TEMP%` when the global Mutex
  is poisoned, causing invisible data loss (notes written to a different DB file).
- **R01-4/R01-1**: SQLite runs in default DELETE journal mode.  Every autosave write holds
  an exclusive file lock; any concurrent read (search) blocks up to 5 s.

These must be addressed before any v0.2 workspace or tree feature lands on top of them.
The remaining items (R01-3, 5, 7, 9, 10, R02-4.1, R02-4.2) are low-disruption and are
batched here to keep the changeset coherent.

## Scope

### Safety (HIGH)

**R01-2 — Mutex poison log** (`crates/lazynote_ffi/src/api.rs:572–579`)

`resolve_entry_db_path` currently silently falls through to `temp_dir()` when
`ENTRY_DB_PATH_OVERRIDE.lock()` returns `Err(Poisoned)`.  Minimum fix: emit an
`error!` log before continuing so the fallback is visible in diagnostics.

```rust
Err(_) => {
    error!("event=db_path_resolve module=ffi status=error error_code=mutex_poisoned");
}
```

**R01-4 — WAL mode** (`crates/lazynote_core/src/db/open.rs:102–107`)

Add `PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;` to `bootstrap_connection`.
WAL allows concurrent readers and writers, eliminating read/write contention during
autosave.  `synchronous=NORMAL` is safe in WAL mode (only OS-level crashes can lose the
last commit, acceptable for a local notes app).

### API / Contract Consistency (MEDIUM)

**R01-3 — ENTRY_LIMIT_MAX constant** (`crates/lazynote_ffi/src/api.rs:24–25`)

`ENTRY_LIMIT_MAX = 10` equals the default limit, making the name misleading.  Rename to
`ENTRY_SEARCH_MAX_LIMIT = 50` to align with `notes_list` and update
`docs/api/ffi-contracts.md` to clarify `entry_search` pagination cap.

**R01-5 — Unregistered error codes** (`crates/lazynote_ffi/src/api.rs:249–292`)

`entry_search` emits `"db_open_failed"` and `"search_failed"` which are not registered in
`docs/api/error-codes.md`.  Replace with stable codes:

- `"db_open_failed"` → `"db_error"`
- `"search_failed"` → `"internal_error"`

Update `docs/api/error-codes.md` to document the `entry_search` error paths explicitly.

### Low-Risk Cleanup (LOW)

**R01-7 — Atom validate guard** (`crates/lazynote_core/src/repo/atom_repo.rs`)

Add `atom.validate()?` at the entry point of `create_atom` and `update_atom` as
defensive validation.  Does not break any existing tests.

**R01-9 — Redundant lowercase in `tags_list_impl`** (`crates/lazynote_ffi/src/api.rs:529–552`)

Remove the `.map(|tag| tag.to_lowercase())` in `tags_list_impl`; storage layer already
normalizes to lowercase on insert.  Add a comment: `// tags are lowercase-normalized at
write time; no re-normalization needed here`.

**R01-10 — `SQLITE_BUSY` not differentiated** (`crates/lazynote_core/src/db/open.rs`)

In `map_repo_error`, add a match arm for `rusqlite::ErrorCode::DatabaseBusy` mapping to a
new stable error code `"db_busy"`.  Register `db_busy` in `docs/api/error-codes.md`.

### Observability (MEDIUM/LOW)

**R02-4.1 — Panic hook flush** (`crates/lazynote_core/src/logging.rs:191–213`)

In `install_panic_hook_once`, after emitting the `error!` log, call
`LOGGING_STATE.get().map(|s| s._logger.flush())` to force-flush the buffer before the
previous hook runs.  Requires `flexi_logger ≥ 0.27` — verify version in `Cargo.lock`
before implementing.

Note: `_logger` is currently a private field of `LoggingState`.  The field must be
accessible from the panic hook closure (already the case since the hook is in the same
module).

**R02-4.2 — Operation-level `duration_ms`** (`crates/lazynote_core/src/service/`)

Add `Instant`-based duration logging at the start/end of three high-frequency operations:
`note_create`, `note_update`, `search_all`.  Format:
`event=note_create module=service status=ok duration_ms=N`.
No new dependencies; uses `std::time::Instant` already present in `open.rs`.

## Planned File Changes

- [edit] `crates/lazynote_ffi/src/api.rs` — R01-2 mutex log, R01-3 constant rename,
  R01-5 error codes, R01-9 redundant lowercase
- [edit] `crates/lazynote_core/src/db/open.rs` — R01-4 WAL pragma, R01-10 db_busy mapping
- [edit] `crates/lazynote_core/src/repo/atom_repo.rs` — R01-7 validate guard
- [edit] `crates/lazynote_core/src/service/note_service.rs` — R02-4.2 duration_ms
- [edit] `crates/lazynote_core/src/search/fts.rs` — R02-4.2 duration_ms for search_all
- [edit] `crates/lazynote_core/src/logging.rs` — R02-4.1 panic hook flush
- [edit] `docs/api/error-codes.md` — register db_busy; clarify entry_search paths
- [edit] `docs/api/ffi-contracts.md` — correct ENTRY_SEARCH_MAX_LIMIT documentation

## Dependencies

- `PR-0017A` (v0.1 closure) — should be complete before this PR executes so the Rust
  test suite is at a stable baseline

## Verification

```bash
cd crates
cargo fmt --all -- --check
cargo clippy --all -- -D warnings
cargo test --all
```

Manual checks:
1. After WAL PRAGMA: open a `.db` file in DB Browser for SQLite and confirm
   `PRAGMA journal_mode;` returns `wal`.
2. After error-code unification: run `entry_search` test suite, confirm no assertions
   reference `"db_open_failed"` or `"search_failed"`.
3. After `_logger.flush()` in panic hook: trigger a panic in test, confirm
   `event=panic_captured` appears in log file.

## Acceptance Criteria

- [ ] `resolve_entry_db_path` Mutex poison path emits `error!` before falling back.
- [ ] `PRAGMA journal_mode=WAL` is applied on every connection bootstrap.
- [ ] `entry_search` error codes match `docs/api/error-codes.md`.
- [ ] `ENTRY_SEARCH_MAX_LIMIT = 50` and docs are consistent.
- [ ] `atom.validate()` is called at repo create/update entry points.
- [ ] `tags_list_impl` no longer duplicates lowercase normalization.
- [ ] `db_busy` is a registered stable error code.
- [ ] Panic hook calls `_logger.flush()` (or documents why it cannot, if version constraint).
- [ ] `note_create`, `note_update`, `search_all` emit `duration_ms` log entries.
- [ ] All Rust quality gates pass.
