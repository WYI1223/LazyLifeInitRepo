# Engineering Standards

本文件定义 LazyNote 的工程硬约束（代码逻辑、架构边界、质量门槛、协作规范）。

## 1. Architecture Rules (Mandatory)

### Rule A: Business invariants live in Rust Core only

- 数据模型、存储、索引、同步、导入导出必须放在 `crates/lazynote_core`。
- Flutter 仅负责 UI、交互、状态编排、平台能力（窗口/快捷键/通知）。
- Flutter 不得直接操作 SQLite 文件（纯只读 debug 场景除外，且需注明）。

### Rule B: FFI exposes use cases, not storage internals

- `crates/lazynote_ffi` 仅导出用例级 API（例如 `create_note`、`search`、`schedule`）。
- 禁止暴露数据库底层细节（例如 `insert_row`、`update_table`）。

### Rule C: Stable ID + soft delete

- 所有核心实体必须使用稳定 ID（`uuid` / `atom_id`）。
- 删除必须默认走软删除字段，以支持同步、恢复与审计。

### Rule D: External sync must use mapping/version fields

- 所有外部系统同步（例如 Google Calendar）必须在 Core 维护统一映射表与版本字段。
- 禁止在 UI 层散落维护 `external_id <-> atom_id` 映射逻辑。

### Rule E: Flutter features are vertical slices only

- `features/<name>` 之间禁止直接依赖对方内部实现。
- 共享能力只能通过 `shared/` 或 Core API 访问。

### Rule F: Local runtime files must use unified app root

- 所有用户可写运行时文件必须归档到统一根目录 `LazyLife`。
- Windows 强制路径：`%APPDATA%/LazyLife/`。
- 其他平台 fallback：`<app_support>/LazyLife/`。
- 包括但不限于：`settings.json`、`logs/`、`data/`（本地数据库与缓存）。

## 2. Code Quality Gates (Mandatory)

### Rust

必须通过：

- `cargo fmt --all -- --check`
- `cargo clippy --all -- -D warnings`
- `cargo test --all`

### Flutter / Dart

必须通过：

- `dart format --output=none --set-exit-if-changed .`
- `flutter analyze`
- `flutter test`

## 3. Git & PR Rules (Mandatory)

### Commit format

必须遵循 Conventional Commits：

- `feat(scope): ...`
- `fix(scope): ...`
- `chore(scope): ...`
- `docs(scope): ...`

### PR minimum requirements

- 明确目标、范围、验证方式。
- 包含测试或可复现手工验证步骤。
- CI 必须通过。

## 4. Standard Files (Baseline)

本仓库应长期保留并维护以下规范文件：

- `.editorconfig`
- `CONTRIBUTING.md`
- `CODE_OF_CONDUCT.md`
- `VERSIONING.md`
- `CHANGELOG.md`
- `apps/lazynote_flutter/analysis_options.yaml`
- `docs/architecture/code-comment-standards.md`

## 5. Exception Process

若需偏离本标准，必须：

1. 在对应 PR 中明确说明偏离原因与影响面。
2. 关联一个 ADR 或 Issue 记录。
3. 经 Maintainer 明确批准后方可合并。
