# PR-0208-workspace-hardening-doc-closure

- Proposed title: `chore(workspace): hardening, regression coverage, and doc closure`
- Status: In Progress (M1/M2 completed, M3 pending)

## Goal

Close v0.2 with explicit hardening regression proof, race-safe workspace behavior, and synchronized docs/contracts.

## Scope (v0.2)

In scope:

- race-condition hardening around pane/tab/buffer transitions
- recovery behavior for FFI `db_error` and stale async responses
- integration tests for explorer + split + editor interaction
- closure docs for release/API/architecture consistency

Out of scope:

- recursive split UX (v0.3)
- long-document performance gates (v0.3)

## Regression Matrix (Bridge PR Replay)

PR-0208 re-verifies findings from PR-0204 / PR-0219 / PR-0220A / PR-0220B after full v0.2 integration.

| Source | Target | Existing Coverage | PR-0208 Action |
|--------|--------|-------------------|----------------|
| PR-0204 R02-1.1 | Draft source must be `buffersByNoteId` | `apps/lazynote_flutter/test/workspace_provider_test.dart` | keep green in replay bundle |
| PR-0204 R02-1.2 | save retry bounded and non-hanging | `apps/lazynote_flutter/test/workspace_provider_test.dart` | add integration race case in `workspace_integration_flow_test.dart` |
| PR-0204 R02-1.3 | closed-tab tag queue must not dispatch FFI | `apps/lazynote_flutter/test/workspace_provider_test.dart` | keep green in replay bundle |
| PR-0219 R01-4 | `journal_mode=WAL` after migrations | migration tests exist, WAL assertion missing | add migration replay WAL assertion in `crates/lazynote_core/tests/db_migrations.rs` |
| PR-0219 R01-5 | `entry_search` stable error codes only | `crates/lazynote_ffi/src/api.rs` tests exist | replay + add explicit regression assertion if needed |
| PR-0220A R02-3.3 | no double `dlopen` after init failure | `apps/lazynote_flutter/test/rust_bridge_test.dart` | keep green in replay bundle |
| PR-0220B R02-2.1 | `loggingLevelOverride` applies at startup bootstrap | `apps/lazynote_flutter/test/rust_bridge_test.dart` | keep green in replay bundle |

## Milestones

### M1 - Regression Codification (now)

1. Add missing replay assertions:
   - WAL mode survives migration chain replay.
   - workspace integration race test (save + pane switching + explorer mutation path baseline).
2. Build one deterministic replay command bundle and record expected outputs.
3. Update PR-0208 checklist to reflect covered/remaining items.

M1 progress:

- [x] WAL replay assertion added: `crates/lazynote_core/tests/db_migrations.rs`
- [x] workspace integration race bundle added: `apps/lazynote_flutter/test/workspace_integration_flow_test.dart`
- [x] bridge regression suites replayed (`cargo test -p lazynote_ffi`, targeted flutter suites)
- [ ] finalize one consolidated replay evidence block in this PR note

### M2 - Runtime Hardening Pass

1. Audit stale async response handling in `NotesController`:
   - list/detail/tag request-id guards
   - save in-flight vs pane switch/close
2. Tighten user-visible recovery:
   - keep existing `SnackBar + Retry` behavior explicit on workspace operations
   - ensure no destructive fallback when FFI returns `db_error`/`db_busy`
3. Add regression tests for any bugfix introduced in this pass.

M2 progress:

- [x] workspace mutation failures now carry actionable retry guidance for `db_busy` / `db_error`
- [x] non-destructive failure regressions added (failed move/delete does not mutate active note/tree revision)
- [x] stale detail-response regression added (late response cannot override newer active note)
- [x] complete remaining audit sweep for notes/workspace core async branches (list/detail/tag/save/workspace mutation paths)

### M3 - Doc Closure and Release Gate

1. Sync docs:
   - `docs/releases/v0.2/README.md`
   - `docs/api/*` (only if contract behavior changed)
   - architecture note updates if state invariants are clarified
2. Execute full replay bundle and capture pass summary.
3. Mark PR-0208 completed with evidence links/commands.

## Detailed Execution Steps

1. Run baseline replay on current branch to detect real gaps before patching.
2. Patch tests first (regression locking), then patch runtime behavior only if tests expose gaps.
3. Re-run targeted suites, then expand to full rust/flutter gates.
4. Close docs only after code/test state is stable.

## Planned File Changes

- [edit] `crates/lazynote_core/tests/db_migrations.rs`
- [add] `apps/lazynote_flutter/test/workspace_integration_flow_test.dart`
- [edit] `apps/lazynote_flutter/lib/features/workspace/*` (if M2 finds race gaps)
- [edit] `apps/lazynote_flutter/lib/features/notes/*` (if M2 finds race gaps)
- [edit] `docs/releases/v0.2/README.md`
- [edit] `docs/releases/v0.2/prs/PR-0208-workspace-hardening-doc-closure.md`
- [edit] `docs/api/*` only if runtime contract actually changes

## Verification Bundle

Rust:

- `cd crates && cargo test -p lazynote_core --test db_migrations`
- `cd crates && cargo test -p lazynote_ffi`

Flutter targeted:

- `cd apps/lazynote_flutter && flutter test test/workspace_provider_test.dart test/notes_controller_workspace_bridge_test.dart test/workspace_integration_flow_test.dart test/rust_bridge_test.dart`

Flutter full gate:

- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test`

Manual smoke (Windows):

- split pane switch while save is pending
- explorer create/rename/move while active editor has unsaved content
- retry path after simulated workspace mutation failure

## Execution Evidence (M1/M2)

- `cd crates && cargo test -p lazynote_core --test db_migrations` (pass, includes WAL replay assertion)
- `cd crates && cargo test -p lazynote_ffi` (pass)
- `cd apps/lazynote_flutter && flutter test test/workspace_integration_flow_test.dart` (pass)
- `cd apps/lazynote_flutter && flutter test test/workspace_provider_test.dart test/notes_controller_workspace_bridge_test.dart test/rust_bridge_test.dart` (pass)
- `cd apps/lazynote_flutter && flutter test` (pass)
- `cd apps/lazynote_flutter && flutter analyze` (pass)

## Acceptance Criteria

- [x] Core workspace interactions are regression-covered.
- [x] Error handling is actionable and non-destructive.
- [ ] Release docs and API docs match shipped behavior.
- [x] Bridge-lane regression matrix (0204/0219/0220A/0220B) has explicit replay evidence.
