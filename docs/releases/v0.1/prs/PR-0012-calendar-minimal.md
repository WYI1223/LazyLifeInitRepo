# PR-0012-calendar-minimal

- Proposed title: `feat(calendar): minimal day/week schedule views`
- Status: Deferred (post-v0.1)

## Goal

Deliver a minimal calendar experience that can visualize and create schedules.

## Deferral Reason

v0.1 has been narrowed to notes-first + diagnostics-readability closure (`PR-0010C2/C3/C4/D`, `PR-0017A`).
This PR remains a post-v0.1 backlog candidate.

## Scope (post-v0.1 backlog)

In scope:

- day and week timeline views (minimal blocks)
- create/update schedule window based on `start_at`/`end_at`
- read-only relation to task context (if linked)

Out of scope:

- drag-and-drop rescheduling
- overlapping-event conflict resolver UI
- recurrence editor

## Architecture Note (Atom Time-Matrix, v0.1.5+)

Calendar events are **not a separate entity**. Under the unified Atom model, an "event" is
an atom in the `[Value, Value]` quadrant (`start_at IS NOT NULL AND end_at IS NOT NULL`).

Implications for implementation:

- `event_repo.rs` listed below must NOT create a new table. Replace with a calendar
  query method on `AtomRepository` that filters atoms by `start_at`/`end_at` range overlap.
- `calendar_service.rs` queries the `atoms` table directly; no new migration required for
  event storage.
- Schedule mutation creates/updates atoms with `kind = event`, sets `start_at`/`end_at`;
  `task_status` remains NULL unless explicitly set.
- Calendar view renders atoms whose time ranges overlap the displayed day/week window.

## Optimized Phases

Phase A (Core + FFI):

- add calendar query and schedule mutation APIs (queries `atoms` table, no new entity)
- enforce start/end validation in service boundary (reuses `Atom::validate()`)
- expose FFI APIs and tests

Phase B (Flutter UI):

- add day/week calendar pages
- wire create/update schedule actions
- add widget/smoke tests

## Step-by-Step

1. Define calendar API contract and validation/error mapping.
2. Add event repository/service methods for range query and schedule mutation.
3. Add validation tests (including reversed range rejection).
4. Expose calendar APIs through FFI.
5. Regenerate FRB bindings.
6. Implement calendar controller state.
7. Build minimal day/week timeline views.
8. Add schedule create/update interactions.
9. Add Flutter tests for loading/rendering and schedule mutation feedback.
10. Run full quality gates.
11. Update release progress docs.

## Planned File Changes

- [add] `apps/lazynote_flutter/lib/features/calendar/calendar_page.dart`
- [add] `apps/lazynote_flutter/lib/features/calendar/day_view.dart`
- [add] `apps/lazynote_flutter/lib/features/calendar/calendar_controller.dart`
- [add] `crates/lazynote_core/src/service/calendar_service.rs`
- [add] `crates/lazynote_core/src/repo/event_repo.rs`
- [edit] `crates/lazynote_ffi/src/api.rs`
- [add] `apps/lazynote_flutter/test/calendar_flow_test.dart`

## Dependencies

- PR0006, PR0008, PR0009, PR0011

## Quality Gates

- `cargo fmt --all -- --check`
- `cargo clippy --all -- -D warnings`
- `cargo test --all`
- `flutter analyze`
- `flutter test`

## Acceptance Criteria

- [ ] Day/week views can render schedule blocks
- [ ] Schedule create/update works with validated time ranges
- [ ] API docs and compatibility docs are updated if contract changed
- [ ] Rust + Flutter tests cover baseline behavior
