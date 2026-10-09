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
- [x] 本机 host 导入/恢复回归及完整 supplier_core 套件实际运行；精确任务分支CI见交付证据。
- [ ] cloud smoke/云UI验收（用户暂缓）；真实PDF/OCR、原生权限及实机留最终待验。
- [x] 独立审查/任务分支提交；回退原导入页，保留草稿、来源、成功回执。

## 通用门禁

本任务已获授权，在独立任务分支实施；遵循[本批计划](../superpowers/plans/2026-10-08-ai-native-next-batch.md)。先运行新增行为回归取得有效失败，再最小实现、针对性复跑和独立审查；原始日志不提交，摘要进提交。云端 UI/业务流程验收通过并修复后可推进下一阶段；未覆盖能力登记待验收，原生及实机集中到 [R-1-AI-UI-final](R-1-AI-UI-final.md)，不逐片设实机前置。现有 Mac 截图例外只限已批准快照，不能自动沿用，见[备忘录](VERIFICATION-MEMO.md)。

## 实施状态（2026-10-09，进行中）

基线 develop `5a243c6abc8542edefc118d04a6b4b5b155633c2`；独立 worktree `/tmp/reg4b-import-pipeline-20261009`，分支 `task/reg-4b-inquiry-import-pipeline`。只提交/推任务分支，不合 develop/main。

- 询价运行时实现 ImportCapable，继续同一 AppState/Store/生命周期。插件把冻结来源、提取与人工覆盖、用途分组、候选选择、确认版本、逐记录回执存到已有 meta；无需新数据库、Agent内核或服务。确认绑定真实源/schema、draft revision、有效recordIds及选择实体版本；模型confirmed布尔不构成审批。
- 复用现有 FileGateway、DocumentParser、表格解析/extractOffers、planOffer/applyOffers、commitAiTask 和 ImportCoordinator。原领域方法新增可选逐记录观察回调，回传实际产品/供应商/报价ID与原规则判定的重复，领域规则保持原逻辑。领域写、源AI apply标记与回执同一原事务。
- `InquiryImportEntry` 要求人选询价功能后准备；`ImportReviewView` 使用UI-3b持久覆盖与共享renderer，首个目标是报价与材料主数据（复用原MaterialImportPage两种用途），支持分组、直接编辑、候选确认、有效记录选择、真实按钮提交、完成项只读和回执后续办。每组5条保持既有200节点上限。共享Field新增可选文本键盘，原默认数字键盘兼容。
- 生产任务中心的既有任务菜单新增“从文件导入业务”，进入独立上下文页：明确选询价插件，选原资料副本或原生文件，再选真实工作区/项目与报价/材料用途。已有任务的UI工作区索引提供持久草稿分组，返回后直接恢复插件草稿，不重新解析或重复入库。恢复与“查询提交回执”只查真实operationId并补原协调器host绑定，未知保持pending，不自动重放领域写。原ownerWorkspace事实过滤项目并在准备/提交前重核；host目标事实校验在插件最终写闭包内同步执行，与原领域事务之间无await，已有回执先返回。回退仍可使用原导入页，草稿/来源/回执保留。
- 范围核对：生产人类上下文导航属于本任务；UI-2a负责对象引用/文件阅读与返回锚点，并非本入口后继。全局assistant.plan_ui与Agent UI映射依赖UI-4b；C4负责软指南元数据，不要求本片开启全局planning/default flag或新增工具授权。旧AgentDispatch/startTool、procurement_import `(sessionId,callId)` 与AskPage不在本片修改，它们的幂等风险留独立修复项，不声称全路径幂等。
- TXT及MD公共表格夹具使用真实解析与SQLite入库；HTML/图像沿原解析器明确拒绝，测试无领域写或pending提交。PDF沿现有pdfrx文本路径，尚未验证本任务真实PDF；扫描PDF/OCR、原生文件权限待最终实机。不伪报五类格式全部通过。无新增付费模型、云服务；云UI用户暂缓，未跑cloud smoke/浏览器部署验收。
- 独审发现同批重复回执、失败Future缓存、候选选择后实体变化三Important；均补实际失败回归并以薄接线修复，最终增量只读复核无新增Critical/Important。原始日志仅 `/tmp/reg4b-evidence-20261009`，不提交。

- 纯材料名称/类别表、材料优先的混合报价表都先按主选用途调用原 offersFromWorkbook 参数，不能识别时只尝试已选其它用途；不合并两轮结果、不新建解析规则。两例在无AI配置环境都取得“误入模型”的有效RED，最终验证记录GREEN。项目采购清单 `list_import` 被正式任务明确列为复用项，属于REG-4b，不能整体归入UI-2a/C4后继。用户已明确保留原 `createProjectFromProposal` 的新建项目语义。清单准备阶段冻结新目标ID，不创建领域项目；首次确认才用原方法创建项目。未完成记录只续办本草稿真实创建回执所证明的同一项目，不提供向任意已有项目追加的入口。并发重复确认返回同一真实回执、仅创建一次。

## 本机验证摘要

最终23项 `inquiry_import_pipeline_test.dart` 全通过（真实Store、字段覆盖、人工按钮、候选/版本、同批去重、故障重试、源AI标记原子性、部分提交与恢复、所选原格式解析）；最终 inquiry/host analyze 无问题。前一完整串行 `scripts/ci.sh` 为8/8 analyze、doctor23、7/8 suites通过，host1181 passed/3 skipped、supplier_core482 passed/3 skipped；inquiry仅原有46截图失败（281 passed/1 skipped）。此轮在最后两项格式参数接线前执行，不能代称最终完整版本通过；最终完整host/候选截图另外串行复跑，结果见交付证据。

精确develop基线与候选独立新跑截图均46失败，失败集合、尺寸、差异像素、184PNG哈希一致；不是截图通过，也不沿用旧SHA例外。最终SHA的任务分支Linux CI单独核验。云UI、cloud smoke、PDF/OCR/真实原生文件权限及实机仍待验收；生产人类入口已接；global planning/defaultflag是UI-4b依赖，旧Agent callId幂等留独立修复项。list_import目标语义已由用户明确，清单适配已实现；云UI及最终原生验收仍待完成。原始日志仅本机临时证据目录。

## 生产入口续段验证（2026-10-09）

新增 `screens/inquiry_import_context.dart`、shell任务菜单；原13文件清单之外只增加新页与两个shell接线文件，避开AskPage/report/agent_dispatch并行修复。最小复用点：原Task/Workspace/KnowledgeService、原FilePicker、插件PreparedDraft、原UIWorkspace索引和ImportCoordinator；不造新Agent任务或业务项目。

本机实际30项针对性测试全通过：原23项，加任务中心真实菜单、准备/人工提交/返回恢复、已提交与未知回执查询、目标归属变化、项目候选过滤与最终写队列期间归属改变。菜单被shell busy挡住与他工作区项目写后才拒绝均取得实际失败回归后修复。独审新发现的项目归属Important及异步写队列窗口按原事实薄接线修复，最终独立只读复核无新增Critical/Important；host/inquiry analyze无问题。完整host重新串行运行，前一次中止不计通过；完整结果与任务分支精确CI见最终交付证据，不用先前SHA冒充本轮完整验证。原始日志只在 `/tmp/reg4b-evidence-20261009`，不提交。


## 项目清单收尾（2026-10-09）

按用户裁决接原 `list_import` 新建项目流程。新增插件 `list_import_pipeline.dart` 为已有 ImportPipeline 同库 part，复用其来源冻结、schema/修订校验、写入门禁、原meta存储和回执；继续原 `runAiTask/proposeFromList`、原候选/报价/数量与单位规则。原 `createProjectFromProposal` 仅增加可选预留ID和实际 itemID观察回调；其原保存循环供本草稿已创建项目的未完成项续办，未重写业务规则。项目/清单/AI apply标记/逐项回执同一原事务。

生产上下文功能“新建项目清单”要求未绑定询价项目的真实工作区，明确填写项目资料；准备和预览无领域写。`InquiryListReviewPage` 每组5项，共享renderer编辑原清单字段，显示将新建的项目名称、原候选型号/规格/单位、实际采用报价及供应商、原规则归一数量与单位备注。项目资料只在第一组统一编辑、创建后固定，避免跨组旧覆盖回退。选择有效项后原 ImportCoordinator 冻结真实 operationId 与确认集合；重复按钮/并发返回同一回执。持久UI工作区恢复草稿与真实回执引用，未知回执保留pending；查询只读领域回执并补原host绑定，无重放或重新解析。

正式规格§18.2的部分续办仅限本草稿原新建项目，检查原创建回执与项目版本；外部修改须重新核对，不能作为任意已有项目追加。§19.4回执包含成功/待补各项状态、错误与真实业务ID，已完成项保留原回执和业务ID。旧确认在来源/schema/草稿/所选实体或目标事实变化后拒绝，原模型许可与插件生命周期门禁继续生效。

独立全分支只读审查发现2项Important（跨组项目字段旧覆盖、同名候选识别及报价预览缺失）和1项Minor（待补项逐项状态）；均取得实际失败回归后修复。跨组6项在第二组创建后回第一组续办，同名不同型号及实际报价/供应商预览均经真实Store/人工页面验证。最终44项定向测试通过；测试仅使用公开本机HTTP夹具，无付费或云模型。完整本机、精确最终分支CI及截图基线对照结果见后续验证摘要。独审报告不声称修复后又进行第二次独审。原始日志留 `/tmp/reg4b-evidence-20261009`，不提交。


最终本机收尾验证：44项导入定向回归通过；完整host1204 passed/3 skipped、supplier_core482/3、module_api38、muyon_ui253、prototype40、research216、ui_preview11通过，doctor23通过。完整脚本最初发现新测试一处括号格式问题，已修复并单独复跑host analyze无问题；其它7包analyze无问题。完整inquiry281 passed/1 skipped/46截图失败，因此本机完整脚本本身未通过，不将其改称全绿。最终候选另在相同 `packages/inquiry_module` cwd、同一字体夹具重跑截图，与精确develop基线均46失败、184张PNG哈希全部一致（无新增/移除/改变）；不是截图通过或沿用旧SHA豁免。提交后精确HEAD的Linux CI另核，不用旧CI冒充本轮。云UI、cloud smoke、真实PDF/OCR/原生权限与最终实机仍待验收；任务分支不合develop/main。
