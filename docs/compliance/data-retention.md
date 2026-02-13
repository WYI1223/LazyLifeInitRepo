# Data Retention

## Purpose

This document defines the default v0.1 data retention policy.

## Retention Scope

This policy covers:

- local SQLite data
- local rolling logs
- sync metadata (planned integration)

## Core Data Retention

- Notes/tasks/events are retained locally until user deletes them.
- Deletion in v0.1 is soft delete (`is_deleted = 1`) by default.
- Hard-delete/compaction workflows are not finalized in v0.1.

## Log Retention

Default rolling retention:

- max file size: 10MB
- max files: 5

Approximate upper bound: 50MB local logs.

Reference implementation target: `docs/architecture/logging.md`.

## Sync Metadata Retention (planned)

For provider sync features:

- retain mapping and sync cursors needed for incremental sync
- retain only required operational metadata
- never retain secrets in logs

## Manual Cleanup

v0.1 cleanup paths:

- user can remove app data directory manually
- future in-app cleanup/export controls are planned (PR-0016+)

## Privacy Constraints

Retention must respect privacy policy:

- no telemetry upload
- no sensitive content in logs
- minimal retained operational metadata

See: `docs/compliance/privacy.md`.

## Review Policy

Retention policy should be reviewed when:

- new provider integrations are introduced
- backup/export/import flows change
- legal/compliance requirements change

## References

- `docs/architecture/logging.md`
- `docs/architecture/data-model.md`
- `docs/compliance/privacy.md`
