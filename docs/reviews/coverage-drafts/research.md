# 科研模块能力覆盖清单初稿（GROK-2）

日期：2026-10-07 · 任务：[GROK-2](../../tasks/GROK-2.md) · 执行：工程师2号（grokbot）· 分支：`task/grok-2-coverage-drafts`
方法：只读源码扫描公开成员（方法/getter/setter，排除 `_` 前缀与 `@visibleForTesting`），**未**运行 Flutter / analyzer；成员集合供 REG-3 用 `analyzer` 实测对照。
依据：[ADR-0004](../../adr/0004-module-contract-v2.md) §8.2；[GROK-1](../2026-10-07-adr-0004-static-checks.md) §4/§7；Q10 用户已确认结论。

## 1. surfaces 表

| 库路径 | 类或扩展名 | 公开成员数 |
|---|---|---|
| `package:research_module/src/core/store.dart` | `WorkbenchStore` | 32 |
| `package:research_module/src/core/outline_store.dart` | `OutlineStore` | 8 |
| `package:research_module/src/core/exchange.dart` | `ResearchExchange` | 12 |
| `package:research_module/src/cards/card_store.dart` | `CardStore` | 15 |
| `package:research_module/src/research_services.dart` | `ResearchServices` | 12 |

**surface 数：5** · **成员合计：79**

## 2. 成员清单

### `WorkbenchStore`（32）

| 成员 | 种类 | 位置 |
|---|---|---|
| `write` | method | `packages/research_module/lib/src/core/store.dart:27` |
| `scoped` | method | `packages/research_module/lib/src/core/store.dart:41` |
| `checkedProject` | method | `packages/research_module/lib/src/core/store.dart:48` |
| `checkedObject` | method | `packages/research_module/lib/src/core/store.dart:55` |
| `migrations` | getter | `packages/research_module/lib/src/core/store.dart:127` |
| `schemaVersion` | getter | `packages/research_module/lib/src/core/store.dart:129` |
| `storedPath` | method | `packages/research_module/lib/src/core/store.dart:206` |
| `resolvePath` | method | `packages/research_module/lib/src/core/store.dart:208` |
| `close` | method | `packages/research_module/lib/src/core/store.dart:210` |
| `projects` | method | `packages/research_module/lib/src/core/store.dart:214` |
| `documents` | method | `packages/research_module/lib/src/core/store.dart:230` |
| `entries` | method | `packages/research_module/lib/src/core/store.dart:245` |
| `tasks` | method | `packages/research_module/lib/src/core/store.dart:260` |
| `taskFromRow` | method | `packages/research_module/lib/src/core/store.dart:267` |
| `taskRevision` | method | `packages/research_module/lib/src/core/store.dart:275` |
| `runs` | method | `packages/research_module/lib/src/core/store.dart:284` |
| `runFromRow` | method | `packages/research_module/lib/src/core/store.dart:291` |
| `notes` | method | `packages/research_module/lib/src/core/store.dart:299` |
| `bindings` | method | `packages/research_module/lib/src/core/store.dart:317` |
| `insertBinding` | method | `packages/research_module/lib/src/core/store.dart:333` |
| `confirmBinding` | method | `packages/research_module/lib/src/core/store.dart:345` |
| `applyBindingChoice` | method | `packages/research_module/lib/src/core/store.dart:359` |
| `setNoteEntry` | method | `packages/research_module/lib/src/core/store.dart:373` |
| `saveProject` | method | `packages/research_module/lib/src/core/store.dart:387` |
| `saveNote` | method | `packages/research_module/lib/src/core/store.dart:396` |
| `saveTask` | method | `packages/research_module/lib/src/core/store.dart:437` |
| `acceptRun` | method | `packages/research_module/lib/src/core/store.dart:472` |
| `assessRun` | method | `packages/research_module/lib/src/core/store.dart:479` |
| `startManualRun` | method | `packages/research_module/lib/src/core/store.dart:505` |
| `updateManualRun` | method | `packages/research_module/lib/src/core/store.dart:541` |
| `outline` | method | `packages/research_module/lib/src/core/store.dart:595` |
| `decode` | method | `packages/research_module/lib/src/core/store.dart:603` |

### `OutlineStore`（8）

| 成员 | 种类 | 位置 |
|---|---|---|
| `sections` | method | `packages/research_module/lib/src/core/outline_store.dart:9` |
| `addSection` | method | `packages/research_module/lib/src/core/outline_store.dart:26` |
| `updateSection` | method | `packages/research_module/lib/src/core/outline_store.dart:45` |
| `moveSection` | method | `packages/research_module/lib/src/core/outline_store.dart:66` |
| `deleteSection` | method | `packages/research_module/lib/src/core/outline_store.dart:85` |
| `addOutline` | method | `packages/research_module/lib/src/core/outline_store.dart:93` |
| `cite` | method | `packages/research_module/lib/src/core/outline_store.dart:103` |
| `removeOutline` | method | `packages/research_module/lib/src/core/outline_store.dart:136` |

### `ResearchExchange`（12）

| 成员 | 种类 | 位置 |
|---|---|---|
| `importResearch` | method | `packages/research_module/lib/src/core/exchange.dart:212` |
| `prepareResearch` | method | `packages/research_module/lib/src/core/exchange.dart:231` |
| `commitResearch` | method | `packages/research_module/lib/src/core/exchange.dart:261` |
| `exportClaimDrafts` | method | `packages/research_module/lib/src/core/exchange.dart:564` |
| `prepareTask` | method | `packages/research_module/lib/src/core/exchange.dart:723` |
| `commitTask` | method | `packages/research_module/lib/src/core/exchange.dart:764` |
| `importTask` | method | `packages/research_module/lib/src/core/exchange.dart:826` |
| `exportTask` | method | `packages/research_module/lib/src/core/exchange.dart:838` |
| `exportResult` | method | `packages/research_module/lib/src/core/exchange.dart:896` |
| `exportSkillExperiment` | method | `packages/research_module/lib/src/core/exchange.dart:964` |
| `importResult` | method | `packages/research_module/lib/src/core/exchange.dart:1006` |
| `exportReport` | method | `packages/research_module/lib/src/core/exchange.dart:1128` |

### `CardStore`（15）

| 成员 | 种类 | 位置 |
|---|---|---|
| `db` | getter | `packages/research_module/lib/src/cards/card_store.dart:180` |
| `requireProject` | method | `packages/research_module/lib/src/cards/card_store.dart:182` |
| `origin` | method | `packages/research_module/lib/src/cards/card_store.dart:188` |
| `keyFor` | method | `packages/research_module/lib/src/cards/card_store.dart:200` |
| `ensureKey` | method | `packages/research_module/lib/src/cards/card_store.dart:214` |
| `requireObject` | method | `packages/research_module/lib/src/cards/card_store.dart:231` |
| `registerDocument` | method | `packages/research_module/lib/src/cards/card_store.dart:240` |
| `deleteDocument` | method | `packages/research_module/lib/src/cards/card_store.dart:262` |
| `citationDocument` | method | `packages/research_module/lib/src/cards/card_store.dart:271` |
| `sourceAvailability` | method | `packages/research_module/lib/src/cards/card_store.dart:289` |
| `save` | method | `packages/research_module/lib/src/cards/card_store.dart:293` |
| `insertRevision` | method | `packages/research_module/lib/src/cards/card_store.dart:343` |
| `revision` | method | `packages/research_module/lib/src/cards/card_store.dart:364` |
| `get` | method | `packages/research_module/lib/src/cards/card_store.dart:378` |
| `list` | method | `packages/research_module/lib/src/cards/card_store.dart:394` |

### `ResearchServices`（12）

| 成员 | 种类 | 位置 |
|---|---|---|
| `citationResolver` | method | `packages/research_module/lib/src/research_services.dart:20` |
| `resolveCitation` | method | `packages/research_module/lib/src/research_services.dart:36` |
| `quoteLocator` | method | `packages/research_module/lib/src/research_services.dart:43` |
| `documents` | method | `packages/research_module/lib/src/research_services.dart:48` |
| `entries` | method | `packages/research_module/lib/src/research_services.dart:53` |
| `runs` | method | `packages/research_module/lib/src/research_services.dart:58` |
| `notes` | method | `packages/research_module/lib/src/research_services.dart:63` |
| `saveNote` | method | `packages/research_module/lib/src/research_services.dart:68` |
| `setNoteEntry` | method | `packages/research_module/lib/src/research_services.dart:90` |
| `acceptRun` | method | `packages/research_module/lib/src/research_services.dart:93` |
| `assessRun` | method | `packages/research_module/lib/src/research_services.dart:95` |
| `addOutline` | method | `packages/research_module/lib/src/research_services.dart:111` |

## 3. operations 表

每个公开成员恰属一个操作。`建议新增工具` 表示代码里尚未 `register`，见缺口汇总。

| id | kind | members | 承载方式 |
|---|---|---|---|
| `research.tx.write` | `internal` | `WorkbenchStore.write` | notExposed: `notBusiness` — 宿主 ManagedDatabase 写事务封装，非独立业务动作，助手不应直接调用。 |
| `research.scope` | `internal` | `WorkbenchStore.scoped`, `WorkbenchStore.checkedProject`, `WorkbenchStore.checkedObject` | notExposed: `notBusiness` — 工作区范围裁剪与校验辅助，由宿主/会话在调用写 API 前使用。 |
| `research.schema` | `internal` | `WorkbenchStore.migrations`, `WorkbenchStore.schemaVersion` | notExposed: `privilegedSystem` — 数据库 schema 元数据，仅迁移与诊断使用，不对助手开放。 |
| `research.paths` | `internal` | `WorkbenchStore.storedPath`, `WorkbenchStore.resolvePath` | notExposed: `notBusiness` — 快照路径相对/绝对换算，属存储细节而非业务操作。 |
| `research.close` | `internal` | `WorkbenchStore.close` | notExposed: `notBusiness` — 关闭库连接的生命周期钩子，由宿主处置会话时调用。 |
| `research.decode` | `internal` | `WorkbenchStore.decode` | notExposed: `notBusiness` — JSON 解码静态辅助，无业务语义，不单独对助手暴露。 |
| `research.query.projects` | `query` | `WorkbenchStore.projects` | 已有工具: `research.objects`（按范围检索项目/文档/条目；完整列表语义待 REG-3 确认是否够用） |
| `research.query.documents` | `query` | `WorkbenchStore.documents` | 已有工具: `research.objects`（同上；按项目列文档的专用工具待确认） |
| `research.query.entries` | `query` | `WorkbenchStore.entries` | 已有工具: `research.objects`（同上） |
| `research.query.tasks` | `query` | `WorkbenchStore.tasks`, `WorkbenchStore.taskFromRow`, `WorkbenchStore.taskRevision` | 建议新增工具（尚未注册）: `research.list_tasks` |
| `research.query.runs` | `query` | `WorkbenchStore.runs`, `WorkbenchStore.runFromRow` | 建议新增工具（尚未注册）: `research.list_runs` |
| `research.query.notes` | `query` | `WorkbenchStore.notes` | 建议新增工具（尚未注册）: `research.list_notes` |
| `research.query.bindings` | `query` | `WorkbenchStore.bindings` | 建议新增工具（尚未注册）: `research.list_bindings` |
| `research.query.outline_rows` | `query` | `WorkbenchStore.outline` | 建议新增工具（尚未注册）: `research.list_outline` |
| `research.binding.insert` | `write` | `WorkbenchStore.insertBinding` | 建议新增工具（尚未注册）: `research.insert_binding` |
| `research.binding.confirm` | `write` | `WorkbenchStore.confirmBinding`, `WorkbenchStore.applyBindingChoice` | 建议新增工具（尚未注册）: `research.confirm_binding` |
| `research.note.set_entry` | `write` | `WorkbenchStore.setNoteEntry` | 建议新增工具（尚未注册）: `research.set_note_entry` |
| `research.project.save` | `write` | `WorkbenchStore.saveProject` | 建议新增工具（尚未注册）: `research.save_project` |
| `research.note.save` | `write` | `WorkbenchStore.saveNote` | 建议新增工具（尚未注册）: `research.save_note` |
| `research.task.save` | `write` | `WorkbenchStore.saveTask` | 建议新增工具（尚未注册）: `research.save_task` |
| `research.run.accept` | `write` | `WorkbenchStore.acceptRun` | 建议新增工具（尚未注册）: `research.accept_run` |
| `research.run.assess` | `write` | `WorkbenchStore.assessRun` | 建议新增工具（尚未注册）: `research.assess_run` |
| `research.run.manual_start` | `write` | `WorkbenchStore.startManualRun` | 建议新增工具（尚未注册）: `research.start_manual_run` |
| `research.run.manual_update` | `write` | `WorkbenchStore.updateManualRun` | 建议新增工具（尚未注册）: `research.update_manual_run` |
| `research.outline.sections` | `query` | `OutlineStore.sections` | 建议新增工具（尚未注册）: `research.list_sections` |
| `research.outline.add_section` | `write` | `OutlineStore.addSection` | 建议新增工具（尚未注册）: `research.add_section` |
| `research.outline.update_section` | `write` | `OutlineStore.updateSection` | 建议新增工具（尚未注册）: `research.update_section` |
| `research.outline.move_section` | `write` | `OutlineStore.moveSection` | 建议新增工具（尚未注册）: `research.move_section` |
| `research.outline.delete_section` | `write` | `OutlineStore.deleteSection` | 建议新增工具（尚未注册）: `research.delete_section` |
| `research.outline.add` | `write` | `OutlineStore.addOutline` | 建议新增工具（尚未注册）: `research.add_outline` |
| `research.outline.cite` | `write` | `OutlineStore.cite` | 建议新增工具（尚未注册）: `research.cite` |
| `research.outline.remove` | `write` | `OutlineStore.removeOutline` | 建议新增工具（尚未注册）: `research.remove_outline` |
| `research.export.claim_drafts` | `external` | `ResearchExchange.exportClaimDrafts` | 建议新增工具（尚未注册）: `research.export_claim_drafts`（Q10 已确认开放为本机导出） |
| `research.export.report` | `external` | `ResearchExchange.exportReport` | 建议新增工具（尚未注册）: `research.export_report`（Q10 已确认开放为本机导出） |
| `research.export.task` | `external` | `ResearchExchange.exportTask` | notExposed: `deferred(REG-3)` — 任务包涉及设备边界与外传，Q10 确认暂不开放，待 Exchange/出站账本齐套。 |
| `research.export.result` | `external` | `ResearchExchange.exportResult` | notExposed: `deferred(REG-3)` — 运行结果包可再外发，Q10 确认暂不开放给助手。 |
| `research.export.skill_experiment` | `external` | `ResearchExchange.exportSkillExperiment` | notExposed: `deferred(REG-3)` — 技能/实验包边界同任务包，Q10 确认暂不开放。 |
| `research.import.research` | `external` | `ResearchExchange.importResearch`, `ResearchExchange.prepareResearch`, `ResearchExchange.commitResearch` | notExposed: `deferred(REG-3)` — 整项目导入体量大且难自动审查，Q10 确认暂不开放。 |
| `research.import.task` | `external` | `ResearchExchange.importTask`, `ResearchExchange.prepareTask`, `ResearchExchange.commitTask` | notExposed: `deferred(REG-3)` — 任务包导入属外部输入写库，Q10 确认暂不开放。 |
| `research.import.result` | `external` | `ResearchExchange.importResult` | notExposed: `deferred(REG-3)` — 外部结果包可污染本机库，Q10 确认暂不开放。 |
| `research.card.db` | `internal` | `CardStore.db` | notExposed: `notBusiness` — 直接暴露底层 Database，属实现细节，不得对助手开放。 |
| `research.card.require` | `internal` | `CardStore.requireProject`, `CardStore.requireObject` | notExposed: `notBusiness` — 作用域断言辅助，由卡片写路径内部使用。 |
| `research.card.origin` | `internal` | `CardStore.origin` | notExposed: `notBusiness` — 对象源标识辅助，非独立业务动作。 |
| `research.card.keys` | `write` | `CardStore.ensureKey`, `CardStore.keyFor` | 建议新增工具（尚未注册）: `research.ensure_card_key`；`keyFor` 为只读查找，可并入同一查询工具。 |
| `research.card.document.register` | `write` | `CardStore.registerDocument` | 建议新增工具（尚未注册）: `research.register_card_document` |
| `research.card.document.delete` | `write` | `CardStore.deleteDocument` | 建议新增工具（尚未注册）: `research.delete_card_document` |
| `research.card.citation` | `query` | `CardStore.citationDocument`, `CardStore.sourceAvailability` | 建议新增工具（尚未注册）: `research.card_citation` |
| `research.card.save` | `write` | `CardStore.save`, `CardStore.insertRevision` | 建议新增工具（尚未注册）: `research.card_save` |
| `research.card.get` | `query` | `CardStore.revision`, `CardStore.get`, `CardStore.list` | 建议新增工具（尚未注册）: `research.card_get` / `research.list_cards` |
| `research.services.citation` | `query` | `ResearchServices.citationResolver`, `ResearchServices.resolveCitation`, `ResearchServices.quoteLocator` | 建议新增工具（尚未注册）: `research.resolve_citation`（薄封装；与 CardStore 引用能力边界待 REG-3 确认） |
| `research.services.query` | `query` | `ResearchServices.documents`, `ResearchServices.entries`, `ResearchServices.runs`, `ResearchServices.notes` | 建议新增工具或并入 `research.objects` 的 scoped 变体；与 WorkbenchStore 同名读方法重复，归类边界待确认 |
| `research.services.note.save` | `write` | `ResearchServices.saveNote`, `ResearchServices.setNoteEntry` | 建议新增工具与 `research.save_note` / `set_note_entry` 共用 handler（转发 WorkbenchStore） |
| `research.services.run` | `write` | `ResearchServices.acceptRun`, `ResearchServices.assessRun` | 建议新增工具与 `research.accept_run` / `assess_run` 共用 |
| `research.services.outline.add` | `write` | `ResearchServices.addOutline` | 建议新增工具与 `research.add_outline` 共用 |

**操作数：54**

## 4. 缺口汇总

### 需要新增工具才能覆盖的操作

- `research.list_tasks` / `list_runs` / `list_notes` / `list_bindings` / `list_outline`（query）
- `research.insert_binding` / `confirm_binding` / `set_note_entry` / `save_project` / `save_note` / `save_task` / `accept_run` / `assess_run` / `start_manual_run` / `update_manual_run`（write）
- `research.export_report` / `research.export_claim_drafts`（external/export，对应已确认开放的导出）
- `research.add_section` 等提纲写工具；`research.card_save` 等卡片写工具

### 归 `internal` / `notBusiness` / `privilegedSystem` 的成员及理由

- 见上表 `kind: internal` 各行的 `notExposed` 理由（均 ≥ 15 字）。
- 摘要：WorkbenchStore.write/scoped/checked*/migrations/schemaVersion/storedPath/resolvePath/close/decode；CardStore.db/requireProject/requireObject/origin

### 拿不准的归类（待 REG-3 确认）

- ResearchServices 与 WorkbenchStore/OutlineStore 同名写/读成员是否作为独立 surface 双登记，或把 ResearchServices 整面标 `notBusiness`（薄转发）——待 REG-3 用 analyzer 与产品口径确认。
- `research.objects` 是否足以承载 projects/documents/entries 的列表示语义，还是必须拆专用 list 工具。
- CardStore.keyFor（只读）与 ensureKey（可能插入）是否拆成 query+write 两个操作更合适。
- 宿主设备桥（research_task_bridge / accepted_research_imports）非 module surface，是否在覆盖清单用 synthetic/deferred 占位——待 REG-3。

### 统计（初稿）

- surfaces: 5
- members: 79
- operations: 54
- 建议新增工具的操作数（含读写/导出）: 36
- deferred(REG-3) 操作数: 6
