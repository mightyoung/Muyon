# leader 交接（第二阶段进行中，第 3 次更新）

更新时间：2026-10-07 · leader：本机 leader 会话（用户 2026-10-07 确认**只保留这一个 leader**，另一个会话不再合入 `develop`）· `develop` 基线：本文件所在提交

**先读：**
- [ADR-0001](../adr/0001-leadership-and-scope-freeze.md)：角色、派发、审查与合入；末尾「后续记录」是全部用户决定的时间线
- [ADR-0003](../adr/0003-phase2-scope.md)：第二阶段范围；[路线图](../superpowers/plans/2026-10-07-roadmap-phase2-4.md) §3、§3.1：任务顺序与退出标准
- 已采纳：[ADR-0002](../adr/0002-graded-assistant-authorization.md) 分级授权、[ADR-0005](../adr/0005-model-adapter-and-agent-loop.md) 模型适配层与 Agent 循环。提议：[ADR-0004](../adr/0004-module-contract-v2.md) 模块契约 v2
- [任务索引 README.md](README.md)、[审查清单 REVIEW.md](REVIEW.md)

## 0. 在途任务（最先处理）

- ADR-0004 已采纳（用户 2026-10-07，Q1～Q13 全部按建议）。
- 已派发：**FOLIO-BYPASS**（junior，安全修复，优先）、**REG-2a**（Codex，外传工具入账，迁移 9）、**REG-2b**（`implementer-sonnet`，模块激活与范围单点，迁移 10）。三项都审查后再合入；REG-2a 和 REG-2b 后合入的一方负责重新编号迁移。
- REG-2 两半都合入后，按路线图 §3.1 派 REG-3、REG-4、T-3。REG-3 派发前，先请用户确认科研导出 / 导入类写操作的清单（Q10）。

## 1. 工作方式

- **执行**（用户 2026-10-07）：开发任务由 leader 派生的 **Sonnet 5.5 子代理** `implementer-sonnet`（`~/.claude/agents/implementer-sonnet.md`，在 `/tmp` 的独立克隆里工作，只推任务分支）执行，Codex（本机，额度已恢复）也可派较大的实现任务；leader 只做派发、审查、合入。真机取证仍由本机 engineer 执行。senior（Opus）、junior（opencode）、grokbot（云端，无 Flutter，只做静态核对）仍可按需使用。
- **额度约束（用户 2026-10-07）**：Claude 额度不够，**开发和审查尽量不用后台子代理**。开发派给 Codex、junior（opencode）、engineer、senior；审查优先交叉派给非作者成员（Codex、junior、engineer 重跑构建和测试，grokbot 做静态核对），leader 只读 diff、抽查关键处。只有安全敏感、又没有合适成员可派时，才用 `reviewer-sonnet-*`，且一次只开一个。
- **派发**：一个任务一个分支 `task/<编号>`，说明 `docs/tasks/<编号>.md` 先提交到 `develop`，再从 `develop` 建任务分支。
- **审查**：按 [REVIEW.md](REVIEW.md)。默认用 `reviewer-sonnet-high`（安全、并发、数据一致性、跨模块）、`-medium`（单模块代码与测试）、`-low`（脚本、文档、证据）；Opus 只在结论有分歧或问题特别难时用。定义在本机 `~/.claude/agents/`，写死 `model: claude-sonnet-5-5`。不要用 `model: "sonnet"`/`"opus"` 别名：`~/.claude/settings.json` 把别名映射到 MiniMax，会 404。
- **合入**：`git merge --no-ff origin/review/<编号>`，核对任务文件与审查版本逐字一致（diff 为 0 行），然后更新索引并推送。审过两三轮、只剩低概率问题时先合入，剩下的另开小任务。
- **本机环境要点**：
  - 本会话的钩子不允许写其他工作树。leader 在自己的工作树里用分离 HEAD 操作：检出 `origin/<分支>`，提交后 `git push origin HEAD:<分支>`。`develop` 被另一个工作树占用，不能直接检出。
  - 子代理在 `/tmp` 下用 `git archive` 导出的副本里跑测试、变异和探针，用完删除。
  - **CI 的并发组会取消同一分支上进行中的运行**（`cancel-in-progress`）。往 `review/<编号>` 推审查文件，要等该分支的 CI 跑完再推。
  - GitHub 仓库是 `mightyoung/Muyon`；`gh` 命令带 `--repo mightyoung/Muyon`。
  - 跑测试时取消代理，并设 `NO_PROXY=localhost,127.0.0.1,::1`；执行 `verify.sh`、`ci.sh` 时不得导出 `MUYON_EVAL_REAL`。
  - 加压测试必须用 `trap` 回收 `yes` 进程。
  - `verify.sh`、`ci.sh` 都把 analyzer 的 info 当失败。本机跑 `ci.sh` 时，inquiry 的 golden 截图会因 macOS 27 渲染漂移失败，属于已知情况。
  - `git` 报 Xcode 许可错误（exit 69）时，命令前加 `DEVELOPER_DIR=/Library/Developer/CommandLineTools`。

## 2. 第二阶段已合入

| 任务 | 审查 | 留下的事 |
|---|---|---|
| K-1、K-1b：ADR-0005 已采纳 | [K-1-review.md](K-1-review.md) | — |
| K-2a 模型适配层、流式、原生工具 | [K-2a-review.md](K-2a-review.md)，三轮 | — |
| K-3 预算式循环、批量确认卡、自动压缩 | [K-3-review.md](K-3-review.md)，两轮 | 卡内不逐个检查预算；卡过期只在确认起点检查（已写入 ADR 注记） |
| K-3b 拆分 `personal_agent.dart` | [K-3b-review.md](K-3b-review.md) | `declineCompaction` 守卫、`modelTokens` 共享键是拆分前就有的问题，影响极低 |
| K-2b 测试连接、流式草稿、预设 | [K-2b-review.md](K-2b-review.md)，两轮 | — |
| K-4 执行记录事件化 | [K-4-review.md](K-4-review.md)，三轮 | 部分事件写在事务外，崩溃后最多留下「已批准无结果」，严重度低 |
| REG-1 ADR-0004（提议） | [REG-1-review.md](REG-1-review.md)，两轮 | Q1～Q13 待用户决定（第 0 节） |
| E-1 多步任务评测 | [E-1-review.md](E-1-review.md)，三轮 | **真实模型基线未跑**，要由有密钥的执行者运行 |

第一阶段已于 2026-10-07 退出，记录见[验收账本](../implementation/muyon-acceptance-ledger.md)末尾。P0 系列任务全部合入，见 README。

## 3. 下一步可派发的任务

| 任务 | 前提 | 执行 | 审查 |
|---|---|---|---|
| **REG-3、REG-4、T-3** | REG-2a、REG-2b 都合入；REG-3 先确认 Q10 清单 | 子代理 / Codex | `-high` |
| **E-1 真实基线** | 有密钥的本机执行者 | engineer | `-low` |
| **R-1** Android 重跑 North Star（vivo V2324A） | 手机连接 | engineer | `-low`（按第 5 节） |
| **UI-0** 现状截图 → **UI-1** 设计系统 → **UI-2** 新外壳 | UI-1 按 v4 `tokens.md` 加 `warn` | engineer / 子代理 | `-medium` |
| 小清理（路线图 §7 末行：注释、无用 tag、`_cardTitle` 按 rune 截断） | 任意空档 | junior | `-low` |

## 4. 第二阶段退出标准（ADR-0003）

1. 只读任务审批次数中位数为 0，写任务为 1（由 E-1 测得）。
2. 首字时延：本机 < 1.5 s，远程 < 3 s。
3. 询价 North Star 在新外壳下有真机加真实模型的证据。
4. 授权测试齐全（过期、撤销、范围变化、防重放、审查器各结果），CI 绿。
5. 示例模块只改模块包与一行登记、宿主零改动；询价、科研、原型通过契约合规测试；**能力覆盖是 CI 硬门槛**。

## 5. 真机证据的审查要点（R-1 等）

1. 证据中不得出现密钥：用 `.env` 中密钥的完整值和首尾各 12 位逐文件 grep，只报命中数；端点只保留到路径；本机路径替换为 `<repo>`。构建产物（`build/macos`、应用沙盒容器）也要 grep。
2. 链路证据 `docs/evidence/…/north-star-<平台>-<slug>.json` 的核对项：
   - `evidenceClass: real-model`、`passed: true`；
   - `readResultsChecked` 同时含 `compare_quotes` 和 `project_budget`；
   - `tasks[].tools` 与逐题判定一致；
   - `write.repeatConfirmRefused` 为 true；
   - `commit` 必须是 `develop` 上已审查过的代码。
3. 每次运行都如实入库，不挑结果。Android 运行后要卸载测试包，因为 `--dart-define` 会把密钥编进构建。

## 6. 已记录、排在后面的事项

见[路线图](../superpowers/plans/2026-10-07-roadmap-phase2-4.md) §4（第三阶段）、§5（第四阶段）、§7（第一阶段搁置项的去向）。另有：
- **设计决定**：设计会话的决定已汇总进 [UI 方案](../design/ui-redesign-brief-2026-10-06.md) §8 第 15～18 条：图标、询价以 Folio 为准（[对照清单](../design/folio-parity-checklist.md)）、数据中心统一、血缘与实例浏览器。两条看似待决的问题已核对出已有决定（原型显示「不适用」；警告色用独立的 `warn`）。设计稿到 v6 为止，不再返工；遗留问题见 [前端开发备忘录](../design/v6/frontend-memo.md)。
- `ci.sh` 不跑 `test_doctor.sh`（P0-J3 可选项）。

## 7. 需要用户处理或决定的事

- ADR-0004 Q1～Q13（第 0 节）。
- `main` 何时更新；PR #1、#2 仍开着。
- 可删除的停用分支：`feat/p0-ci-llm-baseline`、`claude/ui-framework-review-2863c3`（有用内容已移入 `develop`），以及已合入的 `task/*`、`review/*`。删除前先征得用户同意。
- 旧会话曾把 `~/.claude/settings.json` 里的 MiniMax `ANTHROPIC_AUTH_TOKEN` 打印进会话记录（只在本机）。是否轮换由用户决定。
