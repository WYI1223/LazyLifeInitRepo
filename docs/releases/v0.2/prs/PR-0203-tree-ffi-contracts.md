# PR-0203-tree-ffi-contracts

- Proposed title: `feat(ffi): workspace tree API contracts and envelopes`
- Status: In Progress (M1-M3 implemented; awaiting code review)

## Goal

Expose tree operations through stable FFI contracts for Flutter workspace UI,
aligned with the hybrid delete policy from `PR-0221`.

## Scope (v0.2)

In scope:

- use-case-level tree APIs (no SQL internals)
- response envelopes with stable `ok/error_code/message`
- parent-based child listing for lazy explorer rendering
- folder delete contract with explicit mode (`dissolve | delete_all`)
- hybrid visibility semantics documentation (invalid `note_ref` filtered on read)
- contract docs and compatibility policy updates

Out of scope:

- streaming watch APIs
- sync-provider specific tree APIs
- database maintenance scheduler/orchestrator (only API hooks if needed)

## Candidate API Set

- `workspace_list_children(parent_node_id?)`
- `workspace_create_folder(parent_node_id?, name)`
- `workspace_create_note_ref(parent_node_id?, atom_id, display_name?)`
- `workspace_rename_node(node_id, new_name)`
- `workspace_move_node(node_id, new_parent_id?, target_order?)`
- `workspace_delete_folder(node_id, mode)` where `mode in {dissolve, delete_all}`

Rules:

- keep API names use-case oriented
- keep error codes stable and machine-branchable
- keep list contract deterministic without cursor pagination in v0.2
- folder delete modes must be explicit and deterministic
- tree read responses include only visible nodes per core hybrid policy

## Step-by-Step

1. Finalize API contract against `PR-0221` policy decisions.
2. Implement FFI wrappers over core tree service.
3. Define typed DTOs in generated Dart bindings.
4. Add unit tests for envelope and error-code mapping.
5. Update `docs/api/*` and compatibility policy docs.
6. Regenerate FRB bindings.

## Execution Plan (M1-M3)

### M1. Contract Freeze + Rust FFI Surface

1. Add missing FFI APIs over `TreeService`:
- `workspace_list_children(parent_node_id?)`
- `workspace_create_folder(parent_node_id?, name)`
- `workspace_create_note_ref(parent_node_id?, atom_id, display_name?)`
- `workspace_rename_node(node_id, new_name)`
- `workspace_move_node(node_id, new_parent_id?, target_order?)`
2. Keep existing `workspace_delete_folder(node_id, mode)` unchanged for compatibility.
3. Reuse stable envelope style (`ok/error_code/message`) and introduce tree DTO payloads.
4. Add error mapping coverage for invalid UUID/input/semantic errors.

### M2. Flutter Binding + Contract Docs

1. Regenerate Flutter bindings and verify generated wrappers are callable.
2. Update:
- `docs/api/ffi-contracts.md`
- `docs/api/error-codes.md`
- `docs/api/workspace-tree-contract.md` (new detailed contract doc)
3. Ensure docs clearly distinguish:
- Rust FFI error codes
- Flutter controller-local guard codes

### M3. Integration Baseline + Regression

1. Add/extend FFI tests in `crates/lazynote_ffi/src/api.rs`.
2. Add Flutter-side contract smoke tests (at least one call path for create/list/move/rename).
3. Run release gates for touched scopes and record results in PR notes.

## Current Decisions (locked)

1. `PR-0203` first closes Workspace Tree FFI parity gap; UI feature expansion remains in `PR-0204/0205/0207`.
2. `entry_search(kind)` is tracked as next follow-up after `PR-0203` M1 completion.
3. No streaming/watch API in v0.2; request/response only.
4. `workspace_list_children` in v0.2 does not expose `limit/cursor`; pagination is follow-up scope.

## Planned File Changes

- [edit] `crates/lazynote_ffi/src/api.rs`
- [edit] `apps/lazynote_flutter/lib/core/bindings/api.dart` (generated)
- [edit] `apps/lazynote_flutter/lib/core/bindings/frb_generated.dart` (generated)
- [edit] `apps/lazynote_flutter/lib/core/bindings/frb_generated.io.dart` (generated)
- [edit] `docs/api/ffi-contracts.md`
- [add] `docs/api/workspace-tree-contract.md`
- [edit] `docs/api/error-codes.md`
- [edit] `docs/governance/API_COMPATIBILITY.md`

## Verification

- `cd crates && cargo fmt --all -- --check`
- `cd crates && cargo check -p lazynote_ffi`
- `cd crates && cargo test -p lazynote_ffi`
- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test`

## Acceptance Criteria

- [x] Tree APIs are callable from Flutter with stable envelopes.
- [x] Folder delete mode contract (`dissolve | delete_all`) is callable and test-covered.
- [x] Error codes are documented and test-covered.
- [x] API docs guard passes with updated contracts.
- [x] Missing Workspace CRUD FFI parity gap is closed for v0.2.
