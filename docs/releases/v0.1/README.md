# v0.1 Release Plan

## Scope

v0.1 closes the minimum loop:

- capture notes
- search notes/tasks/events
- edit and schedule tasks
- Google Calendar event sync (incremental, mapped)

## Source

- original draft: `docs/research/init/temp-v0.1-plan.md`

## Optimization Review

The original PR list is valid. We applied these optimizations:

- Keep baseline order: Repo/DevEx -> CI -> FRB -> Core -> UI -> Integrations.
- Split PR0003 into two smaller steps:
  - PR-A: FRB minimal API + codegen/binding artifacts
  - PR-B: Flutter Windows runtime call to `ping/core_version`
- Move global hotkey + floating quick-entry window out of v0.1 to v0.2.
- Split Google Calendar work into two PRs:
  - PR0014: OAuth + one-way bootstrap sync.
  - PR0015: two-way sync with `syncToken` and `extendedProperties` mapping.
- Keep CI early (PR0002) to prevent regressions while FRB/Core/UI are added.

## Execution Order

- PR0000, PR0001, PR0002
- PR0003-A, PR0003-B, PR0004, PR0005
- PR0006, PR0007
- PR0008, PR0009A, PR0009B, PR0009C, PR0009D
- PR0010A, PR0010B, PR0010C, PR0010D
- PR0011, PR0012, PR0012B, PR0013
- PR0014, PR0015, PR0016
- PR0017, PR0018

## PR Specs

See `docs/releases/v0.1/prs/`.

## Current Progress

- Completed: `PR-0000` monorepo scaffold
- Completed: `PR-0001` Windows DevEx + doctor
- Completed: `PR-0002` CI (Flutter Windows + Rust Ubuntu)
- Completed: `PR-0003` FRB wire-up (`ping/core_version`) with Windows smoke UI
- Completed: `PR-0004` Atom model (`Atom` + stable ID + soft delete + serde baseline)
- Completed: `PR-0005` SQLite schema + migrations (`open_db` + versioned migrations + DB smoke tests)
- Completed: `PR-0006` core CRUD (`AtomRepository` + `AtomService` + integration tests)
- Completed: `PR-0007` FTS5 search (`atoms_fts` + trigger sync + core search API/tests)
- Completed: `PR-0008` UI shell (Windows) with Workbench default homepage + placeholder routes
- Completed: `PR-0017` Workbench split-shell with pinned debug logs panel, draggable splitter, and local log tail + copy/open-folder actions
- Completed: `PR-0009A` entry FFI surface (async APIs + structured status envelopes)
- Completed: `PR-0009B` entry parser/state + Workbench-integrated Single Entry panel
- Completed: `PR-0009C` realtime search flow (`onChanged` search + result list rendering + stale-response guard + startup DB-path readiness hardening)
- Completed: `PR-0009D` command execution flow (`new note/task/schedule`)
- Completed: `PR-0010A` unified Single Entry panel UI shell
- Completed: `PR-0010B` notes/tags core + FFI contracts (including markdown preview hook)
- Completed: `PR-0018` API contract docs guard (CI gate for contract/doc sync)
- Next: `PR-0010C` notes/tags Flutter UI integration

Execution note:

- Workbench remains the default homepage and debug log viewer.
- Single Entry is introduced as a Workbench-internal tool (button-triggered), not a homepage replacement.
- Planned transition: `PR-0012B` will promote Single Entry to primary home entry and move Workbench to a secondary menu.

## Optimization Notes (Post-PR0018)

To reduce delivery risk, remaining PRs follow a "core/FFI first, UI second" split strategy:

- PR-0010: notes/tag core contracts first, then notes UI/editor.
- PR-0010A: lock unified single-entry floating panel appearance/behavior before note feature UI.
- PR-0011: task section queries first, then tasks page and interactions.
- PR-0012: calendar scheduling contracts first, then day/week views.
- PR-0012B: switch app home entry from Workbench to Single Entry while preserving diagnostics access path.
- PR-0014 and PR-0015: auth/state foundation before full sync behavior.
- PR-0016: export path first, then import + reindex flow.
