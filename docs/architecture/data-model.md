# Data Model

## Purpose

This document defines the canonical v0.1 data model used by LazyNote core.

## Canonical Entity: Atom

`Atom` is the single storage shape for note/task/event projections.

Current fields (implemented):

- `uuid` (stable ID)
- `type` (`note | task | event`)
- `content` (text/markdown body)
- `task_status` (`todo | in_progress | done | cancelled`, optional)
- `event_start` (epoch ms, optional)
- `event_end` (epoch ms, optional)
- `hlc_timestamp` (reserved)
- `is_deleted` (`0 | 1` soft delete)
- `created_at` (epoch ms)
- `updated_at` (epoch ms)

Code reference: `crates/lazynote_core/src/model/atom.rs`.

## Invariants

Mandatory invariants in v0.1:

1. `uuid` is stable and never reused.
2. `uuid` must not be nil.
3. `event_end >= event_start` when both exist.
4. `is_deleted` is the source of truth for visibility lifecycle.

Enforcement points:

- model validation (`Atom::validate`)
- DB schema `CHECK` constraints
- repository/service write boundaries

## Projection Strategy

UI projections map from the same atom record:

- Note projection: `type = note`
- Task projection: `type = task`
- Event projection: `type = event`

No data copying across separate entity tables for note/task/event.

## Relational Schema (v0.1)

Implemented tables:

- `atoms`
- `tags`
- `atom_tags`
- `external_mappings`
- `atoms_fts` (FTS5 virtual table)

Migration files:

- `crates/lazynote_core/src/db/migrations/0001_init.sql`
- `crates/lazynote_core/src/db/migrations/0002_tags.sql`
- `crates/lazynote_core/src/db/migrations/0003_external_mappings.sql`
- `crates/lazynote_core/src/db/migrations/0004_fts.sql`

## ID Policy

- Primary ID type: UUID string.
- ID generation: Rust core.
- FFI/UI must treat IDs as opaque stable identifiers.

## Deletion Policy

- v0.1 default: soft delete only (`is_deleted = 1`).
- Search and default list APIs exclude deleted rows.
- Hard delete is out of scope for v0.1 feature flow.

## External Mapping Model

`external_mappings` provides provider linkage for future sync:

- `provider`
- `external_id`
- `atom_uuid`
- `external_version`
- `last_synced_at`

Uniqueness:

- unique (`provider`, `external_id`)
- unique (`provider`, `atom_uuid`)

## Search Model

FTS index behavior:

- indexes `content` from non-deleted atoms
- maintained via triggers on insert/update/delete
- rank + deterministic tie-break (`updated_at DESC`, `uuid ASC`)

Code reference: `crates/lazynote_core/src/search/fts.rs`.

## Known Risks / Deferred Work

- `Atom` fields are currently public for iteration speed.
- v0.2 target: move to stricter typed mutation paths/private fields.
- `hlc_timestamp` is reserved; CRDT/HLC merge logic is not implemented in v0.1.

## References

- `docs/releases/v0.1/prs/PR-0004-atom-model.md`
- `docs/releases/v0.1/prs/PR-0005-sqlite-schema-migrations.md`
- `docs/releases/v0.1/prs/PR-0006-core-crud.md`
- `docs/releases/v0.1/prs/PR-0007-fts5-search.md`
