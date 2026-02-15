# PR-0220B-settings-config-hardening

- Proposed title: `fix(settings): settings persistence correctness and config wiring`
- Status: Planned
- Source: review-02 §2.1, §2.2, §2.3, §2.4

## Goal

Resolve four findings in `LocalSettingsStore` that cause user-visible misconfiguration
(logging level silently ignored) and silent data loss risk (settings.json write race on
Windows).  All changes are confined to one file and its tests.

## Scope

### R02-2.1 — `loggingLevelOverride` is stored but never applied

**File:** `apps/lazynote_flutter/lib/core/settings/local_settings_store.dart`,
`apps/lazynote_flutter/lib/core/rust_bridge.dart`

`settings.json` can contain `logging.level_override`.  `LocalSettingsStore` reads and
parses it into `_loggingLevelOverride`, but `bootstrapLogging` ignores it, using the
compile-time default instead.

Fix (Option A — wire it up, since `ensureInitialized()` runs before `bootstrapLogging()`
in `main.dart`):

```dart
// rust_bridge.dart: bootstrapLogging()
final level = LocalSettingsStore.loggingLevelOverride ?? defaultLogLevelResolver();
```

Fix (Option B — if not wiring in this PR): add `TODO(v0.2): wire loggingLevelOverride to
bootstrapLogging` in `local_settings_store.dart:59` and add a sentence to
`docs/architecture/settings-config.md` noting the field is stored but not yet applied.

**Preference:** Option A is one line of Dart with no new dependencies; implement Option A.

### R02-2.2 — Three settings fields written but never consumed

**File:** `apps/lazynote_flutter/lib/core/settings/local_settings_store.dart`

`_backfillMissingDefaults` writes `entry.result_limit`, `entry.use_single_entry_as_home`,
and `entry.expand_on_focus` to `settings.json`, but `_loadRuntimeSettings` never reads
them into runtime state.  Any user modification has no effect.

Fix: add `TODO` comments co-located with each backfill write:

```dart
// TODO(v0.2): wire result_limit to SingleEntryController limit parameter
jsonMap['entry']['result_limit'] = 10;
```

This clarifies intent for the next reader without risking regressions from a premature
consumer hook.

### R02-2.3 — `settings.json` write has a brief empty-file window on Windows

**File:** `apps/lazynote_flutter/lib/core/settings/local_settings_store.dart:283–300`

`_writeFileWithTempReplace` on Windows: `File.rename` throws if target exists, triggering
a fallback that does `target.delete()` then `temp.rename(target.path)`.  A process crash
between the two calls leaves no `settings.json`, and the next startup re-creates it with
defaults, silently losing all user settings.

Fix: in the fallback branch, write to a `.bak` file first (atomic rename), then recover on
next startup:

```dart
// Before deleting target, first rename temp → temp.bak (cheap atomic swap)
// If target exists after rename attempt, do: rename target → target.old, rename temp → target
```

Alternatively (simpler), on startup in `_ensureInitializedInternal`, check for the
presence of a leftover `.tmp.*` file alongside the target and use it as a recovery source
if target does not exist.

**Implementation note:** the simpler crash-recovery approach (check for temp file on
startup) is preferred over complicating the write path.  Add:

```dart
// In _ensureInitializedInternal, before reading target:
final recoveryFile = File('${targetPath}.tmp');
if (!targetFile.existsSync() && recoveryFile.existsSync()) {
    await recoveryFile.rename(targetPath);
}
```

### R02-2.4 — `schema_version` is written but never read for migration decisions

**File:** `apps/lazynote_flutter/lib/core/settings/local_settings_store.dart`

`_backfillMissingDefaults` writes `schema_version: 1` but no code reads it to guard
against loading a future-version `settings.json` with unknown fields.

Fix: add a version guard at the start of `_loadRuntimeSettings`:

```dart
final schemaVersion = decoded['schema_version'];
if (schemaVersion is int && schemaVersion > 1) {
    // Cannot parse a settings file from a newer version; fall back to defaults.
    // TODO(v0.2): implement forward-migration when schema_version increases.
    return;
}
```

Also add `TODO(v0.2): add migration for schema_version >= 2` adjacent to the
`backfill` write of `schema_version`.

## Planned File Changes

- [edit] `apps/lazynote_flutter/lib/core/settings/local_settings_store.dart` — R02-2.1
  (loggingLevelOverride getter used), R02-2.2 (TODO comments), R02-2.3 (startup recovery
  check), R02-2.4 (version guard + TODO)
- [edit] `apps/lazynote_flutter/lib/core/rust_bridge.dart` — R02-2.1 (wire
  `loggingLevelOverride` in `bootstrapLogging`)
- [edit] `docs/architecture/settings-config.md` — clarify which fields are active vs
  pending wiring; note schema_version semantics

## Dependencies

- `PR-0220A` — can run in parallel; no shared files
- `PR-0219` — independent; no ordering requirement

## Verification

```bash
cd apps/lazynote_flutter
flutter analyze
flutter test
```

Manual checks:
1. Set `"level_override": "trace"` in `settings.json`, restart, verify `trace`-level
   entries appear in Rust log file (proves R02-2.1 fix).
2. Set `"schema_version": 999` in `settings.json`, restart, verify app uses defaults
   (proves R02-2.4 guard).
3. On Windows: simulate crash between delete and rename (e.g., suspend the process
   in Process Explorer), restart, verify settings.json is restored from `.tmp` recovery
   file (proves R02-2.3 fix).

## Acceptance Criteria

- [ ] (R02-2.1) `bootstrapLogging` uses `loggingLevelOverride` from `LocalSettingsStore`
      when non-null; a test covers the override path.
- [ ] (R02-2.2) `result_limit`, `use_single_entry_as_home`, `expand_on_focus` backfill
      writes have co-located `TODO(v0.2)` comments referencing their future consumer.
- [ ] (R02-2.3) Startup path checks for a leftover `.tmp` recovery file and restores it
      when `settings.json` is absent.
- [ ] (R02-2.4) `schema_version > 1` in `settings.json` causes `_loadRuntimeSettings` to
      skip parsing and return defaults; test verifies.
- [ ] Flutter quality gates pass.
