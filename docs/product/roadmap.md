# Roadmap

## Release Tracks

1. v0.1 (notes-first stabilization)
   - scope: close local notes loop + debug viewer readability baseline
   - focus PRs: `PR-0010C2`, `PR-0010C3`, `PR-0010C4`, `PR-0010D`, `PR-0017A`
   - plan: `docs/releases/v0.1/README.md`
1.5. v0.1.5 (Atom Time-Matrix bridge)
   - scope: time-matrix schema (Migration 6) + Inbox/Today/Upcoming task views
   - focus PRs: `PR-0011`
   - plan: `docs/releases/v0.1.5/README.md`
   - gate: v0.1 (PR-0017A) must close before v0.1.5 begins
2. v0.2 (workspace foundation)
   - scope: tree model, workspace provider, explorer recursion, split v1, extension kernel contracts (command/parser/provider/ui slot/capability), CN/EN i18n, debug viewer phase-2 readability hardening, docs language policy, links v1
   - focus PRs: `PR-0201` to `PR-0218`
   - plan: `docs/releases/v0.2/README.md`
3. v0.3 (IDE-grade recursive workspace)
   - scope: recursive split, drag-to-split, cross-pane coherence, perf gate, workspace launcher experience, local task-calendar projection, Google Calendar provider pluginization
   - focus PRs: `PR-0301` to `PR-0310`
   - plan: `docs/releases/v0.3/README.md`
4. v1.0 (production hardening)
   - scope: reliability, recovery, security, release readiness, cross-platform launcher policy parity, plugin sandbox/distribution/compatibility gates
   - candidate PRs: `PR-1001` to `PR-1009`
   - plan: `docs/releases/v1.0/README.md`

## Deferred from v0.1

- `PR-0011` tasks views → **replanned to v0.1.5** (Atom Time-Matrix, PR-0011)
- `PR-0012` calendar minimal
- `PR-0013` reminders (Windows)
- `PR-0014` local task-calendar projection baseline
- `PR-0015` Google Calendar provider plugin track
- `PR-0016` export/import
- notes delete lifecycle (soft-delete policy, restore path, and permanent delete UX)
