# REG-4b 上下文文件导入接线

## 目标、依赖与边界

依赖 REG-4a、UI-3b、UI-4a。先询价真实现有导入闭环；科研/原型沿 REG-3另迁，不阻塞首个询价目标。不重建解析/OCR或领域去重，不提前 REG-4c完整检索。

## 文件、接口与复用

复用 DocumentParser、FileGateway、ImportCoordinator、accepted_research_imports；supplier_core `material_import.dart` 的 planOffer/applyOffers 及 list_import、既有导入页面。在 `app/adapters/inquiry_module.dart` 接现有 `ImportCapable.prepareImport(SelectedInput,ImportTarget)`、`commitImport(PreparedImport,ImportIntent)`、`receipt(String)`；新增 `app/import_review_projection.dart` 与 host `test/inquiry_import_pipeline_test.dart`。不将工具输出中的 confirmed=true 当真实审批。

选插件→选功能→按既有 schema 分组→来源/字段预览→直接编辑→领域校验/重复与冲突→确认有效 recordIds→实际提交/回执。提交payload解析冻结draft revision及recordIds；operationId/幂等键来自原ImportCoordinator，不能由UIPlan编造；编辑后旧确认失效。ImportCoordinator既有 operationId/恢复不重复建设；源摘要、schema版本、人工覆盖与确认集合绑定到真实输入。

## 验收与测试

`choose_purpose_before_preview`、`edited_partial_import_preserves_receipts`：公共夹具3记录，1有效、1确定重复、1待补；人工改有效记录，确认仅有效集合，实际 Store新增1、重复跳过1、待补1；超时但成功先按 operationId 查回执，再补待补，不重放成功。`uncertain_duplicate_requires_choice`、`source_or_schema_change_invalidates_confirmation`保持可编辑差异。

TXT/MD/HTML/PDF/图像分别记录真实解析/部分可用/不可用。云 Web用公开预提取夹具模拟权限或OCR，UI清楚标识；云 Linux host可测真实领域存储与能运行的解析。原生OCR、真实文件权限和不支持的格式保留最终待验，不伪报五类真实输入均通过。

## 实施顺序

- [ ] 新增上述失败与已有 import_recovery、accepted_research_import、inquiry_write_tools 回归；使用真实Store和确定回执。
- [ ] 只做现有 plan/apply 到 ImportCapable/投影的薄接线，复用 UI-3b人工覆盖和共享renderer。
- [ ] 云浏览器操作预览/编辑/部分提交流程，云宿主测试断言领域实际结果；记录模拟/真实分界。
- [ ] `flutter test test/inquiry_import_pipeline_test.dart test/import_recovery_test.dart`（host）、对应supplier_core导入测试、cloud smoke；通过后推进导航/其它已可用任务。
- [ ] 独立审查/提交；回退原导入页，保留草稿、来源、成功回执。

## 通用门禁

本任务为待 leader 复核的派发草案，尚未开工；遵循[本批计划](../superpowers/plans/2026-10-08-ai-native-next-batch.md)。先运行新增行为回归取得有效失败，再最小实现、针对性复跑和独立审查；原始日志不提交，摘要进提交。云端 UI/业务流程验收通过并修复后可推进下一阶段；未覆盖能力登记待验收，原生及实机集中到 [R-1-AI-UI-final](R-1-AI-UI-final.md)，不逐片设实机前置。现有 Mac 截图例外只限已批准快照，不能自动沿用，见[备忘录](VERIFICATION-MEMO.md)。
