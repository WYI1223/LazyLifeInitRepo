# PR-0213-extension-kernel-contracts

- Proposed title: `feat(platform): extension kernel contracts baseline`
- Status: Completed

## Goal

Define stable extension kernel contracts so command palette, parser, provider integration, and UI extension can evolve without core rewrites.

## Scope (v0.2)

In scope:

- extension manifest baseline (id/version/capabilities/entrypoints)
- extension interface contracts:
  - command action registration
  - input parser registration
  - provider SPI hooks
  - UI slot declaration metadata
- lifecycle surface (`init`, `dispose`, `health`)
- capability model uses string enums in v0.2 (`command|parser|provider|ui_slot`)

Out of scope:

- third-party runtime loading/sandbox execution
- external marketplace/distribution
- bitflags/structured capability model (deferred)
- executable runtime loading (declaration validation only)

## Step-by-Step

1. Define extension kernel interfaces and manifest schema.
2. Add contract docs and error taxonomy.
3. Add first-party adapter for internal modules.
4. Add tests for registry integrity and manifest validation.

## Baseline Decisions (locked for PR-0213)

1. Capability model: string enums for v0.2; bitflags deferred.
2. Runtime behavior: declaration validation only.
3. Integration depth: registry-only first-party adapter wiring.
4. Error strategy: internal Rust enums; no new FFI error surface.
5. Scope boundary: do not implement PR-0214/0215 behavior in this PR.

## Planned File Changes

- [add] `crates/lazynote_core/src/extension/kernel.rs`
- [add] `crates/lazynote_core/src/extension/manifest.rs`
- [add] `crates/lazynote_core/src/extension/mod.rs`
- [edit] `crates/lazynote_core/src/lib.rs`
- [add] `docs/architecture/extension-kernel.md`
- [edit] `docs/governance/API_COMPATIBILITY.md`

## Verification

- `cargo test --all`
- `flutter analyze`

Completion snapshot:

- [x] Added extension module baseline:
  - `crates/lazynote_core/src/extension/manifest.rs`
  - `crates/lazynote_core/src/extension/kernel.rs`
  - `crates/lazynote_core/src/extension/mod.rs`
- [x] Re-exported extension contracts from `crates/lazynote_core/src/lib.rs`.
- [x] Added declaration-time manifest validation and internal error taxonomy.
- [x] Added registry-only first-party adapter wiring and capability index tests.
- [x] Added architecture contract doc: `docs/architecture/extension-kernel.md`.
- [x] Updated compatibility governance for internal architecture contracts.
- [x] Verification passed:
  - `cargo test -p lazynote_core`
  - `flutter analyze`

## Acceptance Criteria

- [x] Extension kernel contracts are documented and implemented.
- [x] First-party modules can register through contract adapters.
- [x] Contract tests prevent invalid manifest/entrypoint wiring.
