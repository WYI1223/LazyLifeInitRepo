# UI Extension Slots (v0.2 Baseline)

## Purpose

Define layered UI extension slots so first-party and future extension features
can compose UI without directly coupling to host page internals.

## Scope (v0.2)

In scope:

- slot contracts for:
  - `content_block`
  - `view`
  - `side_panel`
  - `home_widget`
- in-process slot registry
- host render adapters for list/view slots
- deterministic ordering and fallback behavior
- first-party baseline slot registration

Out of scope:

- remote-loaded UI packages
- dynamic runtime plugin download/sandbox
- full page redesign

## Core Contracts

### Contribution Model

Each `UiSlotContribution` declares:

- `contribution_id` (stable namespaced id)
- `slot_id`
- `layer`
- `priority` (higher renders earlier)
- `builder`
- optional `enabled_when`
- optional lifecycle hooks (`on_mount`, `on_dispose`)

### Registry Rules

`UiSlotRegistry`:

- rejects empty/duplicate `contribution_id`
- rejects empty `slot_id`
- resolves by `(slot_id, layer, enabled_when)`
  - `enabled_when` should be pure
  - if `enabled_when` throws, that contribution is skipped and diagnostics are logged
- sorts deterministically by:
  1. `priority` descending
  2. `contribution_id` ascending

### Host Rules

`UiSlotListHost`:

- used for `content_block`, `side_panel`, `home_widget`
- renders all resolved contributions in registry order
- uses fallback when no contribution is resolved
- if fallback is not provided, renders `SizedBox.shrink()`
- isolates per-contribution failures:
  - if one `builder` throws, that contribution is skipped
  - `on_mount`/`on_dispose` exceptions are logged and do not abort host updates

`UiSlotViewHost`:

- used for `view`
- renders only highest-priority resolved contribution
- uses fallback when no contribution is resolved
- if highest-priority contribution `builder` throws, host falls through to the next contribution

Lifecycle:

- `on_mount` runs when contribution enters active resolved set
- `on_dispose` runs when contribution leaves active resolved set or host disposes

## First-Party Baseline

v0.2 baseline registrations include:

- Workbench Home diagnostics/content blocks
- Workbench Home navigation widgets (`Notes/Tasks/Calendar/Settings`)
- Notes side panel explorer contribution
