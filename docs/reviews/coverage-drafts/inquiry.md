# 询价模块能力覆盖清单初稿（GROK-2）

日期：2026-10-07 · 任务：[GROK-2](../../tasks/GROK-2.md) · 执行：工程师2号（grokbot）· 分支：`task/grok-2-coverage-drafts`
方法：只读扫描 `packages/supplier_core/lib` 中全部 `extension … on Store` 与 `Store` 类公开成员；**未**运行 Flutter / analyzer。
已注册工具依据：`apps/muyon/lib/platform/inquiry_write_tools.dart`（4 写）、`business_tools.dart`（循环注册 `agentTools` 12 读 + `inquiry.object`）。

扫描说明：静态正则曾把 `AgentTools` 内 `_name` 方法体中的 `get(...)` 误识别为公开成员；**已剔除**。最终成员数以 REG-4 的 `analyzer` 实测为准。

## 1. surfaces 表

| 库路径 | 类或扩展名 | 公开成员数 |
|---|---|---|
| `package:supplier_core/src/store.dart` | `Store` | 10 |
| `package:supplier_core/src/agent_tools.dart` | `AgentTools` | 1 |
| `package:supplier_core/src/assistant.dart` | `Assistant` | 2 |
| `package:supplier_core/src/attachments.dart` | `Attachments` | 3 |
| `package:supplier_core/src/background.dart` | `Background` | 1 |
| `package:supplier_core/src/budget.dart` | `Budgets` | 4 |
| `package:supplier_core/src/compare.dart` | `Compare` | 1 |
| `package:supplier_core/src/conflicts.dart` | `Conflicts` | 2 |
| `package:supplier_core/src/data_quality.dart` | `DataQuality` | 2 |
| `package:supplier_core/src/duplicates.dart` | `Duplicates` | 2 |
| `package:supplier_core/src/crypto_file.dart` | `EncryptedExchange` | 1 |
| `package:supplier_core/src/exchange.dart` | `Exchange` | 7 |
| `package:supplier_core/src/folder_sync.dart` | `FolderSyncing` | 1 |
| `package:supplier_core/src/compare.dart` | `History` | 1 |
| `package:supplier_core/src/inquiries.dart` | `Inquiries` | 8 |
| `package:supplier_core/src/list_import.dart` | `ListImport` | 2 |
| `package:supplier_core/src/material_import.dart` | `MaterialImport` | 7 |
| `package:supplier_core/src/merge.dart` | `Merge` | 3 |
| `package:supplier_core/src/spec_extract.dart` | `ParamExtraction` | 2 |
| `package:supplier_core/src/product_params.dart` | `ProductParams` | 4 |
| `package:supplier_core/src/project_export.dart` | `ProjectExport` | 3 |
| `package:supplier_core/src/project_pdf.dart` | `ProjectPdf` | 3 |
| `package:supplier_core/src/quote_excel.dart` | `QuoteExcel` | 3 |
| `package:supplier_core/src/record_query.dart` | `RecordQuery` | 2 |
| `package:supplier_core/src/budget.dart` | `Refresh` | 2 |
| `package:supplier_core/src/search.dart` | `Search` | 7 |
| `package:supplier_core/src/share.dart` | `Share` | 2 |
| `package:supplier_core/src/spec_deviation.dart` | `SpecDeviation` | 1 |
| `package:supplier_core/src/spec_match.dart` | `SpecMatch` | 2 |
| `package:supplier_core/src/spec_migration.dart` | `SpecMigration` | 2 |
| `package:supplier_core/src/spec_request.dart` | `SpecRequests` | 10 |
| `package:supplier_core/src/spec_response.dart` | `SpecResponses` | 9 |
| `package:supplier_core/src/supplier_sheet.dart` | `SupplierSheet` | 1 |
| `package:supplier_core/src/tables.dart` | `Tables` | 3 |
| `package:supplier_core/src/trash.dart` | `Trash` | 2 |
| `package:supplier_core/src/workbench.dart` | `WorkbenchQueries` | 1 |

**surface 数：36**（Store + 35 个 extension，与 ADR/GROK-1 一致）· **成员合计：117**

## 2. 成员清单

### `Store`（10）

| 成员 | 种类 | 位置 |
|---|---|---|
| `isHostManaged` | getter | `packages/supplier_core/lib/src/store.dart:283` |
| `close` | method | `packages/supplier_core/lib/src/store.dart:319` |
| `clockSeen` | method | `packages/supplier_core/lib/src/store.dart:344` |
| `transaction` | method | `packages/supplier_core/lib/src/store.dart:347` |
| `get` | method | `packages/supplier_core/lib/src/store.dart:360` |
| `save` | method | `packages/supplier_core/lib/src/store.dart:377` |
| `delete` | method | `packages/supplier_core/lib/src/store.dart:458` |
| `restore` | method | `packages/supplier_core/lib/src/store.dart:469` |
| `markResolved` | method | `packages/supplier_core/lib/src/store.dart:516` |
| `changes` | method | `packages/supplier_core/lib/src/store.dart:541` |

### `AgentTools`（1）

| 成员 | 种类 | 位置 |
|---|---|---|
| `runTool` | method | `packages/supplier_core/lib/src/agent_tools.dart:168` |

### `Assistant`（2）

| 成员 | 种类 | 位置 |
|---|---|---|
| `ask` | method | `packages/supplier_core/lib/src/assistant.dart:104` |
| `askWithEvidence` | method | `packages/supplier_core/lib/src/assistant.dart:126` |

### `Attachments`（3）

| 成员 | 种类 | 位置 |
|---|---|---|
| `addAttachment` | method | `packages/supplier_core/lib/src/attachments.dart:26` |
| `attachmentsOf` | method | `packages/supplier_core/lib/src/attachments.dart:45` |
| `attachment` | method | `packages/supplier_core/lib/src/attachments.dart:61` |

### `Background`（1）

| 成员 | 种类 | 位置 |
|---|---|---|
| `inBackground` | method | `packages/supplier_core/lib/src/background.dart:13` |

### `Budgets`（4）

| 成员 | 种类 | 位置 |
|---|---|---|
| `quoteOptions` | method | `packages/supplier_core/lib/src/budget.dart:114` |
| `quoteOptionsFor` | method | `packages/supplier_core/lib/src/budget.dart:138` |
| `budget` | method | `packages/supplier_core/lib/src/budget.dart:246` |
| `copyProject` | method | `packages/supplier_core/lib/src/budget.dart:298` |

### `Compare`（1）

| 成员 | 种类 | 位置 |
|---|---|---|
| `compareQuotes` | method | `packages/supplier_core/lib/src/compare.dart:75` |

### `Conflicts`（2）

| 成员 | 种类 | 位置 |
|---|---|---|
| `openConflicts` | method | `packages/supplier_core/lib/src/conflicts.dart:35` |
| `resolveConflict` | method | `packages/supplier_core/lib/src/conflicts.dart:72` |

### `DataQuality`（2）

| 成员 | 种类 | 位置 |
|---|---|---|
| `recordCounts` | method | `packages/supplier_core/lib/src/data_quality.dart:43` |
| `dataQuality` | method | `packages/supplier_core/lib/src/data_quality.dart:56` |

### `Duplicates`（2）

| 成员 | 种类 | 位置 |
|---|---|---|
| `similarSuppliers` | method | `packages/supplier_core/lib/src/duplicates.dart:67` |
| `similarProducts` | method | `packages/supplier_core/lib/src/duplicates.dart:96` |

### `EncryptedExchange`（1）

| 成员 | 种类 | 位置 |
|---|---|---|
| `exportEncryptedTo` | method | `packages/supplier_core/lib/src/crypto_file.dart:150` |

### `Exchange`（7）

| 成员 | 种类 | 位置 |
|---|---|---|
| `exportTo` | method | `packages/supplier_core/lib/src/exchange.dart:105` |
| `dailyBackup` | method | `packages/supplier_core/lib/src/exchange.dart:146` |
| `previewImport` | method | `packages/supplier_core/lib/src/exchange.dart:165` |
| `snapshotCounts` | method | `packages/supplier_core/lib/src/exchange.dart:169` |
| `replaceFrom` | method | `packages/supplier_core/lib/src/exchange.dart:180` |
| `importFrom` | method | `packages/supplier_core/lib/src/exchange.dart:260` |
| `checkAllReferences` | method | `packages/supplier_core/lib/src/exchange.dart:306` |

### `FolderSyncing`（1）

| 成员 | 种类 | 位置 |
|---|---|---|
| `syncWithFolder` | method | `packages/supplier_core/lib/src/folder_sync.dart:44` |

### `History`（1）

| 成员 | 种类 | 位置 |
|---|---|---|
| `priceHistory` | method | `packages/supplier_core/lib/src/compare.dart:194` |

### `Inquiries`（8）

| 成员 | 种类 | 位置 |
|---|---|---|
| `createInquiry` | method | `packages/supplier_core/lib/src/inquiries.dart:143` |
| `quoteForInquiry` | method | `packages/supplier_core/lib/src/inquiries.dart:202` |
| `inquiryMatrix` | method | `packages/supplier_core/lib/src/inquiries.dart:270` |
| `award` | method | `packages/supplier_core/lib/src/inquiries.dart:346` |
| `withdrawAward` | method | `packages/supplier_core/lib/src/inquiries.dart:384` |
| `exportInquirySheet` | method | `packages/supplier_core/lib/src/inquiries.dart:402` |
| `planInquirySheet` | method | `packages/supplier_core/lib/src/inquiries.dart:448` |
| `applyInquirySheet` | method | `packages/supplier_core/lib/src/inquiries.dart:511` |

### `ListImport`（2）

| 成员 | 种类 | 位置 |
|---|---|---|
| `proposeFromList` | method | `packages/supplier_core/lib/src/list_import.dart:68` |
| `createProjectFromProposal` | method | `packages/supplier_core/lib/src/list_import.dart:195` |

### `MaterialImport`（7）

| 成员 | 种类 | 位置 |
|---|---|---|
| `extractOffers` | method | `packages/supplier_core/lib/src/material_import.dart:100` |
| `planOffer` | method | `packages/supplier_core/lib/src/material_import.dart:137` |
| `sameSupplierId` | method | `packages/supplier_core/lib/src/material_import.dart:186` |
| `sameProductId` | method | `packages/supplier_core/lib/src/material_import.dart:189` |
| `applyOffers` | method | `packages/supplier_core/lib/src/material_import.dart:202` |
| `matchOrCreateContact` | method | `packages/supplier_core/lib/src/material_import.dart:316` |
| `offerError` | method | `packages/supplier_core/lib/src/material_import.dart:408` |

### `Merge`（3）

| 成员 | 种类 | 位置 |
|---|---|---|
| `mergeRoot` | method | `packages/supplier_core/lib/src/merge.dart:16` |
| `mergeInto` | method | `packages/supplier_core/lib/src/merge.dart:34` |
| `redirectMerged` | method | `packages/supplier_core/lib/src/merge.dart:63` |

### `ParamExtraction`（2）

| 成员 | 种类 | 位置 |
|---|---|---|
| `planParamFill` | method | `packages/supplier_core/lib/src/spec_extract.dart:67` |
| `applyParamFill` | method | `packages/supplier_core/lib/src/spec_extract.dart:110` |

### `ProductParams`（4）

| 成员 | 种类 | 位置 |
|---|---|---|
| `paramsOf` | method | `packages/supplier_core/lib/src/product_params.dart:115` |
| `setParam` | method | `packages/supplier_core/lib/src/product_params.dart:126` |
| `clearParam` | method | `packages/supplier_core/lib/src/product_params.dart:159` |
| `confirmParams` | method | `packages/supplier_core/lib/src/product_params.dart:166` |

### `ProjectExport`（3）

| 成员 | 种类 | 位置 |
|---|---|---|
| `exportQuoteSheet` | method | `packages/supplier_core/lib/src/project_export.dart:86` |
| `exportCostBudget` | method | `packages/supplier_core/lib/src/project_export.dart:141` |
| `exportInquiryList` | method | `packages/supplier_core/lib/src/project_export.dart:254` |

### `ProjectPdf`（3）

| 成员 | 种类 | 位置 |
|---|---|---|
| `quoteSheetPdf` | method | `packages/supplier_core/lib/src/project_pdf.dart:79` |
| `costBudgetPdf` | method | `packages/supplier_core/lib/src/project_pdf.dart:121` |
| `deviationPdf` | method | `packages/supplier_core/lib/src/project_pdf.dart:207` |

### `QuoteExcel`（3）

| 成员 | 种类 | 位置 |
|---|---|---|
| `exportQuotations` | method | `packages/supplier_core/lib/src/quote_excel.dart:83` |
| `planQuotationImport` | method | `packages/supplier_core/lib/src/quote_excel.dart:162` |
| `applyQuotationImport` | method | `packages/supplier_core/lib/src/quote_excel.dart:182` |

### `RecordQuery`（2）

| 成员 | 种类 | 位置 |
|---|---|---|
| `queryRecords` | method | `packages/supplier_core/lib/src/record_query.dart:40` |
| `relatedRecords` | method | `packages/supplier_core/lib/src/record_query.dart:105` |

### `Refresh`（2）

| 成员 | 种类 | 位置 |
|---|---|---|
| `refreshPlan` | method | `packages/supplier_core/lib/src/budget.dart:381` |
| `applyRefresh` | method | `packages/supplier_core/lib/src/budget.dart:399` |

### `Search`（7）

| 成员 | 种类 | 位置 |
|---|---|---|
| `quoteAttention` | method | `packages/supplier_core/lib/src/search.dart:54` |
| `searchProducts` | method | `packages/supplier_core/lib/src/search.dart:157` |
| `searchByName` | method | `packages/supplier_core/lib/src/search.dart:186` |
| `listQuotations` | method | `packages/supplier_core/lib/src/search.dart:209` |
| `contactsOf` | method | `packages/supplier_core/lib/src/search.dart:241` |
| `productCategories` | method | `packages/supplier_core/lib/src/search.dart:256` |
| `categoryAttributes` | method | `packages/supplier_core/lib/src/search.dart:267` |

### `Share`（2）

| 成员 | 种类 | 位置 |
|---|---|---|
| `shareClosure` | method | `packages/supplier_core/lib/src/share.dart:25` |
| `exportSelection` | method | `packages/supplier_core/lib/src/share.dart:66` |

### `SpecDeviation`（1）

| 成员 | 种类 | 位置 |
|---|---|---|
| `deviationXlsx` | method | `packages/supplier_core/lib/src/spec_deviation.dart:72` |

### `SpecMatch`（2）

| 成员 | 种类 | 位置 |
|---|---|---|
| `productsOfClass` | method | `packages/supplier_core/lib/src/spec_match.dart:112` |
| `matchSpec` | method | `packages/supplier_core/lib/src/spec_match.dart:127` |

### `SpecMigration`（2）

| 成员 | 种类 | 位置 |
|---|---|---|
| `planAttributeMigration` | method | `packages/supplier_core/lib/src/spec_migration.dart:88` |
| `applyAttributeMigration` | method | `packages/supplier_core/lib/src/spec_migration.dart:156` |

### `SpecRequests`（10）

| 成员 | 种类 | 位置 |
|---|---|---|
| `createSpecRequest` | method | `packages/supplier_core/lib/src/spec_request.dart:306` |
| `draftsFromProject` | method | `packages/supplier_core/lib/src/spec_request.dart:340` |
| `specItemsOf` | method | `packages/supplier_core/lib/src/spec_request.dart:359` |
| `specRequests` | method | `packages/supplier_core/lib/src/spec_request.dart:370` |
| `deleteSpecRequest` | method | `packages/supplier_core/lib/src/spec_request.dart:381` |
| `restoreSpecRequest` | method | `packages/supplier_core/lib/src/spec_request.dart:391` |
| `saveClauses` | method | `packages/supplier_core/lib/src/spec_request.dart:422` |
| `chooseProduct` | method | `packages/supplier_core/lib/src/spec_request.dart:450` |
| `setClauseResponse` | method | `packages/supplier_core/lib/src/spec_request.dart:535` |
| `clearChoice` | method | `packages/supplier_core/lib/src/spec_request.dart:571` |

### `SpecResponses`（9）

| 成员 | 种类 | 位置 |
|---|---|---|
| `specItemsOfInquiry` | method | `packages/supplier_core/lib/src/spec_response.dart:212` |
| `responseSheet` | method | `packages/supplier_core/lib/src/spec_response.dart:227` |
| `planSpecResponses` | method | `packages/supplier_core/lib/src/spec_response.dart:270` |
| `applySpecResponses` | method | `packages/supplier_core/lib/src/spec_response.dart:320` |
| `responsesOf` | method | `packages/supplier_core/lib/src/spec_response.dart:356` |
| `checkResponse` | method | `packages/supplier_core/lib/src/spec_response.dart:367` |
| `supplierDeviationXlsx` | method | `packages/supplier_core/lib/src/spec_response.dart:393` |
| `addItemsToBudget` | method | `packages/supplier_core/lib/src/spec_response.dart:474` |
| `chosenCounts` | method | `packages/supplier_core/lib/src/spec_response.dart:504` |

### `SupplierSheet`（1）

| 成员 | 种类 | 位置 |
|---|---|---|
| `planSupplierSheet` | method | `packages/supplier_core/lib/src/supplier_sheet.dart:50` |

### `Tables`（3）

| 成员 | 种类 | 位置 |
|---|---|---|
| `supplierRows` | method | `packages/supplier_core/lib/src/tables.dart:86` |
| `productRows` | method | `packages/supplier_core/lib/src/tables.dart:129` |
| `quoteRows` | method | `packages/supplier_core/lib/src/tables.dart:183` |

### `Trash`（2）

| 成员 | 种类 | 位置 |
|---|---|---|
| `deletedRecords` | method | `packages/supplier_core/lib/src/trash.dart:12` |
| `referencesTo` | method | `packages/supplier_core/lib/src/trash.dart:33` |

### `WorkbenchQueries`（1）

| 成员 | 种类 | 位置 |
|---|---|---|
| `workbench` | method | `packages/supplier_core/lib/src/workbench.dart:50` |

## 3. operations 表

每个公开成员恰属一个操作。已有工具写真实 id；其余写 `建议新增工具` 或 `NotExposedKind`（理由 ≥ 15 字）。

| id | kind | members | 承载方式 |
|---|---|---|---|
| `inquiry.store.host_flag` | `internal` | `Store.isHostManaged` | notExposed: `notBusiness` — 标记库是否由宿主托管，属连接生命周期元数据。 |
| `inquiry.store.close` | `internal` | `Store.close` | notExposed: `notBusiness` — 关闭数据库连接，由宿主会话处置时调用。 |
| `inquiry.store.clock` | `internal` | `Store.clockSeen` | notExposed: `notBusiness` — 后台写入后刷新时钟下限，属并发辅助。 |
| `inquiry.store.transaction` | `internal` | `Store.transaction` | notExposed: `notBusiness` — 通用写事务封装，业务写应走具名操作而非裸 transaction。 |
| `inquiry.record.get` | `query` | `Store.get` | 已有工具: `inquiry.get`、`inquiry.object` |
| `inquiry.record.save` | `write` | `Store.save` | 已有工具（部分）: `inquiry.set_item_qty`、`inquiry.set_inquiry_status`（仅覆盖预算行数量与询价单状态）；通用 save 其余类型建议新增 `inquiry.save_record` 或按类型拆分 —— 见缺口 |
| `inquiry.record.delete` | `write` | `Store.delete` | 建议新增工具（尚未注册）: `inquiry.delete_record`；或 `humanOnly`（待 REG-4 确认不可逆删除策略） |
| `inquiry.record.restore` | `write` | `Store.restore` | 建议新增工具（尚未注册）: `inquiry.restore_record` |
| `inquiry.record.mark_resolved` | `write` | `Store.markResolved` | 建议新增工具（尚未注册）: `inquiry.mark_resolved` |
| `inquiry.record.changes` | `query` | `Store.changes` | 建议新增工具（尚未注册）: `inquiry.list_changes` |
| `inquiry.agent.run_tool` | `internal` | `AgentTools.runTool` | notExposed: `notBusiness` — 宿主把各 `inquiry.*` 读工具转发到此分发器；工具清单以 `agentTools` 注册名为准，不把 runTool 本身再注册为工具。 |
| `inquiry.assistant.ask` | `external` | `Assistant.ask`, `Assistant.askWithEvidence` | notExposed: `deferred(REG-4)` — 走模型/证据链的问答入口，与出站账本及网页取证边界未齐，暂不单开助手工具。 |
| `inquiry.attachment.add` | `write` | `Attachments.addAttachment` | 建议新增工具（尚未注册）: `inquiry.add_attachment` |
| `inquiry.attachment.query` | `query` | `Attachments.attachmentsOf`, `Attachments.attachment` | 建议新增工具（尚未注册）: `inquiry.list_attachments` |
| `inquiry.background` | `internal` | `Background.inBackground` | notExposed: `notBusiness` — 后台 isolate 执行器，供导入/同步等重活复用，非业务动作。 |
| `inquiry.budget.quote_options` | `query` | `Budgets.quoteOptions`, `Budgets.quoteOptionsFor` | 已有工具: `inquiry.quote_options`（对应 quoteOptions；quoteOptionsFor 为变体，待确认是否需第二工具） |
| `inquiry.budget.project` | `query` | `Budgets.budget` | 已有工具: `inquiry.project_budget` |
| `inquiry.budget.copy_project` | `write` | `Budgets.copyProject` | 建议新增工具（尚未注册）: `inquiry.copy_project` |
| `inquiry.budget.refresh` | `write` | `Refresh.refreshPlan`, `Refresh.applyRefresh` | 建议新增工具（尚未注册）: `inquiry.plan_refresh` / `inquiry.apply_refresh` |
| `inquiry.compare.quotes` | `query` | `Compare.compareQuotes` | 已有工具: `inquiry.compare_quotes` |
| `inquiry.compare.price_history` | `query` | `History.priceHistory` | 建议新增工具（尚未注册）: `inquiry.price_history`（compare_quotes 已内嵌部分历史，是否独立开放待确认） |
| `inquiry.conflicts.list` | `query` | `Conflicts.openConflicts` | 建议新增工具（尚未注册）: `inquiry.open_conflicts` |
| `inquiry.conflicts.resolve` | `write` | `Conflicts.resolveConflict` | 建议新增工具（尚未注册）: `inquiry.resolve_conflict` |
| `inquiry.data_quality` | `query` | `DataQuality.recordCounts`, `DataQuality.dataQuality` | 已有工具: `inquiry.data_quality` |
| `inquiry.duplicates` | `query` | `Duplicates.similarSuppliers`, `Duplicates.similarProducts` | 建议新增工具（尚未注册）: `inquiry.similar_suppliers` / `inquiry.similar_products` |
| `inquiry.exchange.export` | `external` | `Exchange.exportTo`, `Exchange.dailyBackup` | notExposed: `deferred(REG-4)` — 整库/日备份导出涉及外传与备份路径，待出站与人工确认策略。 |
| `inquiry.exchange.preview` | `query` | `Exchange.previewImport`, `Exchange.snapshotCounts`, `Exchange.checkAllReferences` | 建议新增工具或保持 humanOnly：导入预览/校验（待 REG-4） |
| `inquiry.exchange.replace` | `external` | `Exchange.replaceFrom` | notExposed: `dangerousIrreversible` — 覆盖整库，须由本人在“恢复”页确认并留安全备份（ADR §8.2 示例）。 |
| `inquiry.exchange.import` | `external` | `Exchange.importFrom` | notExposed: `deferred(REG-4)` — 从快照合并导入，外部内容污染风险，暂不开放助手。 |
| `inquiry.exchange.encrypted_export` | `external` | `EncryptedExchange.exportEncryptedTo` | notExposed: `secretHandling` — 加密导出涉及密钥材料与外传，须人工在安全流程中完成。 |
| `inquiry.folder_sync` | `external` | `FolderSyncing.syncWithFolder` | notExposed: `deferred(REG-4)` — 与文件夹双向同步，边界同交换类，暂不开放。 |
| `inquiry.create` | `write` | `Inquiries.createInquiry` | 已有工具: `inquiry.create_inquiry` |
| `inquiry.record_quote` | `write` | `Inquiries.quoteForInquiry` | 已有工具: `inquiry.record_quote` |
| `inquiry.matrix` | `query` | `Inquiries.inquiryMatrix` | 已有工具: `inquiry.inquiry_matrix` |
| `inquiry.award` | `write` | `Inquiries.award`, `Inquiries.withdrawAward` | 建议新增工具（尚未注册）: `inquiry.award` / `inquiry.withdraw_award` |
| `inquiry.sheet.export` | `external` | `Inquiries.exportInquirySheet` | 建议新增工具或 `humanOnly`：导出询价单表格到文件（待 REG-4 确认效应） |
| `inquiry.sheet.import` | `write` | `Inquiries.planInquirySheet`, `Inquiries.applyInquirySheet` | 建议新增工具（尚未注册）: `inquiry.plan_inquiry_sheet` / `inquiry.apply_inquiry_sheet` |
| `inquiry.list_import` | `write` | `ListImport.proposeFromList`, `ListImport.createProjectFromProposal` | 建议新增工具（尚未注册）: `inquiry.propose_from_list` / `inquiry.create_project_from_proposal`；或部分 humanOnly |
| `inquiry.material.extract` | `query` | `MaterialImport.extractOffers`, `MaterialImport.planOffer`, `MaterialImport.offerError` | 建议新增工具（尚未注册）: `inquiry.extract_offers` 等（解析/计划/校验，未写库） |
| `inquiry.material.match_ids` | `query` | `MaterialImport.sameSupplierId`, `MaterialImport.sameProductId` | 建议新增工具或并入 extract/plan；精确匹配辅助 |
| `inquiry.material.apply` | `write` | `MaterialImport.applyOffers`, `MaterialImport.matchOrCreateContact` | 建议新增工具（尚未注册）: `inquiry.apply_offers`；matchOrCreateContact 写联系人，可并入或拆分 |
| `inquiry.merge` | `write` | `Merge.mergeRoot`, `Merge.mergeInto`, `Merge.redirectMerged` | 建议新增工具（尚未注册）: `inquiry.merge_*`；不可逆合并，也可标 `dangerousIrreversible`/`humanOnly`（待 REG-4） |
| `inquiry.params.query` | `query` | `ProductParams.paramsOf` | 建议新增工具（尚未注册）: `inquiry.params_of` |
| `inquiry.params.set` | `write` | `ProductParams.setParam`, `ProductParams.clearParam`, `ProductParams.confirmParams` | 建议新增工具（尚未注册）: `inquiry.set_param` / `clear_param` / `confirm_params` |
| `inquiry.export.project_sheets` | `external` | `ProjectExport.exportQuoteSheet`, `ProjectExport.exportCostBudget`, `ProjectExport.exportInquiryList` | 建议新增工具或 `humanOnly`：本机表格导出（待 REG-4 确认是否开放 export 效应） |
| `inquiry.export.pdf` | `external` | `ProjectPdf.quoteSheetPdf`, `ProjectPdf.costBudgetPdf`, `ProjectPdf.deviationPdf` | 建议新增工具或 `humanOnly`：本机 PDF 导出 |
| `inquiry.export.deviation_xlsx` | `external` | `SpecDeviation.deviationXlsx` | 建议新增工具或 `humanOnly`：偏离表 xlsx 导出 |
| `inquiry.quote_excel.export` | `external` | `QuoteExcel.exportQuotations` | 建议新增工具或 `humanOnly`：报价 Excel 导出 |
| `inquiry.quote_excel.import` | `write` | `QuoteExcel.planQuotationImport`, `QuoteExcel.applyQuotationImport` | 建议新增工具（尚未注册）: `inquiry.plan_quote_import` / `inquiry.apply_quote_import`（ADR §8.2 示例） |
| `inquiry.query.records` | `query` | `RecordQuery.queryRecords` | 已有工具: `inquiry.query` |
| `inquiry.query.related` | `query` | `RecordQuery.relatedRecords` | 已有工具: `inquiry.related` |
| `inquiry.search.attention` | `query` | `Search.quoteAttention` | 建议新增工具（尚未注册）: `inquiry.quote_attention` |
| `inquiry.search.products` | `query` | `Search.searchProducts`, `Search.searchByName` | 已有工具（部分）: `inquiry.search`（按关键词搜物料/供应商/项目；与 searchProducts/searchByName 的精确映射待 REG-4 用 runTool 路径核对） |
| `inquiry.search.quotations` | `query` | `Search.listQuotations` | 建议新增工具（尚未注册）: `inquiry.list_quotations`；或由 query/related 覆盖 |
| `inquiry.search.contacts` | `query` | `Search.contactsOf` | 建议新增工具（尚未注册）: `inquiry.contacts_of` |
| `inquiry.search.categories` | `query` | `Search.productCategories`, `Search.categoryAttributes` | 已有工具（部分）: `inquiry.spec_classes`（参数字典）；与 category* 边界待确认 |
| `inquiry.share` | `external` | `Share.shareClosure`, `Share.exportSelection` | notExposed: `deferred(REG-4)` — 选择导出/分享闭包涉及外传范围，待策略。 |
| `inquiry.spec.products_of_class` | `query` | `SpecMatch.productsOfClass` | 建议新增工具或并入 `inquiry.match_item` / `spec_classes` |
| `inquiry.spec.match` | `query` | `SpecMatch.matchSpec` | 已有工具: `inquiry.match_item` |
| `inquiry.spec.migration` | `write` | `SpecMigration.planAttributeMigration`, `SpecMigration.applyAttributeMigration` | 建议新增工具（尚未注册）: `inquiry.plan_attribute_migration` / `apply_attribute_migration` |
| `inquiry.spec.param_fill` | `write` | `ParamExtraction.planParamFill`, `ParamExtraction.applyParamFill` | 建议新增工具（尚未注册）: `inquiry.plan_param_fill` / `apply_param_fill` |
| `inquiry.spec_request.create` | `write` | `SpecRequests.createSpecRequest` | 建议新增工具（尚未注册）: `inquiry.create_spec_request` |
| `inquiry.spec_request.query` | `query` | `SpecRequests.draftsFromProject`, `SpecRequests.specItemsOf`, `SpecRequests.specRequests` | 建议新增工具（尚未注册）: `inquiry.list_spec_requests` 等 |
| `inquiry.spec_request.delete_restore` | `write` | `SpecRequests.deleteSpecRequest`, `SpecRequests.restoreSpecRequest` | 建议新增工具（尚未注册）: `inquiry.delete_spec_request` / `restore_spec_request` |
| `inquiry.spec_request.clauses` | `write` | `SpecRequests.saveClauses`, `SpecRequests.chooseProduct`, `SpecRequests.setClauseResponse`, `SpecRequests.clearChoice` | 建议新增工具（尚未注册）: `inquiry.save_clauses` / `choose_product` / `set_clause_response` / `clear_choice` |
| `inquiry.spec_response.query` | `query` | `SpecResponses.specItemsOfInquiry`, `SpecResponses.responseSheet`, `SpecResponses.responsesOf`, `SpecResponses.checkResponse`, `SpecResponses.chosenCounts` | 建议新增工具（尚未注册）: `inquiry.spec_response_*` 只读族 |
| `inquiry.spec_response.apply` | `write` | `SpecResponses.planSpecResponses`, `SpecResponses.applySpecResponses` | 建议新增工具（尚未注册）: `inquiry.plan_spec_responses` / `apply_spec_responses` |
| `inquiry.spec_response.deviation_xlsx` | `external` | `SpecResponses.supplierDeviationXlsx` | 建议新增工具或 `humanOnly`：供应商偏离表导出 |
| `inquiry.spec_response.add_to_budget` | `write` | `SpecResponses.addItemsToBudget` | 建议新增工具（尚未注册）: `inquiry.add_items_to_budget` |
| `inquiry.supplier_sheet.plan` | `query` | `SupplierSheet.planSupplierSheet` | 建议新增工具（尚未注册）: `inquiry.plan_supplier_sheet` |
| `inquiry.tables.rows` | `query` | `Tables.supplierRows`, `Tables.productRows`, `Tables.quoteRows` | 建议新增工具或标 `notBusiness`（UI 表格数据源）；与 query/search 重复度待 REG-4 确认 |
| `inquiry.trash` | `query` | `Trash.deletedRecords`, `Trash.referencesTo` | 建议新增工具（尚未注册）: `inquiry.deleted_records` / `references_to` |
| `inquiry.workbench` | `query` | `WorkbenchQueries.workbench` | 建议新增工具（尚未注册）: `inquiry.workbench`；或由壳层专用、标 humanOnly |

**操作数：73**

### 已注册但无直接 Store 成员的工具（synthetic / 经 `runTool`）

| 工具 ID | 说明 |
|---|---|
| `inquiry.describe` | 本体描述；经 `AgentTools.runTool` → `_describe`，无单独 surface 成员 |
| `inquiry.spec_classes` | 参数字典；经 `runTool` → `_specClasses` |
| `inquiry.search` | 关键词搜索；经 `runTool` → `_search`，部分映射 `Search.*` |

REG-4 落地时这些工具应标 `synthetic` 或挂到 `AgentTools.runTool` 所属操作，并满足 ADR「孤儿工具」反向检查。

## 4. 缺口汇总

### 需要新增工具才能覆盖的操作（建议 ID 与效应）

写（`write`）示例：`inquiry.award`、`inquiry.withdraw_award`、`inquiry.resolve_conflict`、`inquiry.set_param`、`inquiry.create_spec_request`、`inquiry.apply_quote_import`、`inquiry.apply_offers`、`inquiry.copy_project`、`inquiry.delete_record`/`restore_record`、`inquiry.merge_*`、`inquiry.apply_refresh`、`inquiry.add_items_to_budget`、规格请求/响应族等（见上表「建议新增工具」行）。

读（`query`）示例：`inquiry.list_changes`、`inquiry.open_conflicts`、`inquiry.price_history`、`inquiry.workbench`、`inquiry.list_attachments`、Tables/Trash/SpecResponse 只读族等。

导出（`external`）多数标为待确认（新增 export 工具 vs `humanOnly`/`deferred`），勿在无出站账本时仓促开放。

### 归 `internal` / `notBusiness` / `dangerousIrreversible` / `secretHandling` / `deferred` 的成员及理由

- **internal/notBusiness**：`Store.isHostManaged/close/clockSeen/transaction`、`Background.inBackground`、`AgentTools.runTool`。
- **dangerousIrreversible**：`Exchange.replaceFrom`（整库覆盖）。
- **secretHandling**：`EncryptedExchange.exportEncryptedTo`。
- **deferred(REG-4)**：`Exchange.exportTo/dailyBackup/importFrom`、`FolderSyncing.syncWithFolder`、`Share.*`、`Assistant.ask*`。
- **Store.save**：已被 2 个写工具部分覆盖；其余实体类型的通用写入策略待 REG-4，避免「一个 save 打天下」绕过具名操作。

### 拿不准的归类（待 REG-4 确认）

- `Store.delete`/`restore`/`merge*`：开放写工具 vs `humanOnly`/`dangerousIrreversible`。
- 纯文件导出（ProjectExport/ProjectPdf/QuoteExcel.exportQuotations/SpecDeviation 等）是否计入业务覆盖并开放 `export` 效应。
- `Tables.*` 是否 `notBusiness`（UI 表格）还是正式 query 工具。
- `inquiry.search` / `spec_classes` 与 `Search.*` / `SpecMatch.productsOfClass` 的成员归属（避免双重计入或孤儿）。
- `Budgets.quoteOptionsFor` 与 `inquiry.quote_options` 是否一一对应。
- `MaterialImport.matchOrCreateContact` 并入 `apply_offers` 还是独立写操作。

### 统计（初稿）

- surfaces: 36
- members: 117
- operations: 73
- 建议新增工具相关的操作数（含「建议新增或 humanOnly」）: 46
- 已明确挂接现有工具的操作：create_inquiry、record_quote、set_item_qty/set_inquiry_status（部分 save）、get/object、query、related、compare_quotes、quote_options、project_budget、data_quality、match_item、inquiry_matrix 等
