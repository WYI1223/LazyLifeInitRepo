# Contributing

感谢你为 LazyNote 做贡献。

本文件是项目当前阶段的最小贡献规范。后续会随项目发展迭代。

## Before You Start

1. 先阅读 `README.md`、`VERSIONING.md`、`docs/releases/` 下的当前版本计划。
2. 新功能或较大改动请先开 Issue（或在已有 Issue 下认领）。
3. 涉及架构决策时，请同步更新 `docs/architecture/adr/`。
4. 必须遵循 `docs/architecture/engineering-standards.md`。
5. 注释与代码可读性必须遵循 `docs/architecture/code-comment-standards.md`。
6. 涉及 API 合约改动时，必须同步更新 `docs/api/*` 与 `docs/governance/API_COMPATIBILITY.md`。

## Branch Naming

建议使用以下分支命名：

- `feat/<short-name>`
- `fix/<short-name>`
- `chore/<short-name>`
- `docs/<short-name>`
- `refactor/<short-name>`

例如：`feat/single-entry-router`、`fix/windows-ci-path`

## Commit Convention

提交信息必须遵循 Conventional Commits：

- `feat(scope): ...`
- `fix(scope): ...`
- `docs(scope): ...`
- `chore(scope): ...`
- `refactor(scope): ...`
- `test(scope): ...`

示例：

- `feat(core): add atom soft delete support`
- `fix(ci): correct windows flutter cache key`
- `docs(releases): update v0.1 PR dependency notes`

## Pull Request Rules

每个 PR 请尽量小而明确，建议一件事一个 PR。

PR 描述至少包含：

1. 变更摘要（What/Why）
2. 影响范围（模块、平台）
3. 验证方式（本地命令或截图）
4. 是否需要文档更新
5. 是否影响版本计划（`docs/releases/`）

## Quality Gates

合并前应满足：

- CI 通过（至少 lint/test/build）
- API 合约门禁通过（若改动合约文件，必须同步更新 `docs/api/*` 与 `docs/governance/API_COMPATIBILITY.md`）
- 对应测试或验证步骤可复现
- 行为变化已更新文档
- 版本相关改动已更新 `CHANGELOG.md`（如适用）

## Docs-First Rule

以下改动必须同步更新文档：

- 新增用户可见功能
- 改动开发流程或脚本
- 改动版本计划或里程碑
- 改动架构边界或技术决策
- 改动 FFI/Dart API 合约或错误码语义（更新 `docs/api/*`）

## Code Style

- 尽量保持单一职责和小 PR。
- 避免引入无关重构。
- 不要在同一 PR 混合功能改动与大规模格式化。

## Security

请不要在仓库提交密钥、token、证书或任何敏感配置。

如发现安全问题，请走私下通道联系维护者，不要公开披露漏洞细节。
具体流程见仓库根目录 `SECURITY.md`。

## Need Help

如果你不确定改动是否合适，请先开 Draft PR 或 Issue 讨论。
