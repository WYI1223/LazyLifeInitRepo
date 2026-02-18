# Workspace Tree Contract (v0.2)

This document defines Flutter-callable workspace tree contracts exposed by
`crates/lazynote_ffi/src/api.rs`.

## APIs

1. `workspace_list_children(parent_node_id?) -> WorkspaceListChildrenResponse`
2. `workspace_create_folder(parent_node_id?, name) -> WorkspaceNodeResponse`
3. `workspace_create_note_ref(parent_node_id?, atom_id, display_name?) -> WorkspaceNodeResponse`
4. `workspace_rename_node(node_id, new_name) -> WorkspaceActionResponse`
5. `workspace_move_node(node_id, new_parent_id?, target_order?) -> WorkspaceActionResponse`
6. `workspace_delete_folder(node_id, mode) -> WorkspaceActionResponse`

## Payloads

### WorkspaceNodeItem

- `node_id: String`
- `kind: String` (`folder|note_ref`)
- `parent_node_id: String?`
- `atom_id: String?`
- `display_name: String`
- `sort_order: i64`

### Envelopes

- `WorkspaceActionResponse`
  - `ok: bool`
  - `error_code: String?`
  - `message: String`
- `WorkspaceNodeResponse`
  - same as action envelope plus `node: WorkspaceNodeItem?`
- `WorkspaceListChildrenResponse`
  - same as action envelope plus `items: WorkspaceNodeItem[]`

## Behavioral Rules

1. All APIs are request/response and async; no watch/stream contract in v0.2.
2. `parent_node_id = null` means root-level operation.
3. `workspace_list_children` returns deterministic ordering from core repository.
4. Read paths follow hybrid visibility policy:
- invalid/dangling `note_ref` entries are filtered from default child listing.
5. `workspace_delete_folder` requires explicit mode:
- `dissolve`
- `delete_all`
6. `workspace_move_node` normalizes `target_order` by clamping to visible sibling range:
- `< 0` -> `0`
- `> sibling_count` -> append at tail (`sibling_count`)

## Error Codes

See canonical registry: `docs/api/error-codes.md` (Workspace Tree section).
