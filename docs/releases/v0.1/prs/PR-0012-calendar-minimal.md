# PR-0012-calendar-minimal

- Proposed title: `feat(calendar): minimal weekly calendar view with schedule CRUD`
- Status: Complete (post-v0.1.5)
- Source: v0.1 backlog; redesigned with Atom Time-Matrix model
- Split: four sub-PRs (PR-0012A backend, PR-0012B shell+sidebar, PR-0012C grid, PR-0012D interactions)

## Goal

Deliver a minimal weekly calendar experience that visualizes timed atoms and supports
create/edit of schedules. Calendar events are atoms with both `start_at` and `end_at` set —
no new entity or migration needed.

## Design Decisions (Pre-Implementation)

### D1: Week View with table_calendar + Self-Built Grid

`table_calendar` package for mini month sidebar only. Week grid is self-built
using `Stack` + `Positioned` for full visual control. Later evolution to fully custom.

### D2: Hybrid Color Scheme

- Base (container/text/divider): strictly `Theme.of(context).colorScheme.*`
- Event blocks: `CalendarPalette` class with explicit Light/Dark pairs per color
  - Sage: Light `0xFFD6E6CE` / Dark `0xFF2C3E28`
  - Baby Blue: Light `0xFFCBE4F9` / Dark `0xFF1A3A5C`
  - Lavender: Light `0xFFE6D6F5` / Dark `0xFF3D2C52`
  - Red indicator: `0xFFFF5A5F` (both modes)

### D3: Category List Skipped for MVP

Sidebar contains only mini month. Category/source toggles deferred.

### D4: Range Query Reuses AtomListResponse

`calendar_list_by_range` returns `AtomListResponse` (same type as tasks section queries).
No new response type needed.

### D5: Separate Event Time Update API

`calendar_update_event(atom_id, start_ms, end_ms)` is a dedicated FFI function.
Does not mix with `note_update` or `atom_update_status`. Time adjustment is an
independent operation.

### D6: Week Navigation via Header Arrows

Top bar `< >` arrows switch weeks. Mini month date selection also navigates.

## Sub-PR Split

### PR-0012A — Backend: Calendar APIs (Rust Core + FFI)

**Repo layer** (`crates/lazynote_core/src/repo/atom_repo.rs`):
- `fetch_by_time_range(range_start_ms, range_end_ms, limit, offset) -> Vec<SectionAtomRow>`
  - Range overlap: `start_at < range_end AND end_at > range_start`
  - Includes done/cancelled (calendar shows all timed events)
  - Order: `start_at ASC, end_at ASC`
- `update_event_times(id, start_at, end_at) -> RepoResult<()>`
  - Validates `end_at >= start_at`; returns `RepoError::Validation(InvalidEventWindow)` on failure
  - Returns `NotFound` when `changed == 0` (covers both missing and soft-deleted atoms)

**Service layer** (`crates/lazynote_core/src/service/task_service.rs`):
- Extend `TaskService` with `fetch_by_time_range` (+ tag enrichment) and `update_event_times`

**FFI layer** (`crates/lazynote_ffi/src/api.rs`):
- `calendar_list_by_range(start_ms, end_ms, limit?, offset?) -> AtomListResponse`
- `calendar_update_event(atom_id, start_ms, end_ms) -> EntryActionResponse`
- New error code: `invalid_time_range`

**Tests:**
- Range overlap correctness (overlapping, non-overlapping, boundary)
- Done events included in range query
- Update validates reversed range
- Update not-found
- Update success (times changed + updated_at advanced)

Run `scripts/gen_bindings.ps1` after FFI additions.

### PR-0012B — Frontend: Calendar Shell + Sidebar

**Dependencies:** Add `table_calendar: ^3.1.0` to `pubspec.yaml`

**New files:**
- `lib/features/calendar/calendar_style.dart` — `CalendarPalette` (L/D pairs) + semantic base colors + layout constants
- `lib/features/calendar/calendar_controller.dart` — `CalendarController` (ChangeNotifier, injectable invokers, week navigation, loadWeek)
- `lib/features/calendar/calendar_sidebar.dart` — Mini month via `TableCalendar`, day selection → week navigation
- `lib/features/calendar/calendar_page.dart` — Unified card container (borderRadius 24, shadow), header with `< >` navigation, sidebar + placeholder

**Route wiring:**
- Add `calendar` to `WorkbenchSection` enum
- Add `CalendarPage` case in `_buildActiveLeftContent`
- Add Calendar button in workbench home
- Add `/calendar` to `routes.dart`

**Tests:**
- `test/calendar_page_test.dart` — renders shell, week navigation, error state
- `test/smoke_test.dart` — calendar route reachable from workbench

### PR-0012C — Frontend: Week Grid View

**New files:**
- `lib/features/calendar/week_grid_view.dart` — Self-built week grid (Stack + Positioned)
  - Time axis (0:00–23:00), 7 day columns, grid lines
  - Event block positioning by `start_at`/`end_at` → top/height calculation
  - Current time red indicator line
  - `ClipRRect` for rounded corner scrolling
- `lib/features/calendar/event_block.dart` — Pastel-colored block with `CalendarPalette`

**Update:** Replace placeholder in `calendar_page.dart` with `WeekGridView`

**Tests:** `test/week_grid_view_test.dart` — day headers, event positioning, current time indicator

### PR-0012D — Frontend: Create/Edit Interaction

**New file:**
- `lib/features/calendar/calendar_event_dialog.dart` — Create/edit dialog with title + time pickers

**Updates:**
- `CalendarController` — add `createEvent()` (uses `entry_schedule`), `updateEvent()` (uses `calendar_update_event`)
- `WeekGridView` — add `onEmptySlotTap`, `onEventTap` callbacks
- `CalendarPage` — wire dialog open/close + controller calls

**Tests:**
- `test/calendar_event_dialog_test.dart` — create/edit fields, submit/cancel
- Update `test/calendar_page_test.dart` — create/edit triggers reload

## Planned File Changes

PR-0012A:
- [edit] `crates/lazynote_core/src/repo/atom_repo.rs` — +2 trait methods + impl
- [edit] `crates/lazynote_core/src/service/task_service.rs` — +2 service methods
- [edit] `crates/lazynote_ffi/src/api.rs` — +2 FFI functions, +1 error variant, +5 tests
- [regen] `crates/lazynote_ffi/src/frb_generated.rs`
- [regen] `apps/lazynote_flutter/lib/core/bindings/api.dart`

PR-0012B:
- [edit] `apps/lazynote_flutter/pubspec.yaml` — add `table_calendar`
- [add] `apps/lazynote_flutter/lib/features/calendar/calendar_style.dart`
- [add] `apps/lazynote_flutter/lib/features/calendar/calendar_controller.dart`
- [add] `apps/lazynote_flutter/lib/features/calendar/calendar_sidebar.dart`
- [add] `apps/lazynote_flutter/lib/features/calendar/calendar_page.dart`
- [edit] `apps/lazynote_flutter/lib/features/entry/entry_shell_page.dart` — add calendar routing
- [edit] `apps/lazynote_flutter/lib/app/routes.dart` — add `/calendar`
- [add] `apps/lazynote_flutter/test/calendar_page_test.dart`
- [edit] `apps/lazynote_flutter/test/smoke_test.dart` — add calendar route test

PR-0012C:
- [add] `apps/lazynote_flutter/lib/features/calendar/week_grid_view.dart`
- [add] `apps/lazynote_flutter/lib/features/calendar/event_block.dart`
- [edit] `apps/lazynote_flutter/lib/features/calendar/calendar_page.dart` — replace placeholder
- [add] `apps/lazynote_flutter/test/week_grid_view_test.dart`

PR-0012D:
- [add] `apps/lazynote_flutter/lib/features/calendar/calendar_event_dialog.dart`
- [edit] `apps/lazynote_flutter/lib/features/calendar/calendar_controller.dart` — add create/edit
- [edit] `apps/lazynote_flutter/lib/features/calendar/week_grid_view.dart` — add tap callbacks
- [edit] `apps/lazynote_flutter/lib/features/calendar/calendar_page.dart` — wire interactions
- [add] `apps/lazynote_flutter/test/calendar_event_dialog_test.dart`
- [edit] `apps/lazynote_flutter/test/calendar_page_test.dart` — add interaction tests

## Doc Updates (per sub-PR)

PR-0012A:
- [edit] `docs/api/error-codes.md` — add `invalid_time_range`
- [edit] `docs/api/ffi-contracts.md` — add calendar function specs
- [edit] `docs/governance/API_COMPATIBILITY.md` — note new FFI functions

PR-0012 completion:
- [edit] `docs/releases/v0.1/prs/PR-0012-calendar-minimal.md` — this file (mark complete)
- [edit] `CLAUDE.md` — add calendar features

## Dependencies

- PR-0011 (v0.1.5) ✅ — provides `start_at`/`end_at` schema + `AtomListResponse` types
- PR-0012A must complete before PR-0012B (Dart bindings needed)
- PR-0012B must complete before PR-0012C (shell + controller needed)
- PR-0012C must complete before PR-0012D (grid + event blocks needed)

## Verification

```bash
# PR-0012A
cd crates
cargo fmt --all -- --check
cargo clippy --all -- -D warnings
cargo test --all

# PR-0012B/C/D
cd apps/lazynote_flutter
flutter analyze
flutter test
```

## Acceptance Criteria

### PR-0012A ✅
- [x] `fetch_by_time_range` returns overlapping atoms (including done/cancelled)
- [x] `update_event_times` validates end >= start
- [x] `update_event_times` returns not-found for missing/deleted atom
- [x] FFI functions return correct response types
- [x] New error code `invalid_time_range` registered
- [x] All Rust quality gates pass (98 tests)

### PR-0012B ✅
- [x] Calendar button visible on workbench home
- [x] CalendarPage renders with unified card container + sidebar
- [x] Mini month sidebar renders via `table_calendar`
- [x] Week navigation `< >` changes displayed week
- [x] Selecting a day in mini month navigates to that week
- [x] All Flutter quality gates pass (135 tests)

### PR-0012C ✅
- [x] Week grid renders 7 day columns with date headers
- [x] Time axis shows hour labels (0:00–23:00)
- [x] Event blocks positioned at correct vertical offset based on `start_at`/`end_at`
- [x] Current time red indicator line visible on today's column
- [x] Grid scrollable vertically with ClipRRect rounded corners
- [x] All Flutter quality gates pass (140 tests)

### PR-0012D ✅
- [x] Clicking empty time slot opens create dialog
- [x] Clicking event block opens edit dialog with pre-filled values
- [x] Create calls `entry_schedule` and reloads week
- [x] Edit calls `calendar_update_event` and reloads week
- [x] Dialog validates title not empty and end >= start
- [x] All Flutter quality gates pass (148 tests)

## Post-Merge Code Review

Community code review conducted after all four sub-PRs completed. 8 items raised (3 P1, 5 P2).

### Adopted Fixes (3)

**P1-1: `update_event_times` silently succeeds on soft-deleted atoms** — Fixed.
- `atom_repo.rs`: The `changed == 0 && !atom_exists(...)` guard allowed soft-deleted atoms to
  pass through (atom_exists does not filter `is_deleted`). Changed to unconditional `changed == 0`
  → `NotFound`, matching `update_atom_status` behavior.

**P1-2: `_showEditDialog` null force-unwrap on `startAt`** — Fixed.
- `calendar_page.dart`: Added defensive `if (item.startAt == null || item.endAt == null) return;`
  guard before force-unwrap. Functionally safe in current call graph (grid filters null times),
  but prevents crash if method is called from a different path in the future.

**P2-1: `_weekLabel` format wrong across month boundaries** — Fixed.
- `calendar_page.dart`: Added end month name when `start.month != end.month`.
  Before: "Feb 23 – 1, 2026". After: "Feb 23 – Mar 1, 2026".

### Rejected Items (3)

**P1-3: `weekEnd` getter off by one day** — Rejected (reviewer error).
- Reviewer claimed Monday + 6 = Saturday. Actual: Monday + 6 = Sunday (correct).
  Doc comment says "Sunday (end)" and the test confirms "Feb 9 – 15" for a Mon–Sun week.

**P2-3: Dialog end time stricter than backend** — Rejected (intentional).
- Dialog enforces `endMs > startMs` (strictly greater); backend allows equality.
  Zero-duration events have no visual representation on the grid (height = 0).
  UI strictness is correct for the calendar use case.

**P2-4: CLAUDE.md still says `entry_schedule` is stub** — Rejected (already fixed).
- The word "stub" was removed from CLAUDE.md during the PR-0012 documentation pass.

### Deferred Items (2)

**P2-2: Fixed `SizedBox(height: 600)` for the card** — Deferred to v0.2.
- CalendarPage lives inside `WorkbenchShellLayout` which wraps content in `SingleChildScrollView`,
  making `Expanded` unusable. Proper fix requires shell-level refactor.

**P2-6: `EntryActionResponse` missing `error_code` field** — Deferred to v0.2.
- Known limitation of v0.1 envelope design. All single-item mutation operations share
  `EntryActionResponse {ok, atom_id, message}`. Adding `error_code` would affect all callers.
  Planned for v0.2 response type unification.

### Quality Gates (Post-Review)

- `cargo fmt --all -- --check` ✅
- `cargo clippy --all -- -D warnings` ✅
- `cargo test --all` ✅ (98 tests)
- `flutter analyze` ✅
- `flutter test` ✅ (148 tests)
