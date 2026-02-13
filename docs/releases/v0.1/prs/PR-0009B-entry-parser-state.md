# PR-0009B-entry-parser-state

- Proposed title: `feat(ui): add single-entry parser and state model`
- Status: In Progress (B1 Completed)

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

## Interaction Contract (Locked)

- Input `onChanged` triggers parser/router on every text change.
- Pressing `Enter` or clicking the send icon does not start "typing search mode".
- `Enter` / send action opens detail view or returns current detail payload for the latest parsed intent.
- Parse or execution errors must keep original input text unchanged.

## Execution Plan (B1/B2)

### B1: Parser / Router / State (no real FFI execution)

1. Define immutable entry state model (`idle/loading/success/error` + status message type).
2. Implement parser output types (`SearchIntent`, `CommandIntent`, `NoopIntent`, `ParseErrorIntent`).
3. Implement command grammar parser with strict validation messages.
4. Add router function to map raw input to intent.
5. Add tests for valid/invalid command patterns and router branches.

B1 verification:

- `cd apps/lazynote_flutter && dart format .`
- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test`

### B2: Workbench Internal Panel Wiring

1. Wire a Workbench button that toggles/focuses the Single Entry panel.
2. Keep Single Entry inside Workbench left pane (do not replace route/homepage).
3. Wire `onChanged` as realtime parser/router trigger.
4. Bind `Enter` + send icon click to "open/return detail" behavior.
5. Apply locked UI contract (placeholder/icons/send highlight rules).
6. Keep input text preserved on parser or execution error states.
7. Add widget tests for:
   - panel open/close behavior
   - send-icon state change based on input emptiness
   - `onChanged` trigger and Enter/send detail action split
   - input preservation on parse error
   - no regression to right-side debug logs panel

B2 verification:

- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test`

## Acceptance Criteria

- [x] Parser supports locked command grammar.
- [x] Router cleanly distinguishes command vs search.
- [ ] Error states keep input intact and expose readable messages.

## Progress Notes

B1 completed:

- Added immutable entry state model in `entry_state.dart` with explicit transitions (`toLoading`, `toSuccess`, `toError`, `clearStatus`).
- Added command parser in `command_parser.dart`:
  - `> new note <content>`
  - `> task <content>`
  - `> schedule <MM/DD/YYYY HH:mm> <title>`
  - `> schedule <MM/DD/YYYY HH:mm-HH:mm> <title>`
- Added router in `command_router.dart` with `SearchIntent`, `CommandIntent`, `NoopIntent`, `ParseErrorIntent`.
- Added tests:
  - `test/command_parser_test.dart`
  - `test/command_router_test.dart`
  - `test/entry_state_test.dart`
- Verification passed:
  - `dart format lib test`
  - `flutter analyze`
  - `flutter test`
