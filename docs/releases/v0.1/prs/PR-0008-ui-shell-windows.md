# PR-0008-ui-shell-windows

- Proposed title: `ui(shell): Windows app shell + window behavior`
- Status: Completed

## Goal
Stabilize a Windows-first app shell and establish a Workbench homepage for validating features before wiring final module windows.

## Deliverables
- app shell with dedicated app/routes structure
- Workbench homepage with placeholder input + validation status
- placeholder routes for deferred modules (`notes`, `tasks`, `settings`)
- basic Windows window behavior (title, startup size, close-to-exit)

## Planned File Changes
- [edit] `apps/lazynote_flutter/lib/main.dart`
- [add] `apps/lazynote_flutter/lib/app/app.dart`
- [add] `apps/lazynote_flutter/lib/app/routes.dart`
- [add] `apps/lazynote_flutter/lib/features/entry/entry_shell_page.dart`
- [add] `apps/lazynote_flutter/lib/features/diagnostics/rust_diagnostics_page.dart`
- [edit] `apps/lazynote_flutter/windows/runner/main.cpp`
- [add] `apps/lazynote_flutter/test/smoke_test.dart`

## Dependencies
- PR0003

## Acceptance Criteria
- [x] Scope implemented
- [x] Basic verification/tests added
- [x] Documentation updated if behavior changes

## Notes
- Workbench is the default homepage for this stage (`/` and `/entry`).
- FRB smoke-specific UI is removed from `main.dart`; shell concerns are now isolated in `lib/app/*` and `lib/features/*`.
- Added `/diag/rust` route as a dedicated runtime diagnostics entry for Rust bridge checks.
- Placeholder routes are intentionally non-functional and provide explicit "under construction" pages.
- Workbench and placeholder pages now use `SafeArea + SingleChildScrollView` to prevent overflow in small windows.
- Windows runner defaults updated to `LazyNote Workbench` title with a stable startup size.
- Verification:
  - `cd apps/lazynote_flutter && dart format lib test`
  - `cd apps/lazynote_flutter && flutter test`
  - `cd apps/lazynote_flutter && flutter analyze`
