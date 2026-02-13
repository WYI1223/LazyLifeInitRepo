# Architecture Overview

## Purpose

This document defines the current LazyNote architecture baseline for v0.1.

Focus:

- local-first data ownership
- Rust Core as business boundary
- Flutter as UI/runtime boundary
- staged delivery via `docs/releases/v0.1/`

## System Boundaries

### Flutter (`apps/lazynote_flutter`)

Responsibilities:

- UI rendering and interaction flow
- route/shell orchestration
- platform-level integration (window/runtime bootstrap)
- diagnostics surface (for developers)

Non-responsibilities:

- direct SQLite writes
- business invariant ownership
- external sync mapping ownership

### Rust Core (`crates/lazynote_core`)

Responsibilities:

- canonical domain model (`Atom`)
- validation and invariants
- SQLite schema + migrations
- CRUD repository/service
- FTS search
- core logging

### FFI Boundary (`crates/lazynote_ffi`)

Responsibilities:

- expose use-case-level APIs to Flutter
- keep API contracts stable and explicit

Non-responsibilities:

- leaking storage internals

## Current Runtime Flow (v0.1 implemented)

1. Flutter starts app shell.
2. Flutter resolves log directory and initializes Rust logging through FFI.
3. Rust core opens DB and applies migrations (on DB open path).
4. UI interacts with core use-cases via FFI (currently smoke + diagnostics-oriented baseline).
5. Workbench shows right-side live logs panel for local validation.

## Data Plane

- Primary store: SQLite
- Full-text index: FTS5 (`atoms_fts`)
- Migration version source: `PRAGMA user_version`
- Soft delete policy: `is_deleted` tombstone

## Module Map (Current)

- `crates/lazynote_core/src/model`: canonical atom model
- `crates/lazynote_core/src/db`: connection bootstrap + migrations
- `crates/lazynote_core/src/repo`: persistence contracts/SQLite impl
- `crates/lazynote_core/src/service`: use-case orchestration
- `crates/lazynote_core/src/search`: FTS search
- `crates/lazynote_core/src/logging`: structured rolling logs
- `apps/lazynote_flutter/lib/features/entry`: workbench/shell
- `apps/lazynote_flutter/lib/features/diagnostics`: Rust diagnostics + log panel

## Architecture Invariants

1. Business invariants live in Rust Core.
2. FFI exposes use-cases, not SQL internals.
3. IDs are stable; delete defaults to soft delete.
4. External sync mappings are maintained in core, not UI.
5. Feature modules in Flutter must avoid cross-feature internal coupling.

See also: `docs/architecture/engineering-standards.md`.

## Delivery Status Snapshot

Implemented:

- PR-0000 to PR-0008
- PR-0017 (workbench debug logs)

Planned next:

- PR-0009+ feature loop completion (`docs/releases/v0.1/README.md`)

## Out of Scope (current state)

- production-grade multi-provider sync engine
- cloud telemetry pipeline
- cross-platform parity (non-Windows UX maturity)

## References

- `docs/releases/v0.1/README.md`
- `docs/architecture/data-model.md`
- `docs/architecture/sync-protocol.md`
- `docs/architecture/logging.md`
