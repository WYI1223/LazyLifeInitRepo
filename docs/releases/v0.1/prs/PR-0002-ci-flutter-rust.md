# PR-0002-ci-flutter-rust

- Proposed title: `chore(ci): add CI for Flutter + Rust (Windows + Ubuntu)`
- Status: Completed

## Goal
Protect PRs from build/test regressions.

## Deliverables
- Windows: flutter pub get/test/build windows
- Rust: fmt/clippy/test
- .github/workflows/ci.yml baseline

## Planned File Changes
- [edit] `.github/workflows/ci.yml`
- [add] `tools/ci/flutter_windows_build.ps1`
- [add] `tools/ci/rust_checks.ps1`
- [edit] `scripts/format.ps1`

## Dependencies
- PR0000, PR0001

## Acceptance Criteria
- [x] Scope implemented
- [x] Basic verification/tests added
- [x] Documentation updated if behavior changes

## Notes
- CI workflow enforces:
  - Flutter Windows: `pub get`, format check, analyze, test, debug build
  - Rust Ubuntu: `fmt`, `clippy -D warnings`, `test`
- Local CI helper scripts are available:
  - `tools/ci/flutter_windows_build.ps1`
  - `tools/ci/rust_checks.ps1`
