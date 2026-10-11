# 变更日志与投影的覆盖缺口（GB-3）

日期：2026-10-11 · 任务：[GB-3](../tasks/GB-3.md) · 执行：工程师2号（grokbot）· 分支：`review/gb-2-research-write-contracts`（接在 [GB-2](2026-10-11-research-write-contracts.md) 后）
方法：只读 `ModuleChangeLog`、科研 `installResearchChangeLog` / `WorkbenchStore` / `module_tools`、询价宿主 `InquiryPlugin` 触发器与领域 `Store.change_log`、原型 `PrototypeStore`、宿主 `ProjectionService` / `ScopeResolver` / `KnowledgeService.invalidateApplied`；对照 GB-2 汇总表 REG-3d。**未**改代码、**未**运行 Flutter。
给谁用：grok-build 的 REG-3d 及以后；回答 GB-2 §14 第 7 问。

---

## 0. 读前摘要

存在 **三套不同用途的「变更记录」**，不要混为一谈：

| 机制 | 表名 | 用途 | 主要消费者 |
|---|---|---|---|
| **宿主 `ModuleChangeLog`** | `muyon_change_log` | 业务对象 upsert/delete → 驱动宿主投影 | `ProjectionService` → `object_catalog`；删除时 `KnowledgeService.invalidateApplied` |
| **询价领域字段日志** | `change_log`（supplier_core） | 字段级新旧值、设备、时间；交换/冲突 | `exchange` / `conflicts` / UI 历史；**不**进 `object_catalog` |
| **科研导入操作日志** | `change_log`（research，`project_id`+`operation_id`） | 导入幂等/收据 | `commitImport`；**不**进 `object_catalog` |

本调研缺口专指 **`ModuleChangeLog` → 投影/索引/助手发现**。

**REG-3d 结论（先看这里）**：开放 `research.project.save`（`update_project`）与 `research.note.set_entry` 前，**必须同批**补 `project` / `note` 的 `ModuleChangeLog`（当前触发器未跟踪；`save_note` 工具仅显式记 note 创建）。两个读工具与（已有触发器的）`task` 写入不依赖补日志。`binding.confirm` 不强制（`paper_binding` 非本体类型）。询价 `contact`/`product` 可写进工具却不进 `ModuleChangeLog`，属更严重的全局缺口，但不阻塞科研 REG-3d。

---

## 1. 各模块 `ModuleChangeLog` 目前跟踪的对象类型

### 1.1 API（宿主共享）

- `packages/muyon_module_api/lib/src/change_log.dart`
  - `ModuleChangeLog.createTable` · `:34–45`（表 `muyon_change_log`）
  - `ModuleChangeLog.record` · `:47–73`（须同事务于业务行）
  - `ModuleChangeLog.since` · `:75–99`（宿主游标拉取）

### 1.2 科研（触发器 + 一处显式 record）

- 安装：`installResearchChangeLog` · `packages/research_module/lib/src/core/change_log.dart:7–126`；挂在 schema v9 · `research_module.dart:67–70`
- **触发器跟踪**（INSERT/UPDATE/DELETE → upsert/delete）：

| 表 | `object_type` | 安装位置 |
|---|---|---|
| `documents` | `document` | `change_log.dart:49–54` |
| `entries` | `entry` | `:55` |
| `sections` | `section` | `:56` |
| `outline` | `outline` | `:57` |
| `runs` | `run` | `:58–68` |
| `rk_cards`（经 `canonical_object_map`） | `card` | `:69–77` |
| `rk_documents`（仅当前未删版本） | `document` | `:81–102` |
| `tasks`（按 id 投影最新修订；删光才 delete） | `task` | `:106–125` |

- **显式 `ModuleChangeLog.record`**：仅 `research.save_note` 工具在创建 note 后写入 · `module_tools.dart:212–214`
- **未跟踪表/类型**：`projects`（`project`）、`notes`（除上述工具路径）、`paper_bindings`（无本体 `ObjectTypeSpec`）

另：科研还有领域表 `change_log(sequence, project_id, operation_id)` · `research_module.dart:57,410` —— **仅导入操作**，与投影无关。

### 1.3 询价（宿主触发器 + 领域字段日志）

- **`ModuleChangeLog`**：`InquiryPlugin.schema` v2 · `apps/muyon/lib/app/inquiry_plugin.dart:62–125`
  - 对表 `supplier` / `inquiry` / `quotation` / `project` / `project_item` 建 AFTER INSERT/UPDATE/DELETE 触发器（`:71–125`）
  - UPDATE 时若 `project_id` 作用域变化，先对旧 scope `delete` 再对 new upsert（`:100–109`）
- **未进 `ModuleChangeLog` 的实体表**（`entityTypes` 全集 · `supplier_core/store.dart:32–44`）：`contact`、`product`、`product_param`、`spec_request`、`spec_item`、`spec_response`；另 `attachment` 无版本行、无 Module 日志
- **领域 `change_log`**：`Store._log` / `_logRow` · `store.dart:502–542` —— **所有** `save`/`delete`/`restore` 的实体均写字段日志（含 contact/product/spec_*）；供交换与冲突，**不**驱动 `object_catalog`

### 1.4 原型（显式 record，无触发器）

- 建表时 `ModuleChangeLog.createTable` · `prototype_store.dart:40`
- 写入同事务 `record`：
  - 新建 `page` · `:192–197`
  - 新建 `version` · `:216–227`
  - `addFeedback` → `feedback` · `:270–275`
- 本体三类型 `page`/`version`/`feedback` 均覆盖；当前无删除 API（静态未见 delete 路径）

### 1.5 下游谁消费 `ModuleChangeLog`

| 消费者 | 位置 | 行为 |
|---|---|---|
| `ProjectionService.sync/watch` | `apps/muyon/lib/platform/projection_service.dart:53–132` | `since` → 写/删 `object_catalog`；`onApplied` 钩子 |
| `ModuleScopeSource.enumerate` | `scope_resolver.dart:148–189` | **无** `ScopeCandidates` 时，从 `object_catalog` 取 `inGlobalScope` 候选再 `resolve` 校验 |
| `ResearchRuntime` / `PrototypeRuntime` | `research_module.dart:125–136`；`prototype_module.dart:86` | 实现 **`ScopeCandidates`**，枚举**绕过** catalog（直读 Store）；catalog 仍服务知识失效与其它宿主 UI |
| `KnowledgeService.invalidateApplied` | `knowledge_service.dart:78–110`；挂接 `bootstrap.dart:303` | 仅对 **delete** 或 `summary=='revoked'` 删知识索引副本 |
| 本体卡片 | `inquiry_ontology_card_adapter.dart` | 读时走 scope + **模块库真值**；不直接读 change log，但选定对象常依赖 catalog 发现 |

推测：助手「最新状态」的权威路径是模块 `resolve`/`read_object`，不是 catalog 摘要；catalog 缺口主要伤 **发现/列表/删除后的知识失效**，以及依赖 catalog 的模块（询价无 `ScopeCandidates`）。

---

## 2. 写入入口 × 对象类型 × 是否进日志 × 后果

说明：效应「是否进 ModuleChangeLog」指宿主投影日志；领域 `change_log` 另注。

### 2.1 科研

| 写入入口 | 文件:行（代表） | 写的对象 | ModuleChangeLog？ | 下游 | 不进日志时的后果 |
|---|---|---|---|---|---|
| `saveNote`（Store） | `store.dart:396–435` | `note` INSERT（± `setNoteEntry`） | **否**（Store 层） | UI `reader_page:445`；`ResearchServices.saveNote` | UI/服务创建的 note **不进** catalog；助手全局发现不到（note 本就不在 `scopeCandidates` / `inGlobalScope:false`） |
| `research.save_note` 工具 | `module_tools.dart:191–223` | 同上 + **显式** `record(note)` | **是**（仅工具路径） | 投影、工具回执 `objectRefs` | 与 UI 路径不一致：同 API 不同日志覆盖 |
| `setNoteEntry` | `store.dart:373–385`；UI `reader_page:492`；services `:90–91` | `notes.entry_id` UPDATE | **否** | 投影无事件；`resolve` digest 含整行 JSON（`:494–497`）会变 | 钉 digest 的后续写会因 `requireCurrent` 失败（并发保护仍在）；catalog 摘要（若曾入库）不刷新；助手若缓存旧 note 视图可能漏 entry 关联——**读真值可对齐，发现/变更通知落后** |
| `saveProject` | `store.dart:387–395`；UI `workbench_app:698` | `projects.question/next_step` | **否** | `scopeCandidates` 仍列出 project；digest=`sha256(title,question,nextStep)`（`:467–469`） | 发现不依赖 catalog（有 ScopeCandidates）；catalog **从未**有 project 行；摘要/知识删失效路径空缺 |
| 导入 `INSERT projects` | `exchange.dart:319–320,:799–800`；package `:567` | `project` 创建 | **否** | 同上；子对象 documents/entries/… 有触发器 | 新项目靠 ScopeCandidates 可见；catalog 无 project |
| `insertBinding` / `confirmBinding` / 导入重算绑定 | `store.dart:333–368`；`exchange.dart:511–515` | `paper_bindings` | **否**（且非 ObjectType） | `list_bindings` 直读表 | 无 catalog 项可期；助手须读工具/UI；**不**造成 object_catalog 陈旧对象 |
| `saveTask` | `store.dart:437–470` | `tasks` INSERT 新修订 | **是**（tasks 触发器） | catalog/task 投影 | 无此缺口 |
| `acceptRun` / `assessRun` / `startManualRun` / `updateManualRun` | `store.dart:472–592` | `runs` | **是** | catalog | 无此缺口 |
| `addOutline` / section CRUD / cite / remove | `outline_store.dart:26–139`；工具 `add_outline` | `sections`/`outline` | **是** | catalog | 无此缺口 |
| `CardStore.save` / `registerDocument` / `deleteDocument` | `cards/card_store.dart`（经 rk_* 表） | `card` / `document` | **是**（rk 触发器） | catalog；知识删 | 无此缺口（静态） |
| 导入 documents/entries/tasks/runs/… | `exchange.dart` 多处 INSERT/UPDATE/DELETE | 已跟踪表 | **是**（同行触发器，与导入事务同提交） | catalog | 同事务；项目行本身仍缺 |

### 2.2 询价

| 写入入口 | 代表位置 | 写的对象 | ModuleChangeLog？ | 领域 change_log？ | 后果（若不进 Module） |
|---|---|---|---|---|---|
| `Store.save/delete/restore` | `store.dart:378–478` | 任一 `entityTypes` | 仅当类型 ∈ {supplier,inquiry,quotation,project,project_item}（触发器） | **是**（字段级） | 见下 |
| `inquiry.create_record` / `update_record` / `delete_record` / `restore_record` | `inquiry_record_tools.dart`；`_recordTypes` 含 **contact、product**（`:11–19`） | 含 contact/product | contact/product：**否** | 是 | **询价无 ScopeCandidates** → 新建/更新的 contact、product **不会进入** `object_catalog`，全局/工作区枚举发现不了；选定回执仍可临时拿 `objectRefs`；本体卡片依赖已 pinned 的对象 |
| `create_inquiry` / `record_quote` 等专用写 | `inquiry_write_tools.dart` | inquiry / quotation / … | **是**（类型在触发器集内） | 是 | 投影正常（测试亦断言 log · `inquiry_write_tools_test.dart:245–262`） |
| UI / 交换 / 导入合并 | 经 `Store` 或 raw SQL；触发器注释称覆盖 exchange/merge（`inquiry_plugin.dart:68–70`） | 五行类型 | **是** | 是 | 触发器与行同事务 |
| `product_param` / `spec_*` UI 或内部写 | Store | 这些类型 | **否** | 是 | 同样无法经 catalog 发现；当前通用写工具 `_recordTypes` **未**含这些类型（缺口对助手写工具面较小，对 UI→助手发现仍在） |

### 2.3 原型

| 写入入口 | 位置 | 对象 | ModuleChangeLog？ | 后果 |
|---|---|---|---|---|
| `importBuild` | `prototype_store.dart:153–244` | page（可选）+ version | **是**（同 `database.write`） | 无缺口 |
| `addFeedback` / 工具 | `:246–284`；module_tools | feedback | **是** | 无缺口 |
| 读工具 `list_pages` / `page_detail` | module_tools | — | n/a | ScopeCandidates 直读 Store |

---

## 3. 「写了但不进 ModuleChangeLog」缺口（按严重程度）

| 序 | 缺口 | 严重度 | 主要后果类别 |
|---|---|---|---|
| G1 | 询价 **`contact` / `product`** 可经通用写工具创建/改/删，但无 Module 触发器 | **高** | **助手发现/列表读到「没有」**（依赖 catalog 枚举）；删除后知识失效钩也收不到（若曾索引） |
| G2 | 科研 **`notes`**：Store/UI/`setNoteEntry` 不记日志；仅 `save_note` 工具记创建 | **高（对 REG-3d）** | 开放 `set_note_entry` 后变更不进投影；UI 批注与工具批注不一致；助手变更通知/目录落后（真值 `resolve` 仍新） |
| G3 | 科研 **`projects`**：创建（导入）与 `saveProject` 均不记日志 | **中高（对 REG-3d）** | 开放 `update_project` 后 catalog 无项目行/无摘要刷新；发现被 ScopeCandidates **部分缓解**；与 GB-2 §14.7 明确点名一致 |
| G4 | 询价 **`product_param` / `spec_request` / `spec_item` / `spec_response`** 无 Module 日志 | **中** | UI 写入后助手 catalog 发现不到；通用写工具暂未开放这些类型 |
| G5 | 科研 **`paper_bindings`** 无日志 | **低** | 非 ObjectType；读工具直查表即可；不污染 catalog |
| G6 | 原型 | **无**（当前写入面） | — |

「只影响界面刷新」：科研有 ScopeCandidates、询价列表多直读 Store 的页面——多数业务 UI **不**靠 `object_catalog` 刷新；界面侧严重度低于助手发现。

---

## 4. 每个缺口的最小补法与事务边界

### G1 询价 contact / product（及可选 G4 spec_*）

- **最小补法**：在 `InquiryPlugin` **新 migration**（v3）中，对 `contact`、`product`（建议顺带 `product_param`、`spec_*` 若希望与 `inGlobalScope: true` 一致）复用现有五类型触发器模板（`inquiry_plugin.dart:71–125`：scope 用 `json_extract(data,'$.project_id')`，supplier/contact/product 的 project_id 常为 null → `ProjectionService.globalProject` 语义）。迁移末尾 `INSERT … SELECT` 种子现有行。
- **事务边界**：**不改变**。触发器仍在行变更的同一 SQLite 语句/事务内插入 `muyon_change_log`（与现注释一致）。
- **不要**只在工具 handler 里 `record`：UI/导入/合并会漏（当初选触发器的原因 · `:68–70`）。

### G2 科研 notes

- **推荐最小补法（覆盖所有路径）**：新 schema migration **v10**：对 `notes` 表安装与 `track(...)` 同构的 INSERT/UPDATE/DELETE 触发器；`object_type='note'`，`native_project_id=(SELECT project_id FROM documents WHERE id=row.document_id)`，`summary=row.text`（或 substr），可选 digest；并对现有 notes 种子。然后可删除（或保留作冗余）`module_tools.dart:212–214` 的显式 `record`——重复 upsert 对投影幂等可接受，但双写易混淆，建议触发器落地后去掉显式调用。
- **更小但更脆的补法**：仅在 `WorkbenchStore.saveNote` / `setNoteEntry` 末尾、已有 `BEGIN`/`store.write` 内调用 `ModuleChangeLog.record`。能盖住 Store API；**盖不住**未来 raw SQL；导入若从不写 notes 则够用。事务边界：须保证调用方已在写事务中（`saveNote` 自管事务 · `:414–433`；`setNoteEntry` **无**自管事务——调用方须已在 `store.write`，与现 UI/services 一致）；**不**新开外层事务。
- **REG-3d**：开放 `set_note_entry` 前至少让 **UPDATE notes** 产生 Module 记录（触发器或 Store 内 record）。

### G3 科研 projects

- **推荐**：同一 v10 migration 对 `projects`：`object_type='project'`，`object_id=id`，`native_project_id=id`，`summary=title`，digest 可用与 `_resolve` 一致的表达式或先 NULL；种子现有项目。
- **或**：在 `saveProject` 与 `exchange`/`research_package` 的 `INSERT INTO projects` 同事务 `record`——路径多，易漏，不如触发器。
- **事务边界**：触发器不改边界；显式 `record` 必须落在既有 `write`/导入事务内。

### G5 paper_bindings

- **可不补 ModuleChangeLog**（无 ObjectType / 无 catalog 消费者）。若将来本体化绑定，再单开任务。

### 事务边界总表

| 补法 | 是否改变现有事务边界 |
|---|---|
| SQL 触发器（询价 v3 / 科研 v10） | 否（与业务行同提交/回滚） |
| Store/工具内 `ModuleChangeLog.record` | 否（前提：已在写事务内；`setNoteEntry` 勿单独新开事务除非与现 callers 对齐） |
| 仅改投影侧轮询业务表 | **否建议**（违背 ModuleChangeLog「记录与行同事务」设计 · API 注释 `:24–30`） |

---

## 5. 结论：开放 REG-3d 写工具前必须先补什么

对照 [GB-2 §13 汇总表](2026-10-11-research-write-contracts.md) 中建议 REG-3d 的项：

| REG-3d 操作 | 日志前置？ | 说明 |
|---|---|---|
| `research.list_notes` / `research.list_bindings` | **否** | 只读；直查 Store |
| `research.project.save`（`update_project`） | **是 — 必须先补 `project` → ModuleChangeLog** | 否则投影/目录无项目变更；与 GB-2 §14.7 一致。ScopeCandidates 不能代替变更流 |
| `research.note.set_entry` | **是 — 必须先补 `note` 的 UPDATE（及建议统一 INSERT）日志** | 与 §14.7 一致；仅靠 `save_note` 的创建 record **不够** |
| `research.task.save`（若同批） | **否（已有 tasks 触发器）** | 仍建议领域 `expectedRevision`（GB-2），与日志无关 |
| `research.binding.confirm`（若同批） | **否（非强制）** | 无 ObjectType；读路径不靠 catalog |

**回答 GB-2 §14 第 7 问**：开放 `set_note_entry` / `update_project` 时，**必须同批**补 note / project 的 `ModuleChangeLog`（当前未跟踪）。推荐科研 **v10 触发器 + 种子**，避免只补工具路径。

**不阻塞 REG-3d、但应单开跟进**：询价 G1（contact/product）——已对助手开放写、却无投影日志，严重度高于科研 project（科研尚有 ScopeCandidates）。

---

## 6. 未能静态确认

1. 生产环境是否存在依赖 `object_catalog` 的宿主 UI 列表（代码侧主要消费者是 `ModuleScopeSource` 与知识失效）；若有未检索到的 UI，科研 project 缺口的界面影响可能高于本文「中高」。
2. 询价 `contact`/`product` 的 `native_project_id` 在触发器里用 `json_extract($.project_id)` 时，实际 payload 是否总无该字段（推测多为 null → 全局哨兵）；未能对生产数据抽样确认。
3. 是否已有未合入的 inquiry v3 / research v10 草稿（本树未见）。
4. `KnowledgeService` 是否对 note/project 做过索引（当前 invalidation 只认 Module 删除流；科研文档索引多走 `research_search_adapter` 显式 import——推测 note/project 很少进知识库）。

---

## 7. 回报用元数据

- 分支：`review/gb-2-research-write-contracts`
- 交付物：`docs/reviews/2026-10-11-change-log-coverage.md`
- 执行：工程师2号 · 只读代码与写文档 · 未跑 Flutter
- 缺口（严重度序）：G1 询价 contact/product → G2 科研 notes → G3 科研 projects → G4 询价 spec_*/product_param → G5 绑定（可忽略）
- REG-3d 前置必须补：`project` + `note` 的 ModuleChangeLog（建议触发器 migration）
