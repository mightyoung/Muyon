# 任务派发索引

**leader 已交接，接任者先读 [HANDOVER-LEADER.md](HANDOVER-LEADER.md)。** 决定与规则见 [ADR-0001](../adr/0001-leadership-and-scope-freeze.md)，计划见 [第一阶段执行计划](../superpowers/plans/2026-10-05-phase0-plan.md)。**当前处于范围冻结期**，只做 ADR-0001 允许的工作。

## 规则

- **派发**：每个任务一个分支，任务说明在该分支的固定位置 `docs/tasks/<编号>.md`。执行者检出分支、阅读说明、只在该分支提交并推送，不合并到 `develop`。
- **执行**：第二阶段起，用户 2026-10-07 指示开发任务由 leader 派生的 **Sonnet 5.5 子代理**执行，leader 只做派发、审查、合入；真机取证仍由本地 engineer 执行。此前：实现与真机取证都由本地 agent 执行。senior engineer = Opus，engineer = Sonnet，engineer2 = grokbot（云端，无 Flutter；只做静态核对与文档类任务，不派构建与验证），junior = opencode。云端不运行开发任务。
- **审查**：由 leader 进行。任务完成后，leader 从任务分支的最终提交建立 `review/<编号>`，在该分支写入 `docs/tasks/<编号>-review.md`，清单见 [REVIEW.md](REVIEW.md)。需要修改时，执行者检出审查分支修复并推送；leader 复审通过后合入 `develop`。
- **自查**：执行者提交前，先按 [REVIEW.md](REVIEW.md) 的「必做」逐项自查。

## 任务

| 任务 | 分支 | 说明 | 执行 | 依赖 | 状态 |
|---|---|---|---|---|---|
| HANDOVER-A 原 leader 交接 | `task/handover-a` | [HANDOVER-A.md](HANDOVER-A.md) | A | — | 已完成（[审查通过](HANDOVER-A-review.md)） |
| P0-3 询价 North Star 链路 | `task/p0-3-north-star` | [P0-3.md](P0-3.md) | senior | — | 已合入（[审查](P0-3-review.md)，三轮） |
| P0-2 LLM 原生工具调用基线 | `task/p0-2-llm-baseline` | [P0-2.md](P0-2.md) | senior | P0-3 之后 | 已合入（[审查](P0-2-review.md)） |
| P0-1 PR/push 自动门禁 | `task/p0-1-ci` | [P0-1.md](P0-1.md) | junior（修复） | — | 已合入（[审查](P0-1-review.md)，两轮） |
| P0-J1 取证环境自检脚本 | `task/p0-j1-env-doctor` | [P0-J1.md](P0-J1.md) | junior | — | 已合入（[审查](P0-J1-review.md)） |
| P0-J2 自检脚本安全加固 | `task/p0-j2-doctor-hardening` | [P0-J2.md](P0-J2.md) | junior | — | 已合入（[审查](P0-J2-review.md)） |
| P0-S1 模型网关与助手的凭据脱敏 | `task/p0-s1-credential-redaction` | [P0-S1.md](P0-S1.md) | senior | — | 已合入（[审查](P0-S1-review.md)，三轮） |
| P0-S2 MCP 令牌凭据脱敏 | `task/p0-s2-mcp-token-redaction` | [P0-S2.md](P0-S2.md) | senior | — | 已合入（[审查](P0-S2-review.md)，两轮；2026-10-07 由云端 Sonnet 子代理修复 F1～F4 及复核发现的 R1、O1、O2） |
| P0-J3 自检脚本测试收尾（低优先级） | `task/p0-j3-doctor-tests` | [P0-J3.md](P0-J3.md) | junior | E11 之后 | 已合入（[审查](P0-J3-review.md)；自检脚本收口） |
| P0-F1 修复不稳定的局域网安全测试 | `task/p0-f1-lan-flaky-test` | [P0-F1.md](P0-F1.md) | senior | — | 已合入（[审查](P0-F1-review.md)） |
| P0-3c 询价链路判定收尾（低优先级） | `task/p0-3c-chain-per-question` | [P0-3c.md](P0-3c.md) | senior | — | 已合入（[审查](P0-3c-review.md)） |
| P0-3d 助手协议对真实模型的容错（D1） | `task/p0-3d-protocol-robustness` | [P0-3d.md](P0-3d.md) | senior | P0-S1 合入之后 | 已合入（[审查](P0-3d-review.md)） |
| P0-3e 协议容错的测试补齐 | `task/p0-3e-protocol-tests` | [P0-3e.md](P0-3e.md) | senior | P0-3d 之后 | 已合入（[审查](P0-3e-review.md)） |
| P0-F2 修复研究对象页测试的两个 10 分钟超时（门禁变绿） | `task/p0-f2-object-open-timeout` | [P0-F2.md](P0-F2.md) | junior | E11b 合入之后 | 已合入（[审查](P0-F2-review.md)；门禁恢复为绿） |
| E11b 研究对象页收尾（小） | `task/e11b-object-page-tests` | [E11b.md](E11b.md) | junior | P0-1 修复之后、P0-J3 之前 | 已合入（[审查](E11b-review.md)） |
| P0-4 真机与真实模型取证 | `task/p0-4-evidence` | [P0-4.md](P0-4.md) | engineer | — | 第一～三批已合入（[审查](P0-4-review.md)）；**P0-3d 之后 macOS 设备链路通过（R+M）**，用户 2026-10-07 决定以此满足退出标准第 1 项；Android 重跑转第二阶段 R-1 |
| K-1 模型适配层与 Agent 循环设计（ADR-0005） | `task/k-1-model-adapter-adr` | [K-1.md](K-1.md) | Sonnet 子代理 | 第二阶段 | 已合入（[审查](K-1-review.md)，两轮）；ADR-0005 状态“提议”，§10.1 七问待用户决定 |
| E-1 多步任务评测（现状基线） | `task/e-1-agent-task-eval` | [E-1.md](E-1.md) | Sonnet 子代理 | 第二阶段 | 进行中（2026-10-07 派发） |
| UI-0 现状截图与走查 | （未建） | [UI-0.md](UI-0.md) | engineer | 第一阶段之后 | **第一阶段之后**（用户 2026-10-06 决定） |
| UI-1 设计系统 | （未建） | [UI-1.md](UI-1.md) | senior | UI-0 | **第一阶段之后** |
| B 2.4 原型补齐（冻结前在途） | `feat/b-ui` → `review/B-2.4` | [审查](B-2.4-review.md) | engineer | — | 已合入（三轮；S6 第一阶段搁置） |
| E11 研究对象页（冻结前在途） | `feat/e-support` → `review/E11` | [审查](E11-review.md) | junior | — | 已合入（两轮；S6 第一阶段搁置） |

UI 重做的目标稿为 [设计稿 v4](../design/v4/README.md)（2026-10-07 入库，[审阅](../reviews/2026-10-07-design-v4-review.md)）；第一阶段之后按 [UI 重设计方案 §9](../design/ui-redesign-brief-2026-10-06.md) 分换壳与新能力两条线派发，分级授权见 [ADR-0002](../adr/0002-graded-assistant-authorization.md)（已采纳，第一阶段之后实施）。

已停用：过渡集成分支 `feat/p0-ci-llm-baseline` 不再使用，合入目标统一为 `develop`。
