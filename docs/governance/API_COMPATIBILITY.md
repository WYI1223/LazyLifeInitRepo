# API Compatibility Policy

This policy defines compatibility rules for public API surfaces.

## Public API Surfaces

The following are treated as compatibility-sensitive:

- Rust FFI exports in `crates/lazynote_ffi/src/api.rs`
- Dart-visible FFI models in `apps/lazynote_flutter/lib/core/bindings/api.dart`
- behavior contracts documented in `docs/api/*.md`

## Breaking Changes

A change is considered breaking when any of the following happens:

- rename/remove an exposed FFI function
- change parameter semantics, units, or requiredness
- change return field semantics (including `ok/error_code` behavior)
- remove or repurpose stable error codes
- change Single Entry behavior boundary (`onChanged` vs `Enter/send`)

## Allowed Non-Breaking Changes

- additive response fields that preserve existing meaning
- additive error codes
- additive commands behind explicit version docs
- internal refactors without contract change

## Change Process

For compatibility-sensitive changes, PR must include:

1. contract delta in `docs/api/*`
2. tests updated for old/new behavior expectations
3. release note update in `docs/releases/`
4. migration guidance if callers must change

## v0.1 Practical Rule

v0.1 allows fast iteration, but contract breaks still require explicit documentation in the same PR.
Silent API drift is not allowed.
