# PR-0011-tasks-views

- Proposed title: `feat(tasks): atom time-matrix, Inbox/Today/Upcoming sections, universal status update`
- Status: Complete (v0.1.5)
- Source: v0.1 backlog; redesigned with Atom Time-Matrix model
- Split: two sub-PRs (PR-0011A backend, PR-0011B frontend)

## Goal

Deliver the first working time-aware view layer on top of the unified Atom model. After this PR,
users can see all their atoms classified into three sections by time-field logic, and update
atom status (complete, reopen, demote) directly from the list.

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

## Design Decisions (v0.1.5 Pre-Implementation)

The following decisions were made during pre-implementation review and differ from the
original draft spec:

### D1: Universal Completion

Any atom type can have its `task_status` updated — not just tasks.

- For `task`: complete means "check off".
- For `note`: complete means "archived / processed".
- For `event`: complete means "attended / done".

Setting `task_status = null` demotes the atom back to a statusless state (effectively a plain note).

### D2: `atom_update_status` replaces `atom_complete` / `atom_reopen`

A single generic FFI function `atom_update_status(atom_id, status)` replaces the original
two-function design. The `status` parameter accepts:

- `"todo"` — (re)open
- `"in_progress"` — mark as in-progress
- `"done"` — complete
- `"cancelled"` — cancel
- `null` — demote (clear status, revert to statusless atom)

This avoids needing new FFI functions when additional status transitions are needed.

### D3: New `AtomListItem` / `AtomListResponse` types

Tasks section queries return atoms with time and status metadata. The existing `EntryListItem`
does not carry `start_at`, `end_at`, or `task_status`. Rather than extending the existing type
(which would be a breaking change to its semantics), new types are introduced:

- `AtomListItem`: `atom_id`, `kind`, `content`, `preview_text`, `preview_image`, `tags`, `start_at`, `end_at`, `task_status`, `updated_at`
- `AtomListResponse`: `ok`, `error_code`, `items: Vec<AtomListItem>`, `message`, `total_count`

**Migration plan for existing endpoints**: `notes_list` and `tags_list` currently return
`EntryListResponse` / `NoteItem`. These will be migrated to `AtomListResponse` / `AtomListItem`
in v0.2 when the workspace UI unifies all list views. Until then, both type families coexist.

### D4: Frontend-driven time parameters

Section queries receive time boundaries from Flutter (device-local timezone):

- `tasks_list_inbox()` — no time params needed (timeless atoms)
- `tasks_list_today(bod_ms, eod_ms)` — beginning/end of day in epoch ms
- `tasks_list_upcoming(eod_ms)` — end of day as lower bound

Rust Core does not compute device-local time; Flutter is responsible for timezone resolution.

### D5: Defensive FTS trigger rebuild in Migration 6

Migration 6 explicitly DROPs and re-CREATEs the three FTS sync triggers from Migration 4,
rather than relying on SQLite's automatic column-reference update during `ALTER TABLE RENAME COLUMN`.
This ensures correctness across all SQLite versions and avoids silent breakage.

## Sub-PR Split

### PR-0011A — Backend (Rust Core + FFI)

**Migration 6 (`0006_time_matrix.sql`)**:
- Rename `event_start` → `start_at`
- Rename `event_end` → `end_at`
- Add `recurrence_rule TEXT` (nullable; no logic in this PR — reserved for v0.2+)
- DROP + re-CREATE FTS triggers with updated column references (defensive)
- Register in `crates/lazynote_core/src/db/migrations/mod.rs`

**Atom model update** (`crates/lazynote_core/src/model/atom.rs`):
- Rename fields: `event_start` → `start_at`, `event_end` → `end_at`
- Add `recurrence_rule: Option<String>`
- Update `Atom::validate()`: keep `end_at >= start_at` constraint
- Update `AtomDe` deserialization struct
- Update all references in repo, service, and test code

**AtomRepository trait extension** (`crates/lazynote_core/src/repo/atom_repo.rs`):
- `fetch_inbox() -> RepoResult<Vec<Atom>>`
- `fetch_today(bod_ms: i64, eod_ms: i64) -> RepoResult<Vec<Atom>>`
- `fetch_upcoming(eod_ms: i64) -> RepoResult<Vec<Atom>>`
- `update_status(id: AtomId, status: Option<TaskStatus>) -> RepoResult<()>`

**Task service** (`crates/lazynote_core/src/service/task_service.rs`, new file):
- `list_inbox() -> Vec<Atom>`
- `list_today(bod_ms, eod_ms) -> Vec<Atom>`
- `list_upcoming(eod_ms) -> Vec<Atom>`
- `update_status(id, status: Option<TaskStatus>) -> RepoResult<()>` — idempotent

**New FFI types** (`crates/lazynote_ffi/src/api.rs`):
- `AtomListItem { atom_id, kind, content, preview_text, preview_image, tags, start_at, end_at, task_status, updated_at }`
- `AtomListResponse { ok, error_code, items: Vec<AtomListItem>, message, total_count }`

**FFI additions** (`crates/lazynote_ffi/src/api.rs`):
- `tasks_list_inbox() -> AtomListResponse`
- `tasks_list_today(bod_ms: i64, eod_ms: i64) -> AtomListResponse`
- `tasks_list_upcoming(eod_ms: i64) -> AtomListResponse`
- `atom_update_status(atom_id: String, status: Option<String>) -> EntryActionResponse`

Run `scripts/gen_bindings.ps1` after FFI additions.

**Tests:**
- Migration 6 applies cleanly (existing + fresh DB)
- Section query correctness (atoms in right sections given specific time values)
- `update_status` idempotency (same status twice = no error)
- `update_status` with `null` clears status
- Existing note/search tests continue to pass

### PR-0011B — Frontend (Flutter UI)

**`lib/features/tasks/tasks_controller.dart`** (new):
- ChangeNotifier with injectable FFI invokers for testability
- Holds `inbox`, `today`, `upcoming` lists with independent phase/error state per section
- Calls FFI on load with device-local BOD/EOD computed from `DateTime.now()`
- Calls `atom_update_status` on toggle action
- Immediate item removal on toggle (no optimistic rollback — item removed client-side after successful FFI call)
- `createInboxItem(content)` — inline creation via `entry_create_note`, then reloads inbox section

**`lib/features/tasks/tasks_section_card.dart`** (new):
- Reusable card widget with `TasksSectionType` enum (inbox/today/upcoming)
- Three row variants: `_InboxRow` (bullet + text), `_TodayRow` (checkbox + text), `_UpcomingRow` (text + date badge)
- Loading/error/empty states, optional `headerTrailing` and `listHeader` slots

**`lib/features/tasks/tasks_style.dart`** (new):
- Semantic theme token functions — all colors via `Theme.of(context).colorScheme.*`
- Zero hardcoded `Color(0xFF...)` values (dark mode ready)
- Layout constants: `kTasksCardRadius`, `kTasksCardGap`, `kTasksCardElevation`

**`lib/features/tasks/tasks_page.dart`** (new):
- Three equal-width cards in `IntrinsicHeight` + `Row` + `Expanded` layout
- Header with back button + title + reload button
- Inbox card has `+` button toggling inline `TextField` for note creation

**Route wiring** (`lib/features/entry/entry_shell_page.dart`):
- Replaced Tasks placeholder with `TasksPage` widget
- Changed button label from `'Tasks (Placeholder)'` to `'Tasks'`

**`test/tasks_page_test.dart`** (new):
- 5 widget tests: renders three cards, error state, toggle removes item, inline create, reload button
- Uses injectable invokers pattern with `TasksController(prepare: ..., inboxInvoker: ...)`

**`test/smoke_test.dart`** (updated):
- Updated tasks route test to expect real `TasksPage` instead of placeholder

## Planned File Changes

PR-0011A:
- [add] `crates/lazynote_core/src/db/migrations/0006_time_matrix.sql`
- [edit] `crates/lazynote_core/src/db/migrations/mod.rs`
- [edit] `crates/lazynote_core/src/model/atom.rs` — field rename + recurrence_rule
- [edit] `crates/lazynote_core/src/repo/atom_repo.rs` — field name updates + new trait methods
- [edit] `crates/lazynote_core/src/repo/note_repo.rs` — field name updates
- [edit] `crates/lazynote_core/src/service/atom_service.rs` — field name updates
- [edit] `crates/lazynote_core/src/service/note_service.rs` — field name updates
- [add] `crates/lazynote_core/src/service/task_service.rs`
- [edit] `crates/lazynote_ffi/src/api.rs` — new types + FFI functions
- [regen] `crates/lazynote_ffi/src/frb_generated.rs` — codegen (do not edit manually)
- [regen] `apps/lazynote_flutter/lib/core/bindings/api.dart` — codegen (do not edit manually)
- [edit] existing Rust test files — field name updates
- [add] new Rust tests for section queries + status update

PR-0011B:
- [add] `apps/lazynote_flutter/lib/features/tasks/tasks_controller.dart`
- [add] `apps/lazynote_flutter/lib/features/tasks/tasks_section_card.dart`
- [add] `apps/lazynote_flutter/lib/features/tasks/tasks_page.dart`
- [add] `apps/lazynote_flutter/lib/features/tasks/tasks_style.dart`
- [edit] `apps/lazynote_flutter/lib/features/entry/entry_shell_page.dart` — wire TasksPage, update button label
- [edit] `apps/lazynote_flutter/test/smoke_test.dart` — update tasks route test
- [add] `apps/lazynote_flutter/test/tasks_page_test.dart`

## Doc Updates (Step 0 — pre-implementation)

- [edit] `docs/releases/v0.1/prs/PR-0011-tasks-views.md` — this file (design decisions)
- [edit] `docs/api/ffi-contracts.md` — new types + functions
- [edit] `docs/api/error-codes.md` — new error codes for tasks/status
- [edit] `docs/governance/API_COMPATIBILITY.md` — note `AtomListResponse` migration timeline
- [edit] `docs/releases/v0.1.5/README.md` — reflect sub-PR split

## Dependencies

- PR-0017A must be complete (v0.1 closure gate) ✅
- PR-0011A must merge before PR-0011B begins
- Migration 6 must be applied before service layer changes

## Verification

```bash
# PR-0011A
cd crates
cargo fmt --all -- --check
cargo clippy --all -- -D warnings
cargo test --all

# PR-0011B
cd apps/lazynote_flutter
flutter analyze
flutter test test/tasks_flow_test.dart
flutter test
```

Manual smoke (Windows):
1. Create a note (no time fields) → appears in Inbox.
2. Set `end_at` = today on a note → moves to Today.
3. Set `end_at` = tomorrow → moves to Upcoming.
4. Call `atom_update_status(id, "done")` → disappears from all sections.
5. Call `atom_update_status(id, "todo")` → reappears in correct section.
6. Call `atom_update_status(id, null)` → status cleared, atom stays in section based on time fields.
7. Verify `recurrence_rule` column exists in DB (`PRAGMA table_info(atoms)`), value is NULL.

## Acceptance Criteria

### PR-0011A
- [x] Migration 6 applies cleanly; `start_at`, `end_at`, `recurrence_rule` columns present.
- [x] FTS triggers explicitly rebuilt; search continues to work after migration.
- [x] Atom model compiles with renamed fields; all existing tests pass.
- [x] `fetch_inbox`, `fetch_today`, `fetch_upcoming` use correct SQL from data-model.md.
- [x] `atom_update_status` is idempotent; `null` clears status.
- [x] `AtomListItem` includes `kind`, `start_at`, `end_at`, `task_status`.
- [x] FFI functions return `AtomListResponse` with correct items.
- [x] `recurrence_rule` field is present in schema; no RRULE logic exists.
- [x] All Rust quality gates pass.

### PR-0011B
- [x] Flutter tasks page shows three sections; atoms appear in correct sections.
- [x] Status toggle updates section membership in UI (immediate removal after FFI success).
- [x] Reload button reloads all sections.
- [x] Empty-state placeholders render for each section.
- [x] All Flutter quality gates pass (130 tests, 0 failures).
