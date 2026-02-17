# PR-0221-workspace-tree-delete-policy-hybrid

- Proposed title: `feat(workspace-core): hybrid delete policy for note and folder`
- Status: Planned

## Goal

Adopt a hybrid delete policy for workspace tree:

- note delete uses C-style behavior (allow dangling `note_ref`, filter on read)
- folder delete uses explicit user choices (`dissolve` or `delete_all`)

This improves UX while keeping policy explicit and testable.

## Scope (v0.2)

In scope:

- switch note-delete semantics from strict blocking (A) to filtered visibility (C)
- define folder delete actions with two explicit options
- centralize visibility filtering in repository layer
- add maintenance path for dangling `note_ref` cleanup
- sync docs and API error semantics

Out of scope:

- provider sync conflict policy for dangling references
- cross-device merge strategy for tree delete races
- permanent hard-delete compaction policy

## Product Rules

### 1. Delete single note (referenced by workspace tree)

- do not block delete
- soft-delete note atom (`atoms.is_deleted = 1`)
- keep existing `workspace_nodes.note_ref` rows (dangling allowed)
- repository read paths hide invalid `note_ref` automatically
- if note is restored later, original references become visible again

### 2. Delete folder (group)

Two user-facing options:

1. `dissolve` (keep content)
   - soft-delete folder node
   - move its direct children to root (`parent_uuid = NULL`)
   - keep descendants otherwise unchanged
2. `delete_all` (remove group content from workspace, and optionally notes)
   - soft-delete folder subtree references in workspace
   - soft-delete corresponding atoms only when they have no other active references
   - if atom still has active references elsewhere, keep atom active

### 3. Unclassified behavior

- root level (`parent_uuid = NULL`) is the unclassified area
- no dedicated physical folder entity is required

### 4. Multi-reference notes

- operations only affect references inside target folder scope
- references in other folders remain active and visible
- no global atom delete if active references still exist

### 5. Maintenance task

- dangling `note_ref` cleanup is deferred to maintenance task (prune)
- `VACUUM` remains optional and decoupled from delete hot path

## Core Design Changes

1. Add migration `0008_workspace_tree_delete_policy.sql`:
   - remove/replace strict atom-side blocking triggers added by `0007`
   - keep schema shape unchanged
2. Repository layer:
   - `list_children` and related tree reads must filter invalid `note_ref`
   - filtering predicate:
     - `kind='folder'` always visible if active
     - `kind='note_ref'` visible only when joined atom is active note
3. Service layer:
   - add folder delete APIs with explicit mode:
     - `delete_folder_dissolve(folder_id)`
     - `delete_folder_delete_all(folder_id)`
4. Maintenance:
   - add prune entrypoint for dangling references
   - no mandatory prune on every write

## API/FFI Impact

- Add explicit delete mode to folder delete contract:
  - `mode = dissolve | delete_all`
- Note delete no longer returns "referenced-blocked" error
- Document restored note behavior for dangling references

## Step-by-Step

1. Add migration `0008` and register it.
2. Refactor tree repository read queries to centralized filtering.
3. Implement folder delete modes in core service/repository.
4. Update FFI contracts and error-code mapping.
5. Add tests for note delete/restore visibility and folder modes.
6. Add prune workflow tests and docs.
7. Update architecture/release/API docs.

## Planned File Changes

- [add] `crates/lazynote_core/src/db/migrations/0008_workspace_tree_delete_policy.sql`
- [edit] `crates/lazynote_core/src/db/migrations/mod.rs`
- [edit] `crates/lazynote_core/src/repo/tree_repo.rs`
- [edit] `crates/lazynote_core/src/service/tree_service.rs`
- [edit] `crates/lazynote_core/tests/workspace_tree.rs`
- [edit] `crates/lazynote_ffi/src/api.rs`
- [edit] `docs/architecture/data-model.md`
- [edit] `docs/architecture/note-schema.md`
- [edit] `docs/api/error-codes.md`
- [edit] `docs/releases/v0.2/README.md`

## Verification

- `cd crates && cargo fmt --all -- --check`
- `cd crates && cargo clippy --all -- -D warnings`
- `cd crates && cargo test -p lazynote_core`
- `cd crates && cargo test -p lazynote_ffi`
- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test`

## Acceptance Criteria

- [ ] Deleting a referenced note is not blocked.
- [ ] Dangling `note_ref` is hidden in all tree read paths.
- [ ] Restored notes re-appear via original references.
- [ ] Folder delete supports `dissolve` and `delete_all` with deterministic behavior.
- [ ] Multi-reference notes are not accidentally deleted by folder operations.
- [ ] Docs and API contracts match shipped behavior.
