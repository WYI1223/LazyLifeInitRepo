# PR-0220A-flutter-lifecycle-hardening

- Proposed title: `fix(core): RustBridge lifecycle hardening and error separation`
- Status: Completed
- Source: review-02 §3.1, §3.2, §3.3

## Goal

Harden the `RustBridge` initialization lifecycle against two low-probability but
high-impact failure modes identified in the engineering review, and improve diagnostic
clarity when initialization fails.

This PR targets only `rust_bridge.dart` (and `local_settings_store.dart` for the
`resetForTesting` doc comment).  It does **not** touch `notes_controller.dart` — those
state management bugs are addressed by design in `PR-0204`.

## Rationale for a Standalone PR

The `RustBridge` lifecycle bugs (R02-3.2 and R02-3.3) are independent of any feature work
and affect every startup path.  Fixing them before the v0.2 workspace lane (PR-0204+)
reduces diagnostic confusion during development.

## Scope

### R02-3.2 — `bootstrapLogging` and DB-path init error separation

**File:** `apps/lazynote_flutter/lib/core/rust_bridge.dart`

Currently `bootstrapLogging` calls `ensureEntryDbPathConfigured` inside a single
`try/catch`.  Both failures produce the same log message:
`"Rust logging/entry-db init failed. log_dir=... db_path=..."`.

Fix: split into two independent `try/catch` blocks, each with a distinct label in the
error message (`"entry-db-path configure failed"` vs `"logging-init failed"`), so the
diagnostics panel shows which step failed.

### R02-3.3 — FRB `RustLib.init()` concurrent retry risk

**File:** `apps/lazynote_flutter/lib/core/rust_bridge.dart`

When `_initInternal` fails, it clears `_initFuture = null`.  A concurrent caller that
checks `_initFuture == null` after the failure (before the error propagates) will create
a second `_initInternal` future, potentially calling the native `RustLib.init()` (i.e.
`dlopen`) twice.

Fix: add a static `_initFailed` flag.  On failure in `_initInternal`, set
`_initFailed = true`.  In `init()`, if `_initFailed`, return a `Future.error(...)` without
retrying.  Reset `_initFailed` in `resetForTesting()`.

```dart
static bool _initFailed = false;

static Future<void> init() {
    if (_initialized) return Future.value();
    if (_initFailed) return Future.error(StateError('RustBridge init permanently failed'));
    // existing logic...
}

// in _initInternal catch block:
} catch (_) {
    _initFuture = null;
    _initFailed = true;
    rethrow;
}
```

### R02-3.1 — `resetForTesting()` static field documentation

**Files:** `apps/lazynote_flutter/lib/core/rust_bridge.dart`,
`apps/lazynote_flutter/lib/core/settings/local_settings_store.dart`

Add a comment block above `resetForTesting()` in both files:

```dart
/// Resets all static state for test isolation.
/// IMPORTANT: any new static field added to this class MUST be reset here.
/// Current fields: _initialized, _entryDbPathConfigured, _initFuture, _initFailed, ...
static void resetForTesting() { ... }
```

This is a documentation-only change; it imposes a code-review convention for future
contributors.

## Planned File Changes

- [edit] `apps/lazynote_flutter/lib/core/rust_bridge.dart` — R02-3.2 error separation,
  R02-3.3 `_initFailed` flag, R02-3.1 doc comment
- [edit] `apps/lazynote_flutter/lib/core/settings/local_settings_store.dart` — R02-3.1
  doc comment on `resetForTesting()`
- [edit/add] `apps/lazynote_flutter/test/rust_bridge_lifecycle_test.dart` — regression
  test: concurrent init-after-failure does not call `rustLibInit` twice

## Dependencies

- `PR-0219` (Rust infrastructure hardening) — run after to maintain a clean baseline
- Can run in parallel with `PR-0220B`

## Verification

```bash
cd apps/lazynote_flutter
flutter analyze
flutter test test/rust_bridge_lifecycle_test.dart
flutter test
```

Manual check: set `resolvedDbPath` to an unwritable path (`C:\Windows\System32\x.db`),
confirm the diagnostics panel shows `"entry-db-path configure failed"` (not the generic
message).

## Acceptance Criteria

- [x] (R02-3.2) `bootstrapLogging` splits DB-path init and logging init into separate
      `try/catch` blocks with distinct error labels.
- [x] (R02-3.3) `_initFailed` flag prevents a second `RustLib.init()` call after a
      permanent failure; test verifies `rustLibInit` is called at most once per process.
- [x] (R02-3.1) `resetForTesting()` has a doc comment listing all static fields it resets,
      and `_initFailed` is included in the reset.
- [x] Flutter quality gates pass.
