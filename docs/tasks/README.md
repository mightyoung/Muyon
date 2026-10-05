# 任务派发索引

规则：每个任务一个分支，任务说明放在该分支的固定位置 `docs/tasks/<任务编号>.md`。执行者检出分支、读这份文件、只在该分支提交。文件名按任务编号唯一，合并时不会互相冲突。

分工：实现与真机取证由用户本地的 agent 执行（senior engineer = Opus，engineer = Sonnet，junior = opencode）。leader 负责拆解、派发、审查与合并，所有审查都由 leader 做。P0-1～P0-3 在调整分工前已由云端子代理开工，做完为止，**不要重复派发给本地 agent**。

审查也走分支：任务完成后，leader 从任务分支最终提交建立 `review/<任务编号>`，在该分支写入审查结论 `docs/tasks/<任务编号>-review.md`（清单见 [REVIEW.md](REVIEW.md)）。需要修改时，执行者检出 `review/<任务编号>`，按审查结论修复并提交在该分支；leader 复审通过后合入集成分支。

集成分支：`feat/p0-ci-llm-baseline`（leader 审查后合并，不直接改 `develop`）。计划：[第一阶段执行计划](../superpowers/plans/2026-10-05-phase0-plan.md)。

| 任务 | 分支 | 说明 | 执行 | 审查 | 依赖 | 状态 |
|---|---|---|---|---|---|---|
| P0-1 PR/push 自动门禁 | `p0-1-ci` | [P0-1.md](P0-1.md) | 云端子代理（Sonnet） | leader | — | 进行中 |
| P0-2 LLM 原生工具调用基线 | `feat/p0-2-llm-selection-baseline` | [P0-2.md](P0-2.md) | 云端子代理（Opus） | leader | — | 进行中 |
| P0-3 询价 North Star 链路 | `feat/p0-3-north-star-inquiry` | [P0-3.md](P0-3.md) | 云端子代理（Opus） | leader | — | 进行中 |
| P0-J1 取证环境自检脚本 | `task/p0-j1-env-doctor` | [P0-J1.md](P0-J1.md) | 本地 junior（opencode） | leader | — | 已转交 |
| P0-4 真机与真实模型取证 | `task/p0-4-evidence`（待建） | [P0-4.md](P0-4.md) | 本地 engineer | leader | P0-1、P0-2、P0-3、P0-J1 合入 | 待依赖 |
