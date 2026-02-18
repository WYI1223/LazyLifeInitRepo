# PR-0214-command-registry-and-parser-chain

- Proposed title: `feat(entry): command registry and parser chain baseline`
- Status: Completed

## Goal

Refactor Single Entry into an extension-driven registry so commands and input parsers are pluggable.

## Scope (v0.2)

In scope:

- command registry with namespaced command ids
- parser chain with priority and deterministic short-circuit behavior
- conflict handling for duplicate command ids/parser overlaps
- first-party command migration to registry
- explicit boundary for command model ownership in v0.2:
  - `EntryCommand` subtype hierarchy remains first-party internal (`sealed`)
  - extension point is registry/parser registration, not command subclass export

Out of scope:

- third-party downloadable parser plugins
- cloud command execution
- cross-day schedule range semantics (parser keeps same-day `end > start` contract)

## Step-by-Step

1. Add command registry interfaces and adapters.
2. Add parser chain with priority and timeout budget.
3. Migrate first-party entry commands to registry registration.
4. Add tests for parser precedence and conflict behavior.

## Planned File Changes

- [edit] `apps/lazynote_flutter/lib/features/entry/command_parser.dart`
- [add] `apps/lazynote_flutter/lib/features/entry/command_registry.dart`
- [edit] `apps/lazynote_flutter/lib/features/entry/single_entry_controller.dart`
- [add] `apps/lazynote_flutter/test/entry_registry_parser_chain_test.dart`

## Dependencies

- `PR-0213-extension-kernel-contracts`

## Verification

- `flutter analyze`
- `flutter test`

Completion snapshot:

- [x] Added parser chain contract with:
  - namespaced parser ids
  - priority ordering and deterministic short-circuit
  - timeout budget handling (`parser_timeout`)
  - duplicate parser-id conflict error
- [x] Added command registry contract with:
  - namespaced command ids
  - duplicate command-id conflict error
  - action-label lookup for detail payloads
- [x] Migrated Single Entry command execution from hardcoded switch to registry dispatch.
- [x] Added parser/registry regression tests in `entry_registry_parser_chain_test.dart`.
- [x] Clarified v0.2 command-model boundary:
  - `EntryCommand` remains internal/sealed to Flutter app code
  - extension pluggability is provided by registry/parser contracts
- [x] Verification passed:
  - `flutter analyze`
  - `flutter test`

## Acceptance Criteria

- [x] First-party commands are loaded via registry, not hardcoded switch flow.
- [x] Parser chain ordering and timeout behavior are deterministic and tested.
- [x] Duplicate registration conflicts return explicit errors.
