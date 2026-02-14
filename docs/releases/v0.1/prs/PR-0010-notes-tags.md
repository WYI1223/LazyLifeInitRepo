# PR-0010-notes-tags

- Proposed title: `feat(notes): markdown note flow + tag filter baseline`
- Status: In Progress (v0.1 primary closure umbrella)

## Goal

Deliver the first usable note workflow in v0.1:

- create/edit/list notes
- attach and filter by tags

## Release Role

`PR-0010` is the primary remaining feature closure track for v0.1.
Other non-notes tracks are deferred post-v0.1.

## Scope (v0.1)

In scope:

- note list ordered by recent update time
- note editor (plain markdown text area, no rich toolbar)
- simple tag assignment and single-tag filter

Out of scope:

- WYSIWYG markdown rendering
- nested tag taxonomy
- advanced multi-condition filters
- note delete lifecycle (delete/restore/permanent-delete) UI and contract

## PR Split (Locked)

PR-0010 is executed as 4 smaller PRs:

- `PR-0010A`: Single Entry unified floating panel UI shell
  - spec: `docs/releases/v0.1/prs/PR-0010A-entry-unified-panel.md`
- `PR-0010B`: notes/tags core + FFI contracts
  - spec: `docs/releases/v0.1/prs/PR-0010B-notes-tags-core-ffi.md`
- `PR-0010C`: notes/tags Flutter UI integration
  - spec: `docs/releases/v0.1/prs/PR-0010C-notes-tags-ui.md`
- `PR-0010D`: hardening, regression tests, docs closure
  - spec: `docs/releases/v0.1/prs/PR-0010D-notes-tags-hardening.md`

PR-0010C is executed internally as 4 delivery slices:

- `PR-0010C1`: Notes host + list baseline
  - spec: `docs/releases/v0.1/prs/PR-0010C1-notes-host-list-baseline.md`
- `PR-0010C2`: editor + create/select flow
  - spec: `docs/releases/v0.1/prs/PR-0010C2-note-editor-create-select.md`
- `PR-0010C3`: `1.5s` debounced auto-save + switch flush
  - spec: `docs/releases/v0.1/prs/PR-0010C3-note-autosave-switch-flush.md`
- `PR-0010C4`: single-tag filter + integration test closure
  - spec: `docs/releases/v0.1/prs/PR-0010C4-tag-filter-integration-closure.md`

## Current State

- `PR-0010A`: completed
- `PR-0010B`: completed
- `PR-0010C1`: completed
- `PR-0010C2`: completed
- `PR-0010C3`: completed
- `PR-0010C4`: completed
- `PR-0010D`: in progress (hardening + docs closure)

## Phase Summary (B/C/D)

### PR-0010B (Core + FFI)

Purpose:

- establish note/tag domain contracts and typed FFI envelopes

Expected effect:

- Flutter can call stable notes/tags APIs without parsing free-text error messages

Pre-landing checks:

- API contract agreed in docs
- core invariants and error mapping clarified

### PR-0010C (Flutter UI)

Purpose:

- replace Notes placeholder with usable list/editor/filter flow
- establish extractable Notes shell baseline (`NoteExplorer`/`NoteTabManager`/`NoteContentArea`)

Expected effect:

- user can create/edit notes and filter list by one tag in Workbench Notes section
- Notes feature can later be moved out of Workbench with minimal routing change

Pre-landing checks:

- PR-0010B APIs stable and generated bindings refreshed
- product decisions locked:
  - save strategy: `1.5s` debounced auto-save
  - switch note: force flush pending save, no confirmation dialog
  - create note: auto-select + autofocus editor

### PR-0010D (Hardening + Closure)

Purpose:

- close async/race/error risks and complete docs/test closure

Expected effect:

- note/tag flow is stable under overlap/failure/retry scenarios and release docs are synced

Pre-landing checks:

- B/C baseline features pass end-to-end

## Execution Order

1. Land `PR-0010A` (Single Entry UI shell behavior/appearance lock).
2. Land `PR-0010B` (core + FFI APIs for notes/tags).
3. Land `PR-0010C1` (Notes host + list baseline).
4. Land `PR-0010C2` (editor + create/select flow).
5. Land `PR-0010C3` (`1.5s` auto-save + switch flush).
6. Land `PR-0010C4` (tag filter + integration closure).
7. Land `PR-0010D` (error-path polish, tests, docs sync).

## Planned File Changes (B/C/D focus)

- [add] `apps/lazynote_flutter/lib/features/notes/notes_page.dart`
- [add] `apps/lazynote_flutter/lib/features/notes/note_explorer.dart`
- [add] `apps/lazynote_flutter/lib/features/notes/note_tab_manager.dart`
- [add] `apps/lazynote_flutter/lib/features/notes/note_content_area.dart`
- [add] `apps/lazynote_flutter/lib/features/notes/notes_style.dart`
- [add] `apps/lazynote_flutter/lib/features/notes/note_editor.dart`
- [add] `apps/lazynote_flutter/lib/features/notes/notes_controller.dart`
- [add] `apps/lazynote_flutter/lib/features/tags/tag_filter.dart`
- [add] `crates/lazynote_core/src/repo/tag_repo.rs`
- [add] `crates/lazynote_core/src/service/note_service.rs`
- [edit] `crates/lazynote_ffi/src/api.rs`
- [add] `apps/lazynote_flutter/test/notes_flow_test.dart`
- [add] `apps/lazynote_flutter/test/notes_controller_tabs_test.dart`

## Dependencies

- PR0006, PR0007, PR0008, PR0009D
- Settings contract baseline: `docs/architecture/settings-config.md` (for entry/result-limit and home-entry toggles reused by split PRs)

## Quality Gates

- `cargo fmt --all -- --check`
- `cargo clippy --all -- -D warnings`
- `cargo test --all`
- `flutter analyze`
- `flutter test`

## Acceptance Criteria

- [ ] Note list/editor flow works end-to-end
- [ ] Tag attach/detach/filter works on existing notes
- [ ] API docs and compatibility docs are updated if contract changed
- [ ] Tests added for core path and Flutter flow
