# LazyNote

> A minimal, local-first personal productivity system.
> Notes, tasks, and calendar converge into a single entry point.

**[中文文档 →](README_ZH.md)**

---

## What is LazyNote?

LazyNote is a personal productivity app built around three core values:

- **Single Entry** — One search bar and command panel. All key actions are directly reachable.
- **Strong Linkage** — Notes, tasks, and events are different views of the same data graph.
- **Low Friction** — Simple by default, powerful by choice. No feature bloat, no cognitive overhead.

This is not "the most feature-rich" productivity tool. It is the one with the least friction.

---

## Design Principles

| Principle | Description |
|-----------|-------------|
| **Local-First** | Data lives on-device by default. Offline is always available. Sync is optional. |
| **Privacy-First** | Minimum permissions, zero telemetry by default, no forced account. |
| **One Input** | A unified entry point is preferred over multi-page navigation. |
| **Default Simple** | Complex features (e.g., graph view, semantic search) are opt-in, not default. |
| **Cross-Platform by Design** | Architecture targets Windows / macOS / iOS / Android from the start. |

---

## Architecture

```
┌─────────────────────────────────────┐
│         Flutter UI Layer            │
│  Single Entry · Notes · Diagnostics │
└────────────────┬────────────────────┘
                 │  Flutter-Rust Bridge (FRB / FFI)
┌────────────────▼────────────────────┐
│           Rust Core Layer           │
│  Domain Model · Services · Search   │
│  Repo · Migrations · Logging        │
└────────────────┬────────────────────┘
                 │
┌────────────────▼────────────────────┐
│          Local Data Plane           │
│   SQLite (atoms, tags, mappings)    │
│   FTS5 (full-text search index)     │
└─────────────────────────────────────┘
```

The Rust core is the single source of truth for all business logic. Flutter is UI-only — it communicates with the core exclusively through the FFI boundary.

---

## Package Structure

```
apps/
  lazynote_flutter/              # Flutter client (multi-platform)
    lib/
      app/                       # Routes and shell orchestration
      core/                      # RustBridge, FFI bindings (generated), settings, paths
      features/
        entry/                   # Single-entry search + command panel
        notes/                   # Note list, editor, tag filter UI
        tags/                    # Tag filter widget
        search/                  # Search results view
        diagnostics/             # Rust health panel + live log viewer

crates/
  lazynote_core/                 # All business logic (Rust)
    src/
      model/atom.rs              # Canonical Atom entity
      db/                        # SQLite bootstrap + versioned migrations
      repo/                      # Persistence traits + SQLite implementations
      service/                   # Use-case orchestration (NoteService, AtomService)
      search/fts.rs              # FTS5 full-text search
      logging.rs                 # Structured rolling-file logger

  lazynote_ffi/                  # FFI boundary (thin wrappers, no logic)
    src/api.rs                   # Exported FFI functions — edit here
    src/frb_generated.rs         # AUTO-GENERATED — do not edit

  lazynote_cli/                  # CLI debug/import/export tools (stub)

docs/                            # Architecture, API contracts, release plans
scripts/                         # doctor.ps1, gen_bindings.ps1, format.ps1
```

---

## Data Model

LazyNote unifies notes, tasks, and events into a single canonical entity: **Atom**.

The same record can be projected as a note, task, or event. `kind` drives UI rendering shape only; list section membership (Inbox/Today/Upcoming) is determined by `start_at`/`end_at` nullability — not by `kind`. There is no data duplication across entity types.

| Field | Type | Description |
|-------|------|-------------|
| `uuid` | UUIDv4 | Stable global identifier, never reused |
| `kind` | `note \| task \| event` | Rendering hint only — does not drive section classification |
| `content` | String | Markdown body |
| `preview_text` | String? | Derived from content (first plain text) |
| `task_status` | Enum? | `todo \| in_progress \| done \| cancelled`; NULL = no status |
| `start_at` | i64? | Epoch ms — time-matrix anchor (Migration 6, v0.1.5) |
| `end_at` | i64? | Epoch ms; always ≥ `start_at` (Migration 6, v0.1.5) |
| `recurrence_rule` | String? | Reserved RFC 5545 RRULE string — NULL until v0.2+ |
| `is_deleted` | bool | Soft-delete tombstone — authoritative for visibility |
| `hlc_timestamp` | String? | Reserved for CRDT sync (not yet active) |

**Invariants enforced in code:**
- `uuid` is never nil
- `end_at >= start_at` when both are set
- All default queries filter `WHERE is_deleted = 0`
- Deletion is soft-delete only — `DELETE` statements on `atoms` are prohibited

---

## Current Implementation Status (v0.1)

| Feature | Status |
|---------|--------|
| Atom data model + SQLite schema | Implemented |
| SQLite migrations (5 versions) | Implemented |
| FTS5 full-text search | Implemented |
| Note CRUD via FFI | Implemented |
| Tag management (create, assign, filter) | Implemented |
| Single-entry search + command panel | Implemented |
| Note editor (Markdown) | Implemented |
| Structured logging + diagnostics panel | Implemented |
| Windows build | Implemented |
| Tasks engine (Atom Time-Matrix, Inbox/Today/Upcoming) | Planned (v0.1.5 — PR-0011) |
| Calendar engine | Planned (post-v0.1) |
| Google Calendar sync | Planned (post-v0.1) |
| Import / export | Planned (post-v0.1) |
| Mobile (iOS / Android) | Planned (post-v0.1) |
| CRDT / multi-device sync | Planned (long-term) |

---

## Development Setup

### Prerequisites

- Rust stable toolchain (see `rust-toolchain.toml`)
- Flutter SDK (Dart ≥ 3.11)
- Windows SDK (for Windows builds)

### Quick Verification

```powershell
# From repo root
./scripts/doctor.ps1
```

### Build

```bash
# Rust (from crates/)
cargo build --all

# Flutter (from apps/lazynote_flutter/)
flutter pub get
flutter build windows --debug
```

### Test

```bash
# Rust (from crates/)
cargo test --all

# Flutter (from apps/lazynote_flutter/)
flutter test
```

### Code Generation

After modifying `crates/lazynote_ffi/src/api.rs`, regenerate the FFI bindings:

```powershell
./scripts/gen_bindings.ps1
```

For detailed Windows setup instructions, see [docs/development/windows-quickstart.md](docs/development/windows-quickstart.md).

---

## Runtime File Layout

On Windows, LazyNote stores all runtime files under `%APPDATA%\LazyLife\`:

```
%APPDATA%\LazyLife\
  settings.json       — App settings
  logs/               — Rolling log files
  data/
    lazynote.db       — SQLite database
```

---

## Roadmap

| Phase | Focus |
|-------|-------|
| **v0.1** (closing) | Notes + tags + full-text search + single-entry panel |
| **v0.1.5** | Atom Time-Matrix — Inbox/Today/Upcoming task views (PR-0011) |
| **v0.2** | Global hotkey, notes tree (hierarchy), split-pane layout |
| **v0.3** | Advanced layout, drag-to-split, cross-pane sync |
| **v1.0** | Plugin sandbox, iOS distribution, API compat CI gates |

v0.1.5: tasks + time-matrix (PR-0011). Post-v0.1.5: calendar, Google Calendar sync, import/export, mobile.

---

## Key Documentation

| Document | Description |
|----------|-------------|
| [docs/architecture/engineering-standards.md](docs/architecture/engineering-standards.md) | 6 mandatory architecture rules |
| [docs/architecture/data-model.md](docs/architecture/data-model.md) | Atom entity spec and schema |
| [docs/api/ffi-contract-v0.1.md](docs/api/ffi-contract-v0.1.md) | Full FFI API contract |
| [docs/api/error-codes.md](docs/api/error-codes.md) | Stable error code registry |
| [docs/governance/API_COMPATIBILITY.md](docs/governance/API_COMPATIBILITY.md) | API breaking change policy |
| [docs/releases/v0.1/README.md](docs/releases/v0.1/README.md) | v0.1 release plan and PR roadmap |
| [docs/development/windows-quickstart.md](docs/development/windows-quickstart.md) | Windows setup guide |
| [CLAUDE.md](CLAUDE.md) | AI agent development guide |

---

## Contributing

See [docs/governance/CONTRIBUTING.md](docs/governance/CONTRIBUTING.md) for contribution guidelines.

Commits follow [Conventional Commits](https://www.conventionalcommits.org/):
`feat(scope):`, `fix(scope):`, `chore(scope):`, `docs(scope):`, `test(scope):`, `refactor(scope):`

One concern per PR. No mixing features with unrelated refactoring.

---

## License

[MIT License](LICENSE)
