# CI Helpers

- `tools/ci/flutter_windows_build.ps1`
  - Runs Flutter CI checks for Windows: `pub get`, format check, analyze, test, optional windows debug build.
- `tools/ci/rust_checks.ps1`
  - Runs Rust workspace checks: `fmt`, `clippy -D warnings`, `test`.
