# MVP Scope (v0.1)

## Purpose

Define the minimum deliverable product scope for v0.1.

Source of truth for execution order: `docs/releases/v0.1/README.md`.

## Scope Definition

v0.1 is notes-first and closes one stable local notes loop:

- Single Entry capture/search baseline
- notes list/editor/create/select baseline
- debounced autosave + tag filter
- notes flow hardening + API/doc consistency
- Workbench debug viewer readability baseline

## In Scope by Capability

### Foundation (completed)

- monorepo/devex baseline
- CI baseline for Rust + Flutter
- Flutter <-> Rust wire-up
- atom model and validation baseline
- SQLite migrations and repository CRUD
- FTS5 search core
- Windows shell workbench + diagnostics log panel

### Feature loop (remaining in v0.1)

- notes UI closure + diagnostics readability baseline:
  - `PR-0010C2` note editor + create/select
  - `PR-0010C3` autosave + switch flush
  - `PR-0010C4` tag filter integration closure
  - `PR-0010D` hardening and docs closure
  - `PR-0017A` debug viewer readability baseline

## Out of Scope for v0.1

- global hotkey quick entry window (moved to v0.2)
- tasks and calendar feature expansion (moved post-v0.1)
- reminders (moved post-v0.1)
- Google Calendar OAuth/sync (moved post-v0.1)
- export/import portability flow (moved post-v0.1)
- CRDT multi-master sync
- cloud telemetry/analytics pipeline
- advanced AI orchestration features

## Acceptance Criteria (Release-Level)

v0.1 is considered complete when:

1. Single Entry capture/search/command baseline is stable in Workbench.
2. Notes create/select/edit/autosave/filter flow is complete.
3. Notes async/error regression paths are covered (`PR-0010D` closure).
4. Debug viewer readability baseline is available for QA loops (`PR-0017A`).
5. CI and API/doc contracts are synchronized and reproducible.

## Current Progress Snapshot

- Completed:
  - PR-0000 to PR-0009D
  - PR-0010A, PR-0010B, PR-0010C1, PR-0010C2, PR-0010C3, PR-0010C4, PR-0010D
  - PR-0017, PR-0018
- Remaining:
  - PR-0017A

## Deferred Backlog (Post-v0.1)

- `PR-0011` tasks views → **replanned to v0.1.5** (`docs/releases/v0.1.5/README.md`)
- `PR-0012` calendar minimal
- `PR-0013` reminders (Windows)
- `PR-0014` local task-calendar projection baseline
- `PR-0015` Google Calendar provider plugin track
- `PR-0016` export/import

## Verification Baseline

For every in-scope PR:

- quality gates pass (`fmt/analyze/test`)
- smoke flow is reproducible from Windows quickstart
- corresponding release/architecture docs are updated

## References

- `docs/releases/v0.1/README.md`
- `docs/product/milestones.md`
- `docs/product/roadmap.md`
