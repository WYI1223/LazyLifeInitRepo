# PR-0009C-entry-search-flow

- Proposed title: `feat(ui): execute default entry input as search flow`
- Status: In Progress (C1/C2 Completed)

## Goal

Wire non-command entry input to core search and render stable results.
Single Entry is launched from Workbench and runs inside Workbench left pane.

## Scope

In scope:

- Connect default input path to `entry_search`.
- Render search results list/snippets in workbench left panel.
- Keep Single Entry interaction split:
  - `onChanged` executes search path for non-command input.
  - `Enter` / send opens or returns detail based on latest parsed/executed state.
- Keep right debug logs panel behavior unchanged.
- Keep Workbench as primary shell at all times.

Out of scope:

- Command execution (`> ...`) side effects.

## Behavior Contract

1. Input not starting with `>` routes to search.
2. Search limit default is `10`.
3. Empty input clears results and returns to idle hint.
4. Errors are shown inline; input is preserved.
5. Search flow uses the minimalist single-entry input surface defined in PR-0009 epic.
6. Realtime search must avoid stale-response overwrite (latest request wins).
7. Entry DB file path must be configured from Flutter app-support directory to avoid `%TEMP%` test-data pollution.

## Planned File Changes

- [edit] `apps/lazynote_flutter/lib/features/entry/single_entry_controller.dart`
- [edit] `apps/lazynote_flutter/lib/features/entry/single_entry_panel.dart`
- [edit] `apps/lazynote_flutter/lib/features/entry/entry_shell_page.dart` (if result area placement needs shell tweaks)
- [add] `apps/lazynote_flutter/lib/features/search/search_results_view.dart`
- [add] `apps/lazynote_flutter/lib/features/search/search_models.dart` (optional DTO mapping)
- [edit] `apps/lazynote_flutter/lib/core/bindings/api.dart` usage sites only (no generated edits expected)
- [add] Flutter widget tests for search flow

## Execution Plan (C1/C2/C3)

### C1: Search execution pipeline in controller

1. Add async search runner in `SingleEntryController` for `SearchIntent`.
2. Add debounce for `onChanged` search path (recommend 120-180ms; baseline 150ms).
3. Add request sequence guard (`requestId`) so stale async responses are ignored.
4. Map `EntrySearchResponse`:
   - `ok=true` + `items.isNotEmpty` -> success with results
   - `ok=true` + empty items -> success empty state
   - `ok=false` -> error state using `errorCode + message`
5. Keep command path as preview-only in C (execution deferred to PR-0009D).

### C2: Search result rendering and detail action split

1. Add `search_results_view.dart` to render:
   - loading hint
   - empty results hint
   - error hint (colorized)
   - top hits list (`atomId/kind/snippet`)
2. Wire results view into Single Entry panel under status line.
3. Keep interaction split:
   - `onChanged` updates realtime result list
   - `Enter` / send only opens detail payload for latest state
4. Preserve input text on all error paths.

### C3: Tests and regression gates

1. Add controller tests:
   - realtime search success
   - empty input clears results
   - FFI error mapping (`ok=false`)
   - stale-response ignored (latest request wins)
2. Add widget tests:
   - results section updates with input changes
   - Enter/send opens detail without breaking realtime list
   - right debug logs panel remains mounted
3. Update smoke tests if visible Workbench text changes.

## Verification

- `cd apps/lazynote_flutter && dart format lib test`
- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test`
- `flutter run -d windows`

## Acceptance Criteria

- [ ] Default input reliably performs search.
- [ ] Result limit and error behavior match locked requirements.
- [ ] Workbench split-shell remains stable.

## Progress Notes

C1 completed:

- `single_entry_controller.dart` now executes realtime search for `SearchIntent`:
  - async `entry_search` invocation through injected search invoker
  - default debounce `150ms`
  - request-sequence guard to enforce latest-result-wins
- Search result mapping implemented:
  - `ok=true` + hits -> success with count message and detail payload
  - `ok=true` + no hits -> success with `No results.`
  - `ok=false` -> error with `[errorCode] message` when available
- Command path remains preview-only in C phase.
- Added controller tests in `test/single_entry_controller_test.dart` for:
  - success mapping
  - empty input reset
  - error mapping
  - stale response ignored
  - command preview path unchanged
- Updated `single_entry_panel_test.dart` to keep B2 interaction tests independent from realtime FFI calls.

C2 completed:

- Added `search_results_view.dart` and wired it into the Single Entry panel.
- Panel now renders search states in-place:
  - loading (`Searching...`)
  - error (colorized message)
  - empty (`No results.`)
  - result list with `kind/atomId/snippet`
- Controller now exposes structured search-view data:
  - `searchItems`
  - `searchAppliedLimit`
  - `isSearchLoading`
  - `hasSearchError/searchErrorMessage`
- Added widget tests in `test/single_entry_search_flow_test.dart`:
  - realtime search updates list section
  - Enter/send opens detail without removing result list

Infrastructure follow-up completed:

- Added FFI `configure_entry_db_path` and wired Flutter bootstrap to set entry DB path under app-support `data/lazynote_entry.sqlite3`.
- This removes reliance on temp-file defaults for regular app runs and reduces cross-test data contamination.
