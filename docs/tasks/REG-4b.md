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

- [x] 新增上述失败与已有 import_recovery、accepted_research_import、inquiry_write_tools 回归；使用真实Store和确定回执。
- [x] 只做现有 plan/apply 到 ImportCapable/投影的薄接线，复用 UI-3b人工覆盖和共享renderer。
- [ ] 云浏览器操作预览/编辑/部分提交流程，云宿主测试断言领域实际结果；记录模拟/真实分界。
- [ ] `flutter test test/inquiry_import_pipeline_test.dart test/import_recovery_test.dart`（host）、对应supplier_core导入测试、cloud smoke；通过后推进导航/其它已可用任务。
- [x] 独立审查/任务分支提交；回退原导入页，保留草稿、来源、成功回执。

## 通用门禁

本任务已获授权，在独立任务分支实施；遵循[本批计划](../superpowers/plans/2026-10-08-ai-native-next-batch.md)。先运行新增行为回归取得有效失败，再最小实现、针对性复跑和独立审查；原始日志不提交，摘要进提交。云端 UI/业务流程验收通过并修复后可推进下一阶段；未覆盖能力登记待验收，原生及实机集中到 [R-1-AI-UI-final](R-1-AI-UI-final.md)，不逐片设实机前置。现有 Mac 截图例外只限已批准快照，不能自动沿用，见[备忘录](VERIFICATION-MEMO.md)。

## 实施状态（2026-10-09，进行中）

基线 develop `5a243c6abc8542edefc118d04a6b4b5b155633c2`；独立 worktree `/tmp/reg4b-import-pipeline-20261009`，分支 `task/reg-4b-inquiry-import-pipeline`。只提交/推任务分支，不合 develop/main。

- 询价运行时实现 ImportCapable，继续同一 AppState/Store/生命周期。插件把冻结来源、提取与人工覆盖、用途分组、候选选择、确认版本、逐记录回执存到已有 meta；无需新数据库、Agent内核或服务。确认绑定真实源/schema、draft revision、有效recordIds及选择实体版本；模型confirmed布尔不构成审批。
- 复用现有 FileGateway、DocumentParser、表格解析/extractOffers、planOffer/applyOffers、commitAiTask 和 ImportCoordinator。原领域方法新增可选逐记录观察回调，回传实际产品/供应商/报价ID与原规则判定的重复，领域规则保持原逻辑。领域写、源AI apply标记与回执同一原事务。
- `InquiryImportEntry` 要求人选询价功能后准备；`ImportReviewView` 使用UI-3b持久覆盖与共享renderer，首个目标是报价与材料主数据（复用原MaterialImportPage两种用途），支持分组、直接编辑、候选确认、有效记录选择、真实按钮提交、完成项只读和回执后续办。每组5条保持既有200节点上限。共享Field新增可选文本键盘，原默认数字键盘兼容。
- 本交付是可调用的文件上下文入口/投影与插件适配；生产上下文导航、全局Agent映射与默认开关未接，登记为后续接线依赖。旧AgentDispatch/startTool、procurement_import `(sessionId,callId)` 与AskPage不在本片修改；未声称解决它们的幂等或生产入口上线。回退仍可使用原导入页，插件草稿/来源/回执保留。
- TXT及MD公共表格夹具使用真实解析与SQLite入库；HTML/图像沿原解析器明确拒绝，测试无领域写或pending提交。PDF沿现有pdfrx文本路径，尚未验证本任务真实PDF；扫描PDF/OCR、原生文件权限待最终实机。不伪报五类格式全部通过。无新增付费模型、云服务；云UI用户暂缓，未跑cloud smoke/浏览器部署验收。
- 独审发现同批重复回执、失败Future缓存、候选选择后实体变化三Important；均补实际失败回归并以薄接线修复，最终增量只读复核无新增Critical/Important。原始日志仅 `/tmp/reg4b-evidence-20261009`，不提交。

- 纯材料名称/类别表、材料优先的混合报价表都先按主选用途调用原 offersFromWorkbook 参数，不能识别时只尝试已选其它用途；不合并两轮结果、不新建解析规则。两例在无AI配置环境都取得“误入模型”的有效RED，最终验证记录GREEN。项目采购清单 `list_import` 仍走原页面，其 ProposedLine/预算写入尚未迁本协议；若纳入第三功能，需另明确范围，不借本片重写其规则。

## 本机验证摘要

最终23项 `inquiry_import_pipeline_test.dart` 全通过（真实Store、字段覆盖、人工按钮、候选/版本、同批去重、故障重试、源AI标记原子性、部分提交与恢复、所选原格式解析）；最终 inquiry/host analyze 无问题。前一完整串行 `scripts/ci.sh` 为8/8 analyze、doctor23、7/8 suites通过，host1181 passed/3 skipped、supplier_core482 passed/3 skipped；inquiry仅原有46截图失败（281 passed/1 skipped）。此轮在最后两项格式参数接线前执行，不能代称最终完整版本通过；最终完整host/候选截图另外串行复跑，结果见交付证据。

精确develop基线与候选独立新跑截图均46失败，失败集合、尺寸、差异像素、184PNG哈希一致；不是截图通过，也不沿用旧SHA例外。最终SHA的任务分支Linux CI单独核验。云UI、cloud smoke、PDF/OCR/真实原生文件权限及实机仍待验收；生产路由/defaultflag/list_import迁移缺口保留，REG-4b整体仍标进行中。原始日志仅本机临时证据目录。
