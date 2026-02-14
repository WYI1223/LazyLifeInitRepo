# PR-0010C-notes-tags-ui

- Proposed title: `feat(notes-ui): notes list/editor and tag filter integration`
- Status: Implemented (C1/C2/C3/C4 done)

## Goal

Build the first usable Notes UI on top of PR-0010B contracts:

- list notes
- edit note content
- filter by one tag

## Product Decisions (Locked)

1. Save strategy: `1.5s` debounced auto-save.
2. Switch behavior: when switching note, force flush pending save without confirmation dialog.
3. Create behavior: creating a note auto-selects it and autofocuses editor input.

## UX Requirements (Locked)

1. Keep Workbench as current host shell; Notes page is feature content in left pane.
2. Notes list is ordered by recency from backend contract.
3. Selecting a note opens it in editor without route churn.
4. Tag filter is single-select in v0.1:
   - selecting one tag applies filter
   - clear returns to full list
5. Failure states must be explicit and recoverable (retry/manual refresh).

## Architecture Contracts (Locked)

1. Notes feature is composed as shell slots:
   - `NoteExplorer` (left)
   - `NoteTabManager` (top)
   - `NoteContentArea` (center)
2. State model must support multi-instance note sessions:
   - `openNoteIds[]`
   - `activeNoteId`
3. Explorer data model must reserve folder hierarchy recursion even when v0.1 currently renders one folder level.
4. Explorer emits open-note requests; tab manager decides activate/open/close transitions; content area only renders by `activeNoteId`.

## Visual Blueprint (Product Input)

Target visual structure follows a two-column document layout inside a desktop shell:

1. Top window bar:
   - sidebar toggle icon
   - tab strip (active and inactive tabs)
   - desktop window controls (minimize, maximize, close)
2. Left sidebar:
   - workspace switcher
   - primary navigation
   - section headers and page tree
   - utility and settings actions
3. Main content area:
   - breadcrumbs and page header actions
   - document properties actions
   - large page title
   - markdown-oriented editor body with readable line spacing

## Detailed Component Breakdown

### A) Top Window Bar

1. Leading actions:
   - sidebar toggle icon
2. Tab strip:
   - inactive tab visual style
   - active tab visual style
   - close action (`X`) on active tab
   - add tab action (`+`)
3. Window controls:
   - minimize
   - maximize/restore
   - close

### B) Left Sidebar (Navigation and Workspace)

1. Workspace switcher:
   - current workspace/account label
   - new page quick action
2. Primary navigation:
   - search
   - home
   - inbox (supports badge)
   - library (supports feature label such as alpha)
3. Section headers and page tree:
   - recents
   - shared
   - private
   - current page highlight
4. Utility and settings:
   - app shortcuts area
   - settings and members entry
   - trash entry
   - help action near lower-left anchor

### C) Main Content Area (Document Editor)

1. Breadcrumbs and page header:
   - path breadcrumbs
   - right-side page actions (share, star, more)
2. Document properties area:
   - add icon
   - add cover
   - add comment
3. Page title:
   - large-weight title line
4. Editor body:
   - markdown-oriented paragraph editing
   - clear line-height and paragraph spacing
   - supports long-form requirement text editing

## v0.1 Mapping Rules (Locked)

1. Workbench shell remains host in v0.1. Shell-level chrome (top bar, global sidebar) is not rebuilt by PR-0010C.
2. PR-0010C focuses on Notes feature content mounted in existing shell content region.
3. Visual blueprint above is applied to the Notes page composition and styling language where scope allows.
4. Any shell-level redesign beyond current host is deferred to a future shell/navigation PR.

## Code Comment Compliance (Synced)

This PR line follows `docs/architecture/code-comment-standards.md`:

1. Public Notes widgets/controllers include `///` contract comments (purpose, I/O semantics, side effects).
2. Non-obvious UI behavior keeps concise why-comments, including:
   - desktop wheel-to-horizontal mapping in top tab strip
   - explicit scrollbar ownership (avoid duplicate auto scrollbar)
   - hover-gated tab scroll rail visibility and overflow-only rendering
3. Comment updates must land in the same PR as behavior changes to avoid drift.

## Recent C3 Hardening Sync

1. Desktop close performance fix:
   - close interception is now enabled only while pending save work exists
   - clean-state close no longer takes the intercept + flush path
2. Close robustness fix:
   - close path now prefers `windowManager.close()` and falls back to `destroy()` only when needed
   - close flush timeout tightened for best-effort behavior
3. Save-error UX fix:
   - top-right save status now uses short stable copy (`Save failed`)
   - full backend error payload moved to dedicated error banner above editor body
4. Copy quality fix:
   - switch-block banner text normalized to valid UTF-8 English copy
5. Test stability fix:
   - save queue follow-up logic adjusted to avoid retry storms on persistent write failures
6. Tab safety fix:
   - tab close helpers now enforce flush guard semantics instead of direct state mutation
   - close is blocked on flush failure to prevent unsaved draft loss
7. Global close guard fix:
   - pending-save detection now includes all open tabs (not only active tab)
8. Responsive action bar hardening:
   - narrow width uses compact overflow action model to avoid clipping
   - wide and narrow now share dropdown-based `...` interaction contract
   - final behavior validated in manual narrow/window resize runs

## C4 Integration Closure Sync

1. Explorer header now hosts reusable single-tag filter UI.
2. Tag catalog wiring landed:
   - `tags_list` load state + retry path
   - alphabetical tag ordering for deterministic chip layout
3. Notes list filter wiring landed:
   - `notes_list(tag)` apply path
   - clear action returns unfiltered list
4. Contextual create under active filter landed:
   - create note auto-applies current selected tag (`note_set_tags`)
5. Immediate tag mutation path landed:
   - active note tag add/remove writes through `note_set_tags` immediately
6. Ghost-state contract landed:
   - when active note leaves current filter due to tag edit, left list updates
   - right editor remains open on active note
7. Added C4 widget regression suite:
   - filter apply/clear
   - contextual create auto-tag
   - ghost-state behavior
   - filter error and recovery paths
8. C4 post-review fixes:
   - removed dedicated `Clear` button in filter area; selected chip now toggles clear
   - fixed filtered-list pollution when activating a non-matching open tab
   - aligned tag lifecycle with active-note references by pruning orphan tags in core
   - added filter overflow interaction (`+N more` expand / collapse) for large tag sets

## Execution Specs (Split Files)

1. `PR-0010C1`: `docs/releases/v0.1/prs/PR-0010C1-notes-host-list-baseline.md`
2. `PR-0010C2`: `docs/releases/v0.1/prs/PR-0010C2-note-editor-create-select.md`
3. `PR-0010C3`: `docs/releases/v0.1/prs/PR-0010C3-note-autosave-switch-flush.md`
4. `PR-0010C4`: `docs/releases/v0.1/prs/PR-0010C4-tag-filter-integration-closure.md`

## Pre-Landing Checklist

1. PR-0010B FFI contracts and generated bindings are up to date.
2. Error code handling in Flutter is aligned with `docs/api/error-codes.md`.
3. Notes list sort contract is confirmed as backend `updated_at DESC`.
4. Autosave timer policy (`1.5s`) and switch flush behavior are implemented exactly as locked decisions.

## Planned File Changes (C-stage aggregate)

- [add] `apps/lazynote_flutter/lib/features/notes/notes_page.dart`
- [add] `apps/lazynote_flutter/lib/features/notes/note_explorer.dart`
- [add] `apps/lazynote_flutter/lib/features/notes/note_tab_manager.dart`
- [add] `apps/lazynote_flutter/lib/features/notes/note_content_area.dart`
- [add] `apps/lazynote_flutter/lib/features/notes/notes_style.dart`
- [add] `apps/lazynote_flutter/lib/features/notes/note_editor.dart`
- [add] `apps/lazynote_flutter/lib/features/notes/notes_controller.dart`
- [add] `apps/lazynote_flutter/lib/features/tags/tag_filter.dart`
- [edit] `apps/lazynote_flutter/lib/features/entry/entry_shell_page.dart` (Notes section wiring)
- [add] `apps/lazynote_flutter/test/notes_flow_test.dart`

## Dependencies

- PR-0010B (core + FFI contracts ready)
- PR-0008 shell routing baseline
- PR-0010A visual shell contract

## Quality Gates

- `flutter analyze`
- `flutter test`
- plus existing Rust gates in full pipeline

## Acceptance Criteria

- [x] Notes placeholder is replaced by functional notes list/editor UI.
- [x] Single-tag filter works and can be cleared.
- [x] Save path updates UI state consistently.
- [x] Flutter tests cover primary and failure flows.
