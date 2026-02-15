# LazyNote — 工程级深度审查报告

> 审查日期：2026-02-14
> 重点关注：状态管理 · 配置持久化 · 服务生命周期 · 日志与可观测性
> 输出格式：现象 → 影响 → 原因 → 建议 → 验证方式
> 方法：严格基于源代码，所有结论均标注文件路径。

---

## 一、状态管理

### 1.1 `activeDraftContent` 与 `_draftContentByAtomId` 存在双重持有，可在 tab 切换瞬间产生状态撕裂

**现象：**
`NotesController` 同时维护了两个表示"当前编辑内容"的状态：
- `_activeDraftContent: String`（String 字段，代表"当前活跃 tab 的草稿"）
- `_draftContentByAtomId: Map<String, String>`（按 atomId 索引的所有 tab 草稿）

`activeDraftContent` getter（`notes_controller.dart:271–283`）的三段回退逻辑：
```dart
String get activeDraftContent {
    if (_activeNoteId == null) return '';
    final atomId = _activeNoteId!;
    if (_draftContentByAtomId[atomId] case final draft?) return draft;
    if (_activeDraftAtomId == atomId) return _activeDraftContent;
    return _selectedNote?.content ?? '';
}
```

在 `_loadNotes`（`notes_controller.dart:1005–1139`）resetSession 路径下，`_draftContentByAtomId` 被清空（`_resetSessionForReload:1147`），但 `_activeDraftContent` 也同时被设为 `''`（`1165`）。问题出现在以下顺序：
1. 用户正在编辑 noteA，`_draftContentByAtomId["A"] = "新内容"`
2. 用户切换 tag filter → 触发 `_loadNotes(resetSession: false)`
3. `_activeNoteId` 被设为新列表的第一条 noteB（`1073-1083`）
4. 此时 `_activeDraftContent` 仍指向 noteA 的内容，`_activeDraftAtomId == "A"`
5. getter 第二分支：`_activeDraftAtomId == "A" != "B"(atomId)`，跳过
6. 返回 `_selectedNote?.content`（来自服务器的旧内容），而非用户尚未保存的草稿

**影响：**
tab 切换后短暂渲染过时内容。若 autosave debounce 尚未触发，用户在切换 tab 再切回时可能看到编辑内容"消失"（实际仍在 map 中，但 getter 未命中）。

**原因：**
`_activeDraftContent` 是为兼容早期无 map 时的状态模型而保留的冗余字段；`_activeDraftAtomId` 作为同步标记，在 async 操作间的状态转移中存在短暂窗口。

**建议：**
在 `_loadNotes` 中，当 `_activeNoteId` 切换为新 id 时，立即更新 `_activeDraftAtomId` 和 `_activeDraftContent` 为 `_draftContentByAtomId[newId]`：

```dart
_activeNoteId = first.atomId;
_activeDraftAtomId = first.atomId;                          // ← 保持同步
_activeDraftContent = _draftContentByAtomId[first.atomId] ?? first.content;
```

当前代码（`1076–1078`）已有类似写法，但分支覆盖不完整（`preserveActiveWhenFilteredOut=true` 分支`1098–1103`的写法正确，其他分支不一致）。统一所有切换路径即可。

**验证方式：**
1. 编写 widget 测试：打开 note A 并输入内容，切换 tag filter（不触发 save），检查 `activeDraftContent` getter 是否返回用户输入内容而非服务器旧内容。
2. 手动测试：在快速 tag 切换 + autosave debounce 尚未触发时，检查编辑器内容是否保留。

---

### 1.2 `flushPendingSave` 中的 `while(true)` 循环在极端条件下可无限延迟 tab 关闭

**现象：**
`flushPendingSave`（`notes_controller.dart:396–446`）使用无限循环等待：
1. 等待 `_tagMutationQueueByAtomId` 队列清空
2. 等待 `_tagSaveInFlightAtomIds` 清空（polling，12ms 延迟）
3. 等待 in-flight save future
4. 若内容仍 dirty，重新执行 save

若用户在 tab 关闭期间仍在输入（`updateActiveDraft` 持续更新版本号），且每次 save 因 IO 错误失败，则：
- `_isDirty(atomId)` 持续为 true
- `_saveDraft` 持续返回 false
- 版本号不断递增导致 `_draftVersionByAtomId[atomId] != version` 条件触发 `continue`
- 循环无法退出

**影响：**
关闭 tab 或切换 note 操作被无限阻塞，UI 失去响应（Flutter 单线程 event loop 不会卡死，但 `await flushPendingSave()` 调用的地方会一直 pending）。

实际边界：loop 在最终判断 `version != latest` 时会 `continue`，而 save 失败时最终到达 `_switchBlockErrorMessage = 'Save failed...'` 并 `return false`。但若版本号不停变化（用户持续输入），永远无法到达 return false 分支。

**原因：**
循环的退出条件是"save 成功且 isDirty 变 false"或"save 失败且版本未变化"。若版本持续变化，第二个条件始终不满足。

**建议：**
为 `flushPendingSave` 增加最大重试次数或超时上限：

```dart
// 在循环顶部增加计数
int retryCount = 0;
const maxRetries = 5;
while (true) {
    if (retryCount++ > maxRetries) {
        _switchBlockErrorMessage = 'Save failed after $maxRetries retries.';
        notifyListeners();
        return false;
    }
    // ... 现有逻辑
}
```

这不改变正常路径行为，只为异常路径增加保护边界。

**验证方式：**
1. 编写单元测试：模拟 `_noteUpdateInvoker` 始终返回失败 + 用户持续触发 `updateActiveDraft` 更新版本，调用 `flushPendingSave()`，验证在有限时间内返回 false。
2. 检查 `autosaveDebounce` 默认 1500ms，手动触发连续 save 失败，验证 tab 关闭操作不会永久阻塞。

---

### 1.3 `_tagMutationQueueByAtomId` 在 tab 关闭后仍继续执行，可为已关闭笔记发起网络请求

**现象：**
`_enqueueTagMutation`（`notes_controller.dart:645–669`）构建 Promise 链，通过 `.whenComplete` 自清理：
```dart
queued = previous.catchError((_) {}).then((_) async {
    final result = await mutation();
    completer.complete(result);
}).whenComplete(() {
    if (identical(_tagMutationQueueByAtomId[atomId], queued)) {
        _tagMutationQueueByAtomId.remove(atomId);
    }
});
```

当 `closeOpenNote(atomId)` 被调用时，`_resetSessionForReload` 会清空 `_tagMutationQueueByAtomId`（`notes_controller.dart:1153`），但已经在 event loop 中挂起的 Future（`queued`）仍然持有对 mutation 闭包的引用，并会在 `_tagMutationQueueByAtomId.remove` 的清空之后继续执行。

**影响：**
- `_noteSetTagsInvoker` 会被调用（触发一次 FFI 请求），Rust 侧会更新数据库。功能上是正确的（最终一致），但从 Dart 侧看，这次请求完成后 `response.note` 会更新到已被清空的 controller 中（`_insertOrReplaceListItem` 可能在 map 已清空后写入），造成 map 状态与 UI 预期不一致。
- 对于频繁 close+reopen 的场景，可能导致旧的 tag mutation 覆盖新数据。

**原因：**
Promise 链一旦建立，没有 cancellation 机制。Flutter 的 `Future` 不支持取消。

**建议：**
在 `_setNoteTags` 开始执行 `_noteSetTagsInvoker` 前，检查 atomId 是否仍在 `_openNoteIds` 或 `_noteCache` 中：

```dart
Future<bool> _setNoteTags({...}) async {
    // 加入 guard：若该笔记已不在任何活跃 tab 中，跳过 FFI 调用
    if (!_openNoteIds.contains(atomId) && _activeNoteId != atomId) {
        return false;  // 静默放弃，已关闭的 tab 不需要保存 tag
    }
    // ... 现有逻辑
}
```

注意：这里需要权衡——如果 tag 修改是用户明确操作，即使关闭了 tab 也应持久化。可以添加一个 "closed notes pending tag set" 集合，在 close 时立即 flush 一次 tag，然后取消队列。

**验证方式：**
1. 编写测试：打开 noteA，快速触发两次 `addTagToActiveNote`，立即 `closeOpenNote`，检查 FFI 调用次数和最终 tag 状态。
2. 在 `_setNoteTags` 开头加临时日志，验证 close 后的调用是否还会触发。

---

### 1.4 `_items` 列表在每次 `_insertOrReplaceListItem` 时全量 copy

**现象：**
```dart
// notes_controller.dart:1333
final mutable = List<rust_api.NoteItem>.from(_items);
// ... 修改 mutable ...
_items = List<rust_api.NoteItem>.unmodifiable(mutable);
```

每次 note 更新（autosave、tag 修改、detail 加载）都创建一个新的 List 副本。

**影响：**
- 对于 v0.1 场景（通常 < 50 条笔记），每次 O(n) copy 开销约为几微秒，不构成实质性瓶颈。
- `autosaveDebounce=1500ms` 意味着每 1.5 秒执行一次 copy（已有 debounce 保护，合理）。
- 若未来列表扩展到 500+ 条（分页加载），这个 copy 频率和成本会变得显著。

**原因：**
Flutter 中 `ChangeNotifier` 模式通常需要不可变列表来触发 UI 重建，全量 copy 是常见实现。

**建议：**
当前阶段不需要改动。记录为 v0.2 性能预算：当 notes list 支持分页（`offset` 参数已在 FFI 中存在）时，考虑改为 `ObservableList` 或分段 copy（只更新被修改的索引）。

**验证方式：**
通过 Flutter DevTools 的 Memory 面板，在快速 autosave 场景下观察 `NoteItem` 对象的分配频率，设定性能基线。

---

## 二、配置持久化

### 2.1 `loggingLevelOverride` 持久化存储但从未被应用

**现象：**
`settings.json` 包含 `"logging": { "level_override": "debug" }` 字段，`local_settings_store.dart` 中正确地读取和解析了该值（`notes_controller.dart:170–178`），存入 `_loggingLevelOverride`。

但 `rust_bridge.dart:108` 中：
```dart
static String Function() defaultLogLevelResolver = () =>
    kReleaseMode ? 'info' : 'debug';
```

`bootstrapLogging()` 调用链（`rust_bridge.dart:317`）：
```dart
final level = defaultLogLevelResolver();  // ← 使用编译时常量，忽略 settings 值
```

`LocalSettingsStore.loggingLevelOverride` 永远不被读取。

**影响：**
- 用户在 `settings.json` 设置 `level_override: "trace"` 并重启，日志级别不改变（仍为 `info` 或 `debug`）。
- 代码注释中有 "Runtime logging behavior is not changed by this field yet"（`local_settings_store.dart:59`），说明这是已知的，但设置项出现在 UI/文档中会造成用户困惑。

**原因：**
这是有意为之的 v0.1 未完成功能（注释明确说明），但缺少"禁用"或"灰显"的 UI 提示，也没有 `TODO(v0.2)` 追踪标记。

**建议：**

两种可行路径：

**方案 A（最小成本）：** 在 `bootstrapLogging()` 中使用 `loggingLevelOverride`：
```dart
final level = LocalSettingsStore.loggingLevelOverride
    ?? defaultLogLevelResolver();
```
前提：`LocalSettingsStore.ensureInitialized()` 需在 `bootstrapLogging()` 之前完成（已满足，`main.dart` 中的顺序是 `ensureInitialized → bootstrapLogging`）。

**方案 B（完整追踪）：** 在 `local_settings_store.dart:59` 的注释中添加 `TODO(v0.2)` 标记，并在文档中明确说明该字段"设置后需重启生效，v0.2 接入"。

**验证方式：**
1. 修改 `settings.json` 为 `"level_override": "trace"`
2. 重启应用
3. 在 diagnostics 面板检查 Rust 日志中是否包含 trace 级别条目
4. 在 `bootstrapLogging` 中临时打印 `level` 变量，确认使用的是 `"trace"` 还是 `"debug"`

---

### 2.2 `settings.json` 有多个持久化字段实际未被消费

**现象：**
`_backfillMissingDefaults` 会补全以下字段（`local_settings_store.dart:216–220`）：
- `entry.result_limit`（整数，默认 10）
- `entry.use_single_entry_as_home`（布尔，默认 false）
- `entry.expand_on_focus`（布尔，默认 true）

但 `_loadRuntimeSettings` 只加载 `entry.ui.*` 和 `logging.level_override` 到运行时。上述三个字段被写入文件但永远不被读回——它们既不在 `EntryUiTuning` 中，也没有对应的 getter。

**影响：**
- 误导维护者：`settings.json` 中有字段，但修改没有任何效果。
- 如果 `SingleEntryController` 或其他 controller 后来需要这些值，它们会读不到（未持久化到 `LocalSettingsStore`）。

**原因：**
字段在 schema 设计阶段预占，`_loadRuntimeSettings` 未同步实现。

**建议：**
在 `_loadRuntimeSettings` 中补充加载这三个字段，或在 `_backfillMissingDefaults` 中暂时移除尚未实现的字段，避免"写入但无效"的混乱状态。并在代码中添加 `TODO(v0.2): wire result_limit to SingleEntryController` 追踪。

**验证方式：**
1. 修改 `settings.json` 中 `result_limit` 为 5，检查 `LocalSettingsStore.entryUiTuning.xxx` 或任何 getter 是否能读到该值（预期：目前无法读到）。
2. Grep `result_limit` 在 Dart 代码中的所有出现（仅在 `local_settings_store.dart` 的 backfill 中，消费侧为零）。

---

### 2.3 `settings.json` 写入存在短暂空文件窗口（Windows 路径）

**现象：**
`_writeFileWithTempReplace`（`local_settings_store.dart:283–300`）的主路径：
```dart
await temp.rename(target.path);
```
在 Windows 上，若目标文件已存在，`rename` 可能抛出异常（Win32 `MoveFile` 不覆盖已存在文件），触发 fallback：
```dart
await target.delete();       // ← 此处文件消失
await temp.rename(target.path);  // ← 此处文件重新出现
```

若在 `delete` 和 `rename` 之间发生进程崩溃或强制结束，`settings.json` 将不存在，下次启动时 `_ensureInitializedInternal` 会用默认值重建，丢失用户配置。

**影响：**
- 崩溃瞬间丢失所有用户设置（UI tuning + logging override）。
- 对于 v0.1 轻量设置（仅几个 UI 参数），影响有限，但随设置项增加影响放大。

**原因：**
POSIX `rename()` 是原子的，但 Windows `File.rename` 在目标存在时的行为是平台依赖的。

**建议：**
将 Windows 的 "delete + rename" 替换为使用 `dart:io` 的 `File.copySync` + `File.deleteSync`，或先备份再替换：

```dart
// fallback 分支改为：
final backup = File('${target.path}.bak');
if (await target.exists()) {
    await target.copy(backup.path);  // 先备份
}
try {
    await temp.rename(target.path);  // 尝试覆盖
} catch (_) {
    await target.delete();
    await temp.rename(target.path);
}
await backup.delete().onError((_, __) {});  // 清理备份
```

或者更简单：在 startup 时检查 `.tmp.*` 残留文件，若存在且目标不存在，将 temp 文件 rename 为目标（crash recovery）。

**验证方式：**
1. 在 Windows 上运行程序，在 `delete` 操作后、`rename` 之前强制终止进程（使用 Process Explorer）。
2. 重启应用，检查 settings.json 是否存在，以及内容是否为默认值还是保留了用户设置。

---

### 2.4 `schema_version` 写入但从未被读取作版本迁移决策

**现象：**
`_backfillMissingDefaults` 在缺少 `schema_version` 时写入 `1`（`local_settings_store.dart:202`），但没有任何代码读取 `schema_version` 并基于它执行数据迁移逻辑。

**影响：**
- 当 `settings.json` schema 升级时（如 v0.2 新增字段），无法判断当前文件是"空白文件"还是"旧版本文件"，只能依赖 `backfill` 的 key 存在性检查，不够精确。
- 例如：若 v0.2 需要将某字段重命名，backfill 会加入新字段（正确），但无法删除旧字段，导致累积冗余。

**原因：**
`schema_version` 是 schema 演化的基础设施，目前仅完成了写入，缺少读取校验逻辑。

**建议：**
在 `_loadRuntimeSettings` 的开头添加版本校验：
```dart
final schemaVersion = decoded['schema_version'];
if (schemaVersion is int && schemaVersion > 1) {
    // 当前 v0.1 代码处理不了更高版本，降级到默认值
    return;
}
```
并将此作为 v0.2 schema 演化的扩展点（`TODO(v0.2): add migration for schema_version >= 2`）。

**验证方式：**
手动修改 `settings.json` 中 `"schema_version": 999`，重启应用，观察是否使用了默认值（预期：当前代码忽略 schema_version，不会降级）。

---

## 三、服务生命周期

### 3.1 `RustBridge` 静态标志与 `LocalSettingsStore` 静态标志没有跨模块复位保障

**现象：**
`RustBridge` 使用纯 Dart 静态布尔标志（`_initialized`、`_entryDbPathConfigured`）追踪初始化状态（`rust_bridge.dart:70–78`）。`LocalSettingsStore` 同样使用 `_initialized` 静态标志（`local_settings_store.dart:10`）。

两者都提供 `resetForTesting()` 方法，但这些方法是手动维护的——若新增静态字段后忘记在 `resetForTesting()` 中重置，测试间会出现状态泄漏。

**影响：**
- 在集成测试中，若前一个测试成功初始化了 `RustBridge` 并设置了 `_entryDbPathConfigured = true`，后续测试即使传入不同路径，`ensureEntryDbPathConfigured` 也会直接 fast-path 返回，不会重新配置。
- 这在实际应用中不是问题（进程生命周期内只初始化一次），但测试隔离性较弱。

**原因：**
全局单例初始化模式的固有风险，缺少统一的"test lifecycle hook"管理。

**建议：**
将 `resetForTesting()` 中的字段列表整理为一个注释块，明确标注"所有静态字段必须在此处重置"，并在 PR review 中要求新增静态字段时同步更新 `resetForTesting`。这是文档和流程约束，不需要代码改动。

此外，考虑在 CI 中加入一个静态分析检查：`resetForTesting()` 中重置的字段数量 ≥ 静态变量声明数量（可以用 Dart lint 规则或简单的 test 验证）。

**验证方式：**
手动检查 `resetForTesting()` 方法中的字段列表与文件顶部 `static` 声明数量是否一致（`rust_bridge.dart` 中 static 字段有 8 个，`resetForTesting` 重置了 8 个，当前是一致的，但需要持续维护）。

---

### 3.2 `bootstrapLogging` 与 `ensureEntryDbPathConfigured` 耦合，一个失败会屏蔽另一个的错误信息

**现象：**
`bootstrapLogging`（`rust_bridge.dart:316`）在内部调用了 `ensureEntryDbPathConfigured`：
```dart
await ensureEntryDbPathConfigured(dbPathOverride: resolvedDbPath);
final initError = initLoggingCall(level: level, logDir: resolvedLogDir);
```

若 `ensureEntryDbPathConfigured` 抛出异常（如 DB 路径权限不足），`bootstrapLogging` 的 catch 块会捕获并记录为 `failure`，但错误信息是通用的：
```dart
'Rust logging/entry-db init failed. log_dir=... db_path=...'
```

这使得"DB 路径配置失败"和"日志初始化失败"两种故障路径产生完全相同的诊断信息。

**影响：**
- 在 diagnostics 页面，开发者无法区分是"DB 路径失败导致无日志"还是"日志目录创建失败"。
- 线上排查困难：症状相同（logging snapshot 有 errorMessage），根因不同。

**原因：**
两个初始化操作被合并到一个 try/catch 块，错误上下文丢失。

**建议：**
将两步拆分，各自捕获并记录独立的错误标签：

```dart
try {
    await ensureEntryDbPathConfigured(dbPathOverride: resolvedDbPath);
} catch (error, stackTrace) {
    logger(message: 'entry-db-path configure failed', error: error, stackTrace: stackTrace);
    // 记录为特定失败类型，继续尝试日志初始化
}

try {
    final initError = initLoggingCall(level: level, logDir: resolvedLogDir);
    // ...
} catch (error, stackTrace) {
    logger(message: 'logging-init failed', error: error, stackTrace: stackTrace);
}
```

**验证方式：**
1. 将 `resolvedDbPath` 设置为一个无写权限的路径（如 `C:\Windows\System32\lazynote.db`），触发 DB 路径失败。
2. 检查 diagnostics 面板中的 `loggingInitSnapshot.errorMessage` 是否能明确区分"db-path"失败与"logging"失败。

---

### 3.3 FRB `RustLib.init()` 失败后 `_initFuture` 被清空，并发初始化可并发再试

**现象：**
`_initInternal`（`rust_bridge.dart:231–241`）：
```dart
static Future<void> _initInternal() async {
    try {
        final externalLibrary = _resolveWorkspaceLibrary();
        await rustLibInit(externalLibrary);
        _initialized = true;
    } catch (_) {
        _initFuture = null;  // ← 失败后清空 future，允许下次重试
        rethrow;
    }
}
```

若两个并发调用同时发现 `_initFuture == null`（在第一次失败之后、第二次调用到来之间），会创建两个独立的 `_initInternal()` Future，同时调用 `RustLib.init()` 两次。

**影响：**
FRB 的 `RustLib.init()` 若被并发调用，行为取决于 FRB 内部实现（通常是幂等的，但未必有并发保障）。若 native 动态库加载不幂等（如 `dlopen` 两次），可能触发未定义行为。

**原因：**
retry-on-failure 逻辑通过清空 future 实现，但并发窗口未被保护。

**建议：**
在 `init()` 函数中加一个失败计数或"永久失败"标记，避免无限重试：

```dart
static bool _initFailed = false;

static Future<void> init() {
    if (_initialized) return Future.value();
    if (_initFailed) return Future.error(StateError('RustBridge init permanently failed'));
    // ...
}

// 在 _initInternal catch 块：
} catch (_) {
    _initFuture = null;
    _initFailed = true;  // 标记为永久失败
    rethrow;
}
```

在 `resetForTesting()` 中同时重置 `_initFailed`。

**验证方式：**
1. 在测试中将 `rustLibInit` mock 为始终抛出异常，并发调用 `init()` 两次，检查是否产生两次 `rustLibInit` 调用（当前实现：是的）。
2. 修改后验证：失败后的第二次并发调用直接返回已知错误，不重试。

---

## 四、日志与可观测性

### 4.1 `flexi_logger` 使用 `WriteMode::BufferAndFlush`，崩溃前最后几条日志可能丢失

**现象：**
`logging.rs:93`：
```rust
.write_mode(WriteMode::BufferAndFlush)
```

`BufferAndFlush` 将日志写入内存缓冲区，定期 flush 到文件。若进程在 flush 前崩溃（OOM、段错误），缓冲区中的日志丢失。

Panic hook（`logging.rs:196–212`）捕获了 panic 并调用 `error!(...)`，但这条 error log 本身也在缓冲区中，若 panic 后进程立即终止，可能同样丢失。

**影响：**
崩溃时最关键的诊断信息（崩溃前的操作上下文）可能不存在于日志文件中。对于本地桌面应用，这意味着 bug 难以复现。

**原因：**
`BufferAndFlush` 是 flexi_logger 的性能优化模式；同步写入（`WriteMode::Direct`）会显著降低日志吞吐（每条日志都是同步 IO）。

**建议：**
在 panic hook 触发时，显式调用一次强制 flush：

```rust
fn install_panic_hook_once() {
    let previous_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |panic_info| {
        let location = ...;
        let payload = ...;
        error!("event=panic_captured ...", location, payload);

        // 尝试强制 flush（flexi_logger 2.x 支持 LoggerHandle::flush()）
        if let Some(state) = LOGGING_STATE.get() {
            let _ = state._logger.flush();  // LoggerHandle::flush() 是同步的
        }

        previous_hook(panic_info);
    }));
}
```

注意：`LoggerHandle::flush()` 在 `flexi_logger 0.27+` 可用，需确认版本（`Cargo.lock` 中查看 flexi_logger 版本）。

**验证方式：**
1. 构造一个故意触发 Rust panic 的测试（`panic!("test crash")`），检查日志文件中是否有 `event=panic_captured` 条目。
2. 比较 `BufferAndFlush` 与 `WriteMode::Direct` 在快速写入场景下的 benchmark（`cargo bench`），评估切换成本。

---

### 4.2 操作级别没有 `duration_ms` 监控，只有 `db_open` 有耗时日志

**现象：**
`db/open.rs` 中的 `open_db` 正确地记录了 `duration_ms`（`open.rs:44-49`）。但 `note_service.rs`、`atom_service.rs`、`fts.rs` 等操作层没有任何计时日志。

**影响：**
- 无法区分"慢在 DB 打开"还是"慢在业务查询"。
- 用户报告"笔记保存很慢"时，无法从日志定位是迁移、索引更新还是 FTS 同步导致的。

**原因：**
目前日志规范（`docs/architecture/logging.md`）定义了 `duration_ms` 字段，但仅在 `db_open` 层实现了。

**建议：**
为高频路径增加操作计时日志，最小改动：

```rust
// crates/lazynote_core/src/service/note_service.rs: create_note 入口
let started = Instant::now();
// ... 业务逻辑 ...
info!("event=note_create module=service status=ok duration_ms={}", started.elapsed().as_millis());
```

优先为 `note_create`、`note_update`、`search_all` 三个高频操作添加，不需要覆盖所有操作。

**验证方式：**
添加后，在 diagnostics 日志面板中搜索 `event=note_update`，确认每次自动保存都有对应的耗时记录，并观察正常操作下的 p50/p95 延迟分布。

---

### 4.3 Dart 侧日志缺少结构化字段，`_envelopeError` 输出为人类可读字符串

**现象：**
`_envelopeError`（`notes_controller.dart:1546–1558`）将错误格式化为 `"[$errorCode] $message"` 字符串。Dart 侧通过 `dev.log(message, name: 'RustBridge')` 写入 Flutter 调试日志。

diagnostics 面板（`debug_logs_panel.dart`）读取 Rust 滚动日志文件（结构化），但 Dart 侧的错误信息只通过 `dev.log` 输出到 Dart VM 日志，不写入 Rust 日志文件，无法在同一日志视图中关联。

**影响：**
- Rust 日志和 Dart 日志是两个独立的流，无法在同一窗口中做时间序关联分析（如"Dart 发起 note_update → Rust 收到 → Rust 返回错误 → Dart 收到错误"）。
- 排查跨 FFI 调用链的问题需要同时看两个日志源。

**原因：**
Flutter 的 `dev.log` 输出到 Dart VM 日志（Observatory/DevTools），而 Rust 日志写入文件，两者天然分离。

**建议：**
为重要的 Dart 侧错误事件增加一个专用 FFI 调用（`log_dart_event`），将关键 Dart 日志条目写入 Rust 日志文件，使日志流合并：

```rust
// 新增 FFI 函数（crates/lazynote_ffi/src/api.rs）
#[flutter_rust_bridge::frb(sync)]
pub fn log_dart_event(level: String, event: String, module: String, message: String) {
    // 转为结构化日志
    match level.as_str() {
        "error" => error!("event={event} module={module} message={message} source=dart"),
        "warn"  => warn!(...),
        _       => info!(...),
    }
}
```

这是一个小型新增 FFI 接口，不破坏现有 API。

**验证方式：**
1. 在测试中调用 `log_dart_event("error", "note_save_failed", "notes", "FFI returned db_error")`。
2. 在 Rust 日志文件中检索 `source=dart`，验证 Dart 事件出现在正确的时间戳位置。

---

### 4.4 diagnostics 面板读取日志文件时可能与 `flexi_logger` 写入产生竞争

**现象：**
`debug_logs_panel.dart` / `log_reader.dart`（根据文件列表推测）通过读取 `%APPDATA%\LazyLife\logs\lazynote*.log` 文件获取实时日志。同时 `flexi_logger` 以 `BufferAndFlush` 模式持续写入同一文件。

在 Windows 上，文件读写默认不加 `FILE_SHARE_READ` 以外的锁，`flexi_logger` 写入时读取者可能获取到截断的行（最后一行写到一半）。

**影响：**
日志面板偶尔显示不完整的最后一行（截断的 JSON 或结构化行），解析失败显示乱码或空行。

**原因：**
Windows 文件系统的非原子写入行为 + 日志读取时缺少行完整性校验。

**建议：**
在日志读取器中，仅显示以换行符 `\n` 结尾的完整行，丢弃最后一个不完整片段：

```dart
final lines = content.split('\n');
final completeLines = lines.length > 1
    ? lines.sublist(0, lines.length - 1)  // 丢弃最后可能不完整的行
    : lines;
```

这是极小的防御性改动。

**验证方式：**
在快速写入日志（trace 级别 + 高频操作）时，同时开启 diagnostics 面板，观察是否出现截断行或解析异常。

---

## 总结

| # | 分类 | 问题 | 建议改动规模 |
|---|------|------|------------|
| 1.1 | 状态管理 | activeDraftContent 双重持有，tab 切换可产生状态撕裂 | 小（统一切换路径） |
| 1.2 | 状态管理 | flushPendingSave while(true) 可无限延迟 tab 关闭 | 小（加重试上限） |
| 1.3 | 状态管理 | 已关闭 tab 的 tag mutation 仍会发起 FFI 调用 | 小（加 guard 检查） |
| 1.4 | 状态管理 | _items 全量 copy（当前无问题，分页后需关注） | 记录为 v0.2 预算 |
| 2.1 | 配置持久化 | loggingLevelOverride 持久化但从未被应用 | 小（接入 bootstrapLogging 或加 TODO） |
| 2.2 | 配置持久化 | result_limit 等 3 个字段写入但无消费侧 | 小（补充加载或添加 TODO） |
| 2.3 | 配置持久化 | settings.json 写入存在短暂空文件窗口（Windows） | 小（加备份策略） |
| 2.4 | 配置持久化 | schema_version 未参与版本迁移决策 | 小（加读取校验 + TODO） |
| 3.1 | 服务生命周期 | resetForTesting() 需手动同步静态字段，测试隔离弱 | 流程约束（文档） |
| 3.2 | 服务生命周期 | bootstrapLogging 与 DB 路径初始化耦合，错误不可区分 | 小（分离 try/catch） |
| 3.3 | 服务生命周期 | FRB init 失败后可并发重试，可能 dlopen 两次 | 小（加永久失败标记） |
| 4.1 | 可观测性 | BufferAndFlush 模式崩溃前日志可能丢失 | 小（panic hook 中 flush） |
| 4.2 | 可观测性 | 操作层无 duration_ms，无法定位性能热点 | 小（加几条计时日志） |
| 4.3 | 可观测性 | Dart/Rust 日志流分离，无法关联 FFI 调用链 | 中（新增 log_dart_event FFI） |
| 4.4 | 可观测性 | 日志文件读写无完整性保护，可能显示截断行 | 极小（读取时过滤不完整行） |

**优先级建议：** 1.2（安全性） → 2.1（用户可感知的功能失效） → 4.1（崩溃诊断） → 3.2（运维可观测性） → 其余按迭代节奏处理。
