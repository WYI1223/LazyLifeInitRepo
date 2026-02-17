## TODO: Documentation language policy (canonical = English)

## Release/PR Mapping (2026-02-14)

- [x] `v0.2 / PR-0211-docs-language-policy-and-index`:
  - [x] P0 canonical language policy decision and contribution guidance
  - [x] P0 docs entrypoint (`docs/index.md`) and README navigation
  - [x] P1 canonical linking rules and translation header template baseline
- [ ] `v1.0 / PR-1005-release-readiness-and-doc-closure`:
  - [ ] P2 optional automation/linting uplift (if prioritized)

Notes:

- Translation rollout depth (`README.zh-CN.md` only vs `docs/zh-CN/**`) remains a release-time tradeoff and should follow documentation maintenance capacity.

### P0 - Decide and document the policy

- [x] Define English as the canonical source for docs (single source of truth).
- [x] Add a short docs language policy section to `CONTRIBUTING.md`.
  - English is canonical.
  - Translations are optional and may lag behind.
  - Translation PRs are welcome.
- [ ] Decide naming conventions.
  - Canonical: `README.md`, `docs/**`
  - Chinese translation (later): `README.zh-CN.md`, `docs/zh-CN/**` (or `docs/i18n/zh-CN/**`)

### P0 - Entry points and navigation

- [x] Add/ensure a single docs entry page: `docs/index.md`.
  - Link to architecture, product, compliance, governance, and releases.
- [x] Ensure `README.md` links to `docs/index.md` as primary navigation.

### P1 - Canonical linking rules (avoid drift)

- [x] Rule: internal doc links should point to canonical paths (`docs/...`), not translations.
- [ ] Rule: architecture decisions (ADR) are canonical-only (no full translation requirement).

### P1 - Translation mechanism (later, but plan now)

- [x] Define a required translation header format (for future translated pages).
  - Translation of `<canonical_path>` at `<source_commit>`.
  - Translation may lag behind canonical.
- [ ] Decide where translations live.
  - Option A: `README.zh-CN.md` only (minimal)
  - Option B: `docs/zh-CN/**` full tree (later if needed)

### P2 - Automation/maintenance (optional later)

- [ ] Add a PR checklist item: docs updated? translation impacted?
- [ ] (Optional) Add a script to detect translated docs missing `source_commit` header.
- [ ] (Optional) Add a docs lint job in CI (broken links, etc.).
