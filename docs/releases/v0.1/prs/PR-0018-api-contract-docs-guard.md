# PR-0018 API Contract Docs Guard

## Goal

Add an automatic PR gate that prevents API contract changes from being merged without synchronized documentation updates.

## Why

- `PR-0009` introduced richer entry/search command contracts.
- Contract drift risk is now higher when FFI or generated Dart bindings change.
- Manual review alone is easy to miss; CI should enforce the rule.

## Scope

- Add a CI guard job in `.github/workflows/ci.yml` (PR only).
- Detect contract-impacting file changes:
  - `crates/lazynote_ffi/src/api.rs`
  - `apps/lazynote_flutter/lib/core/bindings/api.dart`
  - `apps/lazynote_flutter/lib/core/bindings/frb_generated.dart`
  - `apps/lazynote_flutter/lib/core/bindings/frb_generated.io.dart`
- If detected, require both:
  - at least one change under `docs/api/`
  - change in `docs/governance/API_COMPATIBILITY.md`

## Non-Goals

- semantic diffing of API signatures
- auto-generating API docs from source

## Acceptance Criteria

1. PR touching contract files but not docs fails.
2. PR touching contract files and required docs passes this gate.
3. PR without contract changes is not blocked by this gate.

## Validation

Manual validation with sample diffs:

1. Modify only `crates/lazynote_ffi/src/api.rs` -> guard fails.
2. Modify `crates/lazynote_ffi/src/api.rs` + `docs/api/single-entry-contract.md` + `docs/governance/API_COMPATIBILITY.md` -> guard passes.
3. Modify unrelated Flutter UI files only -> guard reports "No API contract changes detected."
