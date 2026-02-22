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
4. Read paths follow hybrid visibility policy.
   - invalid/dangling `note_ref` entries are filtered from default child listing.
5. `workspace_delete_folder` requires explicit mode.
   - `dissolve`
   - `delete_all`
6. `workspace_move_node` keeps shape compatibility for `target_order`.
7. Core currently normalizes non-null `target_order` by clamping to visible sibling range.
   - `< 0` -> `0`
   - `> sibling_count` -> append at tail (`sibling_count`)
8. v0.2 transition UI policy (PR-0207B freeze): same-parent reorder is not supported in Explorer.
   - UI-originated move is parent-change-only
   - UI passes `target_order = null` (runtime alignment lands in PR-0207C)
9. API-layer rename is generic (`workspace_rename_node`), but v0.2 Notes UI policy only exposes rename on `folder` rows.
10. Root-level note refs may be rendered by Flutter under synthetic `Uncategorized`; this is a UI projection, not a core schema node.
11. v0.2 `Uncategorized` projection requirements.
   - include root-level `note_ref` + legacy notes with no workspace reference
   - do not duplicate notes already referenced under workspace folders
   - avoid rendering the same root `note_ref` both at root and under `Uncategorized`
12. Notes Explorer ordering freeze (PR-0207B; runtime alignment in PR-0207C).
   - root projection: synthetic `Uncategorized` first, then folders by name ascending
     (case-insensitive), tie-break `node_id ASC`
   - normal folder children: `folder` group first, `note_ref` group second
   - within each group: name ascending (case-insensitive), tie-break `node_id ASC`
   - `Uncategorized` note rows: `updated_at DESC`, then `atom_id ASC`
13. Note rows in Explorer are title-only in v0.2 transition policy; preview text is not rendered.

## Error Codes

See canonical registry: `docs/api/error-codes.md` (Workspace Tree section).
