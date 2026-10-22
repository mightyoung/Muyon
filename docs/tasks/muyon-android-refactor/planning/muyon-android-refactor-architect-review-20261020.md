# Muyon Android 改造规划：独立架构审查

审查日期：2026-10-20。结论：**REVISE**。架构状态：**WATCH**；以下三项 P1 合同缺口补齐前，不建议释放相应实现卡。本轮只审查规划和既有源码，没有实施业务变更或运行设备/真实 provider 验收。

审查对象：总计划、任务卡、测试规格三个 `muyon-android-refactor-*-20261020.md` 文件。引用行号对应本次读取的草案；后续修订可能改变行号。范围依据是 `docs/tasks/MUYON-ANDROID-OPEN-WORK-20261020.md:13–20`。

## Summary

独立产品入口、复用共享 Rust 实现、业务库与 admission 分责，以及 API26/真实 provider 分开举证，均符合已确认目标。无需重新讨论功能范围；需要先把“复验准入”“发布附件”“Android 有界 ZIP”三个原则写成有明确线性化点、状态和输入端口的可实现合同，否则不同 owner 很容易各自做对一半而组合出竞态。

## Analysis

### P1-1：跨库分责正确，但授权撤销与业务 COMMIT 的先后关系还未落定

证据：总计划 `:79–81`、任务卡 P03/P04 `:47–60`、测试 DB04 `:37` 已经明确不承诺跨库原子性，但只要求“业务提交前复验”。既有 canary 的 `DurableServiceHostOwner.kt:60–70` 已明确 authority guard 持续持有到 admission `endTransaction`，并拒绝其他进程/不同 authority 对象；同文件 `:417–421` 是 admission/reservation schema。原子实验 `core/src/main.rs:153–185` 仅保证自身业务事务内的 CAS、history、intent 和 receipt 一起提交，不能自动延伸这个 Kotlin guard。

这不是发现了现成产品漏洞，而是新组合的合同缺口：若复验后释放 guard，再进入 Rust 业务 COMMIT，撤权可能已经完成，业务仍提交；如果 Rust 在持锁期间回调同一个 owner，又可能违反现有禁止重入规则。

**最小修订：** P01 固定唯一 authority owner/进程、统一锁顺序和 commit permit 协议。昂贵文件复制/解析在 guard 外；最后一次权限/lease/scope/params/revision 复验与短业务事务 COMMIT 在同一权威串行边界内。撤权先完成则拒绝，COMMIT 先完成则撤权不能抹掉事实；取消采用同一排序。持 guard 的 Rust 提交不再回调同一 authority，不同时开启两个 SQLite 写事务。业务 intent/receipt 保存不可变 admission ID、authority generation 和完整绑定摘要；admission 后续结算失败只改变准入/费用状态，不触发重放业务。

**补充验证：** DB04 增加可控制 barrier 的“复验后、COMMIT 前撤权”和反向排序；证明无死锁、无已撤权的新提交。再覆盖业务已提交而 admission 未结算的真实崩溃，查询返回原业务回执且零新提交。不要仅凭时间 sleep 验证竞态。

### P1-2：附件顺序合理，但 pin 与 GC 必须成为正式状态，不能靠“未引用”判断

证据：总计划 `:82`、任务 P05 `:62–67`、测试 FS02/FS03 `:39–40` 正确识别文件与 SQLite 不存在同一事务，也要求发布中对象不能被清理；尚未定义怎样原子地区分“正在发布且暂未引用”与“可清理孤儿”。旧实现 `exchange.dart:48–68` 先建 snapshot 并落文件，`:343–377` 再登记 document；这些源码只能作为导入语义参考，不能证明新 blob/GC 协议。

**最小修订：** 在开始复制前登记稳定 import intent；P05 明确 `copying → pinned → committed/aborted`（名称可调整）。固化 blob 前后由该 intent 持有持久 pin；发布记录/附件引用/receipt 与释放 pin 在同一业务事务完成。GC 只处理无引用且无有效 pin、并已确定终态的对象，并与 pin/发布使用同一生命周期锁或等价串行机制。unknown/pending 不因“当前无引用”而回收。内容寻址对象复用时复验 digest/长度，不覆盖已有对象。没有成功的 DB COMMIT 就没有论文发布成功。

说明本次承诺的耐久级别：真实进程终止与重开必须通过；若同时声称设备断电耐久，另需文件/目录同步保证。当前计划已明确不以模拟器 kill 证明断电，可保持该边界，不扩任务。

**补充验证：** FS03 用 barrier 并发执行“blob 固化但 DB 尚未发布”和 GC，再执行“引用已发布、pin 已释放”和 GC；两次均保持可读及 digest 一致。断在 pin 持久化前后的临时文件可以成为可识别孤儿，但不能成为成功论文或被误当成可重放已提交操作。

### P1-3：Android ZIP 适配器与 Rust 校验之间缺少可验证的 entry 元数据合同

证据：总计划 `:60,83,93`、任务 R02/U02 `:90–116` 把流读取交 Android、规则复验交 Rust；旧 `exchange.dart:22–34,115–125` 明确验证路径、声明大小，并读取 `entry.isSymbolicLink`。如果平台适配器只给出文件名与解压字节，Rust 无从复验 ZIP 的类型/符号链接标志；同时只有解压完后才计数，也无法证明读取过程有界。

**最小修订：** P01 固定 `FileSource/ArchiveEntry` 端口：不可变 entry identity、原始/规范路径、entry 类型及元数据可观测性、声明长度、按块实际累计长度、源快照/清单摘要，以及受限读取能力。适配器在展开过程中检查实际大小/文件数，Rust 在发布前核对清单、内容与绑定；不信任源 URI 作为普通本地路径，也不将不可观测类型伪填为普通文件。P02/U02 的早期技术验证必须证明选定的现有 ZIP 能力能提供合同所需元数据；若不能，显式报告该入口 BLOCKED/技术缺口，不能删除符号链接断言或仅改扩展名绕过。具体 SDK/ZIP API 选择由实现 owner 查官方文档后固定；本审查没有把未核对的 API 能力当事实。

手填规则无需变更：总计划 `:91` 已清楚区分新的 title/project/PDF 必填规则与 JSONL 宽松回退。500 codepoints 是建议新规则，已如实标明；无需冒称继承旧实现。无项目时显式新建本地项目与当前范围一致。

### P2-1：拆出 U02 的文件端口准备里程碑，并明确公共文件 ownership 的接力

证据：任务 R02 `:92–95` 依赖 Android 有界归档适配器，但 U02 `:113` 的正式依赖包括 R02/R03；虽然文字允许“picker准备从 P01 开始”，它没有把关键端口交付与最终 UI 交付分别作为可验收节点。P01 `:16`、P02 `:25`、P04 `:56–60` 又分别涉及生成绑定，只有全局“公共 owner 独占”不足以说明阶段交接。

**最小修订：** 不增加功能卡，可把 U02 分为 U02a（P01/P02 后交付文件/归档端口与能力验证）和 U02b（R02/R03 后交付 UI 集成）。R02 的真实导入验收明确依赖 U02a，纯 Rust 规则测试可先用受控端口进行，不能据此关闭 Android 导入。P00 owner 表写明绑定/FFI、schema、dispatcher、Manifest/Gradle/CI 的唯一 writer 及 P01→P02→P04 接力点；R01 `application/research*` 与 R02 `application/research_import*` 收窄为互不重叠的具名文件/目录，修改既有公共模块走 owner 请求。

### P2-2：产品提取可行，但不应把全面搬目录作为排障前提

证据：总计划 `:44–62` 已否决重写，也禁止两套领域/权限规则；D01 `:33` 允许在原固定 PR99 checkout 复现，因此没有把超时根因诊断绑死到搬迁。当前可证实的业务实验仍只有 `supplier.name`（原子实验 `main.rs:66,85,145`），真实 Service 当前具名业务入口为 supplier read（canary `AgentRuntimeService.kt:209–217`），新增正式业务核心有必要。

保持 B 方向，但将 P02 的“提取”约束成行为保持的最小切片：产品应用标识与数据目录独立，保留既有锁定工具链；先连接既有共享运行时，再按实际复用模块移动或提取。无需为了目录整齐提前移动全部实验、重写历史脚本或抽成多个 crate。`crates/Cargo.toml`、`crates/muyon-core` 等是拟定落点而非产品验收本身；P00 来源映射和 P02 新旧入口等价回归是判断是否可落地的门槛。

## Root Cause

当前欠缺来自边界组合：已有 admission 的权威锁、原子业务实验的单库事务、旧科研快照的文件和业务规则分别有用，但它们尚未构成一个共享提交协议。现稿已经识别风险，缺的是把这些原则固定为能由两个独立 owner 一致实现并被竞态测试证伪的最小合同。

## Recommendations

1. **P1 / 小到中 / 阻断相关实现释放：** P01 与 DB04 写明权威/撤权/取消到业务 COMMIT 的线性化和锁顺序；P04 明确非重入提交端口。
2. **P1 / 小到中 / 避免附件丢失和误报成功：** P05 与 FS02/FS03 加持久 pin、GC 排序及原 intent 查询规则。
3. **P1 / 小 / 避免 ZIP 验收不可达：** P01/U02a 先固定元数据/有界流端口并验证既有技术能力，不以不可观测属性伪造安全结果。
4. **P2 / 小 / 解除隐含依赖和文件冲突：** 细化 U02a/U02b、生成文件接力和 R01/R02 文件 ownership；保持产品提取切片最小。

上述修订不增加业务范围，不要求历史迁移、额外平台、真机、全文检索或 PDF 解析引擎。D01/D02 可以按现有卡继续作为将来的独立工作，不应受规划目录调整阻塞。

## Trade-offs

| 方案 | 优点 | 代价与边界 |
| --- | --- | --- |
| 继续原 Compose 工程，增加独立产品 variant 和正式业务模块 | 路径/绑定/CI 变化少，最快暴露真实超时与 Service 问题 | 必须真实隔离 fixture、应用/数据命名空间；实验工程治理容易渗入产品 |
| 保留本计划的产品入口，按实际模块最小提取共享 Rust | 产品边界清楚，同时复用现有恢复/权限/工具代码 | 需要来源映射和新旧入口等价回归；全面搬迁会扩大关键路径 |
| 重写运行时并统一成一个大库/单库 | 局部代码表面更统一 | 丢失已审成果，混淆 admission 与业务事实，明显超范围；不建议 |

## Consensus Addendum

- **Antithesis（最强反对方案）：** 用户需要可用的 Android 闭环，原工程已经有 ABI、Service、生成绑定和 CI；目录位于 experiments 本身不是产品不可用的原因。先在现有工程采用隔离 product variant 完成真实链，再按复用需求提取，能够降低搬迁回归和延期风险。
- **Tradeoff tension：** 产品边界和共享规则必须明确，但目录规范化本身不解决 API26 超时、owner 接线或跨介质提交。提前提取太多会掩盖这些现有失败；完全不提取又容易让 synthetic 默认值和专用 harness 进入产品。
- **Synthesis：** 保持本计划的独立产品身份/数据隔离；P02 仅实施行为保持的必要工程切片，既有运行时先复用。以正式 authority/业务/附件合同驱动共享模块提取，不以“迁完全部目录”作为已知堵点排障的前置。

## References and Validation

- `.omx/plans/muyon-android-refactor-20261020.md:44–62,78–93` — 产品提取和权限/业务/附件边界。
- `.omx/plans/muyon-android-refactor-tasks-20261020.md:14–29,47–67,83–116,146–150` — 契约、公共 owner、导入/Android 依赖。
- `.omx/plans/muyon-android-refactor-tests-20261020.md:34–44,50–58,64–78` — 跨库、附件、设备和最终门禁。
- `packages/research_module/lib/src/core/exchange.dart:22–34,48–68,115–125,343–377,393–491` — 路径、大小、类型、快照/文档与修订语义。
- `experiments/redesign/device-deferred/atomic-business-lab/core/src/main.rs:66–85,145–185` — 实验字段范围及单业务事务。
- `/private/tmp/muyon-chat-live-canary-20261019/experiments/redesign/android-compose-lab/app/src/main/kotlin/com/mightyoung/muyon/androidlab/agentipc/DurableServiceHostOwner.kt:60–73,377–405,417–421` — 既有 authority guard、准入/结算职责和 schema。
- 同 checkout `AgentRuntimeService.kt:209–217` — 当前 supplier read 入口。

验证状态：完整读取三份规划；对以上风险进行了相关源码交叉核对；没有执行新代码或测试。审查停止条件是上述 P1 已有明确合同和对应竞态/故障断言、P2 依赖/owner 文本修正后做一次有界复核。规划通过仍不代表实施或产品验收完成。

## 修订后有界复核

复核日期：2026-10-20。本轮仅核对首轮提出的问题及相关新增风险，未扩大源码盘点。**最终规划结论：APPROVE；架构状态：WATCH。** 首轮 REVISE 保留为历史记录；以下结论适用于修订后三份规划，不代表实现完成、测试通过或执行授权。

### 首轮问题处理结果

1. **P1-1 已在规划层闭合。** 总计划 `:79–81` 明确业务 DB 的 grant/generation 是本地业务授权唯一事实源；发行、撤销、取消和业务提交进入同一 Rust 写队列/事务排序。原 Service guard 继续控制外发和计费，两库不同时持写事务，也不持 Kotlin guard 跨 FFI。receipt 绑定 admission/generation，业务已提交而结算未完成时仍只查原事实。任务 P03/P04 `:49–60` 和 DB04 `:37` 已对应加入双向排序 barrier、新 epoch、无重入/双库锁及结算故障验证。这个方案比首轮建议的跨 FFI 持 guard 更小、更容易明确线性化点，且没有把计费权限混入业务 grant。
2. **P1-2 已在规划层闭合。** 总计划 `:83–84`、P05 `:64–67` 与 FS03 `:40` 明确复制前 intent、持久发布 pin、覆盖已持有 reader 的 pin、同事务标 deleting，以及禁止新增租约/发布。unknown 不按超时回收，旧 owner 死亡及引用/意图核对在重启 GC 前完成；进程恢复与断电耐久边界仍保留。
3. **P1-3 已形成可验收技术前置。** 总计划 `:97–101`、A01 `:69–75` 与 AR01 `:41` 不再依赖 Android 填写默认类型。Rust 从同一封存 archive 核对 EOCD/CEN/LOC；Android 负责既有解压引擎及有界流，发布前核对实际 CRC/长度/清单。ZIP32 的支持和明确不支持组合、官方依据、自家导出 round-trip，以及不能可靠通过即阻塞 R02 的停止条件均已写明。
4. **P2-1 已闭合。** 总计划 `:143` 固定 P01→P02→P04 的绑定写权接力；R01/R02/R03 的目录变为 `research_catalog/`、`research_import/`、`paper_create/`（任务卡 `:93,100,107`）。U02a `:119–124` 的平台能力先验与 U02b `:126–130` 的业务 UI 分开，R02 明确依赖前者，无须等待最终科研 UI 才验证文件端口。
5. **P2-2 已闭合。** 总计划 `:62`、P02 `:26` 明确最小提取和行为保持，D01/D02 排障不依赖全面迁目录；独立应用/数据命名空间与共享实现复用的目标都保留。

### 保留的 WATCH 与停止条件

- **A01 是新增的实质实现风险，不是已证实能力。** 元数据 reader 虽不重写解压引擎，仍需独立 review 其边界、名称编码、flags/extra 白名单、offset 算术、descriptor 与 CEN/LOC 配对。规划已把该风险变成具名任务和失败门禁，因此不构成再一轮规划阻塞。A01/AR01、旧研究导出 round-trip 或 API26 有界读流任一未通过时，R02 不可关闭；不能以产品目录、正常 ZIP 样例或仅自家导出通过替代恶意语料断言。
- **“已在规划层闭合”只表示合同与验证要求足够明确。** P01 仍需产出实际 schema/状态表/向量；实现阶段必须拿到 DB04、FS02/FS03、AR01 和真实 API26 结果，不能用本次 APPROVE 代替这些门禁。官方 API/格式依据由主计划链接及研究记录提供，本轮未另外重复网络核验，也未执行新测试。

停止条件已满足：首轮三个 P1 的具体合同、失败场景和 owner 均可定位，两个 P2 的依赖/公共写权已修正；未发现本次修订引入需要再改规划的重大矛盾。可交后续 Critic 独立审查。
