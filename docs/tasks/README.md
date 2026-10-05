# 任务派发索引

决定与规则见 [ADR-0001](../adr/0001-leadership-and-scope-freeze.md)，计划见 [第一阶段执行计划](../superpowers/plans/2026-10-05-phase0-plan.md)。**当前处于范围冻结期**，只做 ADR-0001 允许的工作。

## 规则

- **派发**：每个任务一个分支，任务说明在该分支的固定位置 `docs/tasks/<编号>.md`。执行者检出分支、阅读说明、只在该分支提交并推送，不合并到 `develop`。
- **执行**：实现与真机取证都由本地 agent 执行。senior engineer = Opus，engineer = Sonnet，junior = opencode。云端不运行开发任务。
- **审查**：由 leader 进行。任务完成后，leader 从任务分支的最终提交建立 `review/<编号>`，在该分支写入 `docs/tasks/<编号>-review.md`，清单见 [REVIEW.md](REVIEW.md)。需要修改时，执行者检出审查分支修复并推送；leader 复审通过后合入 `develop`。
- **自查**：执行者提交前，先按 [REVIEW.md](REVIEW.md) 的「必做」逐项自查。

## 任务

| 任务 | 分支 | 说明 | 执行 | 依赖 | 状态 |
|---|---|---|---|---|---|
| HANDOVER-A 原 leader 交接 | `task/handover-a` | [HANDOVER-A.md](HANDOVER-A.md) | A | — | 已完成（[审查通过](HANDOVER-A-review.md)） |
| P0-3 询价 North Star 链路 | `task/p0-3-north-star` | [P0-3.md](P0-3.md) | senior | — | 已交付，核实中（`review/P0-3`） |
| P0-2 LLM 原生工具调用基线 | `task/p0-2-llm-baseline` | [P0-2.md](P0-2.md) | senior | P0-3 之后 | 已交付，核实中（`review/P0-2`） |
| P0-1 PR/push 自动门禁 | `task/p0-1-ci` | [P0-1.md](P0-1.md) | engineer | B 2.4 之后 | 已转交（含 WIP） |
| P0-J1 取证环境自检脚本 | `task/p0-j1-env-doctor` | [P0-J1.md](P0-J1.md) | junior | — | 审查：需修复 F1～F3，在 `review/P0-J1` 上修（见该分支 `docs/tasks/P0-J1-review.md`） |
| P0-4 真机与真实模型取证 | `task/p0-4-evidence`（待建） | [P0-4.md](P0-4.md) | engineer | P0-1、P0-2、P0-3、P0-J1 合入 | 待依赖 |
| B 2.4 原型补齐（冻结前在途） | `feat/b-ui` | `2026-10-04-w1-agent-prompts.md`「追加 · B（Sonnet）· 2.4」 | engineer | — | 在途（据交接：13 个文件改动未提交，验收口径见 [审查](HANDOVER-A-review.md)） |
| E11 研究对象页（冻结前在途） | `feat/e-support` | `2026-10-04-w1-agent-prompts.md`「追加 · E（opencode）· E11」 | junior | — | 在途（据交接：8 个文件改动未提交，验收口径见 [审查](HANDOVER-A-review.md)） |

已停用：过渡集成分支 `feat/p0-ci-llm-baseline` 不再使用，合入目标统一为 `develop`。
