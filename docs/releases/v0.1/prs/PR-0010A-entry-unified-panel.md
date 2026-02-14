# PR-0010A-entry-unified-panel

- Proposed title: `feat(entry-ui): unified floating entry + realtime results panel`
- Status: Implemented (validated on Windows + Flutter test suite)

## Goal

Implement a single floating container for Single Entry:

- top: input bar (`Ask me anything...`)
- bottom: seamless realtime search results panel

This PR is UI-shell only and does not add new core business logic.

## Dependencies

- PR-0009D (single entry parser/search/command baseline)
- `docs/architecture/settings-config.md` (`entry.result_limit`, future home-entry toggle)

## UI Contract (Locked)

### 1) Overall container

- Single container component (`Container` or `Card` as root)
- Background: `Colors.white`
- Border radius: `BorderRadius.circular(24.0)` (baseline; minor tuning allowed)
- Soft floating shadow: large blur, low-opacity gray/black
- Internal layout: vertical `Column`
- Width behavior in Workbench: follow parent content width (no fixed max width in v0.1)

### 2) Top input section

- Embedded in the same white root container (not a separate card)
- `TextField` with `InputDecoration(border: InputBorder.none, hintText: 'Ask me anything...')`
- Icons on right: `Icons.mic`, `Icons.send_outlined`
- Icon color: neutral gray (`Colors.grey[600]` baseline)
- Send icon highlight (when input non-empty): deep gray (`Colors.grey[800]`)
- Input baseline and right-side icons are visually lowered in sync to avoid "top-heavy" appearance.

### 3) Results list section

- `ListView.separated` for realtime rows
- Must be constrained by `Expanded`/`Flexible` to prevent overflow
- Separator must be `Divider`
  - `thickness`: `0.5` ~ `1.0`
  - `height`: `1.0`
  - `indent`: `16.0`
  - `endIndent`: `16.0`
- Scrollbar policy (desktop):
  - only one visible scrollbar in results area
  - explicit `ScrollController` wiring
  - `mainAxisMargin = 16` to keep track endpoints away from rounded edges
  - disable auto-scrollbar wrapping in this subtree to avoid duplicated bars

## Interaction Contract (Locked)

- Expand when input gains focus or has text.
- Collapse only when input loses focus **and** text is empty.
- Search intent updates results on `onChanged`.
- Enter/send opens detail/command result path (existing behavior from PR-0009).
- Clicking a search row opens detail payload for selected result item.
- Press `Esc` to clear current input and close visible detail payload.
- Empty search results keep panel expanded and show explicit empty state.
- Search rows provide subtle hover highlight feedback on desktop pointer move.
- Hover highlight uses a stable light gray tone without strong enter/exit animation jumps.

## Motion and Size Contract (Locked)

- Height animation duration: `180ms`
- Curve: `Curves.easeOutCubic`
- Collapsed height: around `72`
- Expanded max height: around `420` (internal list scrolls)
- These defaults are mirrored in local `settings.json` under:
  - `entry.ui.collapsed_height`
  - `entry.ui.expanded_max_height`
  - `entry.ui.animation_ms`

## Placeholder icon policy (Locked for v0.1)

Result icons are temporary placeholders, mapped by current result kind:

- `note` -> `Icons.description_outlined`
- `task` -> `Icons.check_circle_outline`
- `event` -> `Icons.calendar_today_outlined`
- fallback -> `Icons.insert_drive_file_outlined`

Rationale:

- Atom model can represent multi-role entities (note/task/schedule at once).
- v0.1 keeps a deterministic placeholder icon for readability.
- Future phase can support user-selectable icon strategy.

Implementation note:

- Code must include a short `Why` comment near icon mapping to explain this temporary policy.
- Keep a TODO marker for future user-configurable icon strategy.

## Non-Goals

- No home-route switch in this PR.
- No notes/tasks/calendar feature content in this PR.
- No icon customization UI in this PR.
- Status text is not part of the unified card body; keep it outside card as Workbench debug line.

## Acceptance Criteria

- [x] Single Entry renders as one unified floating card.
- [x] Results panel seamlessly attaches below input section.
- [x] Divider style uses `indent/endIndent = 16.0`.
- [x] Results area has exactly one scrollbar with 16px track endpoint margin.
- [x] Expand/collapse behavior matches interaction contract.
- [x] `Esc` quick reset behavior works (clear input + close detail).
- [x] Desktop hover feedback is visible on result rows.
- [x] Workbench right logs panel remains unaffected.
- [x] `flutter analyze` and `flutter test` pass.
