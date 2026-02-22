# FFI Contracts

This file is the consolidated index for FFI contracts.

## Sources

- Rust API: `crates/lazynote_ffi/src/api.rs`
- Dart generated API: `apps/lazynote_flutter/lib/core/bindings/api.dart`

## v0.1 Contract Sets

1. Single Entry contracts:
   - `docs/api/ffi-contract-v0.1.md`
   - `docs/api/single-entry-contract.md`
2. Notes/tags contracts (PR-0010B):
   - this document section below

## Entry API Notes (PR-0219)

- `entry_search(text, kind?, limit?)`
  - default limit: `10`
  - max limit: `50` (`ENTRY_SEARCH_MAX_LIMIT`)
  - `kind`: optional, case-insensitive `all|note|task|event`
    - `null`/`all` means no type filter
    - blank string is invalid (`invalid_kind`)
  - stable error codes on failure:
    - `invalid_kind` for unsupported `kind` value
    - `db_error` for DB open/bootstrap failures
    - `internal_error` for search execution failures

## Notes/Tags APIs (PR-0010B)

All APIs are use-case level and async.

- `note_create(content)`
- `note_update(atom_id, content)` (full replace)
- `note_get(atom_id)`
- `notes_list(tag?, limit?, offset?)`
- `note_set_tags(atom_id, tags[])` (atomic full replace)
- `tags_list()`

### Response Shape Rules

- Never require UI to parse free-text messages for branching.
- Failure branch must carry stable `error_code`.
- `message` is for diagnostics/display only.

### Notes Payload

- `atom_id`
- `content`
- `preview_text`
- `preview_image`
- `updated_at`
- `tags`

### Pagination

- default limit: `10`
- max limit: `50`
- ordering: `updated_at DESC, uuid ASC`

### Tag Semantics

- normalized lowercase storage
- case-insensitive match
- v0.1 filter is single-tag equality (`tag = X`)

## Error Code Mapping (Notes/Tags)

Producer: `crates/lazynote_ffi/src/api.rs`

- `invalid_note_id`
- `invalid_tag`
- `note_not_found`
- `db_busy`
- `db_error`
- `invalid_argument`
- `internal_error`

See full registry: `docs/api/error-codes.md`.

## Notes UI Shell Alignment (Flutter-only, PR-0205A)

This PR only adjusts Flutter presentation behavior in Notes UI.

- no Rust FFI API added/removed/renamed
- no generated Dart binding shape change
- no response payload or workspace-tree contract change
- no error-code contract change

## Notes Explorer Recursive Lazy UI (Flutter-only, PR-0205)

This PR consumes existing workspace-tree APIs and does not change FFI shape.

- no Rust FFI API added/removed/renamed
- no generated Dart binding shape change
- no new stable error-code namespace
- uses existing `workspace_list_children` response contract for lazy tree branches
- `Uncategorized` is a Flutter synthetic root folder id (`__uncategorized__`):
  - controller intercepts this parent id locally and must not forward it to Rust FFI
  - Rust `workspace_list_children(parent_node_id)` still only accepts `null` or UUID parent ids
  - synthetic child composition:
    - root-level `note_ref` rows are rendered under `Uncategorized`
    - notes with no workspace `note_ref` anywhere are rendered as legacy items
    - notes already referenced in workspace folders are not duplicated
  - root presentation requirement:
    - root folder list remains folder-only in UI projection
    - root `note_ref` visibility is owned by `Uncategorized` projection (single source)
  - explorer ordering transition freeze (PR-0207B; runtime alignment in PR-0207C):
    - root projection: synthetic `Uncategorized` first, then folders by name ascending
      (case-insensitive), tie-break `node_id ASC`
    - normal folder children: `folder` group first, `note_ref` group second
    - within each group: name ascending (case-insensitive), tie-break `node_id ASC`
    - `Uncategorized` note rows: `updated_at DESC`, then `atom_id ASC`
    - same-parent manual reorder is not a UI contract capability in this transition
- bridge exception policy:
  - when bridge is unavailable (e.g. test host without Rust init), controller may
    use deterministic synthetic fallback
  - other exceptions are surfaced as explicit error envelopes so UI can render
    error + retry
- UI callback semantics:
  - single click -> emit open-note intent callback
  - explorer optional double-click callback -> emit pinned-open intent callback
    (default second-click path is pin-only)
  - `open + pin` is only used when target is not opened yet
  - explorer double-click remains source intent only; preview replacement and
    persist policy is tab-model owned
    (`docs/releases/v0.2/prs/PR-0205B-explorer-tab-open-intent-migration.md`)
  - current v0.2 tab strip semantics:
    - single tap on tab = activate
    - rapid second tap on same tab = pin preview tab (stop replacement)
  - deterministic preview/pinned replace/persist behavior is owned by tab model
    (`docs/releases/v0.3/prs/PR-0304-tab-preview-pinned-model.md`)

## Notes Split Layout v1 (Flutter-only, PR-0206)

This PR updates Flutter-side workspace split interaction only.

- no Rust FFI API added/removed/renamed
- no generated Dart binding shape change
- no new FFI stable error-code namespace
- split command result handling is local to Flutter runtime:
  - `WorkspaceSplitResult.ok`
  - `WorkspaceSplitResult.paneNotFound`
  - `WorkspaceSplitResult.maxPanesReached`
  - `WorkspaceSplitResult.directionLocked`
  - `WorkspaceSplitResult.minSizeBlocked`
- split guard constants are local UI/runtime policy:
  - `maxPaneCount = 4`
  - `minPaneExtent = 200`
- active-pane focus command (`notes_next_pane_button`) and split command
  buttons are UI-only interactions and do not call new FFI endpoints
  directly

## Split Pane Unsplit/Merge (Flutter-only, PR-0206B)

This PR extends Flutter-side split workflow with explicit pane close/merge.

- no Rust FFI API added/removed/renamed
- no generated Dart binding shape change
- no new FFI stable error-code namespace
- close-pane command result handling is local to Flutter runtime:
  - `WorkspaceMergeResult.ok`
  - `WorkspaceMergeResult.singlePaneBlocked`
  - `WorkspaceMergeResult.paneNotFound`
- merge policy is local runtime behavior:
  - target pane: previous sibling, or next when closing first pane
  - closed-pane tabs are appended to target in deterministic order
  - active note is preserved when possible after merge
- close-pane command entry (`notes_close_pane_button`) is UI-only interaction
  and does not call new FFI endpoints directly

## Notes Explorer Context Actions Baseline (Flutter-only, PR-0207 M1)

This milestone extends explorer interactions while reusing existing contracts.

- no Rust FFI API added/removed/renamed
- no generated Dart binding shape change
- no new FFI stable error-code namespace
- uses existing workspace/note APIs for action execution:
  - folder create: `workspace_create_folder(parent_node_id?, name)`
  - note create in folder: `note_create(content)` + `workspace_create_note_ref(parent_node_id?, atom_id, display_name?)`
  - rename (folder-only in v0.2 policy): `workspace_rename_node(node_id, new_name)`
  - move: `workspace_move_node(node_id, new_parent_id?, target_order?)`
- UI-local guard rules (M1 frozen):
  - synthetic root `__uncategorized__` is not renameable/movable/deletable
  - `note_ref` rows are not renameable in v0.2 (title comes from atom projection)
  - right-click blank area provides create actions
  - row context menu takes precedence over blank-area context menu on the same gesture target
  - folder row right-click hit area is row-wide (icon/text/row whitespace), and
    should not fall through to blank-area menu
  - default Notes side-panel slot must forward context callbacks via slot keys:
    - `notes_on_create_note_in_folder_requested`
    - `notes_on_rename_node_requested`
    - `notes_on_move_node_requested`
      - M1/menu path: `(node_id, new_parent_node_id)` (`target_order = null`)
      - M2/drag baseline path: `(node_id, new_parent_node_id, {target_order})`
      - PR-0207B transition freeze target: parent-change-only move, UI path uses
        `target_order = null`
  - move uses minimal target-parent dialog (drag reorder is M2)
  - explorer refresh must preserve expand/collapse state after actions
  - successful child-folder delete must refresh affected parent branch to avoid stale child rows
  - successful child-folder rename must refresh affected parent branch to avoid stale labels
  - synthetic `Uncategorized` note row labels follow controller title projection (draft-aware)
  - dissolve mapping: root-level note refs are rendered under synthetic `Uncategorized`;
    promoted child folders stay as root folders

---

## Workspace Tree APIs (PR-0203 + PR-0221)

All APIs are use-case level and async.

### API Set

- `workspace_list_children(parent_node_id?) -> WorkspaceListChildrenResponse`
  - `parent_node_id = null` lists root-level nodes.
- `workspace_create_folder(parent_node_id?, name) -> WorkspaceNodeResponse`
- `workspace_create_note_ref(parent_node_id?, atom_id, display_name?) -> WorkspaceNodeResponse`
- `workspace_rename_node(node_id, new_name) -> WorkspaceActionResponse`
- `workspace_move_node(node_id, new_parent_id?, target_order?) -> WorkspaceActionResponse`
  - backend compatibility behavior:
    - `target_order` is normalized by clamp in current core behavior
    - `< 0` -> `0`
    - `> sibling_count` -> append at tail
  - UI transition freeze (PR-0207B): same-parent reorder is not exposed; UI move
    requests are parent-change-only and pass `target_order = null`
- `workspace_delete_folder(node_id, mode) -> WorkspaceActionResponse`
  - `mode`: `dissolve` | `delete_all`

UI policy freeze (v0.2):

- `workspace_rename_node` remains generic at API level, but Notes Explorer only exposes rename for `folder` rows.
- `note_ref` rename/editable alias is deferred to v3+ to avoid title-source ambiguity.

### Workspace Node Payload

`WorkspaceNodeItem`:

- `node_id`
- `kind` (`folder|note_ref`)
- `parent_node_id`
- `atom_id`
- `display_name`
- `sort_order` (backend compatibility ordering key; no direct same-parent reorder UI contract)

Envelope rules:

- all workspace responses keep deterministic `ok/error_code/message`
- `WorkspaceNodeResponse` carries optional `node`
- `WorkspaceListChildrenResponse` carries `items`

### Error Code Mapping (Workspace Tree)

Producer: `crates/lazynote_ffi/src/api.rs`

- `invalid_node_id`
- `invalid_parent_node_id`
- `invalid_atom_id`
- `invalid_display_name`
- `invalid_delete_mode`
- `node_not_found`
- `parent_not_found`
- `node_not_folder`
- `parent_not_folder`
- `atom_not_found`
- `atom_not_note`
- `cycle_detected`
- `db_busy`
- `db_error`
- `internal_error`

Detailed contract: `docs/api/workspace-tree-contract.md`.

### Controller-Local Error Codes (Workspace Tree UI)

Producer: `apps/lazynote_flutter/lib/features/notes/notes_controller.dart`

These codes are generated by Flutter controller guard paths and are not emitted
from Rust FFI:

- `busy` - reject overlapping folder create/delete action while one is already in flight
- `save_blocked` - reject folder delete when pre-delete draft flush fails

See full registry: `docs/api/error-codes.md`.

---

## Tasks/Status APIs (PR-0011A, v0.1.5)

All APIs are use-case level and async.

### New Response Types

**`AtomListItem`** — full atom projection for section queries:

- `atom_id: String` — stable UUID
- `kind: String` — `"note"` | `"task"` | `"event"` (rendering hint)
- `content: String` — markdown body
- `preview_text: String?` — derived plain-text summary
- `preview_image: String?` — derived first image path
- `tags: Vec<String>` — normalized lowercase tags
- `start_at: i64?` — epoch ms
- `end_at: i64?` — epoch ms
- `task_status: String?` — `"todo"` | `"in_progress"` | `"done"` | `"cancelled"` | null
- `updated_at: i64` — epoch ms

**`AtomListResponse`** — envelope for section list queries:

- `ok: bool` — execution success flag
- `error_code: String?` — stable machine-readable error code
- `items: Vec<AtomListItem>` — result list
- `message: String` — human-readable status text
- `total_count: u32?` — total matching records (before pagination)

**Migration note**: `notes_list` and `tags_list` will migrate from `NoteItem`/`NotesListResponse`
to `AtomListItem`/`AtomListResponse` in v0.2 when list views are unified. Both type families
coexist until then.

### Section Queries

- `tasks_list_inbox() -> AtomListResponse`
  - Returns atoms with `start_at IS NULL AND end_at IS NULL` and active status
  - Order: `updated_at DESC, uuid ASC`

- `tasks_list_today(bod_ms: i64, eod_ms: i64) -> AtomListResponse`
  - `bod_ms`: beginning of today (00:00:00 local, epoch ms)
  - `eod_ms`: end of today (23:59:59 local, epoch ms)
  - Returns atoms active today per time-matrix logic
  - Order: `COALESCE(start_at, end_at) ASC, updated_at DESC`

- `tasks_list_upcoming(eod_ms: i64) -> AtomListResponse`
  - `eod_ms`: end of today (lower bound for future atoms)
  - Returns atoms entirely in the future
  - Order: `COALESCE(start_at, end_at) ASC, updated_at DESC`

Time parameters are computed by Flutter (device-local timezone). Rust Core does not
compute device-local time.

### Status Update

- `atom_update_status(atom_id: String, status: Option<String>) -> EntryActionResponse`
  - `status`: `"todo"` | `"in_progress"` | `"done"` | `"cancelled"` | `null`
  - `null` clears `task_status` (demote to statusless atom)
  - Idempotent: setting the same status twice is not an error
  - Applies to any atom type (universal completion — see PR-0011 §D1)

### Response Shape Rules

Same rules as Notes/Tags:
- Never require UI to parse free-text messages for branching.
- Failure branch must carry stable `error_code`.
- `message` is for diagnostics/display only.

### Error Code Mapping (Tasks/Status)

Producer: `crates/lazynote_ffi/src/api.rs`

- `invalid_atom_id` — atom_id format invalid (non-UUID)
- `atom_not_found` — target atom missing or soft-deleted
- `invalid_status` — status string not in allowed set
- `db_error` — repository/database failure
- `internal_error` — unexpected invariant failure

See full registry: `docs/api/error-codes.md`.

---

## Calendar APIs (PR-0012A)

All APIs are use-case level and async.

### Range Query

- `calendar_list_by_range(start_ms: i64, end_ms: i64, limit?: u32, offset?: u32) -> AtomListResponse`
  - Returns atoms with both `start_at` and `end_at` set that overlap the given time range
  - Overlap condition: `start_at < end_ms AND end_at > start_ms`
  - Includes all statuses (done/cancelled shown on calendar)
  - Order: `start_at ASC, end_at ASC`
  - Reuses `AtomListResponse` / `AtomListItem` types from tasks APIs
  - Default limit: `50`, max: `50`

### Event Time Update

- `calendar_update_event(atom_id: String, start_ms: i64, end_ms: i64) -> EntryActionResponse`
  - Updates only `start_at` and `end_at` for a calendar event
  - Validates `end_ms >= start_ms`; returns `invalid_time_range` error code on failure
  - Returns `atom_not_found` when target atom does not exist or is soft-deleted
  - Does not modify content, tags, or task_status — time adjustment is an independent operation

### Error Code Mapping (Calendar)

Producer: `crates/lazynote_ffi/src/api.rs`

- `invalid_time_range` — end_at < start_at in event time update
- `invalid_atom_id` — atom_id format invalid (non-UUID)
- `atom_not_found` — target atom missing or soft-deleted
- `db_error` — repository/database failure

See full registry: `docs/api/error-codes.md`.
