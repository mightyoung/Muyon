# 科研场景交互走查清单（GROK-7）

日期：2026-10-09 · 任务：[GROK-7](../tasks/GROK-7.md) · 执行：工程师2号（grokbot）· 分支：`task/grok-7-research-walkthrough`
方法：只读科研页面（`packages/research_module/lib/src/app/`、`reader/`、`relations/`）、Store / OutlineStore / Exchange / CardStore、[GROK-6 本体初稿](2026-10-09-research-ontology-draft.md)、[AI 原生界面方案](../design/ai-native-ui-redesign-2026-10-09.md) §4 / §5.2、[AIUI 流式契约](../design/aiui-stream-contract.md)；**未**改代码、**未**运行 Flutter。
给谁用：AIUI-7（科研场景）、AIUI-5（规划提示）、AIUI-3（公式登记）。

科研敏感度已确认（ADR-0004 §12.1）：研究内容与文献作者均为 `none`；卡片 `author` 仅机器标记时为 `none`。外传远程模型仍按 ADR-0002 逐次询问。

导航页签（`workbench_app.dart:89`）：概览 · 文库与证据 · 研究任务 · 运行结果 · 论文写作 · 研究关系。

约定：
- **回答形态**按方案 §4.2：文字 / 文字加补充卡 / 交互小工具 / 工作区。
- **组件名**按方案 §5.2。
- **业务工具**命名对齐 GROK-6 §5.2；宿主**尚未**静态确认已有 `research.*` 写工具注册（GROK-6 §6.1）——下文「现在能不能做」以 Store API 为准，工具层一律记「待 REG-3 登记」。
- **动作路由**：本地（改界面状态）/ 业务（写入或外传，需确认卡）/ 语义（回模型）。
- 数值绑定只能来自快照事实或登记公式（AIUI 契约 §5）；模型不得输出裸数字作数据。

---

## 0. 汇总

| 项 | 数 / 结论 |
|---|---|
| 常见目的 | **20**（§1） |
| AIUI-7 首批建议 | **7**（§3）：P1–P7 |
| 交给 AIUI-3 的公式 | **8**（§4） |
| 必须留原页 | **9** 类操作（§2） |
| Q10 本机开放导出 | `exportReport` / `exportClaimDrafts`（外传本机文件，仍需确认） |
| Q10 deferred | 导入研究/任务/结果、导出任务/结果/技能实验包、LAN 设备交换 |

---

## 1. 常见目的清单

每个目的格式：原话 → 形态 → 组件 → 事实 → 公式 → 动作 → 可行性。

### P1. 看清当前研究目标与下一步

- **原话**：「我们现在在研究什么？下一步该干什么？」
- **形态**：文字加补充卡 —— 结论短句 + 项目目标卡；不宜整页工作区。
- **组件**：Prose、Heading、KeyValue、ObjectChip、Metric、Checklist（下一步建议）
- **事实**：
  - `project.title` / `question` / `next_step` / `layout`（`models.dart:1–17`；读 `store.projects` `:214`）
  - 按 kind 计数：`entries(projectId)`（`:245`）经 UI `countKind`（`workbench_app.dart:637`）
  - `tasks(projectId).length`（`:260`）
- **公式**：`entry_count_by_kind`；`task_count`（见 §4）
- **动作**：
  - 本地：展开/收起计数明细
  - 语义：「帮我改下一步表述」→ 再出编辑卡
  - 业务：无（本目的只读）
- **可行性**：只读事实已有。写工具 `research.update_project` 待 REG-3。可做首批只读回答。

### P2. 改研究问题或下一步

- **原话**：「把研究问题改成……；下一步写成先复现实验 A。」
- **形态**：文字加补充卡（编辑卡 + ConfirmCard）
- **组件**：Form、Choice（可选模板）、ConfirmCard、ObjectChip、WarnBanner（若 layout 为 skill 只读提示）
- **事实**：当前 `project.question` / `next_step`（`saveProject` 写入 `store.dart:387–395`）
- **公式**：无
- **动作**：
  - 业务 · 写入：`research.update_project` → `saveProject`（不改 title/layout/skill_root）
  - 本地：表单草稿
- **可行性**：Store 已有；缺 REG-3 本体与工具登记。**首批建议**。

### P3. 这篇论文支持我的哪个主张

- **原话**：「这篇论文支持我的哪个主张？和哪些主张冲突？」
- **形态**：文字加补充卡 —— 一文一句结论 + 主张 ObjectChip + SourceCard；复杂图给「打开研究关系」工作区入口。
- **组件**：Prose、ObjectChip、SourceCard、Table、Disclosure、WarnBanner（未绑定文档时）
- **事实**：
  - `entry` kind=`papers`/`claims`：`id,title,data`（`models.dart:20–29`；`entries` `:245`）
  - claims 判断键：`supports_statement` 等（`research_kinds.dart:20–26`）
  - 关系边：claims→paper、claims→conflicts（`relations_page.dart:47–55` 静态边规则）
  - `paper_bindings`（`store.bindings` `:317`）文档↔论文
- **公式**：`claim_link_count`（某 paper 被多少 claims 引用；输入为事实边列表）
- **动作**：本地筛选；语义「展开冲突主张」；业务无（只读）。打开关系图 → 工作区入口（非业务写）
- **可行性**：只读可做；边解析逻辑在 RelationsPage，快照需宿主投影边表（REG-3 / AIUI-7 约定）。**首批建议（只读）**。

### P4. 打开这篇文献本地正文

- **原话**：「打开 Smith 2024 那篇 PDF。」
- **形态**：文字加补充卡（文件元数据）+ **工作区**入口打开阅读器
- **组件**：FileCard、ObjectChip、SourceCard；工作区挂 `ReaderPage`
- **事实**：`document.relative_path` / `absolutePath` / `sha256`（`models.dart:32–43`；`documents` `:230`）；绑定 `paper_bindings`（`:317`）
- **公式**：无
- **动作**：本地「打开工作区」；业务无
- **可行性**：打开阅读器是宿主导航，非写工具。对话可出入口卡。划词见 §2。

### P5. 确认歧义的论文绑定

- **原话**：「这篇 PDF 到底对应哪条 papers 记录？帮我确认。」
- **形态**：交互小工具（候选对比）+ ConfirmCard
- **组件**：CompareTable 或 Table、Choice、ConfirmCard、WarnBanner（`hash_ok=false`）
- **事实**：`PaperBinding` 字段（`models.dart:103–114`；`bindings` `:317`）；候选 `ambiguous=1`
- **公式**：无
- **动作**：业务 · 写入：`research.confirm_binding` → `confirmBinding` / `applyBindingChoice`（`store.dart:345–368`，删竞争 ambiguous）
- **可行性**：Store 已有；待 REG-3 工具。**首批建议**。

### P6. 把划词摘录记成精读笔记（对话侧承接）

- **原话**：「把刚才选中的这段记成证据，证据性质是论文结论。」
- **形态**：文字加补充卡（新建笔记 Form）；**locator/quote 宜来自阅读器会话**，否则降级为「请在阅读器划词后继续」
- **组件**：Form、Choice（`evidenceKinds`）、ConfirmCard、SourceCard
- **事实**：目标 `document_id`；可选预填 `page_number`/`quoted_text`（`saveNote` `store.dart:396–404`）
- **公式**：无
- **动作**：业务 · 写入：`research.create_note` → `saveNote`（仅 INSERT）
- **可行性**：Store 已有；无 update/delete。划词本身留阅读器（§2）。对话可在已有 locator 时提交。**首批可做「有 locator 的新建」**。

### P7. 把笔记挂到某条主张/条目

- **原话**：「这条精读笔记是针对主张 C3 的。」
- **形态**：文字加补充卡（关联卡）
- **组件**：ObjectChip、Choice/对象选择、ConfirmCard
- **事实**：`note.id`、`note.entry_id`；同项目 `entry`（`setNoteEntry` `:373–383`）
- **公式**：无
- **动作**：业务 · 写入：`research.set_note_entry` → `setNoteEntry`
- **可行性**：Store 已有。**首批建议**。

### P8. 从实验计划生成研究任务

- **原话**：「把这个 experiments 计划生成一份任务规格。」
- **形态**：文字加补充卡（预览 spec 摘要 + ConfirmCard）
- **组件**：KeyValue、Disclosure、ConfirmCard、ObjectChip
- **事实**：`entry` kind=`experiments` 的 `data`；`taskFromExperiment`（`skill_bridge.dart:27–56`）只读 entry 生成草稿
- **公式**：无
- **动作**：业务 · 写入：生成后 `research.create_task` → `saveTask`（`store.dart:437`）；UI 现路径 `workbench_app.dart:1397`
- **可行性**：桥接函数已有；需 REG-3 工具包装。适合首批。

### P9. 新建或保存任务新修订

- **原话**：「新建任务：复现基线；保存时升一个修订。」
- **形态**：文字加补充卡（新建/编辑卡）
- **组件**：Form、ConfirmCard、ObjectChip、ScopeChip（展示即将产生的 revision）
- **事实**：现任务 head：`tasks` / `taskRevision`（`:260,:275`）；字段 `title,goal,spec,revision`（`models.dart:51–62`）
- **公式**：无（revision+1 是 Store 效应，不是展示公式）
- **动作**：业务 · 写入：`research.create_task` / `research.update_task` → `saveTask`（每次 INSERT 新 revision，禁止改历史行）
- **可行性**：Store 已有；spec 宜白名单字段。**首批建议（窄字段）**。

### P10. 开始手工运行并填写结果

- **原话**：「开始记一次手工运行；跑完了，状态 completed，指标 accuracy=0.81。」
- **形态**：交互小工具（状态/指标表单）+ ConfirmCard；长日志可开工作区
- **组件**：Form、Choice（status）、NumberStepper/Metric、Table、ConfirmCard、ProgressCard
- **事实**：钉死的 `task_id`+`task_revision`；`run.data.metrics` / `status` / `_localManual`（`startManualRun` `:505`；`updateManualRun` `:541`）
- **公式**：可选 `metric_value`（取单个指标，便于小工具本地显示）——若直接绑事实亦可「无」新公式
- **动作**：业务 · 写入：`research.start_manual_run` / `research.update_manual_run`（专用，勿裸 CRUD）
- **可行性**：Store 已有；状态机约束多，适合专用卡。可放首批后段。

### P11. 把这次运行和上次比一下

- **原话**：「把这次运行的结果和上次比一下。」
- **形态**：**交互小工具**（对齐现有 `comparisonCard`，`workbench_app.dart:1195–1266`）
- **组件**：CompareTable、Metric、Choice（选对比运行/指标键）、Toggle（只看数值指标）、Prose（「不自动判断优劣」警告文案）
- **事实**：同 `(taskId, taskRevision)` 的 `runs`（`:284`）；`run.status`、`accepted`、`data.metrics`、`data.conclusion`、`data.workbench_assessment.result`、`data.artifacts`
- **公式**：`run_metric_delta`；`run_metric_pct_change`；`artifact_count`（§4）
- **动作**：本地换对比对象/指标；语义「解释差异」；业务无（比较只读）
- **可行性**：UI 已实现表格式比较；公式需 AIUI-3 登记后绑定。**首批建议（只读+公式）**。

### P12. 评估这次运行的研究结论

- **原话**：「这次运行支持假设吗？帮我记评估。」
- **形态**：文字加补充卡（评估 Form + ConfirmCard）
- **组件**：Choice（`runResults`）、Toggle（discriminating）、Form、ConfirmCard、WarnBanner（failed→只能 inconclusive）
- **事实**：`run.status`、现有 `data.workbench_assessment`；规则 `runAssessment`（`skill_bridge.dart:61–91`）；写入 `assessRun`（`store.dart:479`）
- **公式**：无（结论枚举非计算值）
- **动作**：业务 · 写入：`research.assess_run`
- **可行性**：Store + 规则已有。**首批建议**。

### P13. 接纳运行为证据

- **原话**：「把这次运行纳入证据链。」
- **形态**：文字加补充卡 + ConfirmCard（文案须声明「不代表科学结论已验证」，对齐 `runPage` `:1284`）
- **组件**：ConfirmCard、ObjectChip、WarnBanner
- **事实**：`run.accepted`（`acceptRun` `:472–475`，不改 status）
- **公式**：`accepted_run_count`
- **动作**：业务 · 写入：`research.accept_run`；效应：之后才可被 `cite` 引用（`outline_store.dart:109`）
- **可行性**：Store 已有。**首批建议**。

### P14. 把这几条证据挂到第 3 节

- **原话**：「把这几条证据挂到第 3 节。」
- **形态**：文字加补充卡（关联卡 / 批量关联）+ ConfirmCard；多选时 BatchConfirmCard
- **组件**：ObjectChip、Choice（section）、Checklist、ConfirmCard、BatchConfirmCard、Table（已挂证据预览）
- **事实**：`sections`（`outline_store.dart:9`）；`outline` 链接（`store.outline` `:595`）；证据为 entry / note / **accepted** run（`cite` `:103–134`）
- **公式**：`evidence_count_for_section`
- **动作**：业务 · 写入：`research.cite`（幂等）；失败时若 run 未 accepted → WarnBanner 引导 P13
- **可行性**：Store 已有。**首批建议**。

### P15. 新增或编辑提纲段落

- **原话**：「加一节『相关工作』；把第 2 节论述改成……，支持程度改为部分支持。」
- **形态**：文字加补充卡（新建/编辑卡）
- **组件**：Form、Choice（level 1–3、`sectionSupport` `models.dart:118–124`）、ConfirmCard
- **事实**：`OutlineSection`（`:126–139`）；写 `addSection`/`updateSection`（`outline_store.dart:26,:45`）
- **公式**：`section_support_counts`（项目级汇总，用于回答旁 Metric）
- **动作**：业务 · 写入：`research.add_section` / `research.update_section`；本地：无
- **可行性**：Store 已有。排序/删除见 P16 / §2。**首批建议**。

### P16. 调整段落顺序

- **原话**：「把『方法』挪到『结果』上面。」
- **形态**：交互小工具（上下移）或文字加确认
- **组件**：Checklist/列表 + 本地按钮；或 ConfirmCard 确认一次交换
- **事实**：`section.position`；`moveSection(id, delta)`（`outline_store.dart:66–72`）
- **公式**：无
- **动作**：业务 · 写入：`research.move_section`（或本地若视为纯 UI——但持久化到 DB，故标**业务·写入**）
- **可行性**：Store 已有。优先级低于 P14/P15。

### P17. 导出 Markdown 研究报告

- **原话**：「按提纲导出一份 Markdown 报告。」
- **形态**：文字加补充卡 + ConfirmCard（本机路径）
- **组件**：ConfirmCard、FileCard、ProgressCard
- **事实**：提纲 `sections`+`outline`；报告内容由 `exportReport` 生成（`exchange.dart:1128`）；写作页入口 `writing_page.dart:223` / `workbench_app.dart:1544`
- **公式**：无（导出是副作用）
- **动作**：业务 · **外传**（本机文件）：`research.export_report`（Q10 开放，逐次确认）
- **可行性**：Exchange API 已有；待工具登记。**首批建议**。

### P18. 导出回写主张草稿（skill v2）

- **原话**：「把精读笔记导出成 research-skill 待审 claim 草稿。」
- **形态**：文字加补充卡 + ConfirmCard；需 `layout==research-skill-v2`（`workbench_app.dart:589–598`）
- **组件**：ConfirmCard、Checklist（选笔记/条目）、FileCard、WarnBanner（非 v2）
- **事实**：`project.layout`；笔记与 bindings；`exportClaimDrafts`（`exchange.dart:564`）
- **公式**：无
- **动作**：业务 · **外传**：`research.export_claim_drafts`（Q10 开放）
- **可行性**：API 已有；依赖 skill 项目。适合有 skill 用户时做，首批可选。

### P19. 看提纲哪里证据不足

- **原话**：「哪些段落还没挂证据？哪些标了证据不足？」
- **形态**：文字加补充卡；可带交互筛选
- **组件**：Table、Metric、Choice（按 support 筛）、ObjectChip、Checklist
- **事实**：`sections.support` / `argument`；每节 outline 行（`:595`；写作页组装 `:150–156`）
- **公式**：`evidence_count_for_section`；`section_support_counts`
- **动作**：本地筛选；语义「帮我找证据候选」；业务可跳转 P14
- **可行性**：只读 + 公式即可。**首批建议（只读）**。

### P20. 浏览对象关系（摘要，非布局编辑）

- **原话**：「主张 O1 连到哪些实验和失败记录？」
- **形态**：文字加补充卡（邻接表）；完整力导向图 → **工作区**打开 `RelationsPage`
- **组件**：Table、ObjectChip、Disclosure、Timeline（可选血缘）；工作区入口
- **事实**：entries/tasks/runs/notes + `_flatRefs`/`_nestedRefs`（`relations_page.dart:47–64`）
- **公式**：`claim_link_count`（复用）；可选 `degree_of_object`
- **动作**：本地筛选；打开工作区；业务无
- **可行性**：摘要只读可做；图布局留原页（§2）。

### 未单独成条、但相关的目的（并入上表或 §2）

| 用户说法 | 处理 |
|---|---|
| 导入文献库 / 任务包 / 结果包 | deferred(REG-3 / Q10)；回答「请在原页面或导入流操作」 |
| 导出离线任务包 / 结果包 / 技能实验包 | deferred |
| LAN 设备收发 | 留 `LanTransferPage`（§2） |
| 编辑知识卡片 Markdown | 可后续目的；`research.card_save` + `expectedHead`；冲突 UI 留原页 |
| 删除段落 | 有 `deleteSection`；需强确认；首批可后置 |

---

## 2. 必须留在原页面的操作

| 操作 | 原页面 / 组件 | 理由 |
|---|---|---|
| PDF/文本**划词**与选区定位 | `ReaderPage`（`reader_page.dart:115–160,:758+`） | locator/quote 依赖阅读器选区与页码；对话无稳定指针 |
| 引用跳转高亮 / 歧义匹配提示 | `source_locator.dart`、`source_jump_banner.dart`、`citation_resolver.dart` | 页内坐标与「仅跳页 vs 高亮」承诺分离，需原阅读器 |
| 关系图**布局**拖拽、搜索过滤画布 | `RelationsPage` | 空间布局与大量节点交互；对话只给邻接摘要 + 入口 |
| 卡片 **CardConflict** 解决 | `CardStore.save` 抛 `CardConflict`（`card_store.dart:163,:308`） | 需展示 currentHead vs draft 的合并 UI；静态未见对话级冲突工作区 |
| 论文绑定**自动匹配**全量扫描 UI | 文库页绑定列表 + 导入刷新（exchange 写 bindings） | 批量候选与 hash 校验适合原表；对话只做单次确认（P5） |
| 整库 / 任务 / 结果 **导入**向导 | 概览/任务/结果页菜单；`ResearchExchange.import*` | Q10 deferred；包校验与跳过文件统计在导入流 |
| **导出任务包 / 结果包 / 技能实验包** | 任务页 / 结果页 | Q10 deferred |
| LAN **设备收发** | `LanTransferPage` | 网络权限、配对与文件落盘；非对话卡片 |
| 长文阅读 / 多文件对照 | 阅读器工作区 | 方案 §4.2：工作区承载长时间编辑；回答只给摘要卡 |

说明：提纲排序（P16）、评估（P12）等**可以**进对话，但若用户已在写作页深度编辑，回答应提供「打开写作工作区」以免双源编辑冲突。

---

## 3. 优先级（使用频率 × 现在可行性）

评分只作排序说明（高/中/低），非正式度量。

| 排序 | 目的 | 频率 | 可行性 | 首批？ |
|---|---|---|---|---|
| 1 | P1 目标与下一步（只读） | 高 | 高 | ✓ |
| 2 | P11 运行对比（只读+公式） | 高 | 高（UI 已有） | ✓ |
| 3 | P14 证据挂到段落 | 高 | 高（cite 已有） | ✓ |
| 4 | P3 论文↔主张（只读） | 高 | 中（需边投影） | ✓ |
| 5 | P12 评估运行 | 中高 | 高 | ✓ |
| 6 | P13 接纳证据 | 中高 | 高 | ✓ |
| 7 | P2 / P15 改目标或段落 | 中高 | 高 | ✓（工具登记后） |
| 8 | P9 任务新建/修订 | 中 | 高（窄字段） | 次批 |
| 9 | P5 确认绑定 | 中 | 高 | 次批 |
| 10 | P17 导出报告 | 中 | 高（Q10 开放） | 次批（或首批尾巴） |
| 11 | P7 笔记挂条目 | 中 | 高 | 次批 |
| 12 | P8 实验→任务 | 中 | 中 | 次批 |
| 13 | P10 手工运行 | 中 | 中（状态机） | 后 |
| 14 | P19 证据缺口总览 | 中 | 高（公式） | 可与 P14 捆绑 |
| 15 | P6 新建笔记 | 中 | 中（依赖 locator） | 后（阅读器会话） |
| 16 | P18 claim 草稿导出 | 低（仅 skill v2） | 高 | 可选 |
| 17 | P4 打开文献 | 高 | 高（导航） | 作入口即可 |
| 18 | P16 段落排序 | 低 | 高 | 后 |
| 19 | P20 关系摘要 | 中 | 中 | 后 |
| — | 导入/设备包 | — | deferred | 不做 |

**AIUI-7 首批建议（7 个）**：P1、P11、P14、P3、P12、P13、P2（或 P15，二选一与写作场景绑定；建议 **P2+P15 都进首批若带宽允许，否则 P2 优先概览、P15 与 P14 同批**）。

压缩为 **7**：P1 · P2 · P3 · P11 · P12 · P13 · P14（P15 紧随 P14 作为同场景加项）。

---

## 4. 公式清单（交 AIUI-3）

输入只能是快照事实或用户输入值；输出供 `computed` 绑定。名称建议 `research.*` 前缀。

| 名称 | 输入 | 输出 | 单位 | 一句话定义 |
|---|---|---|---|---|
| `research.entry_count_by_kind` | `project_id`（事实）；`kind`（用户或事实枚举） | 整数 ≥0 | 条 | 项目内 `entries.kind` 等于给定 kind 的条数（对齐 `countKind`） |
| `research.task_count` | `project_id` | 整数 ≥0 | 个 | `tasks(projectId)` 返回行数；该查询已按 id 取 `MAX(revision)`（`store.dart:260–266`），故等于当前任务头数量 |
| `research.artifact_count` | `run_id` | 整数 ≥0 | 个 | `run.data.artifacts` 为 List 时的 length，否则 0（对齐比较表 `:1258–1259`） |
| `research.run_metric_delta` | `run_id_a`；`run_id_b`；`metric_key`（用户） | 数或 null | 与指标相同 | `metrics[key]_a - metrics[key]_b`；任一侧非有限数字则 null（不发明优劣） |
| `research.run_metric_pct_change` | 同上 | 数或 null | 比例（无量纲） | `(a-b)/b`；`b=0` 或非数字则 null |
| `research.evidence_count_for_section` | `section_id` | 整数 ≥0 | 条 | `outline` 中 `section_id` 匹配的行数 |
| `research.section_support_counts` | `project_id` | 对象：各 `support` → 整数 | 段 | 按 `sectionSupport` 键汇总段落数 |
| `research.accepted_run_count` | `project_id` | 整数 ≥0 | 次 | `runs` 中 `accepted==true` 的数量 |
| `research.claim_link_count` | `paper_entry_id` 或 `claim_entry_id`；`direction`∈{from_paper,from_claim}（用户） | 整数 ≥0 | 条 | 按 RelationsPage 边规则计数显式 id+rev 引用（不把标题相似当边） |

以上 **9** 条建议登记；回报「公式数」取 **9**。

`metric_value(run_id, key)` 若只需展示，优先**直接绑事实** `run.data.metrics[key]`，不必登记公式。

---

## 5. 未能静态确认

1. 宿主是否已注册任何 `research.*` 写/导出工具（GROK-6 §6.1；本任务未跑 Flutter）。
2. ~~`tasks` 是否折叠 revision~~：**已确认** `SELECT … revision=(SELECT MAX(revision)…)`（`store.dart:260–266`）；`task_count` 按该列表 length。
3. Relations 边是否应在 DataSnapshot 中物化为事实表，还是 AIUI-7 每次由宿主临时投影 —— 影响 P3/P20。
4. 对话会话如何获得阅读器当前 `locator`/选区（P6）—— 无跨页面会话协议的静态证据。
5. `comparisonCard` 的「产物数」等是否允许模型用文字复述；契约要求数值走事实/公式，文案「不自动判断优劣」须由宿主模板固定。
6. 知识卡片编辑与冲突解决的产品入口是否在本 workbench 主导航内（卡片 API 在 `CardStore`，主导航六页未直接露出 cards UI —— **未能静态确认**独立卡片页路径）。
7. `exportReport` / `exportClaimDrafts` 写入的绝对目录与确认卡文案是否已有 AUTH/助手权限挂钩。
8. REG-3 是否将 `entry` 按 kind 拆多类型 —— 影响 P3 事实字段清单稳定性。

---

## 6. 统计（回报用）

| 项 | 值 |
|---|---|
| 目的总数 | **20** |
| 首批建议 | **7**：P1、P2、P3、P11、P12、P13、P14（P15 建议紧随） |
| 公式数 | **9**（§4） |
| 留原页操作类 | **9** |
| 文档路径 | `docs/reviews/2026-10-09-research-walkthrough.md` |
