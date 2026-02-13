# Logging Strategy (v0.1)

本文件定义 LazyNote 在 v0.1 的日志设计，用于排障与用户问题回传，不用于遥测分析。

## 1. Goals

- Diagnose FFI / DB / sync issues in Rust core.
- Provide user-friendly log export for bug reports.
- Keep logging safe by default (privacy-first, non-crashing).

## 2. Non-goals

- Not a telemetry/analytics system.
- No remote log upload in v0.1.

## 3. Log Levels

- Debug builds default: `debug`
- Release builds default: `info`
- Optional runtime override via settings (temporary, for local diagnostics only).
- Runtime override levels allowed in v0.1: `info | debug | trace`.
- Runtime override is session-scoped: app restart falls back to build default.

## 4. Log Location

### Ownership

- Flutter computes platform log directory using `path_provider`.
- Rust receives `log_dir` via FFI `init_logging()` and writes rolling files.
- Rust must not guess or hardcode platform paths.

### Example path (Windows)

- `%APPDATA%/LazyNote/logs`

### Path contract (v0.1)

- Flutter should resolve an app data base directory (for example, via `getApplicationSupportDirectory()`).
- Flutter appends `logs/` and passes the absolute path to Rust.

### File naming (recommended)

- `lazynote.log` (active)
- `lazynote.log.1` ... `lazynote.log.N` (rolled files)

## 5. FFI API Contract

### `init_logging(level, log_dir)`

- Must be called once during app startup, before `core_init` / `db_open` / `migrate`.
- Repeated calls are idempotent only when `level + log_dir` are unchanged.
- Logging initialization must never crash the app.
- Initialization failures are returned as strings.
- Later calls must not silently reconfigure to a different `level` or `log_dir` in the same session.

Recommended semantic contract:

- Success: empty error (`null` / empty string, depending on binding style) and logging enabled.
- Failure: human-readable error string for UI display and troubleshooting.

## 6. Privacy / Redaction Policy (Mandatory)

Never log:

- note content
- task titles
- calendar event descriptions
- auth tokens / refresh tokens / secrets

Only log metadata:

- IDs (internal stable IDs), counts, durations, status/error codes

User-provided strings:

- must be truncated and/or hashed before logging
- never store full free-text input directly in logs
- recommended pattern: log `input_len` + `input_hash`, not raw input

## 7. Retention

v0.1 default:

- rolling files by size: `10MB x 5 files`

Optional extension (later):

- add age-based cleanup (e.g. keep 7 days max)

## 8. Event Checklist (v0.1)

Minimum events to log:

- `app_start` / `core_init` (include app version, platform, build mode)
- `db_open`
- `db_migrate_start` / `db_migrate_done` (include from/to schema version)
- `fts_update` (include batch size and duration)
- FFI use-case events:
  - `create_note`
  - `search`
  - `schedule`
  - `sync`
  - `export`
  - `import`
- core CRUD events:
  - `atom_create`
  - `atom_update`
  - `atom_soft_delete`
- `sync_start` / `sync_done` / `sync_error`
  - include `token_updated`, `pulled_count`, `written_count`, `conflict_count`
- `export_start` / `export_done` / `export_error`
- `import_start` / `import_done` / `import_error`
- `panic_captured` (via Rust panic hook, with sanitized message only)
- `error` (unexpected failures)

## 9. Event Field Baseline

Required common fields:

- `ts` (timestamp)
- `level`
- `event`
- `module` (`ffi`, `db`, `search`, `sync`, `import_export`)
- `status` (`ok` / `error`)

Recommended optional fields:

- `duration_ms` (when applicable)
- `error_code` (if any)
- `entity_id` / `count` (metadata only)
- `build_mode`
- `platform`
- `session_id`

## 10. Export for Bug Reports

v0.1 should support local export flow:

- user triggers "Export Logs"
- app bundles current rolling logs into one archive
- user manually attaches archive in issue/bug report

Constraints:

- no automatic upload
- no background network transfer

## 11. Failure Policy

- If logging setup fails, app continues running.
- Failures are surfaced as user-readable diagnostics (string error).
- Core business operations must not depend on logging success.

## 12. Implementation Notes (Current)

- Rust side:
  - structured logging is enabled
  - rolling appender is enabled (`10MB x 5`)
  - startup + core operations emit metadata-only events
- Flutter side:
  - computes `log_dir` via `path_provider`
  - calls `init_logging(level, log_dir)` during startup bootstrap
  - shows a non-fatal startup hint when logging bootstrap fails
- Workbench diagnostics:
  - inline live log panel is available in the split-shell workbench
  - panel supports refresh, copy visible logs, open log folder, and periodic polling
  - panel keeps mounted while left-side placeholder pages switch

See also: `docs/releases/v0.1/prs/PR-0017-workbench-debug-logs.md`.

### Remaining gap (v0.1)

- Zip export flow for bug reports is not implemented yet.

## 13. Implementation Rollout Plan (Staged)

为降低工具链风险（特别是 FRB codegen / Flutter daemon 卡死），v0.1 采用三阶段落地：

### Phase A: Core-only logging (no FRB/codegen changes)

Scope:

- Implement `init_logging(level, log_dir)` in `lazynote_core`.
- Add rolling policy (`10MB x 5`) and panic hook logging.
- Add key event logs in core paths:
  - `db_open` / `db_migrate_*`
  - `atom_create` / `atom_update` / `atom_soft_delete`
  - `search`

Validation:

- `cd crates && cargo check -p lazynote_core`
- `cd crates && cargo test -p lazynote_core`

Notes:

- Phase A must not depend on Flutter toolchain readiness.

### Phase B: FFI surface for logging init (codegen isolated)

Scope:

- Expose `init_logging(level, log_dir)` from `lazynote_ffi`.
- Regenerate FRB binding artifacts as a standalone step.

Validation:

- `cd crates && cargo check -p lazynote_ffi`
- FRB generated files are updated and compile cleanly.

Notes:

- If CI/runner repeatedly times out on codegen, run this phase locally first, then commit generated artifacts.

### Phase C: Flutter bootstrap integration

Scope:

- In Flutter startup, compute log directory and call FFI `init_logging`.
- Show non-fatal init error in diagnostics UI (do not block app launch).

Validation:

- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test`
- `flutter run -d windows` startup remains stable.

Notes:

- Logging init failure must not prevent `runApp`.

### Rollback policy

- If any phase becomes unstable, rollback only that phase and keep earlier phases merged.
- Never bundle all three phases into one commit.
