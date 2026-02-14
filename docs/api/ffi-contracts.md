# FFI Contracts

This file is the consolidated index for FFI contracts.

## Sources

- Rust API: `crates/lazynote_ffi/src/api.rs`
- Dart generated API: `apps/lazynote_flutter/lib/core/bindings/api.dart`

## v0.1 Contract Sets

1. Single Entry contracts:
   - `docs/api/ffi-contract-v0.1.md`
   - `docs/api/single-entry-contract.md`
2. Notes/tags contracts (PR-0010B):
   - this document section below

## Notes/Tags APIs (PR-0010B)

All APIs are use-case level and async.

- `note_create(content)`
- `note_update(atom_id, content)` (full replace)
- `note_get(atom_id)`
- `notes_list(tag?, limit?, offset?)`
- `note_set_tags(atom_id, tags[])` (atomic full replace)
- `tags_list()`

### Response Shape Rules

- Never require UI to parse free-text messages for branching.
- Failure branch must carry stable `error_code`.
- `message` is for diagnostics/display only.

### Notes Payload

- `atom_id`
- `content`
- `preview_text`
- `preview_image`
- `updated_at`
- `tags`

### Pagination

- default limit: `10`
- max limit: `50`
- ordering: `updated_at DESC, uuid ASC`

### Tag Semantics

- normalized lowercase storage
- case-insensitive match
- v0.1 filter is single-tag equality (`tag = X`)

## Error Code Mapping (Notes/Tags)

Producer: `crates/lazynote_ffi/src/api.rs`

- `invalid_note_id`
- `invalid_tag`
- `note_not_found`
- `db_error`
- `invalid_argument`
- `internal_error`

See full registry: `docs/api/error-codes.md`.
