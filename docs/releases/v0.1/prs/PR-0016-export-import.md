# PR-0016-export-import

- Proposed title: `feat(portability): export/import Markdown + JSON + ICS`
- Status: Deferred (post-v0.1)

## Goal

Provide baseline portability and local backup/restore.

## Deferral Reason

v0.1 has been narrowed to notes-first + diagnostics-readability closure (`PR-0010C2/C3/C4/D`, `PR-0017A`).
This PR remains a post-v0.1 backlog candidate.

## Architecture Note (Atom Time-Matrix, v0.1.5+)

All import/export must map between external formats and the Atom time-matrix fields:

**Markdown import (`[ ]` syntax):**
- `- [ ] content` → `kind = task`, `task_status = 'todo'`, no time fields (Inbox).
- `- [x] content` → `kind = task`, `task_status = 'done'`.
- Time expressions in content are **not** auto-parsed to `end_at` in v0.1.5; they remain
  as raw text. Automated time extraction is deferred to v0.2+.

**ICS export mapping (atoms → iCalendar):**
- `[Value, Value]` → `VEVENT` (DTSTART = `start_at`, DTEND = `end_at`)
- `[NULL, Value]` → `VTODO` with `DUE = end_at`
- `[Value, NULL]` → `VTODO` with `DTSTART = start_at`, no DUE
- `[NULL, NULL]` → `VTODO` with no time fields, or excluded from ICS output

**ICS import mapping (iCalendar → atoms):**
- `VEVENT` → `kind = event`, `start_at = DTSTART`, `end_at = DTEND`
- `VTODO` with `DUE` → `kind = task`, `end_at = DUE`, `start_at = NULL`
- `VTODO` with `DTSTART` only → `kind = task`, `start_at = DTSTART`, `end_at = NULL`
- `STATUS:COMPLETED` → `task_status = 'done'`; `STATUS:CANCELLED` → `task_status = 'cancelled'`

Finalize and document these mappings in `docs/api/ffi-contracts.md` before implementation.

## Scope (post-v0.1 backlog)

In scope:

- export Markdown/JSON/ICS
- import JSON/Markdown/ICS baseline
- post-import index rebuild

Out of scope:

- merge wizard UI
- partial conflict resolution UI
- encrypted backup format

## Optimized Phases

Phase A (Export First):

- implement export modules and tests
- expose export APIs via FFI
- add minimal UI entry

Phase B (Import + Reindex):

- implement import parsers and validation
- implement transactional import + reindex
- add end-to-end tests

## Step-by-Step

1. Define export/import API contract and error mapping.
2. Implement export modules (`markdown/json/ics`) in core.
3. Add export tests (format validity + deterministic output baseline).
4. Expose export FFI APIs and regenerate bindings.
5. Implement import modules with validation guards.
6. Add transactional import flow and rollback behavior on failure.
7. Trigger FTS/index rebuild after successful import.
8. Add import tests (happy path + malformed input + partial failure).
9. Add backup/restore UI page in settings.
10. Update product scope docs.
11. Run full quality gates.

## Planned File Changes

- [add] `crates/lazynote_core/src/export/mod.rs`
- [add] `crates/lazynote_core/src/export/markdown.rs`
- [add] `crates/lazynote_core/src/export/json.rs`
- [add] `crates/lazynote_core/src/export/ics.rs`
- [add] `crates/lazynote_core/src/import/mod.rs`
- [edit] `crates/lazynote_ffi/src/api.rs`
- [add] `apps/lazynote_flutter/lib/features/settings/backup_restore_page.dart`
- [edit] `docs/product/mvp-scope.md`

## Dependencies

- PR0006, PR0007, PR0010, PR0011, PR0012

## Quality Gates

- `cargo fmt --all -- --check`
- `cargo clippy --all -- -D warnings`
- `cargo test --all`
- `flutter analyze`
- `flutter test`

## Acceptance Criteria

- [ ] Export outputs are valid and re-importable
- [ ] Import is transactional and rebuilds search index
- [ ] Backup/restore entry is available in settings
- [ ] API/product docs updated for user-facing behavior
