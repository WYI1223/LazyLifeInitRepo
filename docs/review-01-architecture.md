# LazyNote — 架构 / 性能 / 稳定性 / 可维护性审查报告

> 审查日期：2026-02-14
> 审查范围：`crates/` Rust 全部模块 + `apps/lazynote_flutter/lib/` 核心路径
> 方法：严格基于源代码，不臆测。所有条目均标注文件路径和行号。
> 原则：不建议大规模重构；不引入不必要依赖。

---

## 风险等级说明

| 等级 | 含义 |
|------|------|
| **HIGH** | 静默数据丢失 / 应用崩溃 / 用户无法感知的错误路径 |
| **MEDIUM** | 可观测的性能退化 / 功能错误 / 合理操作路径下的故障 |
| **LOW** | 可维护性隐患 / 与文档不一致 / 累积技术债 |

---

## 问题 1：每次 FFI 调用都重新打开 SQLite 连接

**风险等级：HIGH**

**位置：**
- `crates/lazynote_ffi/src/api.rs:606–627`（`with_atom_service` / `with_note_service`）
- `crates/lazynote_core/src/db/open.rs:27–60`（`open_db`）
- `crates/lazynote_core/src/db/migrations/mod.rs`（`apply_migrations` 每次都执行 `PRAGMA user_version` 查询）

**现象：**
每个 FFI 函数（`note_create`、`note_update`、`notes_list`、`entry_search` 等）的实现都会：
1. 调用 `open_db(path)` 打开新连接
2. 调用 `apply_migrations` 查询 `PRAGMA user_version` 并遍历迁移表
3. 实例化 `SqliteAtomRepository` / `SqliteNoteRepository`（包含表存在性校验）
4. 创建 Service 对象
5. 执行一次操作后全部销毁

**影响：**
- 笔记自动保存默认间隔为 1500ms（`NotesController.autosaveDebounce`）。若用户持续输入，每 1.5 秒触发一次连接开关+迁移检查+表校验，直接损耗 IO 和 CPU。
- `open_db` 没有配置 `PRAGMA journal_mode=WAL`，使用默认的 DELETE 模式。每次写操作持有排他锁，若与其他读操作并发（如搜索），会产生 busy-wait，超时由 `busy_timeout(5s)` 兜底但不报告给 UI。
- 迁移数量增长后，每次 FFI 调用的准备成本线性增加。

**为什么这样设计（可理解）：**
当前架构将 `Connection` 生命周期与单次请求绑定，避免了连接的跨线程共享问题。FRB 的 async 函数运行在 Dart 协程上，从 Rust 侧来看均在同一线程池，持有静态连接有 Send 约束问题。

**可落地优化建议：**

方案 A（最小改动）：在 `open_db` / `bootstrap_connection` 中增加 WAL 模式，减少锁竞争。

```rust
// crates/lazynote_core/src/db/open.rs: bootstrap_connection 函数末尾添加
conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")?;
```

方案 B（中期）：将迁移检查从 `apply_migrations` 拆分为两步：
1. `check_needs_migration(conn) -> bool`：只读 `PRAGMA user_version`
2. 若版本匹配则跳过迁移事务

这使得"已是最新 schema"的快路径仅需一次只读 PRAGMA。

**如何验证：**
1. 在 `open_db` 前后各打一条 `info!` 日志，包含 `duration_ms`，复现"快速输入触发自动保存"场景，观察日志中每次 FFI 调用的实际耗时。
2. 在 Windows 上用 Process Monitor 追踪文件句柄，验证每次调用确实有文件 open/close。

---

## 问题 2：Mutex 毒化后静默回退到 temp 目录

**风险等级：HIGH**

**位置：** `crates/lazynote_ffi/src/api.rs:572–579`

```rust
fn resolve_entry_db_path() -> PathBuf {
    // ... env var check ...
    if let Ok(guard) = ENTRY_DB_PATH_OVERRIDE.lock() {  // 若 Err(Poisoned), 进入下面分支
        if let Some(path) = guard.as_ref() {
            return path.clone();
        }
    }
    std::env::temp_dir().join(ENTRY_DB_FILE_NAME)  // 静默回退！
}
```

**现象：**
若 `ENTRY_DB_PATH_OVERRIDE`（`Mutex<Option<PathBuf>>`）被毒化（另一个持有锁的线程发生 panic），`lock()` 返回 `Err`，代码不处理错误，直接 fall-through 到 `temp_dir()`。

**影响：**
- 应用继续运行但数据写入 `%TEMP%\lazynote_entry.sqlite3`（与配置的 `%APPDATA%\LazyLife\data\lazynote_entry.sqlite3` 完全不同）。
- 用户感知：笔记创建"成功"，但重启后消失。这是最危险的静默数据丢失场景。
- `ENTRY_DB_PATH_OVERRIDE.lock()` 在正常操作中不会发生竞争（FRB async 任务单线程），但 Rust 测试并行执行时，测试中的 panic 可能毒化全局 Mutex。

**可落地优化建议：**
将 `Ok(guard)` 分支的 fall-through 改为错误返回（对 `resolve_entry_db_path` 调整签名为 `Result<PathBuf, String>`），或至少在毒化时发出明确的 `error!` 日志而非静默继续。

最小改动：

```rust
fn resolve_entry_db_path() -> PathBuf {
    if let Ok(raw) = std::env::var("LAZYNOTE_DB_PATH") { /* ... */ }

    match ENTRY_DB_PATH_OVERRIDE.lock() {
        Ok(guard) => {
            if let Some(path) = guard.as_ref() {
                return path.clone();
            }
        }
        Err(_) => {
            // 至少记录错误，不能静默降级
            error!("event=db_path_resolve module=ffi status=error error_code=mutex_poisoned");
        }
    }

    std::env::temp_dir().join(ENTRY_DB_FILE_NAME)
}
```

**如何验证：**
1. 在测试中手动毒化 Mutex：在一个线程中 `panic!` while holding the lock，然后在另一个调用 `resolve_entry_db_path()`，检查是否返回 temp 路径。
2. 检查该返回的 temp 路径在 FFI 调用中是否确实被使用（添加临时日志）。

---

## 问题 3：`entry_search` 的 ENTRY_LIMIT_MAX 与 `notes_list` 不一致

**风险等级：MEDIUM**

**位置：**
- `crates/lazynote_ffi/src/api.rs:24–25`：`ENTRY_LIMIT_MAX = 10`
- `crates/lazynote_ffi/src/api.rs:555–562`：`normalize_entry_limit`
- `crates/lazynote_ffi/src/api.rs:902`（测试断言）：`assert_eq!(filtered.applied_limit, 50)`（`notes_list` 上限为 50）

**现象：**
```rust
const ENTRY_DEFAULT_LIMIT: u32 = 10;
const ENTRY_LIMIT_MAX: u32 = 10;  // ← default 和 max 相同
```

`normalize_entry_limit` 在请求 limit > 10 时将其截断到 10，即使传入 42 也返回 10（见测试 `entry_search_normalizes_limit_and_finds_created_note`）。
而 `notes_list` 通过 `lazynote_core::normalize_note_limit` 上限为 50。

**影响：**
- 两个 API 的分页行为不一致：`notes_list` 允许最多 50 条，`entry_search` 最多 10 条，但常量名称 `ENTRY_LIMIT_MAX` 暗示的是"最大值"而非"默认值"，会让维护者误解。
- `docs/api/README.md` 写的是 `limit normalization: default 10, max 50`，与代码中 entry search 的 max=10 矛盾。

**可落地优化建议：**
明确拆分为两个常量，让意图更清晰，并与文档对齐：

```rust
const ENTRY_SEARCH_DEFAULT_LIMIT: u32 = 10;
const ENTRY_SEARCH_MAX_LIMIT: u32 = 50;  // 与 notes_list 一致
```

如果 entry search 确实要限定为 10 条，则更新 `docs/api/ffi-contract-v0.1.md` 中关于 entry_search limit 的说明，避免文档与代码矛盾。

**如何验证：**
1. 运行现有测试 `entry_search_normalizes_limit_and_finds_created_note`，检查 `applied_limit` 实际值。
2. 对比 `docs/api/README.md` 中的 limit 说明与代码常量。

---

## 问题 4：SQLite 未开启 WAL 模式

**风险等级：MEDIUM**

**位置：** `crates/lazynote_core/src/db/open.rs:102–107`

```rust
fn bootstrap_connection(conn: &mut Connection) -> DbResult<()> {
    conn.execute_batch("PRAGMA foreign_keys = ON;")?;
    conn.busy_timeout(Duration::from_secs(5))?;
    apply_migrations(conn)?;
    Ok(())
    // ← 没有 PRAGMA journal_mode=WAL
}
```

**影响：**
- 默认 journal_mode 为 DELETE，采用文件级独占锁。笔记保存（写）期间，任何搜索（读）都会被阻塞，反之亦然。
- 在 1.5s 自动保存 + 用户主动搜索同时发生时，会出现最高 5s 的 busy-wait 超时（才能收到 `SQLITE_BUSY` 错误），或者用户操作无响应感知。
- WAL 模式允许读写并发，对桌面应用几乎是无风险的标准优化。

**可落地优化建议：**

```rust
fn bootstrap_connection(conn: &mut Connection) -> DbResult<()> {
    conn.execute_batch(
        "PRAGMA foreign_keys = ON; PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;"
    )?;
    conn.busy_timeout(Duration::from_secs(5))?;
    apply_migrations(conn)?;
    Ok(())
}
```

`synchronous=NORMAL` 在 WAL 模式下是安全的：只有在操作系统崩溃时（非应用崩溃）才可能丢最后一次提交，对于本地笔记应用是可接受的权衡。

**如何验证：**
1. 修改后运行 `cargo test --all`，验证现有测试全部通过。
2. 执行 `PRAGMA journal_mode;` 查询，确认返回 `wal`。
3. 使用 Windows 上的 DB Browser for SQLite 验证 `.db-shm` / `.db-wal` 文件生成，确认 WAL 模式激活。

---

## 问题 5：`entry_search` 使用未注册的错误码

**风险等级：MEDIUM**

**位置：** `crates/lazynote_ffi/src/api.rs:249–292`

```rust
error_code: Some("db_open_failed".to_string()),  // 未在 error-codes.md 注册
// ...
error_code: Some("search_failed".to_string()),    // 未在 error-codes.md 注册
```

**与之对比：** `NotesFfiError::code()` 返回的 `invalid_note_id`、`invalid_tag`、`note_not_found`、`db_error`、`invalid_argument`、`internal_error` 均已在 `docs/api/error-codes.md` 注册。

**影响：**
- Flutter 侧的错误处理代码若按 `errorCode` 分支处理，会遇到未预期的错误码（或因枚举缺失而降级到通用处理）。
- 违反 `docs/governance/API_COMPATIBILITY.md` 关于"stable error codes"的约定。

**可落地优化建议：**
将 `entry_search` 的错误码与已有体系统一：

```rust
error_code: Some("db_error".to_string()),    // 替换 "db_open_failed"
// ...
error_code: Some("internal_error".to_string()), // 替换 "search_failed"
```

并在 `docs/api/error-codes.md` 中补充 `entry_search` 相关的错误码条目，或合并到已有码。

**如何验证：**
1. 在 `docs/api/error-codes.md` 中搜索 `db_open_failed` 和 `search_failed`，确认当前确实未注册。
2. 修改后对 FFI 测试中的错误码断言更新，确保一致性。

---

## 问题 6：`with_note_service` 闭包重复创建 `NoteService`，无法跨操作复用事务

**风险等级：MEDIUM**

**位置：** `crates/lazynote_ffi/src/api.rs:619–628`

**现象：**
`note_set_tags_impl` 先调用 `with_note_service(service.set_note_tags(...))` 修改标签，`with_atom_service` 和 `with_note_service` 每次都是独立的连接和事务。如果 `set_note_tags` 在内部需要"先删除旧标签 + 再插入新标签 + 更新 atom.updated_at"，这些操作在 `note_repo.rs` 中通过单个 `rusqlite` 连接的 transaction 执行，是原子的。但若未来需要"更新内容 + 更新标签"组合操作，无法在同一事务中完成，只能两次 FFI 调用，有中间状态暴露风险。

**影响：**
当前 v0.1 已有的操作（content update 和 tag update 是分开的 FFI 调用）不存在原子性问题，但架构不支持复合原子操作扩展。

**可落地优化建议：**
这是已知的架构权衡（Rule B：FFI 只暴露用例级 API），暂时保持现状。建议在 `docs/architecture/engineering-standards.md` 中明确记录这个约束，并在未来需要组合操作时，在 Core 层新增组合服务方法（如 `note_update_with_tags`），而非在 FFI 层拼接调用。

**如何验证：**
代码审查时检查 `note_repo.rs` 中的 `note_set_tags` 实现是否为单事务。验证"标签删除+插入+updated_at 刷新"在同一事务中执行。

---

## 问题 7：公开的 `Atom` 字段缺少不变量保护

**风险等级：LOW（已知技术债）**

**位置：** `crates/lazynote_core/src/model/atom.rs`

**现象：**
`Atom` 结构体的所有字段均为 `pub`，验证逻辑在 `Atom::validate()` 中，但调用 `validate()` 是可选的，没有类型系统保证"构造即合法"。

**影响：**
- 下游代码可直接修改 `atom.uuid`、`atom.is_deleted` 而绕过验证。
- `SqliteAtomRepository` 中的 SQL 语句直接访问 `atom.uuid.to_string()` 等公开字段，依赖调用者保证合法性。
- 代码注释中已说明 v0.2 计划私有化字段，该技术债有追踪。

**可落地优化建议（不破坏 v0.1）：**
无需改动字段可见性（breaking change），在 `atom_repo.rs` 中的持久化入口（`create_atom`、`update_atom`）添加 `atom.validate()?` 的防御性调用。

```rust
// crates/lazynote_core/src/repo/atom_repo.rs: create_atom 方法入口处
atom.validate()?;
```

这是轻量添加，不破坏现有 API。

**如何验证：**
1. 检查 `atom_repo.rs` 中是否已经有 `validate()` 调用（grep `atom.validate`）。
2. 若无，添加后运行 `cargo test -p lazynote_core`，验证测试通过。

---

## 问题 8：`_noteCache` 与 `_items` 线性扫描并存，逻辑分支复杂

**风险等级：LOW**

**位置：** `apps/lazynote_flutter/lib/features/notes/notes_controller.dart`

**现象：**
`noteById(atomId)` 先查 `_noteCache`（O(1) HashMap），再扫 `_items`（O(n) List）：
```dart
rust_api.NoteItem? noteById(String atomId) {
    return _noteCache[atomId] ?? _findListItem(atomId);  // _findListItem 是 O(n) 扫描
}
```

`_findListItem` 和 `_findLoadedItem` 是两个几乎相同的 O(n) 线性扫描方法，逻辑重复。

**影响：**
- 对于 v0.1 典型笔记数量（<100），性能影响可忽略。
- 维护成本：两个扫描函数如果行为不一致（一个是 `_items`，一个接受 `List` 参数），未来扩展时容易遗漏。

**可落地优化建议：**
统一通过 `_noteCache` 进行 O(1) 查找，确保每次 `_insertOrReplaceListItem` 都维护 cache。当前代码中 `_insertOrReplaceListItem` 已经做 `_noteCache[note.atomId] = note`，所以直接用 `_noteCache[atomId]` 替换 `_findListItem` 不会破坏正确性（只要各路径都调用了 `_insertOrReplaceListItem`）。

**如何验证：**
1. 在现有 Flutter widget 测试中，验证 `noteById` 返回的是 cache 中的最新版本。
2. 检查是否存在"note 在 list 中但未在 cache 中"的路径，如果有，说明 `_insertOrReplaceListItem` 存在未覆盖的调用路径。

---

## 问题 9：`tags_list_impl` 中重复 lowercase 处理

**风险等级：LOW**

**位置：** `crates/lazynote_ffi/src/api.rs:529–552`

```rust
fn tags_list_impl() -> TagsListResponse {
    match with_note_service(|service| {
        service.list_tags()
            .map(|tags| {
                tags.into_iter()
                    .map(|tag| tag.to_lowercase())  // ← 二次 lowercase
                    .collect::<Vec<_>>()
            })
    }) { /* ... */ }
}
```

`note_repo.rs` 中的 `note_set_tags` 已通过 `tag.trim().to_lowercase()` 归一化后存储，`tags` 表的 `name` 字段使用 `COLLATE NOCASE`。返回的标签已经是小写，此处 `to_lowercase()` 为多余操作。

**影响：** 无功能影响，纯冗余计算。

**可落地优化建议：**
删除 FFI 层的 `to_lowercase()`，确保语义由存储层单一负责。同时在 `docs/api/ffi-contracts.md` 中说明"tags 总是以 lowercase 形式返回，由存储层保证"。

**如何验证：**
1. 运行测试 `tags_list_returns_normalized_values`，检查无论加不加这行，结果相同。
2. 在 `note_repo.rs` 中确认插入前的 `to_lowercase` 调用路径，确保存储层归一化是完整的。

---

## 问题 10：DB 连接 `busy_timeout(5s)` 无法传播给 UI

**风险等级：LOW**

**位置：** `crates/lazynote_core/src/db/open.rs:104`

**现象：**
连接设置了 `busy_timeout(5s)`，但这个超时从 Rust 传递到 FFI 再到 Flutter 的路径是：`SQLITE_BUSY` → `rusqlite::Error` → `DbError::Sqlite` → `NotesFfiError::DbError` → `error_code: "db_error"`，而 Flutter 侧只有一个通用 `db_error` 标识符，无法区分"超时"和"其他 DB 错误"。

**影响：**
用户感知：偶发操作失败，错误信息为通用 `db_error`，无法判断是锁超时还是数据损坏。

**可落地优化建议：**
在 `map_repo_error` 中对 `DbError::Sqlite(rusqlite::Error::SqliteFailure(code, _))` 特判 `SQLITE_BUSY`（errcode=5）：

```rust
lazynote_core::RepoError::Db(DbError::Sqlite(rusqlite::Error::SqliteFailure(code, _)))
    if code.code == rusqlite::ErrorCode::DatabaseBusy =>
    NotesFfiError::DbError("db_busy".to_string()),
```

并在 `error-codes.md` 注册 `db_busy`。

**如何验证：**
构造两个并发连接（测试中用两个线程），触发 SQLITE_BUSY，检查错误码是否能区分。

---

## 总结

| # | 问题 | 风险 | 改动规模 |
|---|------|------|---------|
| 1 | 每次 FFI 调用重开 SQLite 连接，含迁移检查 | HIGH | 小（加 PRAGMA） |
| 2 | Mutex 毒化后静默写入 temp 目录 | HIGH | 小（加 error log + fail fast） |
| 3 | `entry_search` LIMIT_MAX=10 与文档 max=50 矛盾 | MEDIUM | 小（改常量 + 更新文档） |
| 4 | SQLite 未开启 WAL 模式 | MEDIUM | 小（一行 PRAGMA） |
| 5 | `entry_search` 使用未注册错误码 | MEDIUM | 小（统一错误码 + 更新文档） |
| 6 | 无法跨操作原子事务（已知架构权衡） | MEDIUM | 文档记录 |
| 7 | Atom 字段公开，无构造级不变量保护 | LOW | 小（加 validate 调用） |
| 8 | `_noteCache` + O(n) 扫描逻辑重复 | LOW | 小（统一查找路径） |
| 9 | `tags_list_impl` 重复 lowercase | LOW | 极小（删一行） |
| 10 | `SQLITE_BUSY` 超时无差异化错误码 | LOW | 小（增加错误码映射） |

**优先级建议：** 先处理 1+2（数据安全）→ 再处理 4（性能无风险） → 再处理 3+5（文档一致性）→ 其余按迭代节奏处理。
