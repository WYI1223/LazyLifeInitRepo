# Privacy

## Purpose

This document defines the v0.1 privacy baseline for LazyNote.

## Principles

1. Local-first by default.
2. Minimum necessary data collection.
3. No telemetry/analytics upload in v0.1.
4. Sensitive data should never appear in logs.

## Data Categories

### Core local data

- notes/tasks/events content
- metadata (IDs, timestamps, status fields)
- local configuration

Storage: local SQLite database under app data directory.

### Integration data (planned for calendar sync)

- provider identifiers and sync metadata
- OAuth tokens (when integration is enabled)

Storage: secure platform storage and/or protected local app data paths.

## Logging Privacy Rules

Never log:

- note body text
- task titles/descriptions
- calendar event description content
- access tokens / refresh tokens / secrets

Allowed in logs:

- IDs
- counts
- durations
- status/error codes

Reference: `docs/architecture/logging.md`.

## Data Sharing

v0.1 behavior:

- no background telemetry upload
- no automatic remote diagnostics upload
- user may manually export and share logs for bug reports

## User Controls

- local data remains usable offline
- user may remove local app data manually
- future export/import flow (PR-0016) is planned for portability

## Security Baseline

- secret material must not be committed to repository
- vulnerability reporting follows `SECURITY.md`
- privacy-impacting changes require docs update in the same PR

## Known Gaps (v0.1)

- dedicated in-app privacy settings UI is not complete
- full integration token lifecycle policy will be finalized with PR-0014/0015

## References

- `docs/architecture/logging.md`
- `docs/architecture/sync-protocol.md`
- `SECURITY.md`
