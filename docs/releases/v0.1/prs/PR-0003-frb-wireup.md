# PR-0003-frb-wireup

- Proposed title (PR-A): `chore(frb): wire minimal ffi api (ping/core_version)`
- Proposed title (PR-B): `feat(flutter): call rust ping/core_version on windows`
- Status: Completed

## Goal
Split FRB wiring into two small PRs, so we can isolate problems:

- PR-A: make codegen/bindings/dylib chain valid
- PR-B: make Flutter Windows call Rust APIs in UI

## Deliverables
- PR-A:
  - Rust FRB API: `ping()` / `core_version()`
  - FRB config file: `.flutter_rust_bridge.yaml`
  - stable binding generation script (`scripts/gen_bindings.ps1`)
  - generated FRB artifacts committed to repo
  - Flutter dependency pin for `flutter_rust_bridge` runtime
- PR-B:
  - Flutter-side bridge wrapper
  - Windows app actually calls `ping()` / `core_version()`
  - UI shows result (DLL load/runtime chain proof)
  - workspace DLL path auto-detection to avoid manual env var setup

## Scope Of This PR (A)

In scope:

- `crates/lazynote_ffi` exposes only minimal use-case-level health APIs.
- FRB generation command is reproducible from `scripts/gen_bindings.ps1`.
- Generated files are updated and tracked.

Out of scope:

- Flutter UI integration and lifecycle init calls.
- any domain/business feature beyond connectivity smoke-check.

## Scope Of This PR (B)

In scope:

- add Flutter-side `rust_bridge` wrapper to call FRB APIs.
- initialize FRB from app startup flow.
- show `ping/coreVersion` in Windows UI as smoke proof.
- keep widget tests independent from local DLL runtime by dependency injection.

Out of scope:

- any feature beyond bridge health-check (notes/tasks/calendar).
- packaging/distribution of Rust dylib.

## Planned File Changes
- [add] `.flutter_rust_bridge.yaml`
- [edit] `crates/lazynote_ffi/Cargo.toml`
- [edit] `crates/lazynote_ffi/src/lib.rs`
- [add] `crates/lazynote_ffi/src/api.rs`
- [gen] `crates/lazynote_ffi/src/frb_generated.rs`
- [edit] `scripts/gen_bindings.ps1`
- [edit] `apps/lazynote_flutter/pubspec.yaml`
- [edit] `apps/lazynote_flutter/pubspec.lock`
- [gen] `apps/lazynote_flutter/lib/core/bindings/api.dart`
- [gen] `apps/lazynote_flutter/lib/core/bindings/frb_generated.dart`
- [gen] `apps/lazynote_flutter/lib/core/bindings/frb_generated.io.dart`
- [gen] `apps/lazynote_flutter/windows/runner/generated_frb.h`
- [add] `apps/lazynote_flutter/lib/core/rust_bridge.dart`
- [edit] `apps/lazynote_flutter/lib/main.dart`
- [edit] `apps/lazynote_flutter/test/widget_test.dart`
- [add] `apps/lazynote_flutter/test/rust_bridge_test.dart`
- [add] `scripts/run_windows_smoke.bat`

## Dependencies
- PR0000, PR0001, PR0002

## Acceptance Criteria
- [x] PR-A scope implemented
- [x] `scripts/gen_bindings.ps1` can regenerate bindings from config
- [x] `cargo test -p lazynote_ffi` passes
- [x] `flutter analyze` passes after dependency update
- [x] PR-B scope implemented
- [x] `flutter run -d windows` shows ping/coreVersion in UI
- [x] `flutter test` passes with injected mock loader
- [x] Documentation updated if behavior changes

## Verification Commands (PR-A)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gen_bindings.ps1

cd crates
cargo test -p lazynote_ffi

cd ..\apps\lazynote_flutter
flutter pub get
flutter analyze
```

## Verification Commands (PR-B)

```powershell
cd crates
cargo build -p lazynote_ffi --release

cd ..\apps\lazynote_flutter
flutter test
flutter run -d windows
```

## Notes
- Keep FRB versions aligned (`2.11.1`) across Rust and Flutter runtime/codegen.
- `rust_bridge.dart` includes workspace DLL path probing for local development.
- Post-review hardening completed:
  - candidate DLL open failure logs path + exception and continues fallback
  - init deduplicates concurrent calls and supports retry after failure
  - dedicated `rust_bridge_test.dart` covers init race/retry/fallback logic
