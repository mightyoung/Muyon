# 任务派发索引

**当前入口：先读[当前状态与默认开启计划](CURRENT-STATUS-2026-10-10.md)，再读[当前交接](HANDOVER-LEADER.md)与[本批集成审查](AIUI-36-39-integration-review.md)。** [较早状态快照 v1](CURRENT-STATUS-2026-10-10-v1.md)固定8deb，只作历史记录；[下一批交付队列 v1](NEXT-DELIVERIES-2026-10-10-v1.md)保留7773时点规划。角色与规则见 [ADR-0001](../adr/0001-leadership-and-scope-freeze.md)。**当前是第二阶段**：范围见 [ADR-0003](../adr/0003-phase2-scope.md)，计划见[第二至第四阶段路线图](../superpowers/plans/2026-10-07-roadmap-phase2-4.md)（第一阶段已于 2026-10-07 退出）。

## 规则

- **派发**：每个任务一个分支，任务说明在该分支的固定位置 `docs/tasks/<编号>.md`。执行者检出分支、阅读说明、只在该分支提交并推送，不合并到 `develop`。
- **执行**：第二阶段起，用户 2026-10-07 指示开发任务由 leader 派生的 **Sonnet 5.5 子代理**执行，leader 只做派发、审查、合入；真机取证仍由本地 engineer 执行；本机实现子代理为 `implementer-sonnet`；Codex 额度已恢复（2026-10-07），可派范围明确的较大实现任务。此前：实现与真机取证都由本地 agent 执行。senior engineer = Opus，engineer = Sonnet，engineer2 = grokbot（云端，无 Flutter；只做静态核对与文档类任务，不派构建与验证），junior = opencode。云端不运行开发任务。
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
| K-1 模型适配层与 Agent 循环设计（ADR-0005） | `task/k-1-model-adapter-adr` | [K-1.md](K-1.md) | Sonnet 子代理 | 第二阶段 | 已合入（[审查](K-1-review.md)）；**ADR-0005 已采纳**（用户 2026-10-07 决定，K-1b 合入） |
| K-2a 模型适配层、流式与原生工具（核心） | `task/k-2a-provider-streaming` | [K-2.md](K-2.md) | Sonnet 子代理 | ADR-0005 已采纳 | 已合入（[审查](K-2a-review.md)，三轮） |
| K-3 预算式循环、批量确认卡、上下文自动压缩 | `task/k-3-budget-loop` | [K-3.md](K-3.md) | Sonnet 子代理 | K-2a 合入 | 已合入（[审查](K-3-review.md)，两轮） |
| K-3b 拆分 `personal_agent.dart`（纯重构） | `task/k-3b-agent-split` | [K-3b.md](K-3b.md) | Sonnet 子代理 | K-3 合入 | 已合入（[审查](K-3b-review.md)） |
| K-2b 测试连接、流式显示与预设（外围） | `task/k-2b-probe-stream-ui` | [K-2.md](K-2.md) | Sonnet 子代理 | K-3b 合入 | 已合入（[审查](K-2b-review.md)，两轮） |
| K-4 执行记录事件化（后端） | `task/k-4-task-events` | [K-4.md](K-4.md) | Sonnet 子代理 | K-3b 合入 | 已合入（[审查](K-4-review.md)，三轮） |
| REG-1 模块契约 v2 与三层插件（ADR-0004） | `task/reg-1-contract-v2-adr` | [REG-1.md](REG-1.md) | Sonnet 子代理 | 评估文档（2026-10-07） | 已合入（[审查](REG-1-review.md)，两轮）；**ADR-0004 已采纳**（用户 2026-10-07，Q1～Q13 全部按建议） |
| FOLIO-BYPASS 宿主模式下 `bypass` 按写入要确认读取 | `task/folio-bypass` | [FOLIO-BYPASS.md](FOLIO-BYPASS.md) | junior | ADR-0004 Q12 | 已合入（[审查](FOLIO-BYPASS-review.md)） |
| REG-2a 外传工具入账（`outbound_tool_requests`，四条通道） | `task/reg-2a-outbound-tool-ledger` | [REG-2a.md](REG-2a.md) | Codex | ADR-0004 已采纳 | 已合入（`b95d6f9`，[审查](REG-2a-review.md)；leader A 2026-10-08 补验） |
| REG-2b 通用模块激活、能力授予、范围单点 | `task/reg-2b-module-host` | [REG-2b.md](REG-2b.md) | implementer-sonnet | ADR-0004 已采纳 | 已合入（`b95d6f9`，PR #5 集成修复，[审查](REG-2b-review.md)） |
| E-1 多步任务评测（现状基线） | `task/e-1-agent-task-eval` | [E-1.md](E-1.md) | Sonnet 子代理 | 第二阶段 | 已合入（[审查](E-1-review.md)，三轮）；真实模型基线待有密钥者运行 |
| UI-1a 设计系统：v6 token、通用组件、自适应尺寸 | `task/ui-1a-design-system` | [UI-1a.md](UI-1a.md) | Codex | — | 已合入（`965d913`，[审查](UI-1a-review.md)） |
| R-1 Android 重跑、E-1 真实基线（UI-0 截图已取消） | `task/r-1-evidence` | [R-1.md](R-1.md) | engineer | 手机连接 | **已派发** |
| JR-1 小清理（ci 跑 test_doctor、按字符截断、无用 tag、注释） | `task/jr-1-cleanups` | [JR-1.md](JR-1.md) | junior | — | 已合入（[审查](JR-1-review.md)） |
| AUTH-1a 授权库、解析器、外传内容审查接口（不接线） | `task/auth-1a-grants` | [AUTH-1a.md](AUTH-1a.md) | Codex | — | 已合入（[审查](AUTH-1a-review.md)） |
| AUTH-1b 授权接线（A、B12、B3、输入来源证明、本机写入自动化） | `task/auth-1b-*` | [AUTH-1b.md](AUTH-1b.md) | Codex（Leader B 派发与审查） | AUTH-1a、REG-2 | A、B12、B3、production 输入与自动化已合入（[审查](AUTH-1b-review.md)）；**C1/C2已发布到develop `00dbd6c`**（[审查](AUTH-1b-model-policy-review.md)，[发布CI成功](https://github.com/mightyoung/Muyon/actions/runs/37792414130)）；[限定Mac例外](VERIFICATION-MEMO.md)不可自动延续；UI/实云模型/实机仍后置 |
| GROK-1 ADR-0004 静态核实与科研导出/导入清单初稿 | `task/grok-1-adr0004-static` | [GROK-1.md](GROK-1.md) | grokbot | — | 已合入（[审查](GROK-1-review.md)）；Q10 清单已确认 |
| GROK-2 能力覆盖清单初稿（科研、原型、询价） | `task/grok-2-coverage-drafts` | [GROK-2.md](GROK-2.md) | grokbot | GROK-1 | 已合入（[审查](GROK-2-review.md)） |
| GROK-3 询价敏感字段划分初稿（Q7，交用户确认） | `task/grok-3-sensitivity-draft` | [GROK-3.md](GROK-3.md) | grokbot | — | 已合入（[审查](GROK-3-review.md)）；Q7 已确认（2026-10-08） |
| GROK-4 UI-1b 盘点：硬编码颜色与询价通用部件 | `task/grok-4-ui-inventory` | [GROK-4.md](GROK-4.md) | grokbot | — | 已合入（[审查](GROK-4-review.md)） |
| UI-0 现状截图与走查 | 历史：曾并入 `task/r-1-evidence` | [UI-0.md](UI-0.md) | engineer | — | **已取消（用户 2026-10-09）**；取代 10-07「R-1 第 3 件」安排，见 [R-1 §3](R-1.md) |
| UI-1 设计系统 | 拆为 UI-1a、UI-1b | [UI-1.md](UI-1.md) | — | — | UI-1a 已合入；UI-1b（迁入询价部件、去硬编码颜色）在 FOLIO-BYPASS、REG-4 之后 |
| B 2.4 原型补齐（冻结前在途） | `feat/b-ui` → `review/B-2.4` | [审查](B-2.4-review.md) | engineer | — | 已合入（三轮；S6 第一阶段搁置） |
| E11 研究对象页（冻结前在途） | `feat/e-support` → `review/E11` | [审查](E11-review.md) | junior | — | 已合入（两轮；S6 第一阶段搁置） |

**历史路线（2026-10-07，已被 2026-10-09 AI 原生方案取代）：** UI 重做的目标稿为 [设计稿 v4](../design/v4/README.md)（2026-10-07 入库，[审阅](../reviews/2026-10-07-design-v4-review.md)）；第一阶段之后按 [UI 重设计方案 §9](../design/ui-redesign-brief-2026-10-06.md) 分换壳与新能力两条线派发，分级授权见 [ADR-0002](../adr/0002-graded-assistant-authorization.md)（已采纳，第一阶段之后实施）。

已停用：过渡集成分支 `feat/p0-ci-llm-baseline` 不再使用，合入目标统一为 `develop`。


## 2026-10-08 AI-native 草案及后续集成记录

原草案标题「待复核，不是已派发」是 10-08 状态；下表已合入行以 10-09 集成记录为准，当前待办见状态快照。

**历史规划状态（2026-10-08 形成该批任务书时）：** [版本化计划](../superpowers/plans/2026-10-08-ai-native-next-batch.md)基于当时已发布00dbd6c；架构稿位于独立docs分支66476e2，保持建议属性。当时该批只形成任务书，尚未发布到develop或开始编码。该历史状态不适用于下表的后续集成结果。

**后续集成与待办：** 下表 AIUI-F1～F6、REG-4a 已合入，REG-4b 源及 ABC 集成也已在 develop 祖先中；这不代表全部验收完成。C4-GUIDE 接入待复核，R-1-AI-UI-final 仍为末次清单草案，原生/实机/Mac及云未覆盖能力继续待验。执行顺序仍为先云端UI/流程验收与修复、再推进下阶段，原生/实机集中末次；模型训练、指南稿和双模型选择不是主线前置。

| 任务 | 拟任务分支 | 目标/依赖 | 状态 |
|---|---|---|---|
| [AIUI-F1（原 UI-3a）](UI-3a.md) | task/ui-3a-semantic-preview | 最小合同+可运行Web预览，已合UI/REG/AUTH | 已合入（见 [10-09 批次审查](../reviews/2026-10-09-leader-b-batch-review.md)） |
| [REG-4a](REG-4a.md) | task/reg-4a-inquiry-adapter | 询价现有能力纯适配，已合REG-2/AUTH | 已合入 `5a243c6`（CI 37883647998） |
| [AIUI-F2（原 UI-4a）](UI-4a.md) | task/ui-4a-dynamic-preview | 确定性渲染/受控云验收，UI-3a及REG-4a联调 | 已合入（见 [10-09 批次审查](../reviews/2026-10-09-leader-b-batch-review.md)） |
| [AIUI-F3（原 UI-4b）](UI-4b.md) | task/ui-4b-planning-harness | 两模式/harness共用planning，UI-3a/4a | 已合入 `655b260` |
| [AIUI-F4（原 UI-3b）](UI-3b.md) | task/ui-3b-workspace-state | 持久编辑/返回，UI-3a/4a | 已合入（见 [10-09 批次审查](../reviews/2026-10-09-leader-b-batch-review.md)） |
| [REG-4b](REG-4b.md) | task/reg-4b-inquiry-import | 既有导入/回执续办，REG-4a+UI-3b/4a | `8025f66c80af9fc22ec7c60ff5f68ccdc1463a96` 及 ABC 集成已在 develop 祖先中，本轮不重复合入 |
| [AIUI-F5（原 UI-2a）](UI-2a.md) | task/ui-2a-reference-navigation | 跨插件对象/文件导航，UI-3b/REG-4b | 已合入（见 [10-09 批次审查](../reviews/2026-10-09-leader-b-batch-review.md)） |
| [AIUI-F6（原 UI-4c）](UI-4c.md) | task/ui-4c-subconversations | 一层子对话/最新引用，UI-2a+UI-4b/3b | 已合入（见 [10-09 批次审查](../reviews/2026-10-09-leader-b-batch-review.md)） |
| [C4-GUIDE](C4-GUIDE.md) | docs/c4-interaction-guides（接口接入另派） | train/dev软指南，UI-3a目录；复用UI-4b可空接口 | 云数据线程起草，接入待复核，不阻塞主线 |
| [R-1-AI-UI-final](R-1-AI-UI-final.md) | 并入现有R-1 | 最终原生/实机/Mac回归 | 末次清单草案，非每片门槛 |

## AI 原生界面（2026-10-09 起，[方案](../design/ai-native-ui-redesign-2026-10-09.md)，取代路线图 UI-2～UI-9）

| 任务 | 分支 | 执行 | 依赖 | 状态 |
|---|---|---|---|---|
| [AIUI-1](AIUI-1.md) 流式界面协议与增量编译器 | `task/aiui-1-streaming-compiler` | Codex | — | 已合入 `276b29146d3eb902380cceac708209cc6ef344c0`；独立复审和完整组合门禁成功，发布 CI 见[集成交接](INTEGRATION-2026-10-09.md)及执行回报 |
| [AIUI-2](AIUI-2.md) 组件库 v1（合并两份目录，补齐约 24 个组件） | `task/aiui-2-component-library` | engineer | — | `4e45836efcb85c86f5c8de57e6b07795aab6166a` Tabs 修复、独立复审及组合 CI 通过，已集成；接口接线另片 |
| [GROK-5](GROK-5.md) 本体业务卡片静态盘点（询价） | `task/grok-5-ontology-cards` | grokbot | — | 已合入（[审查](GROK-5-review.md)） |
| [GROK-6](GROK-6.md) 科研本体盘点（REG-3 前置） | `task/grok-6-research-ontology` | grokbot | — | 已合入（[审查](GROK-6-review.md)）；科研敏感度已确认（2026-10-09） |
| [GROK-7](GROK-7.md) 科研场景交互走查清单（AIUI-7 前置） | `task/grok-7-research-walkthrough` | grokbot | GROK-6 | 已合入 `18ae5127474d6841ad331ca2251076ecca431a81`；独立复审通过，20 目的/首批 7/9 公式；勘误与门禁见[交接](INTEGRATION-2026-10-09.md) |
| [AIUI-3](AIUI-3.md) 本地重算公式 | — | junior | AIUI-1 | F3a `4943c6bb` 纯计算已复审、组合CI通过并集成；运行接线另片 |
| [AIUI-4](AIUI-4.md) 以对话为中心的外壳（4 项导航） | [433436078c6c976cbfafcf2bad2f8575852d3ec6](https://github.com/mightyoung/Muyon/commit/433436078c6c976cbfafcf2bad2f8575852d3ec6) | engineer / 本片云端Codex | AIUI-2 | F4a/F4b已集成；PR38对象双proof修复aaa175获双独审静态机制认可，旧3文件9项fixture已获准迁移至53aacb95，最终433源和b41组合完整CI成功，PR39包含旧片而非新修复；见[集成审查](AIUI-36-39-integration-review.md)，live/完整H3后置 |
| [AIUI-5](AIUI-5.md) 规划提示与模型适配、模板退路 | — | Codex | AIUI-1、2 | F5a `f0203bf` 草案已复审归档；PR19/26已合；PR28 `c9d11a8` 与 PR18 `44bf146` 有界片已独立复审、新组合通过并正常集成，见[复审及遗留](AIUI-5-F5b-F3b-integration-review.md)；完整恢复、F4c等仍在途，见[新队列](NEXT-DELIVERIES-2026-10-10-v1.md) |
| [REG-4c](REG-4c.md) 询价按本体通用的写工具、隐藏 Folio 助手 | `task/reg-4c-general-writes` | Codex | AIUI-1 之后、REG-4b 合入 | PR31 固定源 cb93c740 已独立复审及新组合 CI 通过，用户批准精确 +4 清单例外；[集成复审](REG-4c-review.md)，Mac/真实模型后置 |
| AIUI-6 询价场景（比价、预算小工具、导入审阅工作区） | PR #40 source `650f51a381d6891d16199bf435fe2ef1ed97cd6c` | Codex（compiler/library先接线、卡片与三档持久策略）；Claude Haiku5.5（真实模型/Android/首字） | AIUI-3、4、5；按[默认开启计划](AIUI-DEFAULT-ENABLE-PLAN.md)分工 | 只读切片已纳入本页提交；source/PR/f8组合 CI 成功，详见[集成复审](AIUI-6-REG-3b-integration-review.md)与[当前状态](CURRENT-STATUS-2026-10-10.md)。该快照卡未接助手 shell，不能标完整 AIUI-6 |
| AIUI-7 科研场景 | — | junior / engineer | AIUI-4、5 | 待派 |
| [AIUI-8](AIUI-8-control-center.md) 设置与控制 | [aef127ff501e7c0d141152bec69aa4e9f3719828](https://github.com/mightyoung/Muyon/commit/aef127ff501e7c0d141152bec69aa4e9f3719828) | 云端Codex | AIUI-4 | PR36只读授权/审计控制页，PR39真实设置入口；见[本批审查](AIUI-36-39-integration-review.md)。三档实际策略/持久化/启动恢复为默认开启前置，尚未完成；授权编辑和真机未完成 |
| [AIUI-9](AIUI-9-host-card-slice.md) 本体驱动的业务卡片 | [055a8cbd1e82a63ef632abb013bfc9b2f180172d](https://github.com/mightyoung/Muyon/commit/055a8cbd1e82a63ef632abb013bfc9b2f180172d) | 云端Codex | AIUI-2、5、REG-4c | PR37真实询价快照只读适配/模板；见[本批审查](AIUI-36-39-integration-review.md)。未接对话页面或业务写卡，完整任务未完成 |


## 调度安全补核（2026-10-09）

REG-3a 已合入精确 `48b36375c2ea8ebf3c10281e7f6372a9aa52e5b7`，独立复审、任务及组合 CI 通过；
PR #6 手动基础设施已合入 `107ca439547a01c4ac37e218e059de0a508a0309`，独立审查与 26 离线测试通过；未执行打包。
本轮组合、发布、排除项与父任务可并行待办见[集成交接](INTEGRATION-2026-10-09.md)。

| 任务 | 分支 | 状态 |
|---|---|---|
| [AGENT-DISPATCH-VERIFY-1](AGENT-DISPATCH-VERIFY-1.md) 只读效应边界与读参数恢复独立补核 | `task/agent-dispatch-safety-verification` → `review/AGENT-DISPATCH-VERIFY-1` | 已合入；[独立审查](AGENT-DISPATCH-VERIFY-1-review.md)，任务提交 `5b61b620`，[精确任务CI成功](https://github.com/mightyoung/Muyon/actions/runs/37944860202)；仅边界收紧，无生产越权写入证据 |

## T-3 分片集成（2026-10-10）

首片未注册handler已在develop基线；PR14 [metadata scope机制片](T-3-metadata-scope.md)
最终源 `2f7cdee41a428bd02257de990e2e54242a01ddc1` 经[独立复审](T-3-metadata-scope-review.md)、
Claude/B1复审和[固定源全套CI](https://github.com/mightyoung/Muyon/actions/runs/38018663166)通过后集成。
生产登记仍OFF、完整T-3未完成。历史LAN 400保留为“未重现、原因未明”，无测试豁免；
后续待办与发布CI见[集成交接](INTEGRATION-2026-10-09.md)和执行回报。

## Harness 最小补强（2026-10-10）

| 任务 | 固定源 | 状态 |
| --- | --- | --- |
| [Dream consistency](HARNESS-DREAM-CONSISTENCY.md) / PR15 | `4d86c3433c09142ab4fc5d3bdfab491d769f759a` | 已合cf672；[追补独立复审](HARNESS-DREAM-CONSISTENCY-review.md)无确定阻断，组合CI38019908442成功 |
| [Resume identity](HARNESS-RESUME-IDENTITY.md) / PR16 | `147ad71378af7ae7206b1e2c6ca2d76f98fc0639` | 已合38f2040，组合CI38020976416/发布38021050451成功；合后曾出现manual hold身份P1、审查暂停；PR20已修复并合入，剩余专项验证见[新队列](NEXT-DELIVERIES-2026-10-10-v1.md)，旧[复审更新](HARNESS-RESUME-IDENTITY-review.md)保留历史 |

实际合入账号/时间、PR14发布CI取消与后续成功区分见[交接](INTEGRATION-2026-10-09.md)。
LAN未决与AIUI未来夹具/契约待验另行处理，不自动采纳或合入。

## 本轮质量收口（2026-10-10）

[较早版本化状态与质量清单](CURRENT-STATUS-2026-10-10-v1.md)保留8deb时点记录；基线c265已合lint PR22、恢复PR35、coverage替代PR34、Mac诊断PR33，各发布CI成功，见[当前交接](HANDOVER-LEADER.md)及对应审查。原PR23/30保留；PR18历史整包RED不作通过，已合有界适配片不等于原包全部验收。Mac三例golden、后续专项/性能仍待验。父任务统一review，唯一integrator顺序合develop，本批新组合与发布另验。

用户本轮“制定修复任务并并行开始执行修复”的可定位执行计划：[QUALITY-REPAIR-PLAN-2026-10-10-v1.md](QUALITY-REPAIR-PLAN-2026-10-10-v1.md)。

## 新需求设计任务（2026-10-10）

[输入预测胶囊 UX-PREDICT-1](UX-PREDICT-1.md)与[对话视频 UX-VIDEO-1](UX-VIDEO-1.md)：用户已确认需求、设计待审，尚未启动实现。完整owner/依赖/验收及REG-3b/REG-5/T-3/AIUI-6～9顺序见[版本化交付队列](NEXT-DELIVERIES-2026-10-10-v1.md)；派发不算完成。总体设计同步注明已合基础片、在途接线与未选吉祥物资产，保留旧版本。
