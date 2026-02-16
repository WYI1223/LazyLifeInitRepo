# v0.1 Release Plan

## Scope

v0.1 is now explicitly notes-first and closes a stable local notes loop, with one targeted diagnostics readability uplift for release QA:

- Single Entry capture/search baseline
- notes list/editor/create/select
- autosave + tag filter
- notes flow hardening + API/doc consistency
- Workbench debug viewer readability baseline (timestamp + severity color)

## Source

- original draft: `docs/research/init/temp-v0.1-plan.md`

## Out of Scope (Moved Post-v0.1)

The following tracks are intentionally moved out of v0.1:

- tasks and calendar feature expansion
- reminders
- Google Calendar OAuth/sync
- export/import portability flows
- home-entry route switch placeholder (`PR-0012B`)

## Execution Order (Finalized v0.1)

- PR0000, PR0001, PR0002
- PR0003-A, PR0003-B, PR0004, PR0005
- PR0006, PR0007
- PR0008, PR0009A, PR0009B, PR0009C, PR0009D
- PR0010A, PR0010B, PR0010C1, PR0010C2, PR0010C3, PR0010C4, PR0010D
- PR0017, PR0017A, PR0018

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
- Completed: `PR-0010C1` notes shell baseline (`NoteExplorer` + `NoteTabManager` + `NoteContentArea`) with fixed left-right split, multi-tab state, and back-to-workbench action
- Completed: `PR-0010C2` note editor + create/select flow
- Completed: `PR-0010C3` note autosave + switch flush
- Completed: `PR-0010C4` tag-filter integration closure
- Completed: `PR-0010D` notes/tags hardening + regression + docs closure
- Completed: `PR-0018` API contract docs guard (CI gate for contract/doc sync)
- Completed: `PR-0017A` debug viewer readability baseline (timestamp column, severity colors, incomplete-line guard)
- Remaining: none — v0.1 is closed

Execution note:

- Workbench remains the default homepage and debug log viewer.
- Single Entry is introduced as a Workbench-internal tool (button-triggered), not a homepage replacement.

## Deferred Backlog (Post-v0.1)

- `PR-0011` tasks views ✅ (v0.1.5)
- `PR-0012` calendar minimal ✅ (post-v0.1.5)
- `PR-0013` reminders (Windows)
- `PR-0014` local task-calendar projection baseline
- `PR-0015` Google Calendar provider plugin track
- `PR-0016` export/import

## Plan Hygiene Notes

- `PR-0012B` was referenced in this file but has no spec file in `docs/releases/v0.1/prs/`.
- To avoid drift, it is removed from v0.1 execution plan.
- If reintroduced, it should be added as a fully specified post-v0.1 PR.

## Optimization Notes (Current)

To reduce risk and lock v0.1 quality:

- Keep remaining work inside `PR-0017A` only.
- Preserve "core/FFI first, UI second" sequencing within notes flow.
- Freeze new feature intake into v0.1 until `PR-0017A` closes.
