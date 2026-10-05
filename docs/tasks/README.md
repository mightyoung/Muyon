# 任务派发索引

规则：每个任务一个分支，任务说明放在该分支的固定位置 `docs/tasks/<任务编号>.md`。执行者检出分支、读这份文件、只在该分支提交。文件名按任务编号唯一，合并时不会互相冲突。

审查也是任务：任务完成后，从任务分支最终提交建立 `review/<任务编号>`，专项说明放 `docs/tasks/<任务编号>-review.md`，通用清单见 [REVIEW.md](REVIEW.md)。审查通过的审查分支（含任务提交与审查修复）由规划者合入集成分支。

集成分支：`feat/p0-ci-llm-baseline`（规划者负责审查与合并，不直接改 `develop`）。计划：[第一阶段执行计划](../superpowers/plans/2026-10-05-phase0-plan.md)。

| 任务 | 分支 | 说明 | 执行 | 审查 | 状态 |
|---|---|---|---|---|---|
| P0-1 PR/push 自动门禁 | `p0-1-ci` | [P0-1.md](P0-1.md) | engineer（Sonnet） | senior（Opus） | 进行中 |
| P0-2 LLM 原生工具调用基线 | `feat/p0-2-llm-selection-baseline` | [P0-2.md](P0-2.md) | senior（Opus） | engineer（Sonnet） | 进行中 |
| P0-3 询价 North Star 链路 | `feat/p0-3-north-star-inquiry` | [P0-3.md](P0-3.md) | senior（Opus） | engineer（Sonnet） | 进行中 |
| P0-J1 取证环境自检脚本 | `task/p0-j1-env-doctor` | [P0-J1.md](P0-J1.md) | junior（opencode） | engineer（Sonnet） | 已转交 opencode |
