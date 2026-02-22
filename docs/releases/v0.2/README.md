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
- notes shell style alignment with shared UI standards (`PR-0205A`)
- recursive explorer UI with lazy loading (`PR-0205`)
- explorer open-intent vs tab semantic ownership transition (`PR-0205B`)
- split layout v1 (limited split, min-size guard) (`PR-0206`)
- split pane unsplit/merge follow-up (`PR-0206B`)
- explorer context actions + drag-reorder baseline (`PR-0207`)
- explorer ordering/move contract freeze follow-up (`PR-0207B`)
- explorer ordering + legacy note_ref backfill implementation (`PR-0207C`)
- explorer ordering closure + QA replay (`PR-0207D`)
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
     - `PR-0202` tree schema/repo/service baseline is completed (status calibrated; delete-policy extension tracked in `PR-0221`)
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
   - `PR-0205A-notes-ui-shell-alignment`
   - `PR-0205-explorer-recursive-lazy-ui` (completed: recursive lazy tree + stability regressions)
   - `PR-0205B-explorer-tab-open-intent-migration` (completed: preview/pinned semantic ownership freeze)
   - `PR-0206-split-layout-v1` (in review: post-review remediation landed; QA summary logged with accepted v0.2 limitations)
   - `PR-0206B-split-pane-unsplit-merge` (in review: explicit pane close/merge command landed with regressions)
   - `PR-0207-explorer-context-actions-dnd-baseline` (completed: M1/M2 feature landing + M3 closure)
   - `PR-0207A-explorer-note-ref-title-rename-freeze` (completed: v0.2 title/rename boundary closure)
   - `PR-0207B-explorer-ordering-contract-freeze` (completed: docs contract freeze landed)
   - `PR-0207C-explorer-ordering-and-backfill-implementation` (planned)
   - `PR-0207D-explorer-ordering-closure` (planned)
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
   - [x] run migration-chain replay and FFI contract regression
   - evidence commands:
     - `cd crates && cargo test -p lazynote_core --test db_migrations`
     - `cd crates && cargo test -p lazynote_core --test workspace_tree`
     - `cd crates && cargo test -p lazynote_core --test search_fts`
     - `cd crates && cargo test -p lazynote_ffi`
     - `cd apps/lazynote_flutter && flutter test test/workspace_contract_smoke_test.dart test/entry_search_contract_smoke_test.dart`
3. Extension x Workspace integration smoke (minimal CI sample)
   - [x] add one cross-lane smoke path (`slot + capability gate + workspace op`)
   - evidence test: `apps/lazynote_flutter/test/cross_lane_workspace_extension_smoke_test.dart`
4. `PR-0205A` notes shell alignment follow-up (UI-only)
   - [x] align `My Workspace` header height with top tab strip
   - [x] restore top metadata actions (`Add icon` / `Add image` / `Add comment`)
   - [x] switch note title icon to placeholder and hide active tab border
   - contract note: no FFI/error-code delta (see `docs/api/ffi-contracts.md`)
5. `PR-0205` recursive explorer lazy behavior (M1)
   - [x] add recursive tree row/state components (`explorer_tree_item.dart`, `explorer_tree_state.dart`)
   - [x] wire lazy root/children loading and retry rendering in `note_explorer.dart`
   - [x] add root/child folder create entry and tree refresh hook (UUID parent guarded)
   - [x] keep user expand/collapse state stable across create/delete refresh (no forced `Uncategorized` re-expand)
   - [x] inject default root `Uncategorized` folder (shows root note_ref + legacy unreferenced notes without duplication)
   - [x] freeze `Uncategorized` projection requirement: folder-like UI grouping only; no duplicate note rows across folder branches
   - [x] freeze explorer ordering projection: `folder` rows before `note_ref` rows within same parent branch
   - [x] keep explorer open callback as single intent only; preview/pinned semantic ownership is deferred to `PR-0205B` -> `PR-0304` tab model
   - [x] add explorer tree regression tests (`test/note_explorer_tree_test.dart`)
6. `PR-0205B` explorer/tab semantic transition
   - [x] M1 contract freeze: explorer runtime keeps source-intent boundary only
   - [x] preview/pinned replacement policy ownership is in tab model (not explorer)
   - [x] sync `PR-0205` + `PR-0205B` wording to avoid ownership drift
   - [x] M2 tab-model semantic landing (single tap activate + rapid second tap pin preview)
   - [x] support explorer note-row double-click as explicit pinned-open shortcut intent
   - [x] explorer second-click default is pin-only (no duplicate open); `open + pin` only when target not opened
   - [x] preview replacement uses in-place tab swap (no transient append/remove jitter)
   - [x] add M2 regressions (`notes_controller_tabs_test.dart`, `tab_open_intent_migration_test.dart`)
   - [x] no regression in `notes_page_c1..c4`
   - [x] `PR-0206` start gate satisfied (`M1` interaction freeze completed)
   - [x] M3/M4 cleanup + closure
7. `PR-0206` split layout v1 (M1-M4 baseline + post-review remediation)
   - [x] add split-capable workspace layout model fields (`splitDirection`, `paneFractions`)
   - [x] add `WorkspaceProvider.splitActivePane` with max-pane guard, direction lock, and min-size (`200px`) guard
   - [x] add provider-level split regression tests (`test/workspace_provider_test.dart`)
   - [x] wire split commands and user-visible rejection feedback in Notes shell UI (M2)
   - [x] add widget regressions for split command feedback (`test/workspace_split_v1_test.dart`)
   - [x] route tab/editor projection by active pane and keep pane-local tab topology during sync (M3)
   - [x] add next-pane focus command and bridge regressions (`notes_controller_workspace_bridge_test.dart`)
   - [x] M4 hardening + closure (contracts/docs synced, split no-op feedback regression added)
   - [x] R1 fix: prevent controller/workspace active-note divergence when `note_get` fails in split mode
   - [x] R1 regression: add "detail failure does not fork active state" test
   - [x] R2 fix: route `Ctrl+Tab` / `Ctrl+Shift+Tab` by active-pane tab strip semantics (pane-local cycle)
   - [x] R2 regression: split-mode keyboard cycle test with disjoint pane tabs
   - [x] R3 fix: defensive copy and unmodifiable list wrapping in `WorkspaceLayoutState`
   - [x] R3 regression: input list mutation does not affect stored layout state
   - [x] re-run split verification bundle and update `PR-0206` status back to completed/in-review
   - [x] QA summary logged: narrow-width split attempts blocked by `200px` guard and no unsplit action (accepted as v0.2 baseline limits)
8. `PR-0206B` split pane unsplit/merge follow-up
   - [x] add explicit `close active pane` command and merge result mapping
   - [x] merge closed-pane tabs to deterministic target pane
   - [x] keep active note/editor focus coherent after merge
   - [x] add provider/controller/widget regressions for merge/blocked behavior
9. `PR-0207` explorer context actions + drag baseline
   - [x] freeze M1 boundary and guardrails in PR doc (synthetic-root policy, blank-area menu, move dialog scope, expand-state preservation)
   - [x] freeze v0.2 title/rename boundary: `note_ref` rename deferred, folder rename stays enabled
   - [x] freeze dissolve display mapping: note refs return to synthetic `Uncategorized`, child folders promote to root
   - [x] sync contract index note (`docs/api/ffi-contracts.md`) for PR-0207 M1 (no FFI shape delta)
   - [x] implement M1 context actions (new note/folder, folder rename, move)
   - [x] add M1 regressions for action matrix and expand-state persistence
   - [x] fix row-vs-blank-area right-click menu dedup (single menu per gesture target)
   - [x] fix folder row right-click hit area (icon/text/whitespace all route to row menu; no blank-area fallback on same gesture)
   - [x] fix child-folder delete immediate explorer refresh (no stale/ghost child rows)
   - [x] fix child-folder rename immediate explorer refresh (no stale child labels)
   - [x] fix synthetic `Uncategorized` note title live projection from draft content
   - [x] fix default NotesPage slot wiring for create-note-in-folder / rename / move callbacks
   - [x] add NotesPage + first-party slot integration regression (`notes_page_explorer_slot_wiring_test.dart`)
   - [x] freeze M2 drag boundary (target matrix, same-kind reorder rule, source/target refresh policy)
   - [x] implement M2 drag controller + drop indicator
   - [x] wire drag move via `workspace_move_node` (same-parent reorder + cross-parent move)
   - [x] add M2 drag regressions (success/failure/invalid-target)
   - [x] complete M3 closure (docs/contract sync + verification replay)
10. `PR-0207B/0207C/0207D` ordering/move transition lane
   - [x] `PR-0207B`: freeze ordering + move semantics contract
   - [ ] `PR-0207C`: implement no-reorder move policy + title-only rows + legacy note_ref backfill
   - [ ] `PR-0207D`: closure replay (docs sync + migration/QA evidence + obsolete reorder cleanup)

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
- `docs/releases/v0.2/prs/PR-0205A-notes-ui-shell-alignment.md`
- `docs/releases/v0.2/prs/PR-0205-explorer-recursive-lazy-ui.md`
- `docs/releases/v0.2/prs/PR-0205B-explorer-tab-open-intent-migration.md`
- `docs/releases/v0.2/prs/PR-0206-split-layout-v1.md`
- `docs/releases/v0.2/prs/PR-0206B-split-pane-unsplit-merge.md`
- `docs/releases/v0.2/prs/PR-0207-explorer-context-actions-dnd-baseline.md`
- `docs/releases/v0.2/prs/PR-0207A-explorer-note-ref-title-rename-freeze.md`
- `docs/releases/v0.2/prs/PR-0207B-explorer-ordering-contract-freeze.md`
- `docs/releases/v0.2/prs/PR-0207C-explorer-ordering-and-backfill-implementation.md`
- `docs/releases/v0.2/prs/PR-0207D-explorer-ordering-closure.md`
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
