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

## Reserved Pattern

- Use lowercase snake case.
- Prefix by domain if needed in future:
  - `entry_*`
  - `sync_*`
  - `auth_*`
