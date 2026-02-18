# API Lifecycle Policy

## Purpose

Define one canonical lifecycle policy for compatibility-sensitive API surfaces
so changes are explicit, reviewable, and reversible.

## Applies To

- Rust FFI exports in `crates/lazynote_ffi/src/api.rs`
- Dart-visible FFI bindings and response envelopes
- extension/provider contract docs (`docs/architecture/extension-kernel.md`,
  `docs/architecture/provider-spi.md`)
- behavior contracts in `docs/api/*.md`

## Non-API Internal Boundaries

The following are implementation details and not treated as external API
surfaces in v0.2:

- Flutter `EntryCommand` subtype hierarchy in
  `apps/lazynote_flutter/lib/features/entry/command_parser.dart`
  - currently `sealed` and intentionally internal to first-party app code
  - extension integration point is registry/parser contracts, not external
    subclassing of `EntryCommand`

## Stability Classes

### `experimental`

- default class for new extension/provider contracts in v0.x
- may change quickly, but changes must be documented in the same PR
- no silent drift is allowed
- recommended window: do not keep high-traffic contracts in `experimental`
  for more than 2 minor versions without explicit review

### `stable`

- backward compatibility is expected
- additive changes are preferred
- breaking changes require deprecation-first flow

### `deprecated`

- still available, but replacement path is mandatory
- must include deprecation notice and planned removal target

## Lifecycle Transitions

1. `experimental -> stable`
   - contract behavior is test-covered
   - docs are complete and linked from canonical index
2. `experimental -> removed` (allowed with constraints in v0.x)
   - must include explicit rationale in PR and release notes
   - must provide replacement guidance when callers are known
   - should prefer `experimental -> deprecated -> removed` for non-urgent cases
3. `stable -> deprecated`
   - announce replacement API
   - document deprecation start version
   - include migration guidance and release note
4. `deprecated -> removed`
   - only after minimum deprecation window
   - release note must mention final removal

## Deprecation Window

For v0.x baseline:

- minimum one minor release cycle between deprecation and removal
- minimum 30 days notice when release cadence allows

Definition:

- one minor release cycle means version progression `vX.Y -> vX.(Y+1)`
- example: deprecated in `v0.2.x`, earliest normal removal target is `v0.3.x`

Security exception:

- critical security fixes may accelerate deprecation/removal
- such changes must include explicit security rationale and migration impact

For v1.0+:

- default minimum two minor release cycles
- longer windows are preferred for widely used endpoints

## Version Negotiation Guidance

Extension/provider contracts should evolve using:

- additive fields and additive enum variants first
- explicit contract version bumps for incompatible changes
- feature/capability discovery over implicit behavior switches

## v0.2 Baseline Classification

- extension kernel contracts: `experimental`
- provider SPI contracts: `experimental`
- documented FFI envelopes and machine-branchable error codes: `stable`

## PR Checklist (API-Affecting Changes)

Every API-affecting PR must include:

1. lifecycle class impact (`experimental|stable|deprecated`)
2. contract delta in docs (`docs/api/*` and/or architecture contracts)
3. compatibility notes in release docs
4. deprecation plan (if breaking or replacement is introduced)

Enforcement note (v0.x):

- checklist is reviewer-enforced (manual gate); CI automation is planned for v1.0+
