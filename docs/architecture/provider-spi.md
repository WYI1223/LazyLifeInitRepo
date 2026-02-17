# Provider SPI (v0.2 Baseline)

## Purpose

Define a provider abstraction for sync flows so core app services depend on
stable interfaces instead of provider-specific implementations.

## Scope (v0.2)

In scope:

- provider SPI trait with four operations:
  - `auth`
  - `pull`
  - `push`
  - `conflict_map`
- provider registry and active-provider selection hooks
- provider status and unified error envelope model
- telemetry-safe sync summary contract

Out of scope:

- concrete provider adapters (for example Google)
- webhook/realtime channel lifecycle
- cross-process plugin runtime and sandboxing

## Core Contracts

### Provider Trait

`ProviderSpi` exposes:

- `provider_id()`
- `status()`
- `auth(request)`
- `pull(request)`
- `push(request)`
- `conflict_map(request)`

All operations return `ProviderResult<T>`, which is:

- `Ok(...)` on success
- `Err(ProviderErrorEnvelope)` on failure

### Error Envelope

`ProviderErrorEnvelope` fields:

- `provider_id`
- `stage` (`Auth | Pull | Push | ConflictMap`)
- `code` (stable machine-branchable string)
- `message` (human-readable diagnostics)
- `retriable` (`true/false`)

### Status Envelope

`ProviderStatus` fields:

- `provider_id`
- `health` (`Healthy | Degraded | Unavailable`)
- `auth_state` (`Unauthenticated | Authenticating | Authenticated | Expired`)
- `last_sync_at_ms`

### Sync Summary

`SyncSummary` is telemetry-safe and contains only aggregate fields:

- provider and timing (`provider_id`, `started_at_ms`, `finished_at_ms`)
- counters (`pulled_records`, `pushed_changes`, `conflicts_*`)
- optional `error_code`

No token or payload content is included.

## Registry Contract

`ProviderRegistry` responsibilities:

- validate provider id shape and reject invalid IDs
  - v0.2 id format: `[a-z0-9_-]+`
- reject duplicate provider registrations
- support explicit active-provider selection
  - `register/select_active/get` normalize input by `trim()`
- provide active-operation hooks (`auth_active/pull_active/push_active/conflict_map_active`)
- return explicit `provider_not_selected` envelope when active provider is not set

## Notes

- v0.2 baseline is in-process and contract-focused.
- FFI exposure of provider SPI is intentionally deferred until concrete provider
  integration requirements are finalized.
