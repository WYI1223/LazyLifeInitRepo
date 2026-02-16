# Windows Quickstart (New Clone)

Goal: run LazyNote on Windows with the minimum command set.

## Commands

Run these in repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/doctor.ps1 -SkipFlutterDoctor
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gen_bindings.ps1
cd apps/lazynote_flutter; flutter pub get
flutter run -d windows
```

## Expected Result

After app startup:

- Workbench home loads.
- `Rust Diagnostics` page is reachable.
- Workbench right panel `Debug Logs (Live)` shows rolling logs and refreshes.
- Logs are written under `%APPDATA%\\LazyLife\\logs\\`.
- When opening `Notes/Tasks/Settings/Rust Diagnostics`, the left pane switches while the right logs panel stays mounted.
- The center splitter can be dragged to resize left/right panes (double-click resets width).

If you see `Failed to load dynamic library`, build Rust FFI first:

```powershell
cd crates
cargo build -p lazynote_ffi --release
```

Then run again:

```powershell
cd apps/lazynote_flutter
flutter clean
flutter pub get
flutter run -d windows
```

## Related Smoke Guide

- `docs/development/windows-pr0007-search-smoke.md`
