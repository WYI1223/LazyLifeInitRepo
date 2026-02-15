# v0.1.5 Release Plan

## Purpose

v0.1.5 is a focused intermediate release between v0.1 (notes-first stable loop) and v0.2
(workspace UI + tree). Its strategic goal is to land the **Atom Time-Matrix** data layer before
v0.2 builds its folder/workspace UI on top of it.

## Strategic Intent

- Complete the **bottom half** of time-aware atoms (schema + Core + FFI + basic UI).
- v0.2 inherits `start_at`/`end_at`/`recurrence_rule` and a working section query engine
  without needing another migration cycle.
- Keeps v0.2 focused purely on folder/tree UI and multi-pane workspace, not data model.

## Scope

**One PR only:**

- `PR-0011` — Atom Time-Matrix, Inbox/Today/Upcoming sections, complete/reopen

**In scope:**
- Migration 6: rename `event_start`→`start_at`, `event_end`→`end_at`; add `recurrence_rule`
- Task service with section query logic (Inbox / Today / Upcoming SQL)
- `atom_complete` / `atom_reopen` use-cases
- FFI surface for the above + updated response envelopes
- Flutter tasks page (three sections, checkbox toggle, pull-to-refresh)

**Out of scope:**
- RRULE calculation engine (`recurrence_rule` is schema-only, no logic)
- Calendar view (v0.2+)
- Drag-to-reorder within sections (v0.2)
- Time-picker UI for setting `start_at`/`end_at` from Flutter (v0.2)

## Execution Gate

`PR-0017A` (v0.1 debug viewer readability baseline) must be completed before v0.1.5 work begins.

## Execution Order

1. `PR-0017A` — close v0.1 (debug viewer readability)
2. `PR-0011` — v0.1.5 (atom time-matrix + tasks sections)

## Quality Gates

- `cargo fmt --all -- --check`
- `cargo clippy --all -- -D warnings`
- `cargo test --all`
- `flutter analyze`
- `flutter test`

## Exit Criteria

v0.1.5 is complete when PR-0011 merges with all acceptance criteria checked. At that point:

1. The `atoms` table has `start_at`, `end_at`, `recurrence_rule` columns.
2. A working Inbox/Today/Upcoming view exists in the app.
3. Existing note and search flows continue to pass.
4. v0.2 can begin without any data model migration blockers.

## PR Specs

- `docs/releases/v0.1/prs/PR-0011-tasks-views.md`

## References

- `docs/architecture/data-model.md` — Atom Time-Matrix model and section SQL
- `docs/releases/v0.1/README.md` — v0.1 exit state
- `docs/releases/v0.2/README.md` — v0.2 starts after v0.1.5 closes
