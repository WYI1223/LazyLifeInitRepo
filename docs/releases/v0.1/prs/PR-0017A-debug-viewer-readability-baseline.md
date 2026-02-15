# PR-0017A-debug-viewer-readability-baseline

- Proposed title: `feat(diagnostics): debug viewer readability baseline (timestamp + severity colors)`
- Status: Planned

## Goal

Deliver immediate readability improvements to Workbench debug viewer in v0.1, so QA and local debugging are faster during notes closure.

## Scope (v0.1)

In scope:

- render a consistent timestamp column in log rows
- add severity-aware coloring (`trace/debug/info/warn/error`)
- keep raw log text copy behavior unchanged
- keep existing refresh/coalescing/tail-window behavior unchanged
- filter incomplete (non-newline-terminated) trailing lines before display, preventing
  truncated-row artefacts caused by concurrent `flexi_logger` writes (review-02 §4.4)

Out of scope:

- advanced structured log inspector
- in-panel search/filter query language
- remote upload/telemetry workflows

## Step-by-Step

1. Add best-effort metadata extraction for timestamp and level.
2. Add semantic row rendering for timestamp + level + message.
3. Keep refresh scheduler and reader pipeline unchanged.
4. Add regression tests for timestamp rendering and level color mapping.

## Planned File Changes

- [edit] `apps/lazynote_flutter/lib/features/diagnostics/debug_logs_panel.dart`
- [edit] `apps/lazynote_flutter/lib/core/debug/log_reader.dart` — add incomplete-line guard:
  discard the last line of file content if it does not end with `\n` (review-02 §4.4)
- [add] `apps/lazynote_flutter/lib/features/diagnostics/log_line_meta.dart` (optional)
- [add/edit] `apps/lazynote_flutter/test/debug_logs_panel_test.dart`

## Dependencies

- `PR-0017-workbench-debug-logs`

## Verification

- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test test/debug_logs_panel_test.dart`
- `cd apps/lazynote_flutter && flutter test`

## Acceptance Criteria

- [ ] Debug log rows show a stable timestamp presentation.
- [ ] Severity levels are visually distinct and readable in light theme.
- [ ] Existing refresh stability behavior remains unchanged.
- [ ] Log reader discards any incomplete trailing line (not ending with `\n`); tests verify
      no truncated rows appear under concurrent write simulation.

