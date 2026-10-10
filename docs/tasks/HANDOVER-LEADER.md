# leader 交接（第二阶段进行中，第 4 次交接：leader A → Leader B）

交接时间：2026-10-09 晚 · 交出：leader A（本机 Claude 会话，额度将用完）· 接收：**Leader B（ChatGPT）**，接任统一派发、审查与合入 · `develop` 基线：本文件所在提交

## 当前入口（2026-10-10，PR36～39集成批）

先读[本批集成审查](AIUI-36-39-integration-review.md)及[总体设计当前切片](../design/ai-native-ui-redesign-2026-10-09.md)。
基线为 `c265eb13564ce8b485297fbdd3f1ddb351256e0d`，lint PR22、恢复PR35、coverage替代PR34
与诊断PR33已合且各发布CI成功。原PR23/30保留，不关闭、不删除，不重复合原包。
本批唯一授权云端integrator按固定PR39组合（包含PR36/38）再PR37的依赖顺序正常合入；
精确来源、新组合/发布CI、远端读回与未完成范围见本批审查及执行回报。
当前独立审查确认引用导航最终撤权与对象版本证明缺口，阻断本批合入；原owner修复后
须重新冻结源、非作者复审及新组合CI，旧源或组合绿色不能替代该结论。
Claude调用入口与本机CLI在当前云环境不可用，非作者云端静态审计不冒称Claude交叉审。
完整AIUI-8/9、live F4c、真实业务插件/模型/真机及Mac golden不因本批而完成。
保护测试的2380元数据碰撞仅有字段级提案，未获范围确认、未改文件。

## 早期入口快照（2026-10-10，保留当时时态）

先读 [状态快照 v1](CURRENT-STATUS-2026-10-10-v1.md) → [任务索引](README.md) →
[集成交接](INTEGRATION-2026-10-09.md) 的最新轮次与 PR16 合后 P1 更新 →
[验证备忘录](VERIFICATION-MEMO.md) → ADR-0001 后续记录、ADR-0003 的 10-09 修订及已采纳 AI 原生方案。
当前仅父任务统一 review、唯一 integrator 合 develop；本轮执行分支只提交、推送草稿 PR。

AIUI-1/2、GROK-7、REG-3a 已集成，不能再按下面 A～C 排队审合。
PR16 已合但 manual hold 重复 resume 身份 P1 尚未关闭；独立修复进行中，CI 成功不作无阻断结论。
UI-0 已取消；当前为助手/任务/资料/设置四导航，v6 只保留视觉层。
REG-3a 说明已存在且有界片已合，REG-3b 等剩余能力仍待办；JR-1 已让 CI 跑 doctor。
证据与替代提交见快照；旧决定全部保留供追溯。

## 历史交接正文（2026-10-09 晚，以下时态仅指当时）

> A～D、§2～3、§6～7 的待审/未写/待决条目不是当前队列；其现行状态由上方快照和最新集成交接取代。
> §1 的工作方式仍需结合用户本轮授权；§4 退出标准与 §5 真机审查要求仍须遵守，不因历史标注取消。

**先读（按顺序）：**
1. [ADR-0001](../adr/0001-leadership-and-scope-freeze.md) 末尾「后续记录」：全部用户决定的时间线，最新几条是 10-08、10-09 的。
2. [AI 原生界面方案](../design/ai-native-ui-redesign-2026-10-09.md)（**已采纳**）与 [AIUI 流式界面契约 v1](../design/aiui-stream-contract.md)（AIUI-1 的验收依据）。
3. [ADR-0003](../adr/0003-phase2-scope.md)（含 10-09 修订：界面线改为 AIUI）、[ADR-0002](../adr/0002-graded-assistant-authorization.md)、[ADR-0004](../adr/0004-module-contract-v2.md)（§12.1 注记含 Q7、Q10、科研敏感度）、[ADR-0005](../adr/0005-model-adapter-and-agent-loop.md)。
4. [产品与架构总览](../superpowers/specs/2026-10-04-muspace-product-and-architecture-overview.md) 开头的「现行决定」表。
5. [任务索引 README.md](README.md) 末尾「AI 原生界面」一节、[审查清单 REVIEW.md](REVIEW.md)。

## A. 历史：交接时待审的交付（2026-10-09 晚）

| 任务 | 分支 / 提交 | 执行 | 审查要点 |
|---|---|---|---|
| **AIUI-1** 流式编译器 | `task/aiui-1-streaming-compiler` @ `276b291`（`5cbc4cf` + 修复） | Codex | 逐条对照[契约](../design/aiui-stream-contract.md)：§1 路由和 `expectedDraftRevision` 由宿主决定；§4 单节点规则是从 `validation.dart` **抽取复用**的、最终计划对完整候选计划整树校验、差分测试含坏节点；§6 中断、重复 `end`、超限；§7 四个变异各自被指定测试检出。安全相关，按额度规则可开一个审查子代理，或交叉派给非作者成员 |
| **AIUI-2** 组件库 v1 | `task/aiui-2-component-library` @ `0183918` | engineer | 说明要求约 24 个组件，回报写的是 21 个，要核对少了哪些；两份目录是否真的合并成一份；四种状态、文字等价物、48 点击区、200% 字号；Chart 没有引第三方库；颜色只用 token |
| **GROK-7** 科研走查清单 | `task/grok-7-research-walkthrough` @ `18ae512` | grokbot | 抽查 `文件:行` 引用；首批 5～8 个目的是否合理；公式表交给 AIUI-3 |

审查后按 REVIEW.md 写 `docs/tasks/<编号>-review.md`，合入 `develop`，更新索引。

## B. 在途与排队

| 成员 | 当前 | 之后 |
|---|---|---|
| Codex | AIUI-1 已交付待审 | **REG-4c**（[说明已就绪](REG-4c.md)，前提是 REG-4b 合入）→ **REG-3**（说明**还没写**，见 C-1） |
| engineer | AIUI-2 已交付待审；R-1 还剩 Android 重跑（UI-0 已取消） | AIUI-4 外壳（AIUI-2 合入后） |
| junior | 用户已把 junior 的工作改派给 engineer | 视用户安排 |
| grokbot | GROK-7 已交付待审 | 可派静态任务 |
| REG-4b 询价导入续办 | 部分合入；`task/reg-4b-inquiry-import-pipeline` @ `8025f66` | 收尾与审查 → 合入后才能开 REG-4c |

## C. 历史：当时的下一步（2026-10-09 晚）
1. **写 REG-3 任务说明**（科研迁 v2）：依据 [GROK-6 本体盘点](../reviews/2026-10-09-research-ontology-draft.md) §5 与 [GROK-2 科研覆盖清单](../reviews/coverage-drafts/research.md)。要点：
   - 科研没有统一的 save/delete/restore，也没有统一校验，多数对象没有版本号，所以**不能照搬 REG-4c 的通用写工具**，要先补版本号和校验，或者做具名工具（约 20 个，命名见 GROK-6 §5.2）；
   - v2 模块的知识库、模型能力需要先补受限接口（REG-2b 审查第 1 条偏离）；
   - Q10：只开放报告和主张草稿的本机导出；
   - 敏感度：研究内容都是 `none`。
2. AIUI-1 合入后派 **AIUI-3** 本地重算公式（公式来源：GROK-7 的公式表、询价的含税换算与毛利）。
3. AIUI-1、2 都合入后派 **AIUI-5** 规划提示与模型适配（接 UI-4b harness，加模板退路）。
4. AIUI-2 合入后派 **AIUI-4** 外壳（engineer）。
5. REG-4c 合入后派 **AIUI-9** 本体业务卡片（询价先做）。

## D. 待处理的遗留
- 10-09 批次审查第 3 项：8 个提交合入时没有审查记录，其中 `cc05fa3`（读参数恢复，改了 `agent_dispatch.dart`）属于安全路径，**应补审**（[审查记录](../reviews/2026-10-09-leader-b-batch-review.md)）。
- Mac 上 46 例询价截图失败，根因不明（[验证备忘录](VERIFICATION-MEMO.md)）；`verify.sh` 删掉豁免后本机门禁一直是红的，合并暂时只看 Linux CI。
- 验收账本还没有 AIUI 的验收项，等 AIUI 第一批合入时补。
- 远端有多个已合入的 `task/auth-1b-*` 等停用分支，清理前要征得用户同意。

## 0. 此前的在途记录（leader A 时期，供参考）

- **2026-10-09**：用户决定全面采用 AI 原生界面（[方案](../design/ai-native-ui-redesign-2026-10-09.md)，ADR-0003 已修订），由 leader A 统一派发。已派：AIUI-1（Codex，之后 REG-4c）、AIUI-2（engineer，用户改派；R-1 只剩 Android 重跑，UI-0 已取消）、GROK-5 已合入、GROK-6（grokbot）。下一批：REG-4c（Codex，REG-4b 完成后）、AIUI-3、AIUI-4（engineer 完成 R-1 后）。

- **2026-10-08 更新**：Leader B（ChatGPT，用户指定的 B 角）合入了 REG-2a、REG-2b、UI-1a，以及 AUTH-1b 的 A、B12、B3、输入来源证明与本机写入自动化；leader A 合入 JR-1。leader A 的审查见 [2026-10-08-leader-b-batch-review.md](../reviews/2026-10-08-leader-b-batch-review.md)。AUTH-1b C1/C2 的集成检查点 `ffe6be31` 已发布到 develop `00dbd6c`，[精确发布CI成功](https://github.com/mightyoung/Muyon/actions/runs/37792414130)，保留 Mac 全量失败结论；[验证备忘录](VERIFICATION-MEMO.md)登记后续截图回归要求，例外不可自动延续。[下一批计划](../superpowers/plans/2026-10-08-ai-native-next-batch.md)已形成待复核任务：首片UI-3a可运行Web预览，REG-4a纯适配并行，UI-4a云验收随后；尚未派发/实施。UI/profile入口、实云模型和实机仍后置。进行中：R-1 剩余两件。下一步按路线图 §3.1 派 REG-3、REG-4、T-3、S-1。

- ADR-0004 已采纳（用户 2026-10-07，Q1～Q13 全部按建议）。
- **已合入**：FOLIO-BYPASS（2026-10-07）、AUTH-1a（授权库，未接线）。
- 已派发：**REG-2a**（Codex，外传工具入账，迁移 9）、**REG-2b**（`implementer-sonnet`，模块激活与范围单点，迁移 10）。三项都审查后再合入；REG-2a 和 REG-2b 后合入的一方负责重新编号迁移。
- REG-2 两半都合入后，按路线图 §3.1 派 REG-3、REG-4、T-3。Q10 清单已确认（ADR-0004 §12.1 注记），REG-3 可以直接派。

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
| **REG-3、REG-4、T-3** | REG-2a、REG-2b 都合入（Q10 已确认） | 子代理 / Codex | `-high` |
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
- 历史遗留说明：`ci.sh` 不跑 `test_doctor.sh`（P0-J3 可选项）。**已由 JR-1 取代**：当前 `scripts/ci.sh` 已运行 doctor；见 [JR-1 审查](JR-1-review.md)及状态快照。

## 7. 需要用户处理或决定的事

- ADR-0004 Q1～Q13（第 0 节）。
- `main` 何时更新。PR #1、#2 已于 2026-10-06 上午合并，`main` 停在 `cc7c8d1`，之后没有再动过。
- 可删除的停用分支：`feat/p0-ci-llm-baseline`、`claude/ui-framework-review-2863c3`（有用内容已移入 `develop`），以及已合入的 `task/*`、`review/*`。删除前先征得用户同意。
- 旧会话曾把 `~/.claude/settings.json` 里的 MiniMax `ANTHROPIC_AUTH_TOKEN` 打印进会话记录（只在本机）。是否轮换由用户决定。
