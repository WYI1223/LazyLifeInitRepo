# PR-0011-tasks-views

- Proposed title: `feat(tasks): atom time-matrix, Inbox/Today/Upcoming sections, complete/reopen`
- Status: Planned (v0.1.5)
- Source: v0.1 backlog; redesigned with Atom Time-Matrix model

## Goal

Deliver the first working time-aware view layer on top of the unified Atom model. After this PR,
users can see all their atoms classified into three sections by time-field logic, and toggle
task completion directly from the list.

## Architecture Decision: Atom Time-Matrix

All classification is driven by `start_at`/`end_at` nullability. `type` field is a rendering hint
only and does NOT determine which section an atom appears in.

| start_at | end_at | Semantic | Section membership |
|----------|--------|----------|--------------------|
| NULL | NULL | Pure note / idea | **Inbox** |
| NULL | Value | DDL task | **Today** (overdue/due today) or **Upcoming** |
| Value | NULL | Ongoing task | **Today** (already started) or **Upcoming** |
| Value | Value | Timed event | **Today** (overlaps today) or **Upcoming** |

`task_status IN ('done', 'cancelled')` hides the atom from all sections.

Full SQL specification: `docs/architecture/data-model.md` §Section Query Logic.

## Scope

### Phase A — Schema + Core + FFI

**Migration 6 (`0006_time_matrix.sql`)**:
- Rename `event_start` → `start_at`
- Rename `event_end` → `end_at`
- Add `recurrence_rule TEXT` (nullable; no logic in this PR — reserved for v0.2+)
- Register in `crates/lazynote_core/src/db/migrations/mod.rs`
- Update `docs/architecture/data-model.md` (done in pre-PR docs work)

**Atom model update** (`crates/lazynote_core/src/model/atom.rs`):
- Rename fields: `event_start` → `start_at`, `event_end` → `end_at`
- Add `recurrence_rule: Option<String>`
- Update `Atom::validate()`: keep `end_at >= start_at` constraint
- Update all references in repo, service, and test code

**Task service** (`crates/lazynote_core/src/service/task_service.rs`, new file):
- `fetch_inbox(now_ms: i64) -> Vec<Atom>`
- `fetch_today(bod_ms: i64, eod_ms: i64) -> Vec<Atom>`
- `fetch_upcoming(eod_ms: i64) -> Vec<Atom>`
- `complete_atom(id: AtomId) -> RepoResult<()>` — sets `task_status = 'done'`
- `reopen_atom(id: AtomId) -> RepoResult<()>` — sets `task_status = 'todo'`

**FFI additions** (`crates/lazynote_ffi/src/api.rs`):
- `tasks_list_inbox() -> EntryListResponse`
- `tasks_list_today() -> EntryListResponse`
- `tasks_list_upcoming() -> EntryListResponse`
- `atom_complete(atom_id: String) -> EntryActionResponse`
- `atom_reopen(atom_id: String) -> EntryActionResponse`

Response items must include `start_at`, `end_at`, `task_status` fields so Flutter can render
the appropriate UI form and status indicator.

Run `scripts/gen_bindings.ps1` after FFI additions.

### Phase B — Flutter UI

**`lib/features/tasks/tasks_controller.dart`** (new):
- Holds `inbox`, `today`, `upcoming` lists
- Calls FFI on load and on complete/reopen action
- Optimistic status update + rollback on error

**`lib/features/tasks/task_list_section.dart`** (new):
- Reusable section widget: header label + atom row list
- Atom row renders differently by `type`: checkbox (task), plain text (note), time bar (event)

**`lib/features/tasks/tasks_page.dart`** (new):
- Three `TaskListSection` widgets stacked vertically: Inbox → Today → Upcoming
- Pull-to-refresh triggers full reload
- Empty-state placeholder for each section

**Route wiring** (`lib/app/`):
- Connect `/tasks` placeholder route to `TasksPage`

**`test/tasks_flow_test.dart`** (new):
- Section rendering: correct atoms appear in each section given mocked time
- Toggle: complete sets status, atom disappears from section; reopen restores it

## Planned File Changes

Phase A:
- [add] `crates/lazynote_core/src/db/migrations/0006_time_matrix.sql`
- [edit] `crates/lazynote_core/src/db/migrations/mod.rs`
- [edit] `crates/lazynote_core/src/model/atom.rs` — field rename + recurrence_rule
- [edit] `crates/lazynote_core/src/repo/atom_repo.rs` — field name updates
- [edit] `crates/lazynote_core/src/repo/note_repo.rs` — field name updates
- [edit] `crates/lazynote_core/src/service/note_service.rs` — field name updates
- [add] `crates/lazynote_core/src/service/task_service.rs`
- [edit] `crates/lazynote_ffi/src/api.rs` — new FFI functions
- [edit] `crates/lazynote_ffi/src/frb_generated.rs` — codegen (do not edit manually)
- [edit] `apps/lazynote_flutter/lib/core/bindings/api.dart` — codegen (do not edit manually)
- [edit] `docs/api/ffi-contracts.md`

Phase B:
- [add] `apps/lazynote_flutter/lib/features/tasks/tasks_controller.dart`
- [add] `apps/lazynote_flutter/lib/features/tasks/task_list_section.dart`
- [add] `apps/lazynote_flutter/lib/features/tasks/tasks_page.dart`
- [edit] `apps/lazynote_flutter/lib/app/` — wire `/tasks` route
- [add] `apps/lazynote_flutter/test/tasks_flow_test.dart`

## Dependencies

- PR-0017A must be complete (v0.1 closure gate)
- Migration 6 must be applied before service layer changes

## Verification

```bash
cd crates
cargo fmt --all -- --check
cargo clippy --all -- -D warnings
cargo test --all

cd apps/lazynote_flutter
flutter analyze
flutter test test/tasks_flow_test.dart
flutter test
```

Manual smoke (Windows):
1. Create a note (no time fields) → appears in Inbox.
2. Set `end_at` = today on a note → moves to Today.
3. Set `end_at` = tomorrow → moves to Upcoming.
4. Mark as complete → disappears from all sections.
5. Reopen → reappears in correct section.
6. Verify `recurrence_rule` column exists in DB (`PRAGMA table_info(atoms)`), value is NULL.

## Acceptance Criteria

- [ ] Migration 6 applies cleanly; `start_at`, `end_at`, `recurrence_rule` columns present.
- [ ] Atom model compiles with renamed fields; all existing tests pass.
- [ ] `fetch_inbox`, `fetch_today`, `fetch_upcoming` use correct SQL from data-model.md.
- [ ] `atom_complete` / `atom_reopen` are idempotent.
- [ ] FFI functions return `start_at`, `end_at`, `task_status` in response items.
- [ ] Flutter tasks page shows three sections; atoms appear in correct sections.
- [ ] Complete/reopen toggle updates section membership in UI.
- [ ] `recurrence_rule` field is present in schema; no RRULE logic exists in v0.1.5.
- [ ] All quality gates pass.
