# Extension Kernel Contracts (v0.2 Baseline)

## Purpose

Define a stable extension contract layer so command, parser, provider, and UI
slot integrations can evolve without rewriting core business services.

## Scope (v0.2)

In scope:

- manifest declaration model (`id`, `version`, `capabilities`, `entrypoints`)
- declaration-time manifest validation
- in-process extension registry contract
- first-party adapter registration path
- lifecycle surface declaration (`init`, `dispose`, `health`)

Out of scope:

- dynamic loading/sandbox runtime
- third-party package discovery/distribution
- executable entrypoint invocation engine

## Capability Model

v0.2 uses **string capability enums**:

- `command`
- `parser`
- `provider`
- `ui_slot`

Bitflags/structured capability model is intentionally deferred to later PRs.

## Manifest Contract

`ExtensionManifest` fields:

- `id`: stable extension id (lowercase alnum with `.`/`_`/`-` separators)
- `version`: semantic triplet (`major.minor.patch`)
- `capabilities`: non-empty set of supported capability strings
- `entrypoints`: declaration-only string identifiers

Validation rules:

- id/version format must be valid
- capabilities must be supported and deduplicated
- capability-specific entrypoint declaration must exist
- lifecycle declarations `init/dispose/health` are required

## Registry Contract

`ExtensionRegistry`:

- validates manifest before registration
- rejects duplicate extension ids
- maintains capability index for lookup
- supports first-party adapter baseline registration

This registry is declaration-only in v0.2 and does not execute entrypoints.

## Error Taxonomy (Internal)

- `ManifestValidationError`
  - id/version/capability/entrypoint declaration errors
- `ExtensionKernelError`
  - invalid manifest wrapper
  - duplicate extension id

These are internal core enums; no FFI contract exposure in PR-0213.
