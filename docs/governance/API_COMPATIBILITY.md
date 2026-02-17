# API Compatibility Policy

This policy defines compatibility rules for public API surfaces.

## Public API Surfaces

The following are treated as compatibility-sensitive:

- Rust FFI exports in `crates/lazynote_ffi/src/api.rs`
- Dart-visible FFI models in `apps/lazynote_flutter/lib/core/bindings/api.dart`
- behavior contracts documented in `docs/api/*.md`

Architecture contract docs are also compatibility-sensitive for internal
integration lanes:

- `docs/architecture/extension-kernel.md` (PR-0213 baseline)

## Breaking Changes

A change is considered breaking when any of the following happens:

- rename/remove an exposed FFI function
- change parameter semantics, units, or requiredness
- change return field semantics (including `ok/error_code` behavior)
- remove or repurpose stable error codes
- change Single Entry behavior boundary (`onChanged` vs `Enter/send`)

## Allowed Non-Breaking Changes

- additive response fields that preserve existing meaning
- additive error codes
- additive commands behind explicit version docs
- internal refactors without contract change

## Change Process

For compatibility-sensitive changes, PR must include:

1. contract delta in `docs/api/*`
2. tests updated for old/new behavior expectations
3. release note update in `docs/releases/`
4. migration guidance if callers must change

For internal architecture contracts (for example extension kernel contracts),
PRs must include:

1. updated architecture contract doc
2. validation/registry tests for changed invariants
3. release plan status sync in `docs/releases/`

## v0.x Practical Rule

In v0.x (pre-v1.0), FFI contracts and error codes may change with documented rationale in the same PR.
Fast iteration is allowed; silent API drift is not.

Stability guarantee starts at **v1.0**: from v1.0 onward, all changes to public API surfaces are subject
to the full breaking-change process above, including migration guidance and release note updates.

## Planned Type Migrations

### `AtomListResponse` / `AtomListItem` (v0.1.5 → v0.2)

v0.1.5 introduces `AtomListItem` and `AtomListResponse` for tasks section queries. These types
carry full atom metadata (`kind`, `start_at`, `end_at`, `task_status`) that the existing
`EntryListItem` / `NoteItem` types do not.

**Coexistence plan (v0.1.5):**
- New tasks APIs use `AtomListResponse` / `AtomListItem`.
- Existing notes APIs continue to use `NoteItem` / `NotesListResponse`.
- Both type families are available simultaneously.

**Migration plan (v0.2):**
- `notes_list` migrates from `NotesListResponse` to `AtomListResponse`.
- `tags_list` response is evaluated for unification.
- Old types are deprecated but not removed until v1.0.
- Migration rationale: unified list views in workspace UI need consistent item shape.

This is a **non-breaking additive change** in v0.1.5 (new types only). The v0.2 migration
of existing endpoints will be documented as a breaking change with migration guidance.

### Calendar APIs (PR-0012A)

Two new FFI functions added as **non-breaking additive changes**:

- `calendar_list_by_range(start_ms, end_ms, limit?, offset?) -> AtomListResponse`
- `calendar_update_event(atom_id, start_ms, end_ms) -> EntryActionResponse`

Both reuse existing response types (`AtomListResponse`, `EntryActionResponse`).

New error code: `invalid_time_range` — additive, no impact on existing callers.
