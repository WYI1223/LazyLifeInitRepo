# FFI Contract (v0.1)

This document defines the Flutter-to-Rust Single Entry FFI contract for v0.1.

For notes/tags contracts added in PR-0010B, see:

- `docs/api/ffi-contracts.md`

## Conventions

- Primary export module: `crates/lazynote_ffi/src/api.rs`
- Dart wrappers: `apps/lazynote_flutter/lib/core/bindings/api.dart`
- `sync` APIs return immediate values and may do light setup work.
- `async` APIs are DB-backed operations and should be awaited.
- Business failures should be represented in return payloads (`ok`, `error_code`, `message`) rather than thrown exceptions.

## Data Models

### `EntrySearchResponse`

- `ok: bool`: execution success flag
- `error_code: String?`: stable machine-readable error code
- `items: EntrySearchItem[]`: result list
- `message: String`: human-readable status text
- `applied_limit: u32`: normalized limit used by backend

### `EntryActionResponse`

- `ok: bool`: execution success flag
- `atom_id: String?`: created atom id on success
- `message: String`: human-readable status text

## Function Contracts

## Health and bootstrap

### `ping() -> String`

- Blocking model: `sync`
- Threading: UI-safe
- Error behavior: never throws; always returns string
- Stability: expected value `pong` for smoke diagnostics

### `core_version() -> String`

- Blocking model: `sync`
- Threading: UI-safe
- Error behavior: never throws; always returns string
- Stability: returns Rust core version string

### `init_logging(level, log_dir) -> String`

- Blocking model: `sync`
- Threading: small filesystem setup allowed; keep usage at startup/bootstrap
- Error behavior:
  - success: empty string
  - failure: non-empty error string
- Constraints:
  - `level`: `trace|debug|info|warn|error` (case-insensitive)
  - `log_dir`: absolute path
- Idempotency:
  - same config: allowed
  - conflicting config: returns error

### `configure_entry_db_path(db_path) -> String`

- Blocking model: `sync`
- Threading: UI-safe
- Error behavior:
  - success: empty string
  - failure: non-empty error string
- Constraints:
  - path must be absolute
  - parent directory may be created

## Entry APIs

### `entry_search(text, limit?) -> EntrySearchResponse`

- Blocking model: `async`
- Threading: not UI-thread blocking by contract
- Error behavior:
  - transport/bridge failures may throw at FRB layer
  - business failure encoded as `ok=false` + `error_code`
- Semantics:
  - default limit: 10
  - max limit: 50
  - response `applied_limit` must be used by UI as authoritative value

### `entry_create_note(content) -> EntryActionResponse`

- Blocking model: `async`
- Threading: not UI-thread blocking by contract
- Error behavior: business failure encoded as `ok=false` + message
- Semantics: create note atom and return created `atom_id` on success

### `entry_create_task(content) -> EntryActionResponse`

- Blocking model: `async`
- Threading: not UI-thread blocking by contract
- Error behavior: business failure encoded as `ok=false` + message
- Semantics: create task atom with default status `todo`

### `entry_schedule(title, start_epoch_ms, end_epoch_ms?) -> EntryActionResponse`

- Blocking model: `async`
- Threading: not UI-thread blocking by contract
- Error behavior: business failure encoded as `ok=false` + message
- Semantics:
  - point event: `end_epoch_ms = null`
  - range event: `end_epoch_ms != null` and must be after start
  - time unit: epoch milliseconds

## Compatibility Notes

- Keep `error_code` stable once published.
- Avoid changing payload semantics without updating:
  - `docs/api/error-codes.md`
  - `docs/api/single-entry-contract.md`
  - release notes in `docs/releases/`
