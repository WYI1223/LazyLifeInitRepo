# PR-0010B-notes-tags-core-ffi

- Proposed title: `feat(notes-core): note/tag use-cases and FFI contracts`
- Status: Implemented

## Goal

Land the Rust core + FFI baseline for notes/tags so Flutter can call stable typed APIs.

## Scope (v0.1)

In scope:

- note create/update/get/list use-cases (note-only path)
- single-tag filter query (for list)
- tag set/list operations (`note_set_tags` uses full replacement semantics)
- FFI DTOs + error mapping for Flutter consumption
- core/ffi tests for success and failure paths
- markdown preview hook in core (`preview_text`, `preview_image`)

Out of scope:

- rich markdown rendering semantics
- nested tags/hierarchical taxonomy
- multi-condition advanced filter syntax

## Business/Contract Requirements

1. `note_update` is full replacement.
2. Default sorting is `updated_at DESC, uuid ASC`.
3. Tag names are normalized to lowercase and treated case-insensitively.
4. `note_set_tags` atomically replaces the whole tag set.
5. `notes_list` returns `AtomType::Note` only.
6. Pagination policy: default limit `10`, max limit `50`.
7. Error handling uses stable error codes (for example: `note_not_found`, `db_error`).
8. Response contracts must be string-parse free on Flutter side:
   - explicit `ok` and `error_code`
   - stable payload fields
9. Markdown preview hook (create/update):
   - extract first markdown image path into `preview_image`
   - strip markdown symbols and keep first 100 chars in `preview_text`

## Implemented API Surface

- `note_create(content)`
- `note_update(atom_id, content)`
- `note_get(atom_id)`
- `notes_list(tag?, limit?, offset?)`
- `note_set_tags(atom_id, tags[])`
- `tags_list()`

## Implemented Notes

- Added migration `0005_note_preview.sql` for `preview_text/preview_image`.
- Added core notes repository and service:
  - `crates/lazynote_core/src/repo/note_repo.rs`
  - `crates/lazynote_core/src/service/note_service.rs`
- Updated atom model/repository for preview fields.
- Added typed FFI envelopes and error-code mapping in `crates/lazynote_ffi/src/api.rs`.
- Added core and FFI test coverage for notes/tags success and failure paths.

## File Changes

- [add] `crates/lazynote_core/src/db/migrations/0005_note_preview.sql`
- [add] `crates/lazynote_core/src/repo/note_repo.rs`
- [add] `crates/lazynote_core/src/service/note_service.rs`
- [add] `crates/lazynote_core/tests/notes_tags.rs`
- [edit] `crates/lazynote_ffi/src/api.rs`
- [edit] `crates/lazynote_core/src/model/atom.rs`
- [edit] `crates/lazynote_core/src/repo/atom_repo.rs`
- [edit] `crates/lazynote_core/src/lib.rs`
- [edit] docs under `docs/api/*`, `docs/architecture/*`, `docs/roadmap.md`

## Dependencies

- PR-0006 (core CRUD)
- PR-0007 (query/search baseline patterns)
- PR-0009D (entry command flow contracts)
- PR-0010A (UI shell locked, done)

## Quality Gates

- `cargo fmt --all -- --check`
- `cargo clippy --all -- -D warnings`
- `cargo test --all`
- `flutter analyze`
- `flutter test`

## Acceptance Criteria

- [x] Notes/tags APIs are callable via FFI with typed envelopes.
- [x] Single-tag filter returns expected note subset.
- [x] Error codes are explicit and not string-parsed by Flutter.
- [x] Core + FFI tests cover baseline success/failure paths.
