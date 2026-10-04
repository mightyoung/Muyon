# MuSpace 迁入计划 Critic 审查

日期2026-10-03。角色 `/root/migration_critic`，读取 installed critic prompt、上下文、五规划、第1轮已完成Architect报告，并抽查科研import/Store/outline源码。审查顺序已遵守Architect完成后再Critic；不是产品执行或验收。

## 第1轮：ITERATE

审查对象为Architect第1轮报告记录的同一五文件SHA256，期间未改变正文。目标/原则、替代选项、平台证据边界通过；premortem与分层测试框架通过，但恢复并发契约不具体。未发现需要推翻方向的独立第四项架构阻塞。

必须修订：

1. 无绑定导入入口必须可调用；明确create(targetProjectId)/refresh(existingScope)。主库intent以operationId为主键，含workspaceId/moduleId/targetProjectId/importKind/inputDigest/status，待建立绑定不能并发生成两个项目；分库receipt同身份与提交结果，复用号异输入/目标拒绝。输入digest基于冻结输入，重试不得重新读取变动路径沿用旧号。项目、领域数据、receipt同事务，提交后才激活binding。测试空库、双击/并发、异输入、各提交点中断和无虚假成功。
2. 每物理库轻量 `Future<T> write<T>(T Function(WriteContext) body)` 串行同步SQL事务；异步读文件/解析/hash在事务外，事务内重核状态；旧方法拆外部事务入口和无BEGIN内部操作，receipt/变更序列同提交；迁移关闭同owner。任务1定义、任务2改造，M1验证A准备+B写笔记、A失败不回滚B、重复幂等、无嵌套事务、关闭升级等待。
3. 任务包四分支（当前项目/其他工作区/新项目空工作区/已有其他绑定新工作区）以及结果按taskId+revision确定归属再核scope。保留原projectId/taskId/revision，测试空设备接任务、重复、冲突、错工作区、晚到回调。

非阻塞一并改正：结果附件匹配结果manifest而非原任务；主库治理表补唯一键/版本/digest/状态，分库projection_changes补seq/项目对象删除标记与消费游标位置；目标路径统一packages/research_module/lib/src；迁入自动测试无回归不等于M2所有新分支先完成。

证据：design:71–82/92/94/98–119/133；implementation:21/23/31；research-workbench/lib/core/exchange.dart:217–221/263–300/677–743/959；store.dart:261–267/326；workbench_app.dart:227–236。详细因果见顺序在先的Architect报告。

停止条件：Planner修订后重新Architect → Critic；当前不可交执行。无产品测试/构建/实机证明，不产生执行授权。

## 第2轮：APPROVE / OKAY（2026-10-04，Asia/Shanghai）

在Architect第2轮APPROVE完成并持久化后，`/root/migration_critic` 复审五规划与在先架构报告。三项原阻塞关闭，无新执行级规划阻塞。最终五文件SHA256与最终共识记录一致：

| 文档 | SHA256 |
|---|---|
| design | 00668818c8f163621a990efb9d687404be9880f2a48441347c11f3125caa7e53 |
| prd | 1b55808ce3e603de7e5404c41a0371cf932ec6d0d42575993b6e8dae7b47f36b |
| reuse-matrix | 73b2ad8792ef6f90553ac2a9cb8b179053a8abcf14147c9d707231742073e5da |
| implementation | 58c27f7c85399b71164d1b3c22a735f3c1eae2857da56077679dd0a8d092b3dd |
| test-spec | 6ea8e2f0f8ddeb462ed613c26eb40085eedde788c9d432a0dc919eab79e3b919 |

关闭依据：design:65–94无绑定runtime/session分离；106–110 create/refresh/冻结/单intent/同事务receipt/恢复；129同步write队列与旧事务拆层；154–156任务四分支与结果修订归属。implementation:15–23责任分配，test-spec:25–29具体中断/并发/重复/错scope验证。

已模拟三个代表实施任务：空工作区首次导入恢复；A导入准备期间B保存笔记；另一设备接任务返回结果。皆可依计划执行，无需重新猜接口。

清晰完整性、原则选项一致性、公平替代、风险验证、三失败预演与unit/integration/UI/e2e/observability均通过。治理字段和唯一键足够，业务SQL仍在模块内。M1真实macOS＋Android研究链不被M2/新能力阻塞；真实包、实际执行、重导入、重开不能以合成夹具/空页面代替。Windows后续构建边界清楚。

执行时逐项落实旧BEGIN/事务内异步读取/页面直写，属于计划内验证而非继续规划阻塞。当前只认可规划质量；产品测试、构建、真机仍未执行，不产生产品执行授权。
