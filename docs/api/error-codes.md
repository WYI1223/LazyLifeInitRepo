# Error Codes (v0.1)

This file defines stable error codes that UI should branch on.

## Rules

- Prefer branching by code, not by message text.
- `message` is for display and diagnostics, not control flow.
- New codes must be added here in the same PR.

## Entry Search (FFI)

Producer: `crates/lazynote_ffi/src/api.rs`

| Code | Meaning | Typical Cause | UI Handling |
| --- | --- | --- | --- |
| `db_error` | entry DB cannot be opened | invalid path, permissions, IO failure | show inline error, keep input |
| `internal_error` | search execution failed | SQL/FTS query failure | show inline error, keep input |

## Notes/Tags (FFI)

Producer: `crates/lazynote_ffi/src/api.rs`

| Code | Meaning | Typical Cause | UI Handling |
| --- | --- | --- | --- |
| `invalid_note_id` | note id format invalid | non-UUID `atom_id` | show validation error, keep input |
| `invalid_tag` | invalid tag value | blank or malformed tag input | show validation error, keep input |
| `note_not_found` | target note missing | stale/deleted id | show not-found state and refresh list |
| `db_busy` | repository/database is temporarily locked | concurrent writer/reader lock contention | show retry affordance and keep user input |
| `db_error` | repository/database failure | sqlite/schema/io issue | show error and allow retry |
| `invalid_argument` | input violates contract | unsupported argument/value | show validation error, keep input |
| `internal_error` | unexpected invariant failure | read-back mismatch or unexpected state | show error and allow retry |

## Command Parser (Flutter)

Producer: `apps/lazynote_flutter/lib/features/entry/command_parser.dart`

| Code | Meaning | Typical Input | UI Handling |
| --- | --- | --- | --- |
| `missing_prefix` | command missing `>` prefix | `new note x` | parse error state |
| `empty_command` | command body is empty | `>` | parse error state |
| `unknown_command` | unsupported command keyword | `> remind x` | parse error state |
| `note_content_empty` | note content missing | `> new note` | parse error state |
| `task_content_empty` | task content missing | `> task` | parse error state |
| `schedule_format_invalid` | schedule input format invalid | `> schedule tomorrow x` | parse error state |
| `schedule_title_empty` | schedule title missing | malformed schedule text | parse error state |
| `schedule_datetime_invalid` | date/time parse failed | invalid date/time values | parse error state |
| `schedule_range_invalid` | range end is not after start | `10:45-09:30` | parse error state |

## Tasks/Status (FFI) — v0.1.5

Producer: `crates/lazynote_ffi/src/api.rs`

| Code | Meaning | Typical Cause | UI Handling |
| --- | --- | --- | --- |
| `invalid_atom_id` | atom id format invalid | non-UUID `atom_id` | show validation error |
| `atom_not_found` | target atom missing | stale/deleted id | show not-found state and refresh list |
| `invalid_status` | status value not in allowed set | typo or unsupported status string | show validation error |
| `db_error` | repository/database failure | sqlite/schema/io issue | show error and allow retry |
| `internal_error` | unexpected invariant failure | read-back mismatch or unexpected state | show error and allow retry |

## Calendar (FFI) — PR-0012A

Producer: `crates/lazynote_ffi/src/api.rs`

| Code | Meaning | Typical Cause | UI Handling |
| --- | --- | --- | --- |
| `invalid_time_range` | end_at < start_at in event time update | reversed time range input | show validation error |
| `invalid_atom_id` | atom id format invalid | non-UUID `atom_id` | show validation error |
| `atom_not_found` | target atom missing | stale/deleted id | show not-found state and refresh |
| `db_error` | repository/database failure | sqlite/schema/io issue | show error and allow retry |

## Workspace Tree (FFI) - PR-0221 M2

Producer: `crates/lazynote_ffi/src/api.rs`

| Code | Meaning | Typical Cause | UI Handling |
| --- | --- | --- | --- |
| `invalid_node_id` | folder node id format invalid | non-UUID `node_id` | show validation error, keep dialog open |
| `invalid_delete_mode` | delete mode value is unsupported | value not in `dissolve/delete_all` | show validation error, keep current selection |
| `node_not_found` | target workspace node missing | stale/deleted folder id | refresh tree and show not-found message |
| `node_not_folder` | target node is not folder kind | caller passed `note_ref` id | show operation invalid error and refresh tree |
| `db_busy` | repository/database temporarily locked | concurrent sqlite lock contention | show retry affordance and keep pending action |
| `db_error` | repository/database failure | sqlite/schema/io issue | show error and allow retry |
| `internal_error` | unexpected invariant failure | unexpected data or service invariant break | show error and capture diagnostics |

## Workspace Tree (Flutter Controller Local) - PR-0221 M3

Producer: `apps/lazynote_flutter/lib/features/notes/notes_controller.dart`

| Code | Meaning | Typical Cause | UI Handling |
| --- | --- | --- | --- |
| `busy` | local action guard rejected operation | user triggered folder delete while previous delete is still running | disable repeated action and retry after current operation ends |
| `save_blocked` | pre-delete local draft flush failed | active note has unsaved draft and `flushPendingSave()` returned false | prompt user to retry save or keep editing before delete |

## Reserved Pattern

- Use lowercase snake case.
- Prefix by domain if needed in future:
  - `entry_*`
  - `sync_*`
  - `auth_*`
