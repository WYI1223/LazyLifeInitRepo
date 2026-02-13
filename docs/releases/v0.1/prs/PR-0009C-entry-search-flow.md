# PR-0009C-entry-search-flow

- Proposed title: `feat(ui): execute default entry input as search flow`
- Status: Draft

## Goal

Wire non-command entry input to core search and render stable results.
Single Entry is launched from Workbench and runs inside Workbench left pane.

## Scope

In scope:

- Connect default input path to `entry_search`.
- Render search results list/snippets in workbench left panel.
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

## Planned File Changes

- [edit] `apps/lazynote_flutter/lib/features/entry/entry_shell_page.dart`
- [add] `apps/lazynote_flutter/lib/features/search/search_results_view.dart`
- [edit] `apps/lazynote_flutter/lib/core/rust_bridge.dart` (if adapter methods are added)
- [add] Flutter widget tests for search flow

## Step-by-Step

1. Add search action trigger (button or enter key).
2. Ensure Single Entry is entered via Workbench button (not route replacement).
3. Call entry router and dispatch search intent to FFI.
4. Render loading, success, empty, and error states.
5. Display top hits with stable ordering metadata from core.
6. Keep right-side microphone and outlined send icons aligned with panel style contract.
7. Add tests for:
   - successful search
   - empty input
   - FFI error
   - send icon visual state for empty/non-empty input
8. Validate no regression to shell/log panel behavior.

## Verification

- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test`
- `flutter run -d windows`

## Acceptance Criteria

- [ ] Default input reliably performs search.
- [ ] Result limit and error behavior match locked requirements.
- [ ] Workbench split-shell remains stable.
