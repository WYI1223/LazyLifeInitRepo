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
| `db_open_failed` | entry DB cannot be opened | invalid path, permissions, IO failure | show inline error, keep input |
| `search_failed` | search execution failed | SQL/FTS query failure | show inline error, keep input |

## Notes/Tags (FFI)

Producer: `crates/lazynote_ffi/src/api.rs`

| Code | Meaning | Typical Cause | UI Handling |
| --- | --- | --- | --- |
| `invalid_note_id` | note id format invalid | non-UUID `atom_id` | show validation error, keep input |
| `invalid_tag` | invalid tag value | blank or malformed tag input | show validation error, keep input |
| `note_not_found` | target note missing | stale/deleted id | show not-found state and refresh list |
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

## Reserved Pattern

- Use lowercase snake case.
- Prefix by domain if needed in future:
  - `entry_*`
  - `sync_*`
  - `auth_*`
