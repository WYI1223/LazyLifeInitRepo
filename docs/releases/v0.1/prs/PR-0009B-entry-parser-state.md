# PR-0009B-entry-parser-state

- Proposed title: `feat(ui): add single-entry parser and state model`
- Status: Draft

## Goal

Build parser/state scaffolding for single-entry routing before wiring final execution.

## Scope

In scope:

- Add command parser for English keywords.
- Add entry state model and state transitions.
- Add router abstraction that decides `search` vs `command`.
- Add Workbench-triggered entry activation contract (button call-in).
- Add Single Entry panel visual structure and icon/state wiring contract.

Out of scope:

- Real FFI execution integration.
- Search results UI polish.

## Command Grammar (v0.1 baseline)

1. `> new note <content>`
2. `> task <content>`
3. `> schedule <date_spec> <title>`

Date baseline:

- `MM/DD/YYYY` required family.
- Accept point and range variants in this family:
  - point: `MM/DD/YYYY HH:mm`
  - range: `MM/DD/YYYY HH:mm-HH:mm`

## Planned File Changes

- [add] `apps/lazynote_flutter/lib/features/entry/command_parser.dart`
- [add] `apps/lazynote_flutter/lib/features/entry/command_router.dart`
- [add] `apps/lazynote_flutter/lib/features/entry/entry_state.dart`
- [edit] `apps/lazynote_flutter/lib/features/entry/entry_shell_page.dart` (state wiring + entry-launch button hook)
- [add] parser/state tests

## UI Contract Hand-off (from Epic)

- Placeholder text must be `Ask me anything...`.
- Right icons must include microphone + outlined send icon.
- Send icon state:
  - empty input -> gray (`#757575`)
  - non-empty input -> highlight (v0.1 default `Colors.blue`)
- Panel keeps minimalist style and does not replace Workbench shell.

## Step-by-Step

1. Define immutable entry state model (`idle/loading/success/error`).
2. Implement parser output types (`SearchIntent`, `CommandIntent`).
3. Implement command grammar parser with strict validation messages.
4. Add router function to map raw input to intent.
5. Add tests for valid/invalid command patterns.
6. Wire a Workbench button that toggles/focuses the Single Entry panel.
7. Keep input text preserved on parser or execution error states.
8. Add widget tests for send-icon state change based on input emptiness.

## Verification

- `cd apps/lazynote_flutter && dart format .`
- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test`

## Acceptance Criteria

- [ ] Parser supports locked command grammar.
- [ ] Router cleanly distinguishes command vs search.
- [ ] Error states keep input intact and expose readable messages.
