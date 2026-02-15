# PR-0014-local-task-calendar-projection

- Proposed title: `feat(calendar-core): local task-calendar projection baseline`
- Status: Deferred (post-v0.1, replanned to v0.3 core calendar track)

## Goal

Deliver a provider-agnostic local calendar core baseline:

- local task <-> calendar projection rules
- deterministic local sync behavior between task state and calendar blocks

## Deferral Reason

v0.1 has been narrowed to notes-first + diagnostics-readability closure (`PR-0010C2/C3/C4/D`, `PR-0017A`).
This PR is replanned as v0.3 local calendar core (`PR-0308`) before external providers.

## Architecture Note (Atom Time-Matrix, v0.1.5+)

Under the unified Atom model, tasks and calendar events share the `atoms` table.
"Projection" does **not** require a separate entity table:

- `start_at`/`end_at` on atoms are the canonical time fields.
- Status propagation (`done`/`cancelled`) is already handled by the section query filter.
- A `calendar_projection` migration + repo is only justified if a **separate derived
  cache table** is needed for calendar-specific rendering (e.g., pre-expanded recurrence
  instances for `recurrence_rule`). This decision must be made at implementation time
  and documented in an ADR; do not add a projection table by default.
- If no recurrence expansion is needed, the calendar view should query `atoms` directly.

## Scope (post-v0.1 backlog)

In scope:

- task due/start/end mapping to local calendar event blocks (via `start_at`/`end_at`)
- status propagation rules (complete/reopen/cancel)
- local conflict rules and deterministic tie-breakers
- local query/update APIs for calendar views

Out of scope:

- Google Calendar auth/pull/push
- provider token store and refresh pipeline
- multi-provider arbitration

## Optimized Phases

Phase A (Projection Rules + Data Model):

- define local projection schema and invariants
- implement mapping and propagation rules
- add repository/service tests for projection stability

Phase B (Calendar Core APIs + UI Hook):

- expose query/update APIs via FFI
- connect minimal calendar view usage path
- add summary/error DTOs for UI state

## Step-by-Step

1. Define task-calendar projection contract in API docs.
2. Add or adjust local schema for projection mapping.
3. Implement projection engine and propagation rules.
4. Add tests for complete/reopen/update projection behavior.
5. Expose calendar-core APIs via FFI and regenerate bindings.
6. Connect minimal Flutter calendar view query path.
7. Add regression tests for local projection consistency.
8. Run quality gates and update release docs.

## Planned File Changes

- [add/edit] `crates/lazynote_core/src/service/calendar_projection_service.rs`
- [add/edit] `crates/lazynote_core/src/repo/calendar_projection_repo.rs`
- [add/edit] `crates/lazynote_core/src/db/migrations/*calendar_projection*.sql`
- [edit] `crates/lazynote_ffi/src/api.rs`
- [add/edit] `apps/lazynote_flutter/lib/features/calendar/*`

## Dependencies

- PR0011, PR0012
- PR-0215-provider-spi-and-sync-contract (contract alignment only; no provider runtime dependency)

## Quality Gates

- `cargo fmt --all -- --check`
- `cargo clippy --all -- -D warnings`
- `cargo test --all`
- `flutter analyze`
- `flutter test`

## Acceptance Criteria

- [ ] Local task state and calendar projection remain consistent after updates.
- [ ] Calendar core APIs are provider-agnostic.
- [ ] Regression tests cover local projection and conflict tie-break behavior.
- [ ] API docs are updated without introducing provider-specific coupling.
