# Single Entry Contract (v0.1)

This document defines the runtime contract for Single Entry behavior.

## Scope

- Workbench-embedded Single Entry panel
- parser/router behavior
- search and command execution boundary
- status and detail payload expectations

## Input Behavior Boundary

### `onChanged` path

- Always routes input through parser/router.
- Non-command input (`no > prefix`) triggers realtime search flow.
- Command input (`> ...`) stays in preview mode only.
- `onChanged` must not create/update data side effects.

### `Enter` or send-button path

- Search intent:
  - opens/returns detail payload for latest search state
  - no data mutation
- Command intent:
  - executes mapped command once
  - returns success/error status and detail payload

## Command Grammar (v0.1)

- `> new note <content>`
- `> task <content>`
- `> schedule <MM/DD/YYYY HH:mm> <title>`
- `> schedule <MM/DD/YYYY HH:mm-HH:mm> <title>`

Language: English keywords only.

## Search Contract

- Default limit: 10
- Max limit: 10
- Supported filter kinds: `all` (default), `note`, `task`, `event`
- Filter kind is passed to FFI `entry_search` via optional `kind` parameter.
- Stale async responses must not overwrite newer input states.
- Search failure is non-destructive: keep current input and show error.

## Command Mapping

- `> new note` -> `entry_create_note(content)`
- `> task` -> `entry_create_task(content)`
- `> schedule` -> `entry_schedule(title, start_epoch_ms, end_epoch_ms?)`

## Status and Detail Contract

### Status line

- success: user-readable success message
- error: user-readable error message
- loading: operation progress hint (`Searching...`, `Executing command...`)

### Detail payload

Search detail includes:
- `mode=search`
- query text
- requested/applied limit
- returned items summary

Command result detail includes:
- `mode=command_result`
- `action`
- `ok`
- `message`
- `atom_id` when available
- `raw_input`

## Error Handling

- Parser errors and execution errors are distinct states.
- Input text must remain unchanged on all error paths.
- UI must prefer stable code-based branching when available.

See also:
- `docs/api/ffi-contract-v0.1.md`
- `docs/api/error-codes.md`
