# MVP Scope (v0.1)

## Purpose

Define the minimum deliverable product scope for v0.1.

Source of truth for execution order: `docs/releases/v0.1/README.md`.

## Scope Definition

v0.1 closes one local productivity loop:

- capture notes/tasks/events
- search local content quickly
- schedule and basic task/calendar flow
- prepare provider sync baseline (Google Calendar path)

## In Scope by Capability

### Foundation (completed)

- monorepo/devex baseline
- CI baseline for Rust + Flutter
- Flutter <-> Rust wire-up
- atom model and validation baseline
- SQLite migrations and repository CRUD
- FTS5 search core
- Windows shell workbench + diagnostics log panel

### Feature loop (planned next)

- single entry router (`PR-0009`)
- notes and tags (`PR-0010`)
- task views (`PR-0011`)
- minimal calendar scheduling (`PR-0012`)
- reminders on Windows (`PR-0013`)

### Integration and portability (planned)

- Google Calendar auth + one-way sync (`PR-0014`)
- Google Calendar two-way incremental sync (`PR-0015`)
- export/import Markdown + JSON + ICS (`PR-0016`)

## Out of Scope for v0.1

- global hotkey quick entry window (moved to v0.2)
- CRDT multi-master sync
- cloud telemetry/analytics pipeline
- advanced AI orchestration features

## Acceptance Criteria (Release-Level)

v0.1 is considered complete when:

1. Core CRUD/search works end-to-end through Flutter shell.
2. Basic task/calendar interaction loop is available.
3. Google Calendar integration baseline PRs are completed.
4. Export/import baseline is available.
5. CI and documentation are green and reproducible.

## Current Progress Snapshot

- Completed: PR-0000 to PR-0008, PR-0017
- Active next target: PR-0009

## Verification Baseline

For every in-scope PR:

- quality gates pass (`fmt/analyze/test`)
- smoke flow is reproducible from Windows quickstart
- corresponding release/architecture docs are updated

## References

- `docs/releases/v0.1/README.md`
- `docs/product/milestones.md`
- `docs/product/roadmap.md`
