# MuSpace 迁入架构审查

审查顺序：Planner → Architect → Critic。日期2026-10-03。只读角色 `/root/migration_architect`，已读取 installed architect prompt、上下文、五份规划和科研关键源码。科研HEAD复核为3e981a5002a604dfb6e28a7e3bf361962c34c09e。本记录不是产品实现、测试或执行授权。

## 第1轮：ITERATE

五份规划绑定：design SHA256 `59a76d254f775614232591648585733df1a7d7ac6a596154be820e5b9ed007d8`；prd `711820d5f4dfcd883efd210bf7fb91642687207a7336755dea0d769a96135ac6`；reuse-matrix `2ef9f2dba06916bc9e6d709d4237e1ba74132b6ecac28c0aceb9b2f4281dbd88`；implementation `e2ad3228d7032a7bd542cd178256861c64b78958dfb53e3503f135501a33eabb`；test-spec `95c68f35970f67312b1e059e2f7c875fd968c6c3b54e94b1a865c07946e7390c`。路径对应 docs/superpowers/specs 下三个同日 MuSpace 文件和 plans 下实施计划、research-migration-test-spec。

方向可行，但三项阻塞未闭合：

1. **首次导入。** design:71–82、90–100、113–115要求预分配项目ID和提交后绑定，却只有已绑定scope。现有research-workbench/lib/core/exchange.dart:213–237要求intoProjectId已经存在，否则自动UUID。增加无绑定模块级prepareImport/commitImport，区分create(projectId)/refresh(projectId)。主库intent及分库receipt绑定operationId、targetProjectId、inputDigest、importKind；创建项目、领域数据、回执同事务。成功后激活binding，失败不出现可见空项目。验收每个提交点中断与异输入复用操作号拒绝。
2. **事务执行所有权。** 唯一连接不够。exchange.dart:263–310在BEGIN后await；store.dart:261–267、309–344自行BEGIN。每物理库统一事务队列，异步文件准备在事务外，同步事务内重新读状态；原方法拆成外部事务入口与内部操作，禁止套旧BEGIN。项目变更、receipt、变更序列一并提交。验收A导入时B保存笔记，A失败不回滚B；重复并发提交、迁移/关闭等待。
3. **外来任务归属。** exchange.dart:677–743自行按包projectId建项目，workbench_app.dart:227–236随即切换；需四分支：当前项目则导入；已属其他工作区则显式切换；未存在且当前无绑定则宿主intent+事务创建；当前已绑定另一项目则新工作区。不能改包projectId/taskId/revision。结果按taskId+taskRevision解析归属再核scope，不能只用全库存在检查（exchange.dart:959）。验收空设备收任务、四分支、重复与错误工作区导结果。

非阻塞勘误：implementation:31的结果附件hash应与结果包manifest一致，新生成日志不需与原任务附件hash相同。M1真实链→M2本地全流程→第二业务顺序通过；M1必须恢复绑定/receipt，完整对象目录可M2。

原则违反：资源管理仅明确连接未明确事务；完整业务迁入尚未映射旧任务自动建项目。

最强反方：整体嵌入旧应用及其项目/DB管理能最快保留可点击流程。取舍：全面改写延迟交付，原样保留资源所有权导致多入口/工作区冲突。综合：保留页面、codec、业务判断，仅修无绑定导入、统一事务入口、外来任务绑定三个必需接缝，不建设通用工作流引擎。

第1轮不进入实现；完成修订后必须重新Architect → Critic。

## 第2轮：APPROVE（2026-10-04，Asia/Shanghai）

角色 `/root/migration_architect` 顺序复审已修订五份规划。第1轮三个阻塞全部关闭，无新增必要阻塞。审查版本SHA256将在最终共识记录绑定。

| 缺口 | 关闭依据 |
|---|---|
| 首次无绑定导入 | design:65–94 ModuleRuntime；106–110 create/refresh、冻结输入、单活跃intent、完整receipt、同事务项目创建 |
| 事务交错及嵌套BEGIN | design:129 每库同步write队列、事务外准备/事务内重查、拆旧事务入口、业务/receipt/序列同提交 |
| 外来任务/结果归属 | design:154–156 四分支、原ID保留、恢复归属、taskRevision定位项目与scope、未知修订拒绝 |

implementation:15–23 将平台合同/原代码改造分给任务1/2；test-spec:25–29 将中断/异身份/并发/A失败不回滚B/四分支和错scope列为M1必验。implementation:31已修正附件对结果manifest，design:116–133区分目标/实际schema、事实/目录及主库事务内游标推进。

原则检查通过：平台资源、领域含义、闭环优先、复用实现、单事实源、证据分级保持一致。

WATCH（非阻塞）：实施任务2逐个核对旧BEGIN、事务内文件读取及页面直接写路径；不能只靠同步伪签名声称队列有效，必须运行已列测试。

最强反方：先单app目录划分，延后提包和治理，首阶段更快；已公平列为可行选项。取舍：立即复用速度与后续第二模块资源边界有成本张力。综合：仅建立闭环所需组装/绑定/事务，保留科研原实现，完整目录/第二业务/新增能力后置。

允许继续顺序Critic规划审查；不代表产品已实现、双端已验或执行授权。
