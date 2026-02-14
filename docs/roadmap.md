# Project Roadmap

This file tracks architecture/product items that are confirmed but not in the
current implementation scope.

## Current Delivery Focus

- Active PR scope: `PR-0010B` (core + FFI only)
- In-scope for current implementation:
  - note create/update/get/list use-cases
  - single-tag filter (`tag = X`)
  - tag full-replace API (`note_set_tags`)
  - markdown preview hook (`preview_text`, `preview_image`)

## Deferred / Future (v0.1 later phases)

Status: Deferred until `PR-0010C` / `PR-0010D`.

- Markdown rendering in Flutter (render `content` in UI layer).
- Resource copy workflow for dragged images:
  - Flutter copies files into `%APPDATA%/LazyLife/media/`.
  - Markdown stores relative resource path.
- Editor enhancements:
  - syntax highlight
  - faster markdown input helpers
- Notes/tags repository performance hardening:
  - optimize `notes_list` tag loading to remove N+1 query pattern
  - candidate approaches: batch tag preload or grouped join aggregation
  - tracking source: PR-0010B review decision (non-blocking for v0.1 core contract)

## Deferred / v0.2+

Status: Deferred to `PR-0011` and later milestones.

- Attachment management for non-image files:
  - add dedicated `attachments` relation.
- YAML frontmatter parsing:
  - parse metadata from markdown frontmatter.
  - map selected metadata to system tags.
- Multi-dimensional tag filtering:
  - support AND/OR/NOT combinations beyond single-tag equality.

## Traceability

- Active release breakdown: `docs/releases/v0.1/README.md`
- v0.1 PR umbrella: `docs/releases/v0.1/prs/PR-0010-notes-tags.md`
- Product release track: `docs/product/roadmap.md`
