# Settings Config Contract

## Purpose

Define a stable local settings contract for Flutter UI behavior and runtime toggles.

This document is the source of truth for:

- file format (`settings.json`)
- schema versioning
- validation and fallback behavior
- Flutter/Rust integration boundaries

## Non-Goals (v0.1)

- cloud sync for settings
- remote feature-flag service
- storing auth tokens or secrets in settings file

## Ownership Boundary

Flutter owns settings file IO.

- Read/write/validate `settings.json` in Flutter.
- Apply UI-level settings in Flutter controllers and pages.
- Pass only required runtime values to Rust via explicit FFI API.

Rust must not directly read this UI settings file.

## File Format

- Format: UTF-8 JSON (`settings.json`)
- Required top-level field: `schema_version`
- Unknown fields: ignored by reader (forward-compatible baseline)

## Recommended Location

Use a unified app root folder named `LazyLife`.

Windows example:

- `%APPDATA%\\LazyLife\\settings.json`

Cross-platform fallback:

- `<app_support>/LazyLife/settings.json`

### Mandatory path rule (v0.1+)

All user-writable runtime artifacts must live under the same app root:

- Windows: `%APPDATA%/LazyLife/`
- Non-Windows fallback: `<app_support>/LazyLife/`

This includes:

- `settings.json`
- `logs/`
- `data/` (entry db and future local data files)

## v0.1 Schema (Draft)

```json
{
  "schema_version": 1,
  "entry": {
    "result_limit": 10,
    "use_single_entry_as_home": false,
    "expand_on_focus": true
  },
  "logging": {
    "level_override": null
  }
}
```

## Validation Rules

`schema_version`

- must be a positive integer
- unsupported version falls back to defaults and records a warning

`entry.result_limit`

- integer range: `1..50`
- invalid value falls back to default `10`

`entry.use_single_entry_as_home`

- boolean
- default: `false` in v0.1

`entry.expand_on_focus`

- boolean
- default: `true`

`logging.level_override`

- nullable string enum: `trace | debug | info | warn | error`
- `null` means use build defaults/runtime policy

## Read/Write Behavior

Read path:

1. Try parse file.
2. Validate each supported field.
3. Merge valid values into defaults.
4. Keep app running even if file is missing/corrupted.

Write path:

1. Serialize validated settings object.
2. Write to temp file in same directory.
3. Atomically replace target file.
4. On failure, keep previous file untouched and report warning.

## Runtime Apply Order

1. Load settings early in app bootstrap.
2. Apply UI behavior settings before rendering major shells when possible.
3. Apply runtime bridge settings before first command/search execution if required.

## Flutter-Rust Integration Requirements

Existing FFI API already used:

- `configure_entry_db_path(dbPath)` must still run before first entry query.

Future optional FFI API (if needed):

- `configure_entry_runtime(resultLimit, ...)` for Rust-side defaults.

Rules:

- Never pass raw settings map over FFI.
- Pass explicit typed values only.
- Contract changes must update:
  - `docs/api/*`
  - `docs/governance/API_COMPATIBILITY.md`

## Privacy and Security

- Do not store tokens, passwords, note contents, or calendar event descriptions.
- Only store non-sensitive UX/runtime toggles.
- Settings parsing errors may be logged, but values should be redacted when needed.

## Migration Strategy

- Bump `schema_version` only for breaking schema changes.
- Provide `vN -> vN+1` migration in Flutter settings loader.
- Keep migration deterministic and idempotent.
