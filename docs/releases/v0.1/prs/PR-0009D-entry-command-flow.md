# PR-0009D-entry-command-flow

- Proposed title: `feat(ui): execute single-entry commands`
- Status: Draft

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

## Command Contract (v0.1)

1. `> new note <content>` creates `AtomType::Note`.
2. `> task <content>` creates `AtomType::Task` with `task_status = todo`.
3. `> schedule <date_spec> <title>` creates `AtomType::Event`:
   - point: `event_start` set, `event_end = null`
   - range: `event_start` and `event_end` set

Visual feedback baseline:

- error feedback can use color-emphasized text
- input content must remain unchanged after failures
- send icon remains highlighted when input is still non-empty

## Planned File Changes

- [edit] `apps/lazynote_flutter/lib/features/entry/entry_shell_page.dart`
- [edit] `apps/lazynote_flutter/lib/features/entry/command_router.dart`
- [edit] `apps/lazynote_flutter/lib/features/entry/entry_state.dart`
- [edit] bridge/FFI adapter files used by Flutter
- [add] widget/unit tests for command success/failure

## Step-by-Step

1. Ensure command input path is reachable via Workbench Single Entry button.
2. Dispatch parsed command intents to matching FFI actions.
3. Show success message with stable result summary (e.g., created type and id).
4. Show error messages inline with visual error style.
5. Preserve original input on both parser and execution errors.
6. Add tests for each command path and failure path.
7. Validate command flow does not break search flow.
8. Validate command error styling and non-clearing input behavior.

## Verification

- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test`
- `cd crates && cargo test --all`
- `flutter run -d windows`

## Acceptance Criteria

- [ ] Three baseline commands execute successfully.
- [ ] Error states are visible and non-destructive to input.
- [ ] Schedule point/range behavior matches locked requirements.
