# Google Calendar Compliance

## Purpose

This document defines compliance and safety requirements for Google Calendar integration.

Current status:

- integration implementation is planned (`PR-0014`, `PR-0015`)
- requirements below are the mandatory baseline before release

## Compliance Principles

1. Minimum scope: request only permissions required for event sync.
2. User consent: explicit OAuth authorization required.
3. Token safety: never expose tokens in logs or UI debug text.
4. Deterministic mapping: provider IDs must map to internal stable IDs in core.

## OAuth Requirements

- Use system browser based OAuth flow (PKCE recommended).
- Do not use embedded WebView OAuth for desktop auth flow.
- Store tokens in secure local storage.
- Support token refresh and revocation handling.

## Data Handling Requirements

Allowed to persist:

- provider event ID
- sync token / cursor
- last synced timestamp
- mapping metadata (`provider <-> atom_uuid`)

Not allowed to persist in logs:

- access token / refresh token
- raw event description content
- user secrets

## Sync Safety Requirements

- Sync failures must not corrupt local canonical data.
- Partial sync must not advance checkpoint incorrectly.
- Deletion/update behavior must be explicit and reversible where possible.
- Mapping uniqueness must be enforced at DB layer.

## Logging Requirements

Sync logs should contain metadata only:

- pulled/written/conflict counts
- token-updated flag
- duration and status

No payload text from calendar events may be logged.

## User Transparency

- Clearly indicate integration is optional.
- Provide visible connection state (not connected / connected / sync error).
- Provide disconnect/revoke path in settings (planned).

## Incident Handling

If token leakage or suspected compromise occurs:

1. revoke tokens immediately
2. rotate client credentials if applicable
3. notify maintainers via `SECURITY.md` process

## Release Gate (before enabling by default)

- threat model documented
- token storage reviewed
- redaction tests in place
- error/retry behavior verified

## References

- `docs/releases/v0.1/prs/PR-0014-gcal-auth-one-way.md`
- `docs/releases/v0.1/prs/PR-0015-gcal-two-way-incremental.md`
- `docs/architecture/sync-protocol.md`
- `docs/architecture/logging.md`
- `SECURITY.md`
