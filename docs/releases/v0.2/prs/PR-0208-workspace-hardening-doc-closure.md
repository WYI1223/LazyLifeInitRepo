# PR-0208-workspace-hardening-doc-closure

- Proposed title: `chore(workspace): hardening, regression coverage, and doc closure`
- Status: Planned

## Goal

Close v0.2 with reliability polish, regression tests, and documentation synchronization.

## Scope (v0.2)

In scope:

- race-condition hardening around pane/tab/buffer transitions
- recovery behavior for FFI `db_error` and stale async responses
- integration tests for explorer + split + editor interaction
- docs closure for architecture and API changes

Out of scope:

- recursive split UX (v0.3)
- long-document performance gate (v0.3)

## Regression Targets from Pre-Feature Hardening PRs

The following items were addressed in PR-0219/0220A/0220B and by design in PR-0204.
PR-0208 must include regression confirmation that they survive the full v0.2 refactor:

| Source | Finding | Verification |
|--------|---------|-------------|
| PR-0204 design constraint (R02-1.2) | Save coordinator has bounded retry (≤ 5) | test: save-failure + concurrent typing does not block tab close indefinitely |
| PR-0204 design constraint (R02-1.1) | Draft buffer always from `buffersByNoteId` | test: tab/pane switch renders last-typed content, not server snapshot |
| PR-0204 design constraint (R02-1.3) | Closed-tab tag mutations do not fire FFI | test: close tab → pending tag queue → FFI call count = 0 |
| PR-0219 (R01-4 WAL) | `journal_mode=WAL` survives new migrations | `PRAGMA journal_mode;` = `wal` after all v0.2 migrations applied |
| PR-0219 (R01-5 error codes) | `entry_search` uses stable codes | no `"db_open_failed"` / `"search_failed"` in test assertions |
| PR-0220A (R02-3.3) | No double `dlopen` on FRB init failure | `rustLibInit` invoked ≤ 1 time even with concurrent callers after failure |
| PR-0220B (R02-2.1) | `loggingLevelOverride` applied on startup | settings override value flows through `bootstrapLogging` in integration |

## Step-by-Step

1. Audit async state races in workspace provider.
2. Add integration tests for:
   - pane switching during save
   - tree refresh during open tabs
   - move/rename under active note
3. Harden error recovery UX (`SnackBar + Retry` paths).
4. Verify all regression targets from the table above.
5. Update release and architecture docs.

## Planned File Changes

- [edit] `apps/lazynote_flutter/lib/features/workspace/*`
- [edit] `apps/lazynote_flutter/lib/features/notes/*`
- [add] `apps/lazynote_flutter/test/workspace_integration_flow_test.dart`
- [edit] `docs/architecture/overview.md`
- [edit] `docs/architecture/note-schema.md`
- [edit] `docs/api/*` (if contract deltas exist)
- [edit] `docs/releases/v0.2/README.md`

## Verification

- `cd crates && cargo test --all`
- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test`
- manual Windows smoke for split/explorer/error-retry paths

## Acceptance Criteria

- [ ] Core workspace interactions are regression-covered.
- [ ] Error handling is actionable and non-destructive.
- [ ] Release docs and API docs match shipped behavior.

