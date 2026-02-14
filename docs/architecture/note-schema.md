# Note Schema (v0.1)

## Purpose

Define the canonical note data shape used by Rust core and exposed through FFI.

## Storage Model

Notes are stored in `atoms` with:

- `type = 'note'`
- `is_deleted = 0` for active rows

Core columns used by note flow:

- `uuid` (stable note id)
- `content` (raw markdown source)
- `preview_text` (derived summary, nullable)
- `preview_image` (derived first image path, nullable)
- `updated_at` (ordering and recency)

Tag relationship:

- `tags` table (`name` unique, case-insensitive)
- `atom_tags` bridge (`atom_uuid` -> `tags.id`)

## Contract Rules

1. `note_update` is full replace:
   - caller submits complete markdown `content`
   - previous `content` is fully replaced
2. List ordering is fixed:
   - `updated_at DESC, uuid ASC`
3. Tag normalization:
   - tags are normalized to lowercase on write
   - lookup is case-insensitive
4. `note_set_tags` is atomic full replacement:
   - existing links removed
   - provided tag set inserted in one transaction
5. `notes_list` returns note rows only:
   - no task/event rows in this API

## Markdown Preview Hook

Hook runs in Rust on note create/update.

Input:

- raw markdown string (`content`)

Derived fields:

- `preview_image`:
  - extract first markdown image path with regex match (`!\[[^\]]*]\(([^)]+)\)`)
- `preview_text`:
  - remove markdown image/link/symbol syntax
  - normalize whitespace
  - keep first 100 characters

Notes:

- `content` remains source of truth.
- `preview_*` are denormalized view fields for faster list rendering.

## Pagination Rules

- default `limit = 10`
- max `limit = 50`
- single-tag filter in v0.1: `tag = X`

## Non-Goals (v0.1)

- rich markdown rendering in core
- attachment lifecycle management
- YAML frontmatter parsing
- multi-tag boolean expression filtering
