# LazyNote

> 一个极简、本地优先的个人效率系统。
> 笔记、任务与日程，收敛到同一个入口。

**[English →](README.md)**

---

## 项目定位

LazyNote 聚焦三个核心价值：

- **单一入口（Single Entry）** — 统一搜索框 + 命令面板，所有核心动作可直达。
- **强联动（Strong Linkage）** — 笔记、任务、事件是同一数据图谱的不同视图。
- **低负担（Low Friction）** — 默认简单，按需增强。避免功能膨胀与认知负担。

这不是"功能最多"的生产力工具，而是"摩擦最小"的个人第二大脑。

---

## 设计原则

| 原则 | 说明 |
|------|------|
| **Local-First** | 数据默认保存在本地，离线可用，同步是可选能力 |
| **Privacy-First** | 最小权限，默认零遥测，无强制账号 |
| **One Input** | 统一入口优先于多页面跳转 |
| **Default Simple** | 复杂能力（图谱视图、语义检索等）按需启用，不作为默认 |
| **Cross-Platform by Design** | 架构从一开始面向 Windows / macOS / iOS / Android |

---

## 技术架构

```
┌─────────────────────────────────────┐
│         Flutter UI 层               │
│  单一入口 · 笔记 · 诊断面板          │
└────────────────┬────────────────────┘
                 │  Flutter-Rust Bridge（FRB / FFI）
┌────────────────▼────────────────────┐
│           Rust Core 层              │
│  领域模型 · 服务 · 全文搜索          │
│  数据仓库 · 迁移管理 · 日志          │
└────────────────┬────────────────────┘
                 │
┌────────────────▼────────────────────┐
│           本地数据层                │
│  SQLite（atoms、tags、mappings）     │
│  FTS5（全文检索虚拟表）              │
└─────────────────────────────────────┘
```

Rust Core 是所有业务逻辑的单一数据源。Flutter 只负责 UI，全部数据操作通过 FFI 边界调用 Rust。

---

## 包结构

```
apps/
  lazynote_flutter/              # Flutter 客户端（多平台）
    lib/
      app/                       # 路由与 Shell 编排
      core/                      # RustBridge、FFI 绑定（自动生成）、设置、路径
      features/
        entry/                   # 单一入口搜索 + 命令面板
        notes/                   # 笔记列表、编辑器、标签过滤 UI
        tags/                    # 标签过滤组件
        search/                  # 搜索结果视图
        diagnostics/             # Rust 健康检查面板 + 实时日志查看器

crates/
  lazynote_core/                 # 全部业务逻辑（Rust）
    src/
      model/atom.rs              # 规范 Atom 实体
      db/                        # SQLite 启动 + 迁移管理（5 个版本）
      repo/                      # 持久化 Trait + SQLite 实现
      service/                   # 用例编排（NoteService、AtomService）
      search/fts.rs              # FTS5 全文检索
      logging.rs                 # 结构化滚动日志

  lazynote_ffi/                  # FFI 边界（薄包装层，不含逻辑）
    src/api.rs                   # 导出 FFI 函数 — 在此编辑
    src/frb_generated.rs         # 自动生成 — 禁止手动编辑

  lazynote_cli/                  # CLI 调试/导入导出工具（骨架）

docs/                            # 架构文档、API 契约、版本计划
scripts/                         # doctor.ps1、gen_bindings.ps1、format.ps1
```

---

## 统一数据模型（Atom）

LazyNote 将笔记、任务、事件统一为同一个规范实体：**Atom**。

同一条记录可根据 `type` 字段和元数据，在不同视图中投影为 Note / Task / Event，无需数据复制或迁移。

| 字段 | 类型 | 说明 |
|------|------|------|
| `uuid` | UUIDv4 | 全局稳定标识，绝不复用 |
| `kind` | `note \| task \| event` | 投影类型 |
| `content` | String | Markdown 正文 |
| `preview_text` | String? | 从 content 派生（首段纯文本） |
| `task_status` | Enum? | `todo \| in_progress \| done \| cancelled` |
| `event_start` | i64? | 毫秒级 Epoch 时间戳 |
| `event_end` | i64? | 毫秒级 Epoch 时间戳；始终 ≥ `event_start` |
| `is_deleted` | bool | 软删除标记 — 对可见性具有权威性 |
| `hlc_timestamp` | String? | 为 CRDT 同步预留（暂未启用） |

**代码层强制执行的不变量：**
- `uuid` 永不为空
- 当 `event_start` 与 `event_end` 均存在时，`event_end >= event_start`
- 所有默认查询过滤 `WHERE is_deleted = 0`
- 仅允许软删除 — 禁止对 `atoms` 执行 `DELETE` 语句

---

## 当前实现状态（v0.1）

| 功能 | 状态 |
|------|------|
| Atom 数据模型 + SQLite Schema | 已实现 |
| SQLite 迁移管理（5 个版本） | 已实现 |
| FTS5 全文检索 | 已实现 |
| 笔记 CRUD（通过 FFI） | 已实现 |
| 标签管理（创建、分配、过滤） | 已实现 |
| 单一入口搜索 + 命令面板 | 已实现 |
| 笔记编辑器（Markdown） | 已实现 |
| 结构化日志 + 诊断面板 | 已实现 |
| Windows 构建 | 已实现 |
| 任务引擎 | 计划中（post-v0.1） |
| 日历引擎 | 计划中（post-v0.1） |
| Google Calendar 同步 | 计划中（post-v0.1） |
| 导入 / 导出 | 计划中（post-v0.1） |
| 移动端（iOS / Android） | 计划中（post-v0.1） |
| CRDT / 多端同步 | 计划中（长期目标） |

---

## 开发环境搭建

### 前置依赖

- Rust stable 工具链（见 `rust-toolchain.toml`）
- Flutter SDK（Dart ≥ 3.11）
- Windows SDK（Windows 构建所需）

### 快速验证

```powershell
# 在仓库根目录执行
./scripts/doctor.ps1
```

### 构建

```bash
# Rust（在 crates/ 目录下）
cargo build --all

# Flutter（在 apps/lazynote_flutter/ 目录下）
flutter pub get
flutter build windows --debug
```

### 测试

```bash
# Rust（在 crates/ 目录下）
cargo test --all

# Flutter（在 apps/lazynote_flutter/ 目录下）
flutter test
```

### 代码生成

修改 `crates/lazynote_ffi/src/api.rs` 后，必须重新生成 FFI 绑定：

```powershell
./scripts/gen_bindings.ps1
```

Windows 详细开发说明见 [docs/development/windows-quickstart.md](docs/development/windows-quickstart.md)。

---

## 运行时文件布局

Windows 下，LazyNote 的所有运行时文件存储在 `%APPDATA%\LazyLife\`：

```
%APPDATA%\LazyLife\
  settings.json       — 应用设置
  logs/               — 滚动日志文件
  data/
    lazynote.db       — SQLite 数据库
```

---

## 版本路线图

| 阶段 | 重点 |
|------|------|
| **v0.1**（当前） | 笔记 + 标签 + 全文检索 + 单一入口面板 |
| **v0.2** | 全局快捷键、笔记树（层级结构）、分屏布局 |
| **v0.3** | 高级布局、拖拽分屏、跨面板实时同步 |
| **v1.0** | 插件沙箱、iOS 发布、API 兼容性 CI 门控 |

post-v0.1 计划：任务引擎、日历引擎、Google Calendar 同步、导入/导出、移动端。

---

## 关键文档索引

| 文档 | 说明 |
|------|------|
| [docs/architecture/engineering-standards.md](docs/architecture/engineering-standards.md) | 6 条强制架构规则 |
| [docs/architecture/data-model.md](docs/architecture/data-model.md) | Atom 实体规范与数据库 Schema |
| [docs/api/ffi-contract-v0.1.md](docs/api/ffi-contract-v0.1.md) | FFI API 契约全文 |
| [docs/api/error-codes.md](docs/api/error-codes.md) | 稳定错误码注册表 |
| [docs/governance/API_COMPATIBILITY.md](docs/governance/API_COMPATIBILITY.md) | API 破坏性变更策略 |
| [docs/releases/v0.1/README.md](docs/releases/v0.1/README.md) | v0.1 发布计划与 PR 路线图 |
| [docs/development/windows-quickstart.md](docs/development/windows-quickstart.md) | Windows 开发环境快速上手 |
| [CLAUDE.md](CLAUDE.md) | AI Agent 开发指南 |

---

## 贡献指南

请参阅 [docs/governance/CONTRIBUTING.md](docs/governance/CONTRIBUTING.md)。

提交信息遵循 [Conventional Commits](https://www.conventionalcommits.org/) 规范：
`feat(scope):`、`fix(scope):`、`chore(scope):`、`docs(scope):`、`test(scope):`、`refactor(scope):`

每个 PR 只处理一件事，不允许将功能开发与无关重构混入同一 PR。

---

## 许可证

[MIT License](LICENSE)
