# MuSpace 科研迁入验收规范（修订 3）

本文件为待实施验收设计，当前未运行任何测试。关联[具体设计](../specs/2026-10-03-muspace-v0.1-design.md)与[任务计划](2026-10-03-muspace-v0.1-implementation.md)。

## M1 必须满足的结果

| ID | 断言 | 证据 |
|---|---|---|
| A1 | 仅启动 MuSpace 就能创建/切换工作区并进入真实科研六区，项目绑定无自动 fallback | 路由/双工作区测试 + 两端界面记录 |
| A2 | 真研究成果与论文导入后可阅读、保存现有页码引句笔记，退出重开保留 | 真实包来源/许可/内容hash、截图、结构对照 |
| A3 | 任务导出→外部设备执行→结果返入→人工评估和接纳→关联提纲→含证据报告导出 | taskId/revision/runId、包hash、操作记录和报告 |
| A4 | 同源重导入不丢人工笔记、绑定、提纲及接纳状态；坏包不会报告成功 | 重导入前后领域对象断言、错误包结果 |
| A5 | macOS/Android 在无模型及断网条件完成本地动作；跨设备传包走用户选择渠道 | 应用commit、设备OS/build、步骤日志；无设备标未验 |

M1 自动测试可用合成夹具，但 A2/A3 的最终证据必须是真实项目/执行产物。外部执行不是要求 Agent 自动远程调度；手工运行且返回符合当前任务/结果格式即可。文件 receipt、导入成功、人工接纳、科学结论分开记录。

## 分层测试矩阵

| 层次 | 位置（拟建/迁入） | 必测情形 | 阶段 |
|---|---|---|---|
| Unit | apps/muspace/test/module_registry_test.dart | 重复moduleId/依赖缺失/循环拒绝，可选服务缺失不阻断 | M1 |
| Unit | apps/muspace/test/storage_manager_test.dart | 一库单owner；schema超前拒绝；迁移失败回滚；foreign_keys开启；重复open去重 | M1 |
| Unit | apps/muspace/test/workspace_binding_test.dart | 两workspace绑定不同字符串projectId；缺绑定/已失效不选首项目；ID不可猜转换 | M1 |
| Unit | packages/research_module/test/research_services_test.dart | 所有document/note/run操作核对project归属；UI和工具适配器同规则 | M1 |
| Integration | apps/muspace/test/storage_recovery_test.dart | 无绑定create/有绑定refresh；intent单活跃create；主库intent前/后、本库提交前/后、主库激活前/后中断；恢复不重复项目、不显示空项目；同operationId异digest/目标/类型拒绝；冻结输入重试不重读已变路径 | M1 |
| Integration | apps/muspace/test/transaction_queue_test.dart | A导入异步prepare时B存笔记；A失败不回滚B；并发重复commit只一次；无嵌套BEGIN/事务内await；迁移和关闭等待队列，关闭后拒绝新写 | M1 |
| Integration | packages/research_module/test/task_scope_test.dart | 空设备接任务；当前项目/另一工作区/空工作区新项目/已绑定另一项目建新工作区四分支；原ID不变；重复与同修订异内容；未知taskRevision结果拒绝；错scope与晚到回调不串写 | M1 |
| Integration | packages/research_module/test/exchange_test.dart | 研究/skill/task/result现有格式；路径/hash/size检查；同run回导/修订冲突；未知源字段保真 | M1主链，M2完整 |
| Integration | apps/muspace/test/file_recovery_test.dart | staging中断、文件已落盘DB未提交、缺附件明确失败，临时数据可对账 | M1 |
| Integration | apps/muspace/test/projection_recovery_test.dart | 本库提交主库未更新，重放幂等，删除传播，重建目录；打开再核领域事实 | M2 |
| UI | packages/research_module/test/workbench_test.dart等迁入 | 六区入口、Reader、评估/接纳、提纲/关系跳转；200%字号/窄屏可触达关键动作 | M1主链，M2完整 |
| E2E | apps/muspace/integration_test/research_journey_test.dart | A1–A5；切换工作区期间导入/回调完成仍属原scope；重开持久化 | M1 |
| Observability | docs/acceptance/muspace-research-migration.md | module/version/schema/currentWorkspace/operationId及阶段可诊断；错误不记录全文/secret | M1 |

原科研测试迁入基线至少包括 core_test、workbench_test、research_skill_test、skill_ui_test、skill_bridge_test、reader_evidence_test、outline_notes_test、relations_test、run_comparison_test。LAN测试作为后续通信资产保留，不能因不开放明文listener删除该迁入跟踪项。

## 真场景记录模板

每次记录：MuSpace commit/build、迁入源HEAD、设备/OS、fixture来源及hash、开始结束时间、步骤、期望、实际、截图/产物路径、失败及复测。包内任务执行命令只由用户选择的执行环境运行，不因导入自动执行。

导入前后对照 documents/notes/tasks/runs/sections/outline/relations 的有关 ID 与内容；不只比较行数。报告必须包含本次已接纳结果的引用，空报告不通过。结果附件hash对照结果manifest，任务身份/修订对照任务导出，新生成日志无需等于原任务输入附件。重导入后人工笔记内容、对应文档身份和手工接纳保留。不同PDF不得因文件名一致替换已引用原文件；现有格式不支持的精确定位明确显示页级信息，不升级测试声明。

## M2 完整性清单

研究目录/ZIP、skill识别/源字段/重导入、论文绑定及歧义人工选择、PDF/Markdown、页码引句与研究条目笔记、任务导入导出/修订、手工run/结果导入导出/比较/评估/接纳、实验/claim草稿导出、提纲分节与证据关联、报告、关系导航全部有对应现有流程回归。缺项保持 open 并说明原因，不能用 M1 成功抹去。

## 停止与阻塞规则

M1 A1–A5 全部有当次证据可交付首闭环；M2 清单随后全部关闭方可称本地科研全迁入。坏包部分提交、跨项目写入、报告引用错对象、重开丢失任一发生均阻止相关里程碑交付。新 FTS/精确锚点/模型不可用不阻塞本期。缺真实研究包时可继续合成自动测试但 A2/A3 未验；缺设备/工具链时记录环境阻塞，完成不依赖设备的验证，不能替代实测。
