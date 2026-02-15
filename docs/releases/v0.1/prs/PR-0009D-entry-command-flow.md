# PR-0009D-entry-command-flow

- Proposed title: `feat(ui): execute single-entry commands`
- Status: Completed

## Goal

Execute command intents from the single entry input and show actionable feedback.
Single Entry remains a Workbench-internal tool, called by button.

## Scope

In scope:

- Execute command intents from parser/router.
- Implement command feedback states in workbench.
- Colorize error message styling while keeping input untouched.
- Keep Workbench landing UX unchanged.
- Preserve single-entry minimalist visual identity while executing commands.

Out of scope:

- Natural-language command expansion.
- Non-English command aliases.

## Business Logic Contract (v0.1)

### Input Change Path (`onChanged`)

1. Every input change still goes through parser/router.
2. Search text (no `>`) keeps realtime search behavior from `PR-0009C`.
3. Command text (`> ...`) only shows preview metadata and validation status.
4. `onChanged` must not create/update atoms for command input.

### Commit Path (`Enter` / send button)

1. Search intent:
   - opens current search detail payload
   - does not create data side effects
2. Command intent:
   - executes exactly one mapped command action
   - returns stable success/error status and detail payload
   - keeps input unchanged even on execution errors

### Command Mapping

1. `> new note <content>` -> `entry_create_note(content)`
2. `> task <content>` -> `entry_create_task(content)`
3. `> schedule <date_spec> <title>` -> `entry_schedule(...)`
   - point: `end_epoch_ms = null`
   - range: `end_epoch_ms = Some(value)`

### Feedback and Error Contract

1. Success:
   - status line shows action result (`Note created.` / `Task created.` / `Event scheduled.`)
   - detail payload includes `action`, `atom_id`, and normalized input summary
2. Failure:
   - status line uses error style color
   - detail payload includes stable failure context (`action`, message, input snapshot)
   - input text remains unchanged
3. Parse failure and execution failure are distinct:
   - parse failure: router/grammar error before execution
   - execution failure: FFI/core error after valid parse

## Command Contract (v0.1)

1. `> new note <content>` creates `AtomType::Note`.
2. `> task <content>` creates `AtomType::Task` with `task_status = todo`.
3. `> schedule <date_spec> <title>` creates `AtomType::Event`:
   - point: `event_start` set, `event_end = null` _(renamed to `start_at`/`end_at` in Migration 6, v0.1.5)_
   - range: `event_start` and `event_end` set _(renamed to `start_at`/`end_at` in Migration 6, v0.1.5)_

Visual feedback baseline:

- error feedback can use color-emphasized text
- input content must remain unchanged after failures
- send icon remains highlighted when input is still non-empty

## Planned File Changes

- [edit] `apps/lazynote_flutter/lib/features/entry/single_entry_controller.dart`
- [edit] `apps/lazynote_flutter/lib/features/entry/entry_shell_page.dart`
- [edit] `apps/lazynote_flutter/lib/features/entry/command_router.dart`
- [edit] `apps/lazynote_flutter/lib/features/entry/entry_state.dart`
- [edit] bridge/FFI adapter usage sites in Flutter
- [add] controller/widget tests for command success/failure and input preservation

## Step-by-Step

### D1: Controller execution wiring

1. Keep command `onChanged` path as preview-only.
2. Add command execution path in `handleDetailAction` for `CommandIntent`.
3. Map each `EntryCommand` subtype to matching async FFI call.
4. Build deterministic detail payload including `action`, `atom_id`, and request summary.
5. Keep input unchanged on execution failure.

### D2: UI feedback and tests

1. Ensure status text and color reflect execution success/error.
2. Keep send icon behavior unchanged (depends on input emptiness only).
3. Add controller tests:
   - `new note` success
   - `task` success (default status expectation in returned message)
   - `schedule` point/range success
   - execution failure mapping (status + detail + input retained)
4. Add widget test coverage for command execute via Enter/send.
5. Run non-regression tests to confirm search flow still works.

### D3: Docs and maintenance sync

1. Update this PR file status/checklist.
2. Sync epic tracker `PR-0009-single-entry-router.md`.
3. Sync `docs/releases/v0.1/README.md` progress line when D is completed.

## Verification

- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test`
- `cd crates && cargo test --all`
- `flutter run -d windows`

## Acceptance Criteria

- [x] Three baseline commands execute successfully.
- [x] Error states are visible and non-destructive to input.
- [x] Schedule point/range behavior matches locked requirements.

## Progress Notes

D1 implemented:

- `SingleEntryController` now executes `CommandIntent` on `Enter/send`.
- Added command invoker wiring for:
  - `entry_create_note`
  - `entry_create_task`
  - `entry_schedule`
- Added command prepare hook with default DB-path readiness (`RustBridge.ensureEntryDbPathConfigured()`).
- Added command request sequence guard to ignore stale async completions.

D2 implemented:

- Command execution now sets explicit loading/success/error states.
- Command result detail payload now includes stable fields:
  - `action`
  - `ok`
  - `message`
  - `atom_id` (when available)
  - `raw_input`
- Added controller tests for:
  - note command success
  - task command success
  - schedule range epoch mapping
  - command failure with preserved input
- Added widget test for send-button command execution with mocked command invoker.

D3 completed:

- PR doc/business contract and maintenance record updated.
- Epic tracker (`PR-0009-single-entry-router.md`) and release summary were synchronized.
- Manual Windows validation passed against the command/search checklist.

## Maintenance Record

- 2026-02-13: Expanded business logic contract for command execution boundaries (`onChanged` preview vs `Enter/send` commit path).
- 2026-02-13: Added D1/D2/D3 execution checklist to make implementation and review traceable.
- 2026-02-13: Marked PR-0009D as completed after local command-flow manual validation.
