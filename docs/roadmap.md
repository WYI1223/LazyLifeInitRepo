# Project Roadmap

This file tracks architecture/product items that are confirmed but not in the
current implementation scope.

## Current Delivery Focus

- Active scope: v0.1 closure (`PR-0017A` — debug viewer readability baseline)
- Gate for v0.1.5: PR-0017A must merge first
- Next: v0.1.5 (`PR-0011` — Atom Time-Matrix, Inbox/Today/Upcoming sections)

## Deferred from v0.1 / Landed in v0.1.5

- `PR-0011` tasks views → **v0.1.5** (Atom Time-Matrix; `docs/releases/v0.1.5/README.md`)

## Deferred / v0.2+

- Attachment management for non-image files:
  - add dedicated `attachments` relation.
- YAML frontmatter parsing:
  - parse metadata from markdown frontmatter.
  - map selected metadata to system tags.
- Multi-dimensional tag filtering:
  - support AND/OR/NOT combinations beyond single-tag equality.
- Markdown rendering in Flutter (render `content` in UI layer).
- Editor enhancements: syntax highlight, faster markdown input helpers.
- Notes/tags N+1 tag loading optimization (`notes_list` batch preload).

## Traceability

- v0.1 release plan: `docs/releases/v0.1/README.md`
- v0.1.5 release plan: `docs/releases/v0.1.5/README.md`
- v0.2+ release plan: `docs/releases/v0.2/README.md`
- Product milestone tracker: `docs/product/milestones.md`
- Product release track: `docs/product/roadmap.md`
