# LazyNote 功能实现与使用同步报告（v0.2阶段）

## 1. 结论摘要

1. 项目当前实现与使用总体匹配度高，尤其是 Extension kernel lane（PR-0213 ~ PR-0218）已完成并做过 post-review hardening。  
2. “基础设施先声明、后暴露”的策略是成立的：Provider SPI、Extension Kernel、Capability 模型目前停留在 core/registry 层，不直接暴露给前端，符合 v0.2 的设计目标。  
3. 当前最明确的两个功能缺口是：  
`entry_search` 未暴露类型过滤（kind），以及 Workspace Tree 的 create/list/rename/move 未完成 FFI 对外。  
4. 原始报告中的部分 PR 映射有误（例如 PR-0207/0208/0209/0211 的描述与 release 计划不一致），已在本版修正。

## 2. 统计口径

1. 本报告基于以下来源：
- `docs/releases/v0.2/README.md`
- `docs/releases/v0.2/prs/*.md` 的 `Status`
- `crates/lazynote_ffi/src/api.rs`
- `crates/lazynote_core/src/service/tree_service.rs`
2. “已使用”定义：
- 功能在 Flutter 页面/控制器中存在明确接入路径（而不只是代码存在）。
3. “有意延迟”定义：
- core 或文档契约已完成，但未进入 FFI/UI 公共调用面，且该延迟符合对应 PR 的 scope 说明。

## 3. 已实现且已接入（高置信）

1. UI Slots 系统  
实现：`apps/lazynote_flutter/lib/app/ui_slots/`  
接入：`apps/lazynote_flutter/lib/features/entry/entry_shell_page.dart`、`apps/lazynote_flutter/lib/features/notes/notes_page.dart`
2. Command Registry / Parser Chain  
实现：`apps/lazynote_flutter/lib/features/entry/`  
接入：`apps/lazynote_flutter/lib/features/entry/single_entry_controller.dart`
3. Diagnostics 页面能力  
实现：`apps/lazynote_flutter/lib/features/diagnostics/`  
接入：Workbench 路径
4. Settings 基础能力  
实现：`apps/lazynote_flutter/lib/features/settings/`  
接入：Workbench 路径
5. LocalSettingsStore  
实现：`apps/lazynote_flutter/lib/core/settings/`  
接入：多处调用
6. FFI 主链路能力  
实现：`crates/lazynote_ffi/src/api.rs`  
说明：当前可见 `pub async fn` 导出入口为 17 个；“FFI 全部使用”需要按绑定调用图做单独核验，建议不在评审文档中写死“全部使用”。

## 4. 已实现但按策略暂不暴露（有意延迟）

1. Provider SPI（PR-0215）  
实现：`crates/lazynote_core/src/sync/`  
状态：core 合同完成，未走 FFI 暴露
2. Extension Kernel（PR-0213）  
实现：`crates/lazynote_core/src/extension/`  
状态：registry/manifest 完成，未走 FFI 暴露
3. Plugin Capability Model（PR-0217）  
实现：`crates/lazynote_core/src/extension/capability.rs`  
状态：core 守卫完成，前端 audit 页当前是 v0.2 静态快照策略
4. API Lifecycle Policy（PR-0218）  
实现：`docs/governance/api-lifecycle-policy.md`  
状态：治理文档完成

## 5. 当前真实缺口（建议优先补齐）

1. Search 类型过滤未对前端开放  
证据：`crates/lazynote_ffi/src/api.rs` 中 `entry_search` 构建 `SearchQuery` 时固定 `kind: None`。  
影响：前端不能按 note/task/event 类型过滤搜索。  
建议：在 `entry_search` FFI 增加可选 `kind` 参数，并同步错误码与文档。
2. Workspace Tree CRUD 的 FFI 暴露不完整  
证据：`crates/lazynote_core/src/service/tree_service.rs` 已有 `create_folder/create_note_ref/list_children/rename_node/move_node/delete_folder`，但 FFI 目前仅 `workspace_delete_folder`。  
影响：前端无法完成树结构创建、浏览、重命名、拖拽移动等闭环。  
建议：在 PR-0203 里渐进开放剩余操作，优先顺序为：
`list_children -> create_folder/create_note_ref -> rename_node -> move_node`。

## 6. PR 状态快照（以当前文档为准）

1. `Completed`：PR-0211、PR-0213、PR-0214、PR-0215、PR-0216、PR-0217、PR-0218、PR-0219、PR-0220A、PR-0220B、PR-0221  
2. `Planned`：PR-0201、PR-0202、PR-0203、PR-0204、PR-0205、PR-0206、PR-0207、PR-0208、PR-0209、PR-0210、PR-0212

## 7. 推荐后续动作

1. 先推进 PR-0203 的剩余 FFI 合同（Workspace CRUD），让 Workspace lane 具备真实 UI 可达性。  
2. 在 Support lane 中补 `entry_search(kind)`，作为低风险高收益改进。  
3. 给本报告加“自动化校验脚本”入口（例如 PR 状态抓取 + FFI 导出数量统计），避免后续人工映射漂移。
