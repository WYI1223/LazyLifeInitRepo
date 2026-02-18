# PR-0218-api-lifecycle-policy

- Proposed title: `docs/governance: API lifecycle and deprecation-first policy`
- Status: Completed

## Goal

Set stable API lifecycle rules for extension and provider surfaces, aligned with backward-compatibility-first governance.

## Scope (v0.2)

In scope:

- API stability classes (`experimental`, `stable`, `deprecated`)
- deprecation window policy before removal
- version negotiation guideline for extension/provider contracts
- release note requirements for API-affecting changes

Out of scope:

- fully automated compatibility CI enforcement (planned in v1.0)

## Step-by-Step

1. Define lifecycle policy document and examples.
2. Update governance docs and PR checklist references.
3. Tag existing APIs by stability class where needed.
4. Add manual checklist for deprecation communication.

## Planned File Changes

- [edit] `docs/governance/API_COMPATIBILITY.md`
- [edit] `docs/governance/CONTRIBUTING.md`
- [edit] `docs/product/roadmap.md`
- [add] `docs/governance/api-lifecycle-policy.md`

## Dependencies

- `PR-0213-extension-kernel-contracts`

## Verification

- Docs link and policy consistency review

## Completion Snapshot

- [x] Added canonical lifecycle policy doc:
  - `docs/governance/api-lifecycle-policy.md`
- [x] Synced compatibility policy to canonical lifecycle policy entry:
  - `docs/governance/API_COMPATIBILITY.md`
- [x] Updated governance contribution guidance with lifecycle requirements:
  - `docs/governance/CONTRIBUTING.md`
- [x] Updated docs entry index to include lifecycle policy:
  - `docs/index.md`
- [x] Updated roadmap scope text to reflect lifecycle baseline in v0.2:
  - `docs/product/roadmap.md`
- [x] Added explicit internal-boundary note for command model:
  - `EntryCommand` sealed hierarchy is implementation detail, not public API
  - canonicalized in `docs/governance/api-lifecycle-policy.md`

## Acceptance Criteria

- [x] Lifecycle/deprecation policy is explicit and discoverable.
- [x] Extension/provider API changes require policy-compliant notes.
- [x] Governance docs reference one canonical lifecycle policy.
