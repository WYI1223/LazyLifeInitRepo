# PR-0212-links-index-open-v1

- Proposed title: `feat(links): links extraction/index and safe open v1 (Windows first)`
- Status: Planned

## Goal

Deliver v1 baseline for links parsing/indexing and safe open behavior for folder/file/url targets.

## Scope (v0.2)

In scope:

- define supported link types (`folder`, `file`, `url`)
- markdown link extraction on note save/update
- links index storage and query API
- safe open action for `http/https/file` (Windows first)

Out of scope:

- workspace launcher `Open All` orchestration
- multi-platform open behavior parity
- advanced custom schemes whitelist

## Source Reference

This PR operationalizes P0 items in:

- `docs/research/todo_Link&Workspace_Launcher.md`

## Security Rules

1. Only allow `http`, `https`, `file` schemes.
2. Reject command-like or untrusted schemes.
3. Return actionable errors for invalid path/permissions/not-found.

## Step-by-Step

1. Add links schema and indexes.
2. Add markdown link extractor and persistence update path.
3. Add links query APIs (`list_links`, `search_links`).
4. Add open-link use-case with scheme validation.
5. Expose FFI for links list/search/open.

## Planned File Changes

- [add] `crates/lazynote_core/src/db/migrations/0008_links.sql`
- [add] `crates/lazynote_core/src/repo/link_repo.rs`
- [add] `crates/lazynote_core/src/service/link_service.rs`
- [edit] `crates/lazynote_core/src/service/note_service.rs`
- [edit] `crates/lazynote_ffi/src/api.rs`
- [add] `apps/lazynote_flutter/lib/features/links/*`
- [add] `apps/lazynote_flutter/test/links_flow_test.dart`
- [edit] `docs/research/todo_Link&Workspace_Launcher.md` (status mapping note)

## Verification

- `cd crates && cargo test --all`
- `cd apps/lazynote_flutter && flutter analyze`
- `cd apps/lazynote_flutter && flutter test`

## Acceptance Criteria

- [ ] Links are extracted from markdown and indexed.
- [ ] UI can query and open supported link targets.
- [ ] Open action enforces scheme safety and returns explicit errors.

