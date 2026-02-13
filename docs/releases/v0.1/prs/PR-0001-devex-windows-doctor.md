# PR-0001-devex-windows-doctor

- Proposed title: `chore(devex): add Windows dev docs + doctor scripts`
- Status: Completed

## Goal
Make local setup reproducible for new contributors.

## Deliverables
- docs/development/windows.md
- scripts/doctor.ps1
- .gitattributes for line-ending control

## Planned File Changes
- [edit] `docs/development/windows.md`
- [edit] `scripts/doctor.ps1`
- [add] `.gitattributes`
- [edit] `README.md`

## Dependencies
- PR0000

## Acceptance Criteria
- [x] Scope implemented
- [x] Basic verification/tests added
- [x] Documentation updated if behavior changes

## Notes
- Implemented:
  - `docs/development/windows.md`
  - `scripts/doctor.ps1`
  - `.gitattributes` line-ending policy
  - README development entry updates
- Typical verification:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/doctor.ps1 -SkipFlutterDoctor`
