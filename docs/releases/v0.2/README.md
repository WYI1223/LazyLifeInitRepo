# v0.2 Release Plan

## Positioning

v0.2 upgrades Notes from a single-pane feature into a workspace-capable foundation.

Theme:

- workspace runtime architecture
- hierarchical explorer baseline
- limited split layout baseline
- extension kernel contracts (command/parser/provider/ui slot/capability)
- quick-entry productivity flow
- CN/EN localization baseline
- diagnostics viewer readability phase-2 hardening
- docs language policy baseline
- links/index/open foundation

v0.2 is the architectural bridge between:

- v0.1 "usable notes flow"
- v0.3 "recursive IDE-grade split/editor experience"

## User-Facing Outcomes

At the end of v0.2, users should be able to:

1. Open quick entry with a global hotkey (Windows baseline).
2. Navigate notes in a folder-style tree (lazy loaded).
3. Open notes in an active pane and switch pane focus explicitly.
4. Use basic split layout (non-recursive baseline) with safe min-size constraints.
5. Continue using stable autosave + tag filtering from v0.1.
6. Switch UI language between Chinese and English.
7. Read debug logs with normalized semantics and denser high-volume readability.
8. Open indexed note links (file/folder/url) safely from app actions.
9. Keep existing features stable while extension architecture is introduced behind interfaces.

## Architecture Outcomes

At the end of v0.2, engineering should have:

1. Core-side tree schema and invariants (folder/note hierarchy).
2. FFI contracts for tree operations and lazy children queries.
3. Flutter `WorkspaceProvider` with state hoisting:
   - active pane
   - pane tabs
   - shared note buffers
   - save coordination hooks
4. Explorer and pane state decoupled from concrete UI layout.
5. Flutter localization scaffolding and language preference persistence.
6. Debug viewer phase-2 semantic normalization and rendering pipeline.
7. Canonical docs language policy and entrypoint baseline.
8. Link extraction/index/open use-case pipeline.
9. Extension kernel interfaces for:
   - command registration
   - input parser chain
   - provider SPI (auth/pull/push/conflict)
   - UI extension slot model
10. Capability model and API lifecycle/deprecation policy baseline.
11. Workspace delete-policy contract baseline (hybrid note/folder semantics).

This is the required substrate for v0.3 recursive split and drag-to-split.

## Scope

In scope:

- **v0.1 鈫?v0.2 infrastructure bridge** (execute first, before feature lanes):
  - Rust safety + observability hardening (`PR-0219`)
  - Flutter RustBridge lifecycle hardening (`PR-0220A`)
  - settings & config correctness (`PR-0220B`)
- global hotkey quick-entry window (`PR-0201`)
- notes tree schema + repository/service (`PR-0202`)
- workspace tree delete policy (hybrid C+B semantics) (`PR-0221`)
- tree FFI contracts + docs update (`PR-0203`)
- workspace provider foundation 鈥?incl. R02-1.1/1.2/1.3 design constraints (`PR-0204`)
- recursive explorer UI with lazy loading (`PR-0205`)
- split layout v1 (limited split, min-size guard) (`PR-0206`)
- explorer context actions + drag-reorder baseline (`PR-0207`)
- hardening and release closure 鈥?incl. regression verification for bridge PRs (`PR-0208`)
- CN/EN localization baseline (`PR-0209`)
- debug viewer readability phase-2 upgrade 鈥?incl. optional `log_dart_event` FFI (`PR-0210`)
- docs language policy and docs index baseline (`PR-0211`)
- links/index/open foundation (`PR-0212`)
- extension kernel contracts (`PR-0213`)
- command registry + parser chain baseline (`PR-0214`)
- provider SPI + sync contract (`PR-0215`)
- UI extension slots (`PR-0216`)
- plugin capability model (`PR-0217`)
- API lifecycle + compatibility policy (`PR-0218`)

Out of scope:

- unlimited recursive split layout
- drag tab to edge split
- full cross-pane live buffer sync semantics
- 60 FPS performance gate for very long markdown in multi-split
- third-party general scripting runtime for plugins
- database maintenance tooling (vacuum, purge) 鈥?reserved for v0.2.x patch or v0.3

> **Note:** v0.1 uses soft-delete only. Without periodic vacuum, long-running databases will accumulate deleted records and bloat. This is a known issue to be addressed in a maintenance-focused PR after v0.2 stabilizes.

## Dependencies from v0.1

Recommended prerequisite completion:

- `PR-0010C2` note editor + create/select
- `PR-0010C3` autosave + switch flush
- `PR-0010C4` tag filter integration closure
- `PR-0010D` notes/tags hardening
- `PR-0017A` debug viewer readability baseline

Parallel track allowed:

- `PR-0201` can progress in parallel with `PR-0010*`.

## Execution Order

Recommended order:

0. **Infrastructure bridge lane** (must land before feature work):
   - `PR-0219-rust-infrastructure-hardening` (Rust-only; fixes HIGH-risk data-path bugs)
   - `PR-0220A-flutter-lifecycle-hardening` (rust_bridge.dart; can run after PR-0219)
   - `PR-0220B-settings-config-hardening` (local_settings_store.dart; can run parallel with PR-0220A)
1. Core contract lane:
   - `PR-0202-notes-tree-schema-core`
   - `PR-0221-workspace-tree-delete-policy-hybrid`
   - `PR-0203-tree-ffi-contracts`
   - migration numbering note: reserve `0008` for workspace policy; links uses `0009`
   - current priority (execution refinement):
     - `PR-0203` Workspace CRUD FFI parity is completed (create/list/rename/move + delete contract alignment)
     - `entry_search(kind)` follow-up patch is completed (note/task/event/all filter + contract/test sync)
2. Extension kernel lane:
   - `PR-0213-extension-kernel-contracts`
   - `PR-0214-command-registry-and-parser-chain`
   - `PR-0215-provider-spi-and-sync-contract`
   - `PR-0216-ui-extension-slots`
   - `PR-0217-plugin-capability-model`
   - `PR-0218-api-lifecycle-policy`
   - post-review hardening sequence:
     - `P0` (completed): manifest/registry key canonical policy (strict reject non-canonical id/capability/runtime-capability input; add regression tests)
     - `P1` (completed): slot rendering and execution isolation (render all contributed side_panel entries; isolate callback failures with diagnostics fallback)
     - `P2` (completed): contract/document closure (capability audit data source statement, EntryCommand boundary statement, lane acceptance refresh)
3. Workspace lane (depends on bridge lane complete):
   - `PR-0204-workspace-provider-foundation` (addresses R02-1.1/1.2/1.3 by design)
   - `PR-0205-explorer-recursive-lazy-ui`
   - `PR-0206-split-layout-v1`
   - `PR-0207-explorer-context-actions-dnd-baseline`
4. Support lane (parallel after shell baseline is stable):
   - `PR-0209-ui-localization-cn-en`
   - `PR-0210-debug-viewer-readability-upgrade` (optional: add log_dart_event FFI)
   - `PR-0211-docs-language-policy-and-index`
   - `PR-0212-links-index-open-v1`
   - `PR-0201-global-hotkey-quick-entry`
5. Closure:
   - `PR-0208-workspace-hardening-doc-closure` (verifies regression targets from bridge lane)

## Current Week Execution Tasks

1. `PR-0204` M1 skeleton (workspace provider interface freeze)
   - [x] add provider/models baseline and guardrail tests for R02-1.1/1.2/1.3
   - [x] bridge `NotesController` ownership to provider (M2)
   - [x] wire `notes_page`/`entry_shell_page` to provider selectors (M3)
2. `PR-0202/0203/0221` migration + contract consistency audit
   - [ ] run migration-chain replay and FFI contract regression
3. Extension x Workspace integration smoke (minimal CI sample)
   - [ ] add one cross-lane smoke path (`slot + capability gate + workspace op`)

## Quality Gates

- `cargo fmt --all -- --check`
- `cargo clippy --all -- -D warnings`
- `cargo test --all`
- `flutter analyze`
- `flutter test`
- Windows smoke run for hotkey and split-shell interaction
- startup/memory/command-latency/background-cpu baseline capture for post-v0.2 regression tracking

## Acceptance Criteria (Release-Level)

v0.2 is complete when:

1. Tree hierarchy can be created/read/renamed/moved from UI through Rust core.
2. Explorer lazy-load behavior is stable and deterministic.
3. Active pane + limited split workflow is usable and guarded by min-size constraints.
4. Note buffer state remains coherent while switching tabs/panes.
5. Docs/API contracts are synchronized with implementation.
6. CN/EN language switch is stable and persisted locally.
7. Debug viewer phase-2 rendering remains readable under continuous high-volume refresh.
8. Link index/open baseline is implemented with scheme safety guards.
9. Extension kernel contracts are implemented and used by first-party flows where applicable.
10. API lifecycle/deprecation policy is documented and linked from governance docs.

## PR Specs

Infrastructure bridge (execute first):

- `docs/releases/v0.2/prs/PR-0219-rust-infrastructure-hardening.md`
- `docs/releases/v0.2/prs/PR-0220A-flutter-lifecycle-hardening.md`
- `docs/releases/v0.2/prs/PR-0220B-settings-config-hardening.md`

Feature lanes:

- `docs/releases/v0.2/prs/PR-0201-global-hotkey-quick-entry.md`
- `docs/releases/v0.2/prs/PR-0202-notes-tree-schema-core.md`
- `docs/releases/v0.2/prs/PR-0221-workspace-tree-delete-policy-hybrid.md`
- `docs/releases/v0.2/prs/PR-0203-tree-ffi-contracts.md`
- `docs/releases/v0.2/prs/PR-0204-workspace-provider-foundation.md`
- `docs/releases/v0.2/prs/PR-0205-explorer-recursive-lazy-ui.md`
- `docs/releases/v0.2/prs/PR-0206-split-layout-v1.md`
- `docs/releases/v0.2/prs/PR-0207-explorer-context-actions-dnd-baseline.md`
- `docs/releases/v0.2/prs/PR-0208-workspace-hardening-doc-closure.md`
- `docs/releases/v0.2/prs/PR-0209-ui-localization-cn-en.md`
- `docs/releases/v0.2/prs/PR-0210-debug-viewer-readability-upgrade.md`
- `docs/releases/v0.2/prs/PR-0211-docs-language-policy-and-index.md`
- `docs/releases/v0.2/prs/PR-0212-links-index-open-v1.md`
- `docs/releases/v0.2/prs/PR-0213-extension-kernel-contracts.md`
- `docs/releases/v0.2/prs/PR-0214-command-registry-and-parser-chain.md`
- `docs/releases/v0.2/prs/PR-0215-provider-spi-and-sync-contract.md`
- `docs/releases/v0.2/prs/PR-0216-ui-extension-slots.md`
- `docs/releases/v0.2/prs/PR-0217-plugin-capability-model.md`
- `docs/releases/v0.2/prs/PR-0218-api-lifecycle-policy.md`
