# PR-0210-debug-viewer-readability-upgrade

- Proposed title: `feat(diagnostics): debug viewer readability phase-2 (semantic normalization + dense rendering)`
- Status: Planned

## Goal

Build phase-2 diagnostics readability on top of v0.1 baseline, focused on semantic normalization and high-volume scanning quality.

## Scope (v0.2)

In scope:

- normalize multiple timestamp/level formats into a stable semantic row model
- tighten severity visual hierarchy in high-density log lists
- preserve existing refresh/coalescing safety behavior
- improve multi-line wrapping and copy workflows for long log rows
- **[optional]** `log_dart_event` FFI bridge: a new sync FFI function that writes
  structured Dart-side events (level, event name, module, message) into the Rust rolling
  log file (review-02 §4.3).  This unifies Dart and Rust log streams so the diagnostics
  viewer shows a single timeline.  Requires running `gen_bindings.ps1` after adding the
  function to `api.rs`.  Include in this PR if the codegen step does not block the
  readability work; otherwise defer to `PR-0208`.

Out of scope:

- baseline timestamp + severity colors already delivered in `PR-0017A`
- remote log upload
- full structured JSON log inspector

## UX Rules

1. Semantic columns remain stable under mixed raw log formats.
2. Severity color and emphasis remain readable in dense rows.
3. Raw copy still preserves original line text.

## Step-by-Step

1. Add/extend line parser for timestamp and level normalization rules.
2. Add semantic rendering model for dense row layout and fallback states.
3. Keep tail-window and refresh pipeline unchanged.
4. Add tests for parser normalization and rendering fallbacks.

## Planned File Changes

- [edit] `apps/lazynote_flutter/lib/features/diagnostics/debug_logs_panel.dart`
- [edit] `apps/lazynote_flutter/lib/core/debug/log_reader.dart`
- [add] `apps/lazynote_flutter/lib/features/diagnostics/log_line_parser.dart`
- [add] `apps/lazynote_flutter/test/debug_viewer_readability_test.dart`
- [edit] `crates/lazynote_ffi/src/api.rs` — [optional] add `log_dart_event` sync FFI fn
- [edit] `crates/lazynote_ffi/src/frb_generated.rs` — [optional, codegen] regenerated
- [edit] `apps/lazynote_flutter/lib/core/bindings/api.dart` — [optional, codegen]
  regenerated

## Dependencies

- `PR-0017A-debug-viewer-readability-baseline`

## Verification

- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test test/debug_viewer_readability_test.dart`
- `cd apps/lazynote_flutter && flutter test`

## Acceptance Criteria

- [ ] Parser normalization handles mixed timestamp/level raw formats.
- [ ] Dense rows preserve readability and raw copy fidelity.
- [ ] Existing refresh stability behavior is preserved.
- [ ] [If `log_dart_event` implemented] Calling `logDartEvent` from Dart writes a
      `source=dart` structured entry into the Rust log file at the correct timestamp.
