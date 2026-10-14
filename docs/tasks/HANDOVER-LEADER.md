> **当前职责与设计入口 — 2026-10-14 北京时间**
> 用户已将全部派发、任务说明、审查组织、登记、独立验证和唯一 develop 合入职责交给 **Leader B**，Leader A 暂停；以下旧交接正文按其日期和固定SHA保留为历史。最新决定与适用边界见 [ADR0001 新接任记录](../adr/0001-leadership-and-scope-freeze.md#2026-10-14leader-b-全职责接任与-v132-改造开工)。
> 本次改造规范入口为 [v1.3.2 两册与迁移追踪](../design/redesign-v1.3.2-20261014/README.md)，固定设计SHA `58fe9c62612d74a973614c41677e62a54332e6d6`；实际开工与writer登记见 [M01/A00](REDESIGN-M01-20261014.md)。产品基线 `01e56cc2d729dab70e1b1def05c3aa93b28f421a` 的旧功能继续保留，52项新架构验收仍未执行。M03尚未冻结；不把合同草案、文档CI或派发当成产品完成，不自动扩真实数据/模型/设备成本或发布范围。

# 第 6 次交接：leader A → Leader B（2026-10-11 深夜）

用户决定：Leader B 接替 leader A 的全部工作（派发、写任务说明、组织 ChatGPT 审查、登记回报），加上原有的集成、独立验证与合入。ADR 分工条目见 `docs/adr/0001-leadership-and-scope-freeze.md` 2026-10-11 晚两条（已在 develop）。本节是交接时的快照，develop = `330020c0`。

> 集成复核补注（2026-10-11）：下文第 6 次交接保留交接当时状态。LE-01 `202e44af` 已独立确认两个阻断项，待补修，不能按「宜先合」直接放行，见[独立最小复现](https://github.com/mightyoung/Muyon/blob/abf9f9e1ff43c4d3e01dc84c9c57d05249071c4b/docs/reviews/2026-10-11-le01-independent-blocking-review.md)（在独立审查分支，尚未进入 develop）。WC-D-F 已正式交付并在独立组合复验；合入证据以本批报告为准。Mac 失败归因是作者报告，本机 Linux 复验与固定 SHA CI 分别记录，不能据此直接豁免。PR #50 的原 base 仍为作者任务分支，保持原状态，不以改 base/自动关单替代验证。

> 后续集成核验：WC-D-F已正常合入develop `8b01223918e45bc0c3340ab1e3c5e13e45fe9502`，合后CI38154862759 success。LE01补修bf63985a766f39912a53661bc63e37caa430ab7b原两I已独立闭合，完整八套与旧floor/新分母复核见[最终独验](LE01-freeze-independent-combination-review-20261011.md)；本次按已授权正常合入，合后终态另核。前文旧202e44af阻断快照与完整历史保留。OC21两位前作者均停止、源dd519fc20c072188cc0de4a7a1bfdfe37e8c0b63仅任务说明；零测试探针不算验收，现由既有可用SDK的唯一集成执行会话在本批闭环后接手Linux有效基线/纯测试抽取，精确六文件并排除OC18，不重复派发。

## 工作方式（沿用）
- 每个任务一份 `docs/tasks/<编号>.md`，推到独立 `task/<编号>-...` 分支；只含文档的分支推完立即取消其 CI（cancel-in-progress 会占 runner）。
- 转交给成员的消息格式：一段可直接转发的文字，写明分支、基线 SHA、任务说明路径、测试先行、必须做的变异、固定行数回报（实现类 6 行，opencode 5 行）。
- 成员回报后：核对提交范围（`git diff --stat`）、RED 是否真实、变异是否抓到、失败是否分类（develop 基线也失败 / 负载相关单独重跑通过 / 本次导致），再登记、交集成。leader A 不再本机复跑；检查写成任务派 ChatGPT（在线 3 并行，只读审查 / 设计）或 Codex。
- 用户回复「按推荐」时，把决定写进 ADR-0001 末尾并在设计文档头标注。
- 成员能力：grok-build（Grok 4.7，可本地构建测试实现）、Sonnet = senior engineer 会话（实现）、Haiku = junior engineer 会话（实现，做事细，回报可靠）、Codex（2 并行）、opencode（deepseek flash，只做小的机械测试，必须给停止条件）、ChatGPT（3 并行，只读）、grokbot 额度用完**不要派**。

## 在途任务
| 成员 | 任务 | 分支 / 基线 | 状态 |
|---|---|---|---|
| grok-build | SN-6 审批 widget 测试挂在 waitingConfirmation 的根因与修复 | `task/sn-6-approval-widget-hang`，基线 PR #51 `d5cd97a1` | 未见提交 |
| Sonnet | LE-05 本机导出意图与两阶段审批绑定 | `task/le-05-local-export-intent`，基线 LE-01 `202e44af` | 中间进展已到（26 测试、三处变异抓到、RED `9df60d0d` 未推）；已要求补两测：模型参数带 destination / `local-export:save` 被拒零执行；从派发入口走一次，`authorizationRequest`/`approveWithGrant` 抛错转为拒绝或人工确认、任务不崩 |
| Codex ① | REG-3e-a 科研手工运行两个写工具 | `task/reg-3e-manual-runs`，基线原 PR #49 head（已在 develop） | 进行中 |
| Codex ② | LE-02 科研报告内容准备器 | `task/le-02-report-preparer`，基线 LE-01 | 进行中 |
| Haiku | LE-04 宿主本机导出生成与清理状态机 | `task/le-04-export-staging`，基线 LE-01 | 刚派 |
| opencode | 空闲 | — | 下一件：见「排队」第 1 条 |
| ChatGPT | 空闲 | — | 等 CR-18 |

## 待集成（已登记、未进 develop）
- **LE-01** `task/le-01-local-export-contract` @ `202e44af`（Sonnet；module_api 268 全过；新增 `local_export.dart` 会让 module_api 覆盖率门禁分母变化，需复核基线）。LE-02/04/05 都基于它，宜先合。
- **WC-D-F** `task/wc-d-fixes` @ `7ad4c81e`（Haiku；#50 合入后补修，修 CR-16 I-1/I-2；scope 检查按真实存储格式——`objects` 每项是 4 元数组的 JSON 字符串，任务说明原写法有误，以实现为准）。合入后可关 PR #50。
- **审查文档** `task/cr-15-17-chatgpt` @ `7de86d28`：CR-15（PR #49 可合入）、CR-16（WC-D/#50 需修改 → WC-D-F）、CR-17 设计 `docs/design/research-local-export-facade-2026-10-11.md`、CR-18 任务说明。
- **CR-12 报告与 SN-4 补充** `task/sn-5-aiui-handover-fixes` @ `b6e4a421`（只含文档；SN-5 实际由 PR #52 交付，Sonnet 那边 SN-5 已停、本地改动未推）。

## AIUI 放行链（主线）
PR42 交接点 `b6e1856` + SN-4 `6d47da8` / PR #51 `d5cd97a` + SN-5 PR #52 `11225c4` + SN-6（未交）。SN-6 交回后：整链与最新 develop 组合 → 终态 CI → 派 **CR-18**（`task/cr-15-17-chatgpt` 的 `docs/tasks/CR-18.md`，填组合 SHA 与 CI）→ 统一审查通过后合入。遗留待 CR-18 判断：无视图取消且在范围写入前已超时，要等视图之后的 reconcileRead 才清退路（grok-build 报告）。PR #42、#51、#52 合入后关闭；#30 为旧 AIUI-5 F5c，需判断是否已被取代。AIUI 合入后才能做 CR-14 的 CR14-02～09（设计在 `docs/design/cr14-f1-f2-implementation-2026-10-11.md`）、Android 冒烟（Haiku，构建完等用户连手机，测完卸载）、AIUI 默认开启。

## 排队（已有设计或说明，等人）
1. **opencode：测试夹具整理**——OC-15～OC-20 已全部进 develop，可派：把 `apps/muyon/test/oc15..oc20_*` 与 `reg3c_outline_tools_test.dart` 里重复的科研建库 / 建链 / 确认辅助代码抽到 `test/support/` 共用，只动测试，全部原断言不变。
2. **LE-03** 主张草稿准备器：排在 Codex 的 LE-02 之后（都改 `exchange.dart`）。按 ADR CR-17 第 3 条：以 research-skill v6.8 为准，资格是当前日志 `schema_version: 2` 的项目，只写挂论文的 `claims` 行，不导出 `assertions`。
3. **LE-06～LE-14**：依赖见 CR-17 设计第 6 节（LE-06 账本依赖 01、05；LE-07 确认卡；LE-08 系统选择交接；LE-09 macOS；LE-10/11 Android；LE-12/13 接通两个工具；LE-14 平台验收）。
4. **WC-B** 询价候选准备抽取（CR-11 片 B）：还没写任务说明；OC-14 已锁住 update 值语义（空串与 null 一样清空、false 被类型校验拒绝）。
5. CR-13 延期：N-2 删除确认展示级联清单；N-3 回执版本化保存逐项 ChangeOp（OC-20 已锁现状）。
6. 科研导出（REG-3e-b）要等 LE 全链。

OIUI调研新增三项待设计队列见 [OIUI-RESEARCH-QUEUE](OIUI-RESEARCH-QUEUE.md)，全部依赖SN6/CR18整链放行，完整方案待交。

## 已知环境情况
- Mac 本地全量常见失败：inquiry_module 16 项（develop 上同样失败，多为截图差异）、`human_new_project_preview_commit_and_resume`、列表预览不稳定用例；均以 Linux CI 为准。机器负载高时 formula、encrypted-import 等会超时，单独重跑可过。
- flutter pub get 会改 xcconfig / Podfile / analysis_options，永不提交。
- 不读不打印 `.env`；真实模型评测不在 verify/ci 里导出 `MUYON_EVAL_REAL`；原始验证日志不进仓库。

# leader 交接（第二阶段进行中，第 5 次交接：Leader B → leader A）

**2026-10-10 晚：Leader B 额度用完，经用户同意由 leader A 接手合入**（派发、审查、合入 develop）。合入流程：已审分支先在 `review/leader-a-batch-*` 组合分支上合到最新 develop，组合 CI 成功后快进 develop。此后的待办见[当前状态](CURRENT-STATUS-2026-10-10.md)与下方「当前入口」；第 4 次交接（leader A → Leader B）的正文保留为历史。

交接时间：2026-10-09 晚 · 交出：leader A（本机 Claude 会话，额度将用完）· 接收：**Leader B（ChatGPT）**，接任统一派发、审查与合入 · `develop` 基线：本文件所在提交

## 当前入口（2026-10-10）

**先读[当前状态与默认开启计划](CURRENT-STATUS-2026-10-10.md)**，再读[本批集成审查](AIUI-36-39-integration-review.md)、[Leader A 状态审查](../reviews/2026-10-10-leader-a-status-review.md)及[总体设计当前切片](../design/ai-native-ui-redesign-2026-10-09.md)。早期[状态快照 v1](CURRENT-STATUS-2026-10-10-v1.md)固定在8deb，仅供历史追溯；本文 A–D 交接任务同为历史原文，现行状态以新状态页和精确提交/CI证据为准。
本页所在集成提交追加 AIUI-6 / REG-3b，代码检查点 f8c50517 的全8套组合CI成功；完整源SHA、独审、覆盖和有限边界见[本批新增审查](AIUI-6-REG-3b-integration-review.md)。默认仍关闭，下一接线/持久化/烟测/开关候选的条件目标见[默认开启计划](AIUI-DEFAULT-ENABLE-PLAN.md)。原PR36–39证据继续保留。
本批原基线为 `c265eb13564ce8b485297fbdd3f1ddb351256e0d`，PR22/35/34/33已各自合入；PR36/39与PR37固定组合、PR38修复及PR39/PR37最终合入结果见[集成审查](AIUI-36-39-integration-review.md)，代码组合为 `a42e4e5516b7b7ae1a5175569d8511013738ff79`，当前 develop 已前进至 a68。PR23、PR4现已只读核对为closed/unmerged（见[PR23](https://github.com/mightyoung/Muyon/pull/23)、[PR4](https://github.com/mightyoung/Muyon/pull/4)）；PR30保留其历史记录，本交接不操作关闭/删除。
原独审确认导航最终撤权/对象改版缺口；原owner的aaa175已获双非作者静态机制复审。
旧3文件9项正向fixture已获用户明确范围批准并按公开v2迁移，夹具源53aacb95、仅自有分析修正最终433436；
2380/artifact/gate排除，Research-origin迁Inquiry不作科研验收。代码组合`a42e4e5`已集成；成功的[38055487124](https://github.com/mightyoung/Muyon/actions/runs/38055487124)
是文档head `b41e192` 的review组合CI，不标作a68发布CI。非作者all8hash/DA复算通过，旧cec2绿色不替代修复验证；
a68发布run `38056891075` 已精确SUCCESS，见[当前状态](CURRENT-STATUS-2026-10-10.md)。40/41另批 f8，不混原 b41 组合。
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

## A. 冻结历史：交接时待审的交付（2026-10-09 晚；下文状态不代表当前排队）

| 任务 | 分支 / 提交 | 执行 | 审查要点 |
|---|---|---|---|
| **AIUI-1** 流式编译器 | `task/aiui-1-streaming-compiler` @ `276b291`（`5cbc4cf` + 修复） | Codex | 逐条对照[契约](../design/aiui-stream-contract.md)：§1 路由和 `expectedDraftRevision` 由宿主决定；§4 单节点规则是从 `validation.dart` **抽取复用**的、最终计划对完整候选计划整树校验、差分测试含坏节点；§6 中断、重复 `end`、超限；§7 四个变异各自被指定测试检出。安全相关，按额度规则可开一个审查子代理，或交叉派给非作者成员 |
| **AIUI-2** 组件库 v1 | `task/aiui-2-component-library` @ `0183918` | engineer | 说明要求约 24 个组件，回报写的是 21 个，要核对少了哪些；两份目录是否真的合并成一份；四种状态、文字等价物、48 点击区、200% 字号；Chart 没有引第三方库；颜色只用 token |
| **GROK-7** 科研走查清单 | `task/grok-7-research-walkthrough` @ `18ae512` | grokbot | 抽查 `文件:行` 引用；首批 5～8 个目的是否合理；公式表交给 AIUI-3 |

审查后按 REVIEW.md 写 `docs/tasks/<编号>-review.md`，合入 `develop`，更新索引。

## B. 冻结历史：在途与排队（2026-10-09 晚；下文状态不代表当前排队）

| 成员 | 当前 | 之后 |
|---|---|---|
| Codex | AIUI-1 已交付待审 | **REG-4c**（[说明已就绪](REG-4c.md)，前提是 REG-4b 合入）→ **REG-3**（说明**还没写**，见 C-1） |
| engineer | AIUI-2 已交付待审；R-1 还剩 Android 重跑（UI-0 已取消） | AIUI-4 外壳（AIUI-2 合入后） |
| junior | 用户已把 junior 的工作改派给 engineer | 视用户安排 |
| grokbot | GROK-7 已交付待审 | 可派静态任务 |
| REG-4b 询价导入续办 | 部分合入；`task/reg-4b-inquiry-import-pipeline` @ `8025f66` | 收尾与审查 → 合入后才能开 REG-4c |

## C. 冻结历史：当时的下一步（2026-10-09 晚）
1. **写 REG-3 任务说明**（科研迁 v2）：依据 [GROK-6 本体盘点](../reviews/2026-10-09-research-ontology-draft.md) §5 与 [GROK-2 科研覆盖清单](../reviews/coverage-drafts/research.md)。要点：
   - 科研没有统一的 save/delete/restore，也没有统一校验，多数对象没有版本号，所以**不能照搬 REG-4c 的通用写工具**，要先补版本号和校验，或者做具名工具（约 20 个，命名见 GROK-6 §5.2）；
   - v2 模块的知识库、模型能力需要先补受限接口（REG-2b 审查第 1 条偏离）；
   - Q10：只开放报告和主张草稿的本机导出；
   - 敏感度：研究内容都是 `none`。
2. AIUI-1 合入后派 **AIUI-3** 本地重算公式（公式来源：GROK-7 的公式表、询价的含税换算与毛利）。
3. AIUI-1、2 都合入后派 **AIUI-5** 规划提示与模型适配（接 UI-4b harness，加模板退路）。
4. AIUI-2 合入后派 **AIUI-4** 外壳（engineer）。
5. REG-4c 合入后派 **AIUI-9** 本体业务卡片（询价先做）。

## D. 冻结历史：待处理的遗留（2026-10-09 晚）
- 10-09 批次审查第 3 项：8 个提交合入时没有审查记录，其中 `cc05fa3`（读参数恢复，改了 `agent_dispatch.dart`）属于安全路径，**应补审**（[审查记录](../reviews/2026-10-09-leader-b-batch-review.md)）。
- Mac 上 46 例询价截图失败，根因不明（[验证备忘录](VERIFICATION-MEMO.md)）；`verify.sh` 删掉豁免后本机门禁一直是红的，合并暂时只看 Linux CI。
- 验收账本还没有 AIUI 的验收项，等 AIUI 第一批合入时补。
- 远端有多个已合入的 `task/auth-1b-*` 等停用分支，清理前要征得用户同意。

本节 D 的第 3 条“验收账本还没有 AIUI 验收项”是当时时点记录；该项已由[AIUI 第二阶段现状补记](../implementation/muyon-acceptance-ledger.md)同步更新。当前未完成项及精确依据见[当前状态与默认开启计划](CURRENT-STATUS-2026-10-10.md)。

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
