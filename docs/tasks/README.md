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
| P0-3 询价 North Star 链路 | `task/p0-3-north-star` | [P0-3.md](P0-3.md) | senior | — | 审查第 2 轮：F1～F8 已修复，需再修 R2-A～D（`review/P0-3`，先做） |
| P0-2 LLM 原生工具调用基线 | `task/p0-2-llm-baseline` | [P0-2.md](P0-2.md) | senior | P0-3 之后 | 已合入（[审查](P0-2-review.md)） |
| P0-1 PR/push 自动门禁 | `task/p0-1-ci` | [P0-1.md](P0-1.md) | junior（修复） | E11 之后 | 审查：方案 A 去掉 tag 排除，修复改由 junior 在 `review/P0-1` 上做 |
| P0-J1 取证环境自检脚本 | `task/p0-j1-env-doctor` | [P0-J1.md](P0-J1.md) | junior | — | 已合入（[审查](P0-J1-review.md)） |
| P0-J2 自检脚本安全加固 | `task/p0-j2-doctor-hardening` | [P0-J2.md](P0-J2.md) | junior | — | 已合入（[审查](P0-J2-review.md)） |
| P0-S1 模型网关与助手的凭据脱敏 | `task/p0-s1-credential-redaction` | [P0-S1.md](P0-S1.md) | senior | P0-3 修复之后 | 已派发 |
| P0-J3 自检脚本测试收尾（低优先级） | `task/p0-j3-doctor-tests` | [P0-J3.md](P0-J3.md) | junior | E11 之后 | 待转交 |
| P0-F1 修复不稳定的局域网安全测试 | `task/p0-f1-lan-flaky-test` | [P0-F1.md](P0-F1.md) | senior | P0-S1 之后 | 待转交 |
| P0-4 真机与真实模型取证 | `task/p0-4-evidence`（待建） | [P0-4.md](P0-4.md) | engineer | P0-3 合入（P0-2、P0-J1 已合入；P0-1 不再是前置） | 待依赖 |
| B 2.4 原型补齐（冻结前在途） | `feat/b-ui` → 修复在 `review/B-2.4` | `2026-10-04-w1-agent-prompts.md`「追加 · B（Sonnet）· 2.4」；审查见 `review/B-2.4` 上的 `docs/tasks/B-2.4-review.md` | engineer | — | 审查：需修复 S1～S3、S5、S7（S6 待 E11） |
| E11 研究对象页（冻结前在途） | `feat/e-support` | `2026-10-04-w1-agent-prompts.md`「追加 · E（opencode）· E11」 | junior | — | 在途（据交接：8 个文件改动未提交，验收口径见 [审查](HANDOVER-A-review.md)） |

已停用：过渡集成分支 `feat/p0-ci-llm-baseline` 不再使用，合入目标统一为 `develop`。
