# ADR-0004 §12.2 静态核实 + 科研导出/导入清单初稿（GROK-1）

日期：2026-10-07 · 任务：[GROK-1](../tasks/GROK-1.md) · 执行：工程师2号（grokbot）· 分支：`task/grok-1-adr0004-static` · 方法：只读代码与 `grep`/`rg`，**未**运行 Flutter / 测试 · 代码对照：本分支与 `origin/develop` 在 `apps/`、`packages/` 无差异（`git diff --stat origin/develop...HEAD -- apps/ packages/` 为空）；REG-2a 尚未合入 develop。

每个结论附 `文件:行` 引用。不确定处标「未能静态确认」，不猜测。

---

## 1. §12.2 第 6 项：`foundation_scope_test` / `tool_registry_test` 是否断言全局范围含摘要

**结论：否。两份测试都没有断言「全局范围解析出的 `ObjectRef` 带有 `contentDigest`（摘要）」。**

生产路径里，全局范围**会**填摘要：

- 询价：`apps/muyon/lib/platform/business_tools.dart:69-71`（对行 `data` 做 SHA-256）
- 科研项目 / 文档 / 条目：同文件 `:86-96`、`:110`、`:121-123`
- 全局直接返回这些对象：`:138-142`

但测试侧：

| 测试 | 与 digest / 全局范围的关系 |
|---|---|
| `apps/muyon/test/foundation_scope_test.dart` | 全文**无** `contentDigest` / `digest` 字面量。全局用例只断言对象身份存在与否（如 `:35`、`:37-40`、`:91`），不检查摘要字段。 |
| `apps/muyon/test/tool_registry_test.dart` | `contentDigest` 仅出现在夹具 `ObjectRef`（`:22`、`:270`），用于「修订/摘要变化使审批失效」类场景（`:260-277`）。范围解析是测试内伪造的 `resolve`（`:36-41`），**不**覆盖真实 `resolveAssistantScope`，也**不**断言全局范围必须含摘要。 |

一句话：实现已为全局范围挂摘要；这两份测试未钉住该行为。

---

## 2. §12.2 第 7 项：`document_parser.dart` / `knowledge_service.dart` 从 `research_module` 取用的符号

**结论：两处都只依赖 `ResearchDocument`（及其实例成员）；未见其它 `research_module` 类型/顶层函数被直接引用。**

### `apps/muyon/lib/services/documents/document_parser.dart`

- 导入：`:6` `import 'package:research_module/research_module.dart';`
- 使用的符号：
  - 类型 `ResearchDocument`（参数类型，`:16`）
  - 实例成员 `absolutePath`（`:17`、`:26`）、`isPdf`（`:24`）、`relativePath`（`:38`）
- 定义出处：`packages/research_module/lib/src/core/models.dart:32-43`（经 `research_module.dart` → `src/core/models.dart` 导出）

### `apps/muyon/lib/services/knowledge/knowledge_service.dart`

- 导入：`:7` `import 'package:research_module/research_module.dart';`
- 使用的符号：构造 `ResearchDocument(...)`（`:341-346`，字段 `id` / `projectId` / `relativePath` / `absolutePath`）
- 同文件中的 `DocumentParser` / `DocumentParser.version` 来自相对导入 `../documents/document_parser.dart`（`:10`、`:52-55`、`:382` 等），**不是** `research_module` 符号。

未能静态确认：barrel `research_module.dart` 是否因其它导出产生未使用的传递依赖（分析器级）；就源码引用而言，只用到 `ResearchDocument`。

---

## 3. §12.2 第 8 项：询价 `ontology` 文案与 `ontology_test` 的耦合；`describe` 输出被哪些测试钉住

**结论：`ontology_test` 强耦合本体结构与 `ontologyCard()` 文案骨架；工具 `describe` 的输出形状主要由 `ontology_paths_test` 钉住；`ontology_test` 只要求 `describe` 能跑通，不钉全文。**

### 与 `ontology` / 文案的耦合（`packages/supplier_core/test/ontology_test.dart`）

| 钉住内容 | 引用 |
|---|---|
| 各实体字段名顺序 = 存储 payload 字段 | `:14-24`（`ontology[type]!.fields` vs `payloadFields`） |
| 对象类型分组覆盖全集 | `:27-30` |
| 本体链接 ↔ `references` / `listReferences` | `:32-47` |
| 枚举取值 = 校验器接受集 | `:50-63` |
| `required` 字段为空则校验失败 | `:66-146` |
| `ontologyCard()` 含 `### {name} {label}`，且总长 `< 7000` | `:149-156`；实现见 `packages/supplier_core/lib/src/ontology.dart:719-741` |

`actions` / `rules` 等人读文案（`ontology.dart:707-716`、`:700-704`）进入 `describe()` 的 `actions_in_app` / `rules`（`agent_tools.dart:338-341`），但 **`ontology_test` 不逐条比对这些中文句子**。

### `describe` 输出被谁钉住

实现：`packages/supplier_core/lib/src/agent_tools.dart:330-369`（无参：`types`/`links`/`rules`/`actions_in_app`；有参：类型 JSON + `paths_to` 等）。

| 测试 | 钉住什么 |
|---|---|
| `packages/supplier_core/test/ontology_paths_test.dart:102-116` | **有参** `describe(type)`：`paths_to` 非空、不含自身、具体路径串（如 `project` → `related inquiry.supplier_ids → get inquiry.project_id`，`:108-111`）、存在 `paths_to_format`；**无参** `describe()`：无 `paths_to`，键集合恰为 `{types, links, rules, actions_in_app}`（`:114-116`） |
| `packages/supplier_core/test/ontology_test.dart:186-213` | 将 `describe` 列入「每个声明工具都能跑」；只断言无 `error`，**不**比对正文 |
| `packages/supplier_core/test/spec_match_test.dart:192`、`spec_fill_test.dart:210` | 钉的是约束对象的 `.describe()` 字符串，**不是** ontology 工具 `describe` |

一句话：改 `ontology` 字段/链接/枚举/卡片标题会红 `ontology_test`；改 `describe` 的键集合或 E9 路径文案会红 `ontology_paths_test`；改 `actions`/`rules` 中文句子本身**未必**有测试钉住。

---

## 4. §12.2 第 13 项：科研操作面完整清单，并核对评估「16 类」

**结论：评估「16 类」是带省略号的粗口径，无法从源码唯一还原为恰好 16 个叶子方法；按 ADR-0004 所述操作面（`WorkbenchStore` / `OutlineStore` / `CardStore` / `ResearchExchange`，外加薄封装 `ResearchServices`）静态枚举，公开写操作叶子方法明显多于 16。只读查询方法另列。**

依据：[评估 §1](2026-10-07-ai-native-and-registration.md) 表行「科研 · 写」；[ADR-0004](../adr/0004-module-contract-v2.md) 约 `:511`、`:588`、§12.2 第 13 项。

### 建议的 `surfaces` 登记目标（粗粒度）

| surface | 库路径 | 说明 |
|---|---|---|
| `WorkbenchStore` | `packages/research_module/lib/src/core/store.dart` | 类本体写/读 |
| `OutlineStore` | `.../outline_store.dart` | `extension … on WorkbenchStore` |
| `ResearchExchange` | `.../exchange.dart` | 导入/导出与设备包 |
| `CardStore` | `.../cards/card_store.dart` | 知识卡片 |
| `ResearchServices` | `.../research_services.dart` | 对 store 的 scoped 写封装（非独立真相源） |

### 写操作逐项（读/写、文件或设备）

#### A. `WorkbenchStore`（`store.dart`）

| 操作名 | 读/写 | 文件或设备 | 行 |
|---|---|---|---|
| `insertBinding` | 写 | 否（库） | `:333` |
| `confirmBinding` | 写 | 否 | `:345` |
| `applyBindingChoice` | 写 | 否（供事务内调用） | `:359` |
| `setNoteEntry` | 写 | 否 | `:373` |
| `saveProject` | 写 | 否 | `:387` |
| `saveNote` | 写 | 否 | `:396` |
| `saveTask` | 写 | 否 | `:437` |
| `acceptRun` | 写 | 否 | `:472` |
| `assessRun` | 写 | 否 | `:479` |
| `startManualRun` | 写 | 否 | `:505` |
| `updateManualRun` | 写 | 否 | `:541` |

（同文件大量 `projects`/`documents`/`entries`/`tasks`/`runs`/`notes`/`bindings`/`outline` 等为读。）

#### B. `OutlineStore`（`outline_store.dart`）

| 操作名 | 读/写 | 文件或设备 | 行 |
|---|---|---|---|
| `addSection` | 写 | 否 | `:26` |
| `updateSection` | 写 | 否 | `:45` |
| `moveSection` | 写 | 否 | `:66` |
| `deleteSection` | 写 | 否 | `:85` |
| `addOutline` | 写 | 否 | `:93` |
| `cite` | 写 | 否 | `:103` |
| `removeOutline` | 写 | 否 | `:136` |

（`sections` `:9` 为读。）

#### C. `ResearchExchange`（`exchange.dart`）— 多数涉及文件；经 UI/宿主可再上设备

| 操作名 | 读/写 | 文件或设备 | 行 |
|---|---|---|---|
| `importResearch` | 写 | **是**（目录/zip → 库+快照） | `:212` |
| `prepareResearch` | 写准备 | **是**（读入包，尚未 commit） | `:231` |
| `commitResearch` | 写 | 是（提交已准备快照） | `:261` |
| `exportClaimDrafts` | 写（导出） | **是**（写目标目录） | `:564` |
| `prepareTask` | 写准备 | **是** | `:723` |
| `commitTask` | 写 | 是 | `:764` |
| `importTask` | 写 | **是** | `:826` |
| `exportTask` | 写（导出） | **是**（zip → 目录；工作台用 `exports/`，`:838`；UI `workbench_app.dart:1081`） | `:838` |
| `exportResult` | 写（导出） | **是** | `:896` |
| `exportSkillExperiment` | 写（导出） | **是** | `:964` |
| `importResult` | 写 | **是**（json/zip；亦可经宿主接收设备包） | `:1006` |
| `exportReport` | 写（导出） | **是**（报告文件到目录） | `:1128` |

宿主侧设备桥（非 module surface，但与上列导入/导出衔接）：`apps/muyon/lib/app/research_task_bridge.dart`、`accepted_research_imports.dart`（ADR-0004 §2.1「设备交换」）。

#### D. `CardStore`（`card_store.dart`）

| 操作名 | 读/写 | 文件或设备 | 行 |
|---|---|---|---|
| `ensureKey` | 写（可能插入键） | 否 | `:214` |
| `registerDocument` | 写 | 可能登记路径元数据 | `:240` |
| `deleteDocument` | 写 | 否（目录层） | `:262` |
| `save` | 写 | 否 | `:293` |
| `insertRevision` | 写 | 否 | `:343` |

#### E. `ResearchServices`（薄封装，`:68-112`）

`saveNote` / `setNoteEntry` / `acceptRun` / `assessRun` / `addOutline` — 全部转发 `WorkbenchStore`/`OutlineStore`，本机库写，无直接文件 I/O。

### 与评估「16 类」的对齐

- 评估枚举示例七个：`saveNote`、`addOutline`、`assessRun`、`acceptRun`、`exportTask`、`importResult`、`exportReport`（均能在上表找到），后接「……」。
- 叶子写操作合计：WorkbenchStore 写 11 + OutlineStore 写 7 + Exchange 写/导出相关 12 + CardStore 写约 5 ≈ **三十余**（视是否把 `prepare*`/`applyBindingChoice`/`ensureKey` 算入而略变）。
- **未能静态确认**评估作者心中恰好哪 16 个「类」（可能是 UI 业务动作聚类，而非公开方法全集）。静态可确认的是：完整 surface 清单长于「16」，REG-3 应以本表叶子方法（或明确的聚合规则）为准，而不是沿用未展开的「16」。

---

## 5. §12.2 第 14 项：询价写操作条数（按 `extension … on Store`），对齐「27 类」

**结论：`supplier_core` 中 `extension … on Store` 共 35 个（与 ADR 一致）；在扩展内判定为「写库或写文件」的公开成员约 36 个，再加上 `Store` 本体的 `save`/`delete`/`restore`/`markResolved` 共约 40 个。评估「27 类」是更粗、带省略号的口径，与叶子写成员数不一致；ADR「约 35」更接近本次数值。**

统计方法（静态、可复查）：

1. 枚举 `packages/supplier_core/lib/**/*.dart` 中 `^extension \w+ on Store` → **35** 个扩展。
2. 扩展内公开成员（非 `_` 前缀）约 **107** 个。
3. 写判定：方法体含 `transaction(` / `INSERT|UPDATE|DELETE|REPLACE` 的 `db.execute`，或明确写文件；并人工校正明显误判（读方法如 `paramsOf`/`specItemsOf`/`plan*`/`previewImport` 等排除；`createInquiry`/`setClauseResponse`/`clearChoice` 等经 `save`/`transaction` 的纳入）。

### 按扩展列出的写成员

| 扩展 | 文件 | 写成员（名 @ 行） |
|---|---|---|
| `Attachments` | `attachments.dart` | `addAttachment` `:26` |
| `Budgets` | `budget.dart` | `copyProject` `:298` |
| `Refresh` | `budget.dart` | `applyRefresh` `:399` |
| `Conflicts` | `conflicts.dart` | `resolveConflict` `:72` |
| `EncryptedExchange` | `crypto_file.dart` | `exportEncryptedTo` `:150` |
| `Exchange` | `exchange.dart` | `exportTo` `:105`，`dailyBackup` `:146`，`replaceFrom` `:180`，`importFrom` `:260` |
| `FolderSyncing` | `folder_sync.dart` | `syncWithFolder` `:44` |
| `Inquiries` | `inquiries.dart` | `createInquiry` `:143`，`quoteForInquiry` `:202`，`award` `:346`，`withdrawAward` `:384`，`applyInquirySheet` `:511` |
| `ListImport` | `list_import.dart` | `createProjectFromProposal` `:195` |
| `MaterialImport` | `material_import.dart` | `applyOffers` `:202` |
| `Merge` | `merge.dart` | `mergeRoot` `:16`，`mergeInto` `:34`，`redirectMerged` `:63` |
| `ProductParams` | `product_params.dart` | `setParam` `:126`，`clearParam` `:159`，`confirmParams` `:166` |
| `QuoteExcel` | `quote_excel.dart` | `applyQuotationImport` `:182` |
| `Share` | `share.dart` | `exportSelection` `:66` |
| `ParamExtraction` | `spec_extract.dart` | `applyParamFill` `:110` |
| `SpecMigration` | `spec_migration.dart` | `applyAttributeMigration` `:156` |
| `SpecRequests` | `spec_request.dart` | `createSpecRequest` `:306`，`deleteSpecRequest` `:381`，`restoreSpecRequest` `:391`，`saveClauses` `:422`，`chooseProduct` `:450`，`setClauseResponse` `:535`，`clearChoice` `:571` |
| `SpecResponses` | `spec_response.dart` | `applySpecResponses` `:320`，`addItemsToBudget` `:474` |
| **`Store` 类本体**（非 extension，但 ADR 要求归类） | `store.dart` | `save` `:377`，`delete` `:458`，`restore` `:469`，`markResolved` `:516` |

**计数：** 扩展内写成员 **36** + Store 本体 **4** = **40**。

评估示例七个（`award`、`createSpecRequest`、`setParam`、`restore`、`mergeInto`、`applyQuotationImport`、`resolveConflict`）均落在上表。「27 类」**未能静态确认**其精确集合；REG-4b 应用上表叶子名单（或书面规定的聚合规则）替换「27」。

纯导出到字节/文件但**不**改库的方法（如 `exportInquirySheet`、`exportQuotations`、各类 PDF/XLSX 导出）本表记为读/导出副作用，**未**计入「写成员 40」；若覆盖清单把「导出」也算操作面，需另册登记。

---

## 6. §12.2 第 15 项：出站账本除模型网关外是否还有写入点（基于当前 develop）

**结论：对表 `outbound_requests` / API `OutboundLedger.begin`，生产代码里唯一写入调用链是模型网关；未见 MCP / 询价网页或资料中心通道写入该账本。REG-2a 尚未合入。**

| 检查点 | 结果 | 引用 |
|---|---|---|
| `INSERT INTO outbound_requests` | 仅 `OutboundLedger.begin` 内 | `apps/muyon/lib/platform/outbound_ledger.dart:66-70` |
| 谁调用 `ledger?.begin` / `ledger.begin` | 仅网关出站通道 | `apps/muyon/lib/services/models/model_gateway.dart:630` |
| `finish` / 状态更新 | 网关通道收尾；启动时 `recoverInterrupted` 把中断行标为 interrupted | `model_gateway.dart:342+`、`:546`；`bootstrap.dart:220`；`outbound_ledger.dart:94+`、`:133` |
| MCP / 询价通道 | 未引用 `OutboundLedger` / `outbound_requests` | `mcp_adapter.dart`、`inquiry_hub_authority.dart`、`inquiry_web_authority.dart` 无命中 |
| 与 develop 一致性 | 本分支 `apps/`/`packages/` 与 `origin/develop` 无差；develop 上同样只有上述 `begin` 调用 | `git grep` on `origin/develop` |

易混淆但**不是**该账本：`ChatLog.insertOutbound` 写入 `chat_messages`（`apps/muyon/lib/services/transfer/chat_log.dart:155-177`），与 `outbound_requests` 无关。

这与 ADR-0004 §2.3-6 / §9.1 所述缺口一致：外传类工具目前不入出站账本；补齐属 REG-2a（`outbound_tool_requests`），当前 develop 尚未合入。

---

## 7. Q10 清单初稿：科研导出 / 导入类写操作（交用户确认）

以下从第 4 项中挑出**涉及文件或（经宿主）设备交换**的写/导出操作。措辞面向非开发者。建议仅作初稿；最终以用户在 REG-3 派发前确认为准（ADR-0004 §12.1 Q10）。

图例：

- **建议开放**：助手将来可按授权调用（仍走一次性审批/回执；效应建议 `export` 或受控 `write`）。
- **建议暂不开放（`deferred` / `notExposed`）**：先只留在人工界面；等 REG-3 把范围、污染与设备边界说清再开。

| 操作（内部名） | 用户能感知的事 | 涉及的文件或设备 | 风险说明 | 建议 | 理由 |
|---|---|---|---|---|---|
| `exportReport` | 把当前项目的阅读笔记/证据整理成一份报告文件，写到本机导出目录 | 本机文件（`exports/` 下报告） | 报告可能含摘录与判断；默认不出网，但文件可被用户拷走 | **开放**（本机导出） | 不自动发往其他设备；便于助手「整理成文」；仍应逐次确认 |
| `exportClaimDrafts` | 导出若干主张草稿到本机目录 | 本机文件 | 同上，体量通常小于整包 | **开放**（本机导出） | 本机、可审阅；风险低于整库/任务包 |
| `exportTask` | 打出「研究任务包」（zip），供别处执行 | 本机 zip；常经传输/设备发给执行端 | 任务说明、材料引用可能外流；是跨设备工作流入口 | **暂不开放** | 涉及设备边界与外传；宜等 Exchange/transfer 与出站账本方案齐套 |
| `exportResult` | 导出某次运行结果包 | 本机文件；可再发送 | 结果与日志可能含敏感实验数据 | **暂不开放** | 同上 |
| `exportSkillExperiment` | 导出技能/实验相关包 | 本机文件 | 可能含路径与中间产物 | **暂不开放** | 使用面窄、边界同任务包 |
| `importResult` | 从结果文件（或设备收到的包）写入本机运行记录 | 本机文件 **或** 设备收包后导入 | 外部包可污染库；ADR 外部内容污染（Q11）相关 | **暂不开放** | 外部输入 + 写库；助手自动导入风险高 |
| `importTask` / `prepareTask`+`commitTask` | 从任务包装入任务 | 文件 / 设备 | 同上 | **暂不开放** | 同上 |
| `importResearch` / `prepareResearch`+`commitResearch` | 从文件夹或 zip 导入整个研究项目 | 本机目录/zip（工作台文件选择器） | 大批量写入；第三方材料可作提示注入载体 | **暂不开放** | 体量大、难自动审查；应保持人工导入 |
| 宿主任务桥发送/接收（`research_task_bridge` / `accepted_research_imports`） | 在设备之间收发科研任务/结果 | **设备 / 局域网传输** | 真正的跨设备外传；今日不经 `outbound_requests` 模型账本 | **暂不开放**（对助手） | 外传底线与 REG-2a 账本未齐；界面人工流程可保留 |

**本机库写入**（`saveNote`、`addOutline`、`assessRun`、`acceptRun`、提纲编辑、`saveProject`/`saveTask`、手工 run 等）按 Q10 建议方向属「可对助手开放为 `write`」之列，**不在本表**（非导出/导入类）；REG-3 另做覆盖清单即可。

---

## 未能静态确认（汇总）

1. 评估「科研 16 类」「询价 27 类」的精确成员集合（仅有示例 + 省略号）。
2. `analyzer` 级：宿主文件 import `research_module` barrel 是否拉入未直接引用的符号（与第 7 项使用点无关）。
3. `actions`/`rules` 中文句子是否被其它非测试路径（提示词快照、金样）钉住——本任务未扫全仓非 `*_test.dart` 的字符串夹具。
4. 将「纯文件导出但不写库」的询价方法是否计入覆盖清单写操作——需 REG-4b / REG-3 产品口径，而非静态对错。

---

## 每项一句话结论（回报用）

1. **§12.2-6**：`foundation_scope_test` 与 `tool_registry_test` **均未**断言全局范围含摘要。
2. **§12.2-7**：两文件从 `research_module` 只用 `ResearchDocument`（及 `absolutePath`/`isPdf`/`relativePath`）。
3. **§12.2-8**：`ontology_test` 钉字段/链接/枚举/卡片；`describe` 键与 `paths_to` 由 `ontology_paths_test` 钉住。
4. **§12.2-13**：科研写操作叶子远多于评估「16 类」；完整 surface 见上文表。
5. **§12.2-14**：35 个 `on Store` 扩展；写成员约 36+4（Store 本体）≈40，大于评估「27 类」。
6. **§12.2-15**：`outbound_requests` 生产写入仅模型网关；REG-2a 未合入。
7. **Q10**：导出/导入类初稿见 §7；建议本机报告/草稿导出可开放，任务包与导入/设备交换暂不开放。
