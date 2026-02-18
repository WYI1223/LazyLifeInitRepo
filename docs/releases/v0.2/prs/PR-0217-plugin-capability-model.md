# PR-0217-plugin-capability-model

- Proposed title: `feat(security): plugin capability model baseline`
- Status: Completed

## Goal

Establish capability-based permission declarations for extensions before sandbox runtime arrives.

## Scope (v0.2)

In scope:

- capability schema:
  - `network`
  - `file`
  - `notification`
  - `calendar`
- manifest-declared capability validation
- runtime gate checks in extension invocation path
- user-visible capability description strings

Out of scope:

- process-level sandbox runtime
- signed plugin distribution policy

## Step-by-Step

1. Define capability schema and validation rules.
2. Add enforcement points in extension invocation path.
3. Add deny-by-default behavior for undeclared capabilities.
4. Add tests for allow/deny matrix.

## Planned File Changes

- [add] `crates/lazynote_core/src/extension/capability.rs`
- [edit] `crates/lazynote_core/src/extension/kernel.rs`
- [edit] `apps/lazynote_flutter/lib/features/settings/*`
- [add] `docs/governance/plugin-capabilities.md`
- [add] `crates/lazynote_core/tests/capability_guard_test.rs`

## Dependencies

- `PR-0213-extension-kernel-contracts`
- `PR-0215-provider-spi-and-sync-contract`

## Verification

- `cargo test --all`
- `flutter test`

## Completion Snapshot

- [x] Added runtime capability schema (`network|file|notification|calendar`):
  - `crates/lazynote_core/src/extension/capability.rs`
- [x] Added manifest runtime capability declaration + strict validation:
  - `ExtensionManifest.runtime_capabilities`
  - dedupe/unsupported/empty validation in `manifest.validate()`
- [x] Added deny-by-default invocation guard in extension registry:
  - `ExtensionRegistry::assert_runtime_capability(...)`
- [x] Added allow/deny matrix tests:
  - `crates/lazynote_core/tests/capability_guard_test.rs`
- [x] Added governance policy doc for capability descriptions and guard semantics:
  - `docs/governance/plugin-capabilities.md`
- [x] Added invocation-level capability enforcement in extension kernel:
  - `ExtensionInvocation` to runtime-capability mapping
  - `ExtensionRegistry::assert_invocation_allowed(...)`
  - unit tests for allow/deny behavior and provider-sync multi-capability guard
- [x] Added Flutter settings capability visibility surface:
  - `SettingsCapabilityPage` with extension snapshot + capability catalog
  - Workbench `Settings` section wired from placeholder to audit page
  - widget/smoke tests for capability visibility and route reachability
- [x] Clarified v0.2 audit data source boundary:
  - settings capability page uses first-party static snapshot data in v0.2
  - registry-backed live snapshot query is deferred follow-up work

## Acceptance Criteria

- [x] Extension invocations enforce declared capabilities with deny-by-default.
- [x] Capability declarations are visible and auditable.
- [x] Guard tests cover network/file/notification/calendar access paths.
