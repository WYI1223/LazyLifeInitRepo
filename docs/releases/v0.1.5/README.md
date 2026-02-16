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

**Two sub-PRs:**

- `PR-0011A` — Backend: Migration 6, Atom model rename, section queries, status update, new FFI types
- `PR-0011B` — Frontend: Tasks page with Inbox/Today/Upcoming sections, status toggle

**In scope:**
- Migration 6: rename `event_start`→`start_at`, `event_end`→`end_at`; add `recurrence_rule`; defensive FTS trigger rebuild
- AtomRepository extension with section queries (`fetch_inbox`, `fetch_today`, `fetch_upcoming`)
- Universal `atom_update_status(id, status)` — any atom type, supports `null` (demote)
- New `AtomListItem` / `AtomListResponse` FFI types
- FFI surface for the above
- Flutter tasks page (three sections, status toggle, pull-to-refresh)

**Out of scope:**
- RRULE calculation engine (`recurrence_rule` is schema-only, no logic)
- Calendar view (v0.2+)
- Drag-to-reorder within sections (v0.2)
- Time-picker UI for setting `start_at`/`end_at` from Flutter (v0.2)
- Migration of `notes_list`/`tags_list` to `AtomListResponse` (v0.2)

## Execution Gate

`PR-0017A` (v0.1 debug viewer readability baseline) must be completed before v0.1.5 work begins. ✅

## Execution Order

1. Step 0: Spec alignment (design decisions documented) ✅
2. `PR-0011A` — Backend (Rust Core + FFI) ✅
3. `PR-0011B` — Frontend (Flutter UI) ✅

## Quality Gates

- `cargo fmt --all -- --check`
- `cargo clippy --all -- -D warnings`
- `cargo test --all`
- `flutter analyze`
- `flutter test`

## Exit Criteria

v0.1.5 is complete when both PR-0011A and PR-0011B merge with all acceptance criteria checked.

All exit criteria met ✅:

1. ✅ The `atoms` table has `start_at`, `end_at`, `recurrence_rule` columns.
2. ✅ FTS triggers are rebuilt and search works correctly.
3. ✅ A working Inbox/Today/Upcoming view exists in the app.
4. ✅ `atom_update_status` supports all transitions including `null` (demote).
5. ✅ Existing note and search flows continue to pass.
6. ✅ v0.2 can begin without any data model migration blockers.

## Design Decisions

Key design decisions documented in `docs/releases/v0.1/prs/PR-0011-tasks-views.md`:

- **D1**: Universal completion (any atom type can be completed/demoted)
- **D2**: `atom_update_status` replaces `atom_complete`/`atom_reopen`
- **D3**: New `AtomListItem`/`AtomListResponse` types (coexist with existing types until v0.2)
- **D4**: Frontend-driven time parameters (Flutter computes BOD/EOD)
- **D5**: Defensive FTS trigger rebuild in Migration 6

## PR Specs

- `docs/releases/v0.1/prs/PR-0011-tasks-views.md`

## Post-v0.1.5 Work

- `PR-0012` Calendar Minimal ✅ — completed immediately after v0.1.5
  - 4 sub-PRs: backend APIs → shell+sidebar → week grid → create/edit interactions
  - See `docs/releases/v0.1/prs/PR-0012-calendar-minimal.md`

## References

- `docs/architecture/data-model.md` — Atom Time-Matrix model and section SQL
- `docs/api/ffi-contracts.md` — New types and function contracts
- `docs/api/error-codes.md` — New error codes for tasks/status
- `docs/governance/API_COMPATIBILITY.md` — AtomListResponse migration timeline
- `docs/releases/v0.1/README.md` — v0.1 exit state
