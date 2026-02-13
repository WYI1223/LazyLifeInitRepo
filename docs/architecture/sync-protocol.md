# Sync Protocol

## Purpose

This document describes the synchronization protocol baseline and planned evolution.

Current status:

- v0.1 sync protocol is partially prepared at schema level.
- Full provider sync engine is not implemented yet.

## Design Goals

- keep local data authoritative (local-first)
- support deterministic provider mapping
- support incremental sync and conflict visibility
- keep sync logic inside Rust core

## Scope by Version

### v0.1 (current + planned PRs)

Already implemented:

- `external_mappings` table as canonical provider link registry
- stable atom IDs + soft-delete semantics

Planned in draft PRs:

- PR-0014: OAuth + one-way bootstrap pull
- PR-0015: two-way incremental sync with `syncToken` and provider mapping

### v0.2+

- better conflict UX and replay tooling
- broader provider support and reliability hardening

## Core Concepts

### Sync Unit

- Unit of sync is Atom-projected event/task data.
- `atom_uuid` is the canonical internal identity.

### Mapping Registry

- mapping lives in `external_mappings` (Rust core owned)
- UI must not manage provider ID mapping logic

### Deletion Semantics

- local delete = tombstone (`is_deleted = 1`)
- provider-side delete policy will be explicit per provider adapter

## Planned Protocol States (Provider Adapter)

1. `bootstrap`: initial full pull
2. `steady`: incremental pull using provider delta token
3. `reconcile`: apply local changes and resolve conflicts
4. `checkpoint`: persist sync token and sync timestamp

## Conflict Baseline (v0.1 target)

Minimal rule set (planned):

- deterministic last-writer strategy for low-risk fields
- preserve mapping consistency first
- expose conflict count and status in logs/diagnostics

Detailed conflict UI is out of scope for current v0.1 progress.

## Error Handling Principles

- sync failures must not block local CRUD operations
- token/auth failures are surfaced as actionable errors
- partial failures should retain previous stable checkpoint

## Logging and Observability

Sync-related events should emit metadata only:

- `sync_start`
- `sync_done`
- `sync_error`

Recommended fields:

- `pulled_count`
- `written_count`
- `conflict_count`
- `token_updated`
- `duration_ms`

See: `docs/architecture/logging.md`.

## Security and Compliance Boundaries

- OAuth credentials and refresh tokens are secret data
- no sensitive payload content in logs
- provider API scope must follow minimum required permissions

See: `docs/compliance/google-calendar.md` and `docs/compliance/privacy.md`.

## Non-goals (current state)

- CRDT-level multi-master merge implementation
- remote telemetry upload
- provider-agnostic universal sync abstraction in v0.1

## References

- `docs/releases/v0.1/prs/PR-0014-gcal-auth-one-way.md`
- `docs/releases/v0.1/prs/PR-0015-gcal-two-way-incremental.md`
- `docs/architecture/data-model.md`
- `docs/architecture/logging.md`
