# Muyon Android 改造规划：独立质量审查

日期：2026-10-20。审查范围为规划可执行性，不含业务实施、测试通过、真实调用、合并或发布授权。

**OKAY — APPROVE（规划）**

**Justification：** 完整读取主计划、21 张任务卡、36 项测试规格及 Architect 首轮和修订后结论，并与已确认范围和代表性源码交叉核对。未发现需要退回重做的重大缺口。现稿已将真实 owner、授权与业务提交排序、附件发布/读取/清理、ZIP 元数据能力、API26 与真实 provider 的缺口分别落到具名卡、失败断言和停止条件；执行者可以按前置和文件写权推进，无需自行扩张业务范围或把旧实验成功解释成产品完成。

## Summary

- Clarity：目标、排除边界、旧输入、计划新建路径和完成条件清楚；本轮止于规划交付，所有实现卡仍未开工。
- Verifiability：36 个场景覆盖合同、真实 SQLite/进程、文件、API26、真实 provider 和结果聚合；明确实际运行数、原始日志和 source/build 绑定。脚本检查得到 21 个唯一任务编号、36 个唯一场景编号，任务中显式引用的测试编号均有定义。
- Completeness：原清单 T01–T10 和 B01–B04 有对应任务；没有遗漏供应商完整字段、软删恢复与引用、目录/ZIP、独立 PDF、业务读取、取消和新数据恢复。
- Big Picture：采用独立产品身份和最小共享代码提取；保留原实验和旧数据。未把桌面、历史迁移、全文提取、其他业务模块或正式发布变成当前前置。
- Principle/Option Consistency：通过。B 方案与复用、单一权限事实源和固定候选验证一致；P02 已限制全面搬目录，D01/D02 可先针对固定原候选工作。
- Alternatives Depth：足够。保留原工程的最小产品切片、建立独立产品入口、全栈重写的取舍已经交代；不需要为本次普通规划追加 Ralplan 共识流程。
- Risk/Verification Rigor：通过。关键竞态用 barrier，恢复用真实进程终止和独立物理查询，关键逆向变异不得靠编译失败冒充 RED；provider/API26/I04 任一缺证不关闭整体目标。
- Deliberate Additions：本次不要求 deliberate 共识扩展；现有三类失败预演及分层测试已足够支撑规划判断。

## 范围覆盖与任务调度

| 已确认目标或堵点 | 计划落点 | 关键验收出口 |
| --- | --- | --- |
| 唯一候选、来源和旧任务漂移 | P00、P02、V03 | SOURCE-MAP、产品身份、完整 required 结果及旧任务状态刷新 |
| 正式 Android 业务合同与真实 owner | P01、P03、P04 | CT01–CT04、DB04、AN01/AN06 |
| API26 搜索发送实际失败 | D01、C01、V01 | 原两条用例、AN02、OR01；不得只调大超时 |
| I04 恢复缺证 | D02、V02、V03 | RC01；受阻时保持 BLOCKED/HOLD |
| 供应商完整 CRUD、软删/撤销恢复和引用 | S01、S02、U01 | SU01–SU03、DB02、AN03 |
| 科研目录/ZIP、独立 PDF 和私有附件 | P05、A01、R01–R03、U02a/U02b | RE01–RE04、FS01–FS03、AR01、AN04/AN05 |
| 真实普通聊天、搜索和新增业务读取 | C01、V01 | CH01–CH04、AN07；accepted answer 与外部搜索证据 |
| 新数据、intent、原回执和附件恢复 | P03–P05、V02 | DB01–DB04、FS02/FS03、RC02 |

依赖未见实质循环。U02a 与 U02b 的拆分使 R02 不再等待其自身依赖的最终科研 UI；R03 可先在独立子模块验证，再与真实文件端口共同进入 U02b/V01。P04 的公共端口和绑定先固定，业务卡通过接口请求补入实现，不由各 lane 同时改公共 dispatcher。

文件写权可派工：P01 合同源、P02 首次工程/绑定、P04 后续导出/Service 的接力明确；公共 schema 属 P03，Manifest/Gradle/CI 属集成人。S01/S02 串行，R01 的 catalog/store 与 R02 import、R03 paper_create 分目录。四槽建议是调度约束，不是要求五个逻辑 owner 同时运行。隔离 worktree 和最终返回后才能标完成的要求足够明确。

## 代表性实施路径推演

### 1. 完整供应商修改后丢回包，再软删和恢复

P01 固定八字段和原 intent 绑定；P03 在同一事务写业务、history、终态、原 receipt；P04 接真实确认和 Rust 用例；S01/S02 分别实现完整更新及新 revision 的 delete/restore；U01 展示当前值和历史回执。DB02 的 COMMIT 前后窗口、SU02 的重放/竞争、SU03 与 AN03 能分别证伪半提交、重复效果和引用丢失。旧 `entities.dart:13–45`、`values.dart:43–67`、`store.dart:460–482,627–650` 支撑字段和引用语义；原子实验只改 name，已被如实限制为输入。

### 2. ZIP 导入固化附件后中断，与 GC 和已有 reader 竞争

A01 从同一封存原字节建立可信条目元数据，U02a 只给批准条目有界流；R02 解析/校验在短业务事务外完成。P05 复制前登记 intent，发布 pin 覆盖未引用窗口；论文、引用、receipt 发布与释放 pin 同事务。已有 reader 持 pin，GC 原子标 deleting 后拒绝新增租约。FS02/FS03 和 AR01 明确覆盖固化未发布、发布后、已持 reader、损坏/缺文件及异常 ZIP，不会只凭正常导出样例给绿灯。旧 `exchange.dart:19–34,106–142,393–495` 支撑限额、符号链接拒绝、重复修订和引用保护。

### 3. 真实普通聊天/搜索成功后重开，业务已提交但费用未结算

P03/P04 将业务 grant/generation 和业务 COMMIT 排序放在同库；原 Service admission 继续管外发、预算和 reservation。DB04 要求两个排序方向及结算故障，禁止双库写锁和跨 FFI 重入。C01 必须把 canary parser 修复重新构建并接真实 transport，CH02/CH03 要求有效回答/外部结果，CH04 保留旧 unknown reservation。V01/V02 在同候选验证且不重发。现有 `DurableServiceHostOwner.kt:60–73,377–421` 与 `AgentRuntimeService.kt:209–217` 证明旧实现的职责和 supplier read 边界，并不能证明新增业务已实现；计划没有混淆这一点。

## 文字限定复核：已闭合

审查期间建议明确 P01 的作用域。planner 已在主计划第 5 节开头和 P01 卡写明：仅冻结本次 Android 主链合同与 Rust/Kotlin 向量，不关闭完整跨端 M03 或公共插件 API，不将 Electron/全平台 oracle 纳入前置；本次 required 场景仍须全部实际执行，不接受 skip 代替。已读取修订文字并确认该项闭合。

旧 M02 任务仍记录跨端 M03、Normalization 数据版本及 oracle 边界；该限定能避免派工误读，同时保留本次编码、规范化和真实绑定的 CT01/CT04 要求。没有新增业务或验证范围。最终结论保持 OKAY / APPROVE，无待修订的阻断项。

## 保留的 WATCH 和执行停止条件

1. **ZIP reader 是待实现能力。** 无新依赖不等于低风险；A01 必须独立审查边界算术、编码/flags、EOCD/CEN/LOC 和 descriptor，并通过恶意语料、自家导出 round-trip 及 API26 有界流。任何一项不满足即阻断 R02；不得弱化断言。本轮未重新联网核验格式/API资料，也不声称 reader 已可用。
2. **授权排序与附件生命周期只在规划层成立。** P01 实际 schema/状态/向量以及 DB04、FS02/FS03 是后续必要证据；审查通过不能替代 barrier/进程测试或真实 owner。
3. **provider 和 API26 仍是未完成项。** canary CURRENT 明确两次 handoff、accepted 0、旧批次 stopped；parser 修复设备构建和两轮真实验收尚未成立。有效授权不足仅阻断相应 live 实测，不阻断本地工作；不得重开旧批次、清 reservation 或用 HTTP200/fixture 关闭目标。
4. **候选与门禁不能拼接。** P00 重新固定当时远端和采用源；V03 核全部本次 required 结果。旧 suite 的非必需 skip 不自动扩大目标，但本次 required 场景的 skip/NOT_RUN/BLOCKED 均不能形成整体通过；I04 HOLD 不能靠 selector 或新目录绕开。

## 验证边界与停止条件

本次只进行了规划静态审查、任务/场景编号交叉检查和代表性源码核对；没有实施功能、运行产品测试、设备或模型请求，没有刷新远端候选或改变 HOLD。官方 API/ZIP 格式链接作为主计划待执行能力验证的依据，不是本次新增实测证据。

停止条件已满足：所有已确认目标可映射到具名卡与验收出口，关键边界有明确 owner 和失败门禁，Architect 已要求的修订不再存在重大遗漏，未发现必须退回 planner 的阻断问题。可交付规划；未来按 P00 开始并逐卡验证。**规划 APPROVE 不等于实现通过，也不启动本轮执行。**
