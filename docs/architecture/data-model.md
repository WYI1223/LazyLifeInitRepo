# Data Model

## Purpose

This document defines the canonical data model used by LazyNote core, covering v0.1 through v0.2.

## Canonical Entity: Atom

`Atom` is the single storage shape for all projections (note/task/event). There are no separate entity tables. All data lives in `atoms`.

### Fields

| Field | Type | Nullable | Description |
|-------|------|----------|-------------|
| `uuid` | TEXT | NO | Stable UUIDv4, never reused |
| `type` | TEXT | NO | Rendering hint: `note \| task \| event`. Determines UI form, not list classification. |
| `content` | TEXT | NO | Markdown body |
| `task_status` | TEXT | YES | `todo \| in_progress \| done \| cancelled`. Applies to all atom types (universal completion). NULL = no status (statusless / note-like). Setting to `null` demotes the atom. |
| `start_at` | INTEGER | YES | Epoch ms. Meaning depends on time-matrix quadrant. |
| `end_at` | INTEGER | YES | Epoch ms. Meaning depends on time-matrix quadrant. |
| `recurrence_rule` | TEXT | YES | Reserved — RFC 5545 RRULE string (e.g. `FREQ=WEEKLY`). **v0.1.5: always NULL, no logic.** |
| `preview_text` | TEXT | YES | Derived first non-empty text line |
| `preview_image` | TEXT | YES | Derived first markdown image path |
| `hlc_timestamp` | TEXT | YES | Reserved for CRDT/HLC merge logic |
| `is_deleted` | INTEGER | NO | `0 \| 1` soft-delete flag |
| `created_at` | INTEGER | NO | Epoch ms |
| `updated_at` | INTEGER | NO | Epoch ms |

Code reference: `crates/lazynote_core/src/model/atom.rs`.

---

## Workspace Tree Entity (v0.2)

`workspace_nodes` stores hierarchy metadata for folders and note references.

### Fields

| Field | Type | Nullable | Description |
|-------|------|----------|-------------|
| `node_uuid` | TEXT | NO | Stable workspace-node UUID |
| `kind` | TEXT | NO | `folder \| note_ref` |
| `parent_uuid` | TEXT | YES | Parent workspace node id (`NULL` = root) |
| `atom_uuid` | TEXT | YES | Required for `note_ref`; must be `NULL` for `folder` |
| `display_name` | TEXT | NO | Node label field (`folder` authoritative; `note_ref` reserved for compatibility/placeholder in v0.2) |
| `sort_order` | INTEGER | NO | Backend compatibility ordering key for deterministic storage/replay |
| `is_deleted` | INTEGER | NO | `0 \| 1` soft-delete marker |
| `created_at` | INTEGER | NO | Epoch ms |
| `updated_at` | INTEGER | NO | Epoch ms |

### Tree Invariants

1. `kind='folder'` must not carry `atom_uuid`.
2. `kind='note_ref'` must carry `atom_uuid`; create/update validates target as an active note atom.
3. `parent_uuid` may be `NULL` (root) or reference another `workspace_nodes.node_uuid`.
4. Service layer rejects cycle-producing moves (`A -> ... -> A`).
5. Core child listing order is deterministic for storage/replay: `sort_order ASC, node_uuid ASC`.
6. Atom delete/type change is not blocked by existing `note_ref`; references may become dangling.
7. Tree read paths hide invalid `note_ref` and only surface active-note references.

Code reference: `crates/lazynote_core/src/repo/tree_repo.rs`, `crates/lazynote_core/src/service/tree_service.rs`.

### Title/Label Semantics Freeze (v0.2)

This is a product-boundary policy layered on top of the schema:

1. Canonical content owner is still `atoms.content`.
2. `note/task/event` visible titles in Explorer are projection values derived from Atom data (and draft state in Flutter), not a separately user-managed `note_ref` alias.
3. `workspace_nodes.display_name` remains in schema for forward compatibility, but `note_ref` rename is frozen in v0.2.
4. `folder` rename remains fully supported and uses `workspace_nodes.display_name` as the authoritative folder label.
5. Independent `note_ref` alias/title editing is deferred to a later milestone (v3+).

### Explorer Ordering/Move Transition Freeze (v0.2)

This is a UI policy freeze that coexists with the current schema:

1. Explorer move is parent-change-only; same-parent manual reorder is not a user capability.
2. `workspace_move_node(..., target_order?)` is retained for compatibility, but UI move paths use `target_order = null`.
3. Explorer row order policy:
   - root: synthetic `Uncategorized` first, then folders by name ascending (case-insensitive)
   - folder children: `folder` group first, `note_ref` group second
   - within each group: name ascending (case-insensitive), stable id tie-break
   - `Uncategorized` note rows: by note `updated_at DESC`, then note id tie-break
4. Explorer note rows are title-only (no preview text line in row rendering).

---

## Atom Time-Matrix (v0.1.5+)

Classification for list views is **driven entirely by `start_at`/`end_at` nullability** — not by the `type` field.

| start_at | end_at | Semantic | UI rendering | Default section |
|----------|--------|----------|--------------|----------------|
| NULL | NULL | Pure note / idea (Timeless) | Plain text | **Inbox** |
| NULL | Value | DDL task — "complete before end_at" | Checkbox + countdown | **Today** (if end_at ≤ today) or **Upcoming** |
| Value | NULL | Ongoing task — "started at start_at, no deadline" | Checkbox + elapsed time | **Today** (if start_at ≤ today) or **Upcoming** |
| Value | Value | Timed event / time block | Time range bar | **Today** (if overlaps today) or **Upcoming** |

**Rule**: `type` decides shape; time-matrix decides position. These two axes are independent.

---

## Section Query Logic

Let `BOD` = today 00:00:00 (device local, epoch ms), `EOD` = today 23:59:59.

Atoms with `task_status IN ('done', 'cancelled')` are excluded from all sections.

### Inbox

```sql
WHERE start_at IS NULL
  AND end_at IS NULL
  AND (task_status IS NULL OR task_status NOT IN ('done', 'cancelled'))
  AND is_deleted = 0
ORDER BY updated_at DESC, uuid ASC
```

### Today

Any atom "active today" — three OR conditions:

```sql
WHERE is_deleted = 0
  AND (task_status IS NULL OR task_status NOT IN ('done', 'cancelled'))
  AND (
    -- DDL overdue or due today [NULL, Value]
    (end_at IS NOT NULL AND end_at <= :eod AND start_at IS NULL)
    -- Ongoing task already started [Value, NULL]
    OR (start_at IS NOT NULL AND end_at IS NULL AND start_at <= :eod)
    -- Event overlapping today [Value, Value]
    OR (start_at IS NOT NULL AND end_at IS NOT NULL
        AND start_at <= :eod AND end_at >= :bod)
  )
ORDER BY COALESCE(start_at, end_at) ASC, updated_at DESC
```

### Upcoming

Any atom anchored entirely in the future:

```sql
WHERE is_deleted = 0
  AND (task_status IS NULL OR task_status NOT IN ('done', 'cancelled'))
  AND (
    -- Future DDL [NULL, Value]
    (end_at IS NOT NULL AND end_at > :eod AND start_at IS NULL)
    -- Future ongoing [Value, NULL]
    OR (start_at IS NOT NULL AND end_at IS NULL AND start_at > :eod)
    -- Future event [Value, Value]
    OR (start_at IS NOT NULL AND end_at IS NOT NULL AND start_at > :eod)
  )
ORDER BY COALESCE(start_at, end_at) ASC, updated_at DESC
```

---

## Invariants

1. `uuid` is stable, never nil, never reused.
2. `end_at >= start_at` when both are non-null.
3. `is_deleted` is the source of truth for visibility lifecycle.
4. `recurrence_rule` must be NULL or a valid RFC 5545 RRULE string (enforced when logic is activated in v0.2+).

Enforcement: `Atom::validate()`, DB `CHECK` constraints, repository write boundaries.

---

## Projection Strategy

The `type` field drives UI rendering only:

- `type = 'note'`: plain text display
- `type = 'task'`: checkbox, status indicator
- `type = 'event'`: time range bar, calendar slot

List section membership (Inbox/Today/Upcoming) is derived from time fields, not `type`.

---

## Relational Schema

| Migration | File | Change |
|-----------|------|--------|
| 1 | `0001_init.sql` | `atoms` table with `type`, content, timestamps, soft-delete |
| 2 | `0002_tags.sql` | `tags`, `atom_tags` junction |
| 3 | `0003_external_mappings.sql` | `external_mappings` for sync linkage |
| 4 | `0004_fts.sql` | `atoms_fts` FTS5 virtual table + sync triggers |
| 5 | `0005_note_preview.sql` | `preview_text`, `preview_image` columns |
| 6 | `0006_time_matrix.sql` | Rename `event_start`→`start_at`, `event_end`→`end_at`; add `recurrence_rule TEXT` |
| 7 | `0007_workspace_tree.sql` | Add `workspace_nodes`, ordering index, and note-ref integrity triggers |
| 8 | `0008_workspace_tree_delete_policy.sql` | Remove atom-side blocking triggers and switch tree visibility to read-time filtering |

---

## Search Model

FTS index behavior:

- Indexes `content` from all non-deleted atoms regardless of `type`.
- Search results include notes, tasks, and events in a unified result set.
- Frontend uses `type` to render result rows differently (checkbox badge, time badge, etc.).
- Rank + deterministic tie-break: `updated_at DESC, uuid ASC`.

Code reference: `crates/lazynote_core/src/search/fts.rs`.

---

## ID Policy

- Primary ID: UUID string, generated in Rust Core.
- FFI and UI treat IDs as opaque stable identifiers.

---

## Deletion Policy

- Business-path deletion: soft-delete only (`is_deleted = 1`).
- Search and list APIs exclude `is_deleted = 1` rows.
- Maintenance/purge hard-delete requires an ADR (see `engineering-standards.md` Rule C).

---

## External Mapping Model

`external_mappings` provides provider linkage for future sync:

| Column | Description |
|--------|-------------|
| `provider` | Sync provider name (e.g. `google_calendar`) |
| `external_id` | Provider-side ID |
| `atom_uuid` | Foreign key to `atoms.uuid` |
| `external_version` | Provider version/etag |
| `last_synced_at` | Epoch ms of last sync |

Uniqueness constraints: `(provider, external_id)` and `(provider, atom_uuid)`.

---

## Known Deferred Work

| Item | Target |
|------|--------|
| `Atom` fields currently public | v0.2: privatize fields, use typed mutation paths |
| `hlc_timestamp` reserved | Future: CRDT/HLC merge logic |
| `recurrence_rule` field added | v0.2+: RRULE calculation engine (Rust `rrule` crate) |

---

## References

- `docs/releases/v0.1/prs/PR-0004-atom-model.md`
- `docs/releases/v0.1/prs/PR-0005-sqlite-schema-migrations.md`
- `docs/releases/v0.1/prs/PR-0006-core-crud.md`
- `docs/releases/v0.1/prs/PR-0007-fts5-search.md`
- `docs/releases/v0.1.5/README.md`
