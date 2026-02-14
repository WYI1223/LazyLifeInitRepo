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
    "expand_on_focus": true,
    "ui": {
      "collapsed_height": 72,
      "expanded_max_height": 420,
      "animation_ms": 180
    }
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

`entry.ui.collapsed_height`

- number (pixels), recommended range `48..160`
- default: `72`

`entry.ui.expanded_max_height`

- number (pixels), recommended range `220..720`
- default: `420`

`entry.ui.animation_ms`

- integer (milliseconds), recommended range `80..500`
- default: `180`

`logging.level_override`

- nullable string enum: `trace | debug | info | warn | error`
- `null` means use build defaults/runtime policy
- v0.1 behavior: value is validated and persisted, but not applied at runtime yet

## Read/Write Behavior

Read path:

1. Try parse file.
2. Validate each supported field.
3. Merge valid values into defaults.
4. Backfill missing known keys to file (without overriding existing valid values).
5. Keep app running even if file is missing/corrupted.

Write path:

1. Serialize validated settings object.
2. Write to temp file in same directory.
3. Replace target file from temp (`rename-over-existing` where supported, fallback replace otherwise).
4. On failure, keep previous file untouched and report warning.

## Runtime Apply Order

1. Load settings early in app bootstrap.
2. Apply UI behavior settings before rendering major shells when possible.
3. Runtime bridge settings are applied before first command/search execution when required.
4. `logging.level_override` is reserved in v0.1 (persist-only, no runtime apply yet).

### Startup policy (v0.1)

- Keep first frame non-blocking.
- Current bootstrap execution order:
  1. `LocalSettingsStore.ensureInitialized()`
  2. `RustBridge.bootstrapLogging()`
- Both run in background startup orchestration (not before `runApp`).

### Layered loading trigger (future rule)

When any setting changes first-frame UI behavior (for example: home route,
theme, locale), startup must switch to layered loading:

- critical settings: load before `runApp` (optionally with a short timeout)
- non-critical settings: continue loading in background

This rule must be reflected in:

- `apps/lazynote_flutter/lib/main.dart`
- this document (`docs/architecture/settings-config.md`)

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

- Path migration policy for v0.1:
  - no old-path data migration is performed in this version
  - runtime storage location switches directly to the unified `LazyLife` root
  - this is acceptable because v0.1 has no production user data baseline
- Future versions may add user-visible migration workflows and configurable
  storage location policy.
- Bump `schema_version` only for breaking schema changes.
- Provide `vN -> vN+1` migration in Flutter settings loader.
- Keep migration deterministic and idempotent.
