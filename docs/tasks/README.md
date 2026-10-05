# 任务派发索引

规则：每个任务一个分支，任务说明放在该分支的固定位置 `docs/tasks/<任务编号>.md`。执行者检出分支、读这份文件、只在该分支提交。文件名按任务编号唯一，合并时不会互相冲突。

集成分支：`feat/p0-ci-llm-baseline`（规划者负责审查与合并，不直接改 `develop`）。计划：[第一阶段执行计划](../superpowers/plans/2026-10-05-phase0-plan.md)。

| 任务 | 分支 | 说明 | 执行 | 审查 | 状态 |
|---|---|---|---|---|---|
| P0-1 PR/push 自动门禁 | `p0-1-ci` | [P0-1.md](P0-1.md) | engineer（Sonnet） | senior（Opus） | 进行中 |
| P0-2 LLM 原生工具调用基线 | `feat/p0-2-llm-selection-baseline` | [P0-2.md](P0-2.md) | senior（Opus） | engineer（Sonnet） | 进行中 |
| P0-3 询价 North Star 链路 | `worktree-agent-aeed2e9750de4aa36` | [P0-3.md](P0-3.md) | senior（Opus） | engineer（Sonnet） | 进行中 |
| P0-J1 取证环境自检脚本 | `task/p0-j1-env-doctor` | [P0-J1.md](P0-J1.md) | junior（opencode） | engineer（Sonnet） | 待领取 |
