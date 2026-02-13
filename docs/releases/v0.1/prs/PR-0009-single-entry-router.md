# PR-0009-single-entry-router

- Proposed title: `ui(entry): single entry (search + command router)`
- Status: Draft (Epic)

## Goal
Deliver a single input experience that supports both search and commands in Workbench.
Workbench remains the default homepage and log viewer shell.

## Epic Split

This work is split into four smaller PRs:

1. `PR-0009A`: FFI and core use-case surface for entry operations.
2. `PR-0009B`: Flutter parser/state scaffolding and command contract validation.
3. `PR-0009C`: Search execution flow (default input -> search results).
4. `PR-0009D`: Command execution flow (`> new note`, `> task`, `> schedule`).

## Locked Requirements

1. Commands support English keywords only in v0.1.
2. Date input baseline uses `MM/DD/YYYY`.
3. Default search result limit is `10`.
4. On command/search error, keep current input and show error message (colorized UI hint is allowed).
5. `> task` should create task atoms with default status `todo`.
6. `> schedule` should support both time point and time range in one date format family:
   - point: creates event with `event_start` and `event_end = null`
   - range: creates event with both `event_start` and `event_end`
7. Single Entry is opened from Workbench by a dedicated button; it does not replace Workbench as the landing page.

## UI Style Specification (Locked)

Visual direction:

- minimalist input surface inspired by Gemini/Google search bar language
- clean neutral off-white background (`Scaffold`/panel tone, no clutter)
- centered and prominent single input container
- solid opaque white rounded rectangle with very soft diffuse shadow

Input composition:

- placeholder text: `Ask me anything...`
- right-side icons inside input:
  - microphone
  - send (outlined paper-plane style)

Icon system:

- baseline: Flutter built-in icons
  - microphone: `Icons.mic` (fallback: `CupertinoIcons.mic`)
  - send: `Icons.send_outlined` (outlined only, not filled)
- optional future replacement: thinner icon pack (Lucide/Heroicons/SVG) if needed

Icon styling:

- neutral gray, baseline `#757575` (`Colors.grey[600]`)
- size baseline: `24.0`
- no extra icon border or chip container
- spacing/padding should preserve comfortable breathing room

Interaction styling:

- send icon default: neutral gray
- send icon when input is non-empty: highlighted (default `Colors.blue` in v0.1)
- microphone stays secondary action visual weight

Layout constraint:

- Workbench remains the shell and log viewer.
- Single Entry is a Workbench-internal panel called by button, not a standalone homepage.

## Planned File Changes
- [add] `docs/releases/v0.1/prs/PR-0009A-entry-ffi-surface.md`
- [add] `docs/releases/v0.1/prs/PR-0009B-entry-parser-state.md`
- [add] `docs/releases/v0.1/prs/PR-0009C-entry-search-flow.md`
- [add] `docs/releases/v0.1/prs/PR-0009D-entry-command-flow.md`

## Dependencies
- PR0007, PR0008

## Acceptance Criteria
- [ ] Scope implemented
- [ ] Basic verification/tests added
- [ ] Documentation updated if behavior changes

## Notes
- This is now an epic tracker.
- Implementation and verification details live in PR-0009A/B/C/D.
