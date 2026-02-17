# PR-0215-provider-spi-and-sync-contract

- Proposed title: `feat(sync): provider SPI and sync contract baseline`
- Status: In Progress (core contract baseline completed; FFI exposure deferred)

## Goal

Introduce provider abstraction for calendar/tasks sync so core app depends on interfaces, not a specific provider.

## Scope (v0.2)

In scope:

- provider SPI contracts:
  - `auth`
  - `pull`
  - `push`
  - `conflict_map`
- provider status and error envelope model
- sync summary contract and telemetry-safe fields

Out of scope:

- concrete Google provider implementation
- webhook and realtime channel management

## Step-by-Step

1. Define provider SPI interfaces and DTOs.
2. Add provider registry and selection hooks.
3. Add sync summary/diagnostics contract.
4. Add tests for provider adapter compliance.

## Planned File Changes

- [add] `crates/lazynote_core/src/sync/mod.rs`
- [add] `crates/lazynote_core/src/sync/provider_spi.rs`
- [add] `crates/lazynote_core/src/sync/provider_registry.rs`
- [add] `crates/lazynote_core/src/sync/provider_types.rs`
- [edit] `crates/lazynote_core/src/lib.rs`
- [add] `docs/architecture/provider-spi.md`
- [edit] `docs/architecture/sync-protocol.md`

## Dependencies

- `PR-0213-extension-kernel-contracts`

## Verification

- `cargo test --all`
- `flutter analyze`

Completion snapshot:

- [x] Added provider SPI trait contract (`auth/pull/push/conflict_map`):
  - `crates/lazynote_core/src/sync/provider_spi.rs`
- [x] Added provider DTO/error/summary contracts:
  - provider status and auth state envelopes
  - stage-aware provider error envelope (`ProviderErrorEnvelope`)
  - telemetry-safe sync summary (`SyncSummary`)
  - `crates/lazynote_core/src/sync/provider_types.rs`
- [x] Added in-process provider registry + active selection hooks:
  - provider id validation
  - duplicate registration guard
  - `provider_not_selected` error envelope for active operations
  - `crates/lazynote_core/src/sync/provider_registry.rs`
- [x] Added provider adapter compliance tests in registry module.
  - covers invalid/blank provider ids
  - covers trimmed `select_active` behavior
  - covers reselecting active provider
  - covers `clear_active` -> active operation error path
- [x] Exported sync contracts from core crate root:
  - `crates/lazynote_core/src/lib.rs`
- [x] Added architecture docs:
  - `docs/architecture/provider-spi.md`
  - `docs/architecture/sync-protocol.md` references updated
- [x] Verification passed:
  - `cargo test -p lazynote_core`
  - `flutter analyze`

Notes:

- FFI surface is intentionally deferred in this PR to keep v0.2 baseline at
  declaration/registry contract level without binding unstable provider payloads.

## Acceptance Criteria

- [x] Provider SPI is complete for auth/pull/push/conflict needs.
- [x] Core services compile without direct provider-specific dependencies.
- [x] Contract and error mapping docs are synchronized.
