# 公共插件合同源码研究：科研与询价

日期：2026-10-15。状态：**source research / 设计建议 / 未实施 / 未冻结**。本文件不宣称 M03 完成，也不把 experimental `inquiry.object` IPC 形状提升为公共 core 合同。

## 1. 身份、范围及证据规则

- adopted base：`3836149416020a0ac58f9e7ca788c20e66688e0e`。父线程报告本次远端 develop 核验仍为该 SHA；本研究独立核验其本地 commit/blob 身份，不冒充自行远端核验。
- experimental host：仅引用 `c4702eecaf50bbdfa3d93faefdadfb1915468b41`。父线程后续 EOF 修复不在本研究范围；旧 combo/CI 的测试数量不能证明公共插件能力。
- 独立 shared clone：`/tmp/Muyon-plugin-contract-research-20261015`，分支 `review/plugin-contract-research-20261015`，从上述 adopted base 建立，保留 alternates。
- 读到的规则：基线 `docs/tasks/REVIEW.md`；此 clone 与借用源无 `AGENTS.md`/`.agents`，`/workspace/.agents` 为空。没有借用其他不相关工作区的规则。已读 ADR-0004/0005、ADR-0002授权底线、v1.3.2 redesign、D01a/D03a minimal contracts 和历史 invariant audit。历史审计结论只作为检查线索，不冒充当前缺陷复核；其中旧taint/放行按钮规则不能覆盖较新v1.3.2已定FullAllow语义。
- 只读源研究；仓库只新增本文。没有产品变更、第二 research adapter、真实模型/凭据/业务库/真机访问、历史迁移、默认授权改变、UI/REA扩展、merge/push/deploy。Rust/Dart writer 共享目录未修改。
- `inventory.json` 存于 `/tmp/rd-plugin-contract-research-20261015/`，记录每项完整 SHA、路径、行区间、blob SHA、excerpt SHA-256 和原文。下文 `[Snn]` 均可在第7节找到完整 SHA:file:line；negative-search 结论限定为明确搜索范围，不宣称全产品安全证明。

## 2. 核心结论：已有接线应继承，公共桥接尚缺

**Dart 基线已经能让合格 V2 模块声明工具后进入通用 Agent 工具目录和执行链。** 科研自身就是此路径的实例：`ResearchModule.registerTools → registerResearchTools`；启动处通过 catalog 注册，ModuleHost 循环构建 registrar，AgentTaskFactory 从 ToolRegistry 按实际可用性、范围、类别及模型可见性筛选，生成 native function 或 compat 描述。这里不需要为“科研也接 AI”再写一套 adapter。这个结论限于注册、候选选择和工具描述投影；不能外推为整条来源链已无业务特判。[S01–S10,S29–S31,S58]

“自动接入”应精确定义为：**通过可信安装/登记、合同校验且当前可见的能力自动发现、生成工具投影，并统一调度已有业务 handler**。它不意味着发现全部业务方法，不意味着 capabilities 请求自动获准，不意味着能直接拿 model gateway，不意味着读取许可同时允许发送给模型，更不意味着安装不可信代码后能靠声明限制其所有进程权限。[S15,S16,S36,S40,S41]

询价现有路径比科研更耦合宿主：`InquiryBusinessModule` 是可信 host 兼容 adapter，显式要求 `HostToolRegistrar`，继续使用现有 inquiry owner 与 host-only effect intent/result guards。应记录这个迁移接缝，不复制它作为未来所有插件的模板，也不删除既有权威校验。[S32]

experimental host 使用了可继承的 provider/authorization/tool port 思路、活 prepared handle 和原回执核验，但三处仍是业务专用：Rust start/schema/result、Dart prepare/invoke、模型 tool-name 映射。直接增加 `research.*` 分支只会复制特殊通道；应该先定义一份通用 catalog/dispatch/projection 合同，再让两模块由同一个桥接使用。[S43–S48]

来源与出口有四个不同事实，必须分别继承和补齐：

1. **字段 sensitivity 传递仍缺**：ToolSpec.resultSensitivity没有进入HostToolRegistrar生成的ToolDescriptor，不能据此宣称字段/实际值分类及用途全链已闭合。[S20,S21]
2. **宿主来源事实 owner 已有**：HostSourceFact稳定身份和HostTaskFacts独立于模型消息、任务快照、摘要；HostAuthorizationFacts只由host维护，缺事实为unknown，markExternal先锁存再持久化，持久化失败不能清除锁存。新设计应复用该来源身份和持久化边界，不能再造一份插件自报的事实owner。[S59]
3. **来源识别仍有业务名分支**：AgentDispatch._external在排除pure local write后，按external effect、mcp provider或inquiry/knowledge/research模块名判断。_invokeOne命中才在invoke前记tool_invocation来源、结果后记objectRefs。因此合法注册的新本机read插件不因完成V2注册就自动继承这几类模块的来源事实路径；这是“不改Agent业务switch”验收前必须泛化的接缝，不是本研究已修复的实现。[S58]
4. **最终模型payload审查已有**：AgentModelTurn.preparePermission编码实际请求与可选兼容变体，HostModelAuthorization.prepare读取host task facts并审查最终payload的UTF-8字节、重验policy；兼容payload变化有独立绑定/复核。此机制应继承，不能因resultSensitivity未传递而写成没有来源/授权/内容审查；它也不证明新版五类字段/实际值/用途门禁已经完整实现。[S60–S62]

只继承来源身份、宿主事实持久化及不能自证的边界，不把旧HostTaskFacts.requiresConfirmation的tainted/unknown映射机械复制到新版FullAllow。较新的已定模式语义仍以v1.3.2为准。[S41,S59]

## 3. 真实链路与层间缺口

| 环节 | adopted base 已存在 | 尚缺或受限 | 边界/归属 |
| --- | --- | --- | --- |
| 注册 | BusinessModuleV2、静态 catalog；重复module ID拒绝整个catalog构造，API/依赖/未知capability不兼容按模块隔离；ToolRegistrar sealed 注册 [S01–S06] | 非任意动态插件加载器；兼容 inquiry host adapter 尚未独立 [S32] | 安装身份和可信级别由宿主决定；插件只能请求能力 |
| schema校验 | 参数/result schema受限子集；参数prepare时校验、成功结果dispatch后校验 [S06,S07,S11,S13] | resultSchema可空；不是全 JSON Schema；ontology/coverage不是同一运行时schema闸门 | 新公共合同声明schema dialect/version；不支持的安全字段拒绝，不能靠不同语言各自猜测 |
| 能力发现 | 工具按scope/category/availability/modelSelectable筛选；coverage有exposed/deferred理由 [S08,S36] | “存在于目录”不证明当前可调用；feature声明也不证明端到端实现 | discovery回应仅元数据；invoke必须再次核当前 authority |
| Agent工具投影 | native及compat都直接来自同一descriptor [S09] | experimental模型层硬编码inquiry.object [S47]；ToolSpec分类未投递到descriptor [S20,S21] | core只认识工具ID和注册schema，不认识业务名；模型候选不能签发权限 |
| 来源事实/模型用途 | HostAuthorizationFacts独立来源身份/先锁存后持久化；最终编码payload已有授权/内容审查与兼容变体复核 [S59–S62] | AgentDispatch._external含业务moduleId分支；新read插件不能仅靠注册获得等价来源标记；resultSensitivity传递及完整新版用途链仍缺 [S20,S58] | 可信host绑定真实来源，插件/模型自报clean不得清洗；复用既有事实owner与最终payload入口 |
| prepare/invoke | 一次性批准/host grant链、scope/current policy、generation检查；同key合并/冲突 [S10–S14] | 跨语言prepare handle尚未通用；effect-specific trusted intent不应由manifest或模型提供 | 插件handler保留业务校验；授权、dispatch ownership、消费、审计在可信host/core |
| 回执/核对 | ToolRegistry原回执与receiptFor；BusinessReceiptLookup全身份只读核对合同 [S13,S33,S34] | 查询 `lookupBusinessReceipt` 的生产命中仅询价实现/接口声明，未发现通用Agent消费者；科研Runtime的implements也未声明此接口 [S35,S63] | 通用回执路由可以设计，不能把所有插件都称已支持原业务核对；notFound≠未执行 |
| 撤权/关闭/卸载 | ModuleHost epoch失效、withdraw、cancelProvider、持久撤权、防重新激活、close/drain [S17] | ModuleRuntime无dispose/unload；session.dispose≠动态卸载；没有通用安装/升级/卸载事务 [S25] | 最小先定义disable/revoke/drain语义，不急造热更新或卸载框架；持久回执不随卸载删除 |

重要实现限制：注册方法决定 descriptor effect，不能据此声称任意本机 native 插件无法偷偷写入。`ModuleResources` 提供数据库/files，`ManagedDatabase.raw` 是直接数据库能力 [S16,S24,S25]；native 模块仍是受信任进程代码。公共合同的权限控制保证受控执行路径，不替代进程/存储隔离。不可信插件若将来成为范围，必须另定能力隔离与可信安装合同，本轮不建沙箱框架。

## 4. 最小公共面：复用、需新设计、业务留存

| 面 | 可继承 | 最小新设计建议（未冻） | 留在业务插件 |
| --- | --- | --- | --- |
| 对象与动作 | ObjectRef、OntologyFieldSpec/ObjectTypeSpec/ActionSpec、ToolSpec [S18–S21] | 跨语言可编码的稳定对象身份与版本字段；单一schema事实源；所有工具参数仍由各自schema决定 | 科研project/document/entry/card与询价supplier/quote等模型、CAS/合法性/领域规则；不强迫工具都使用type/id |
| 敏感度/用途 | 五类Sensitivity、unreviewed默认、trusted来源和目的限定 [S19,S40,S41] | 补齐字段/实际值分类证据→结果投影→最终model/outbound payload的可信关联；按用途和版本核对；声明自报标签只输入事实校验，不降类/授许可 | 已确认字段分类及实际领域内容；询价地址none等既定分类不随意重标，科研不一律commercial |
| context来源 | ContextRef项目绑定、ScopeResolver、ModuleScopeSource/session resolve，以及独立HostAuthorizationFacts；最终编码模型payload已有审查 [S21–S23,S59–S62] | 可信来源分类/绑定替代_external业务名分支；保留真实来源/对象修订/权限版本/用途并接既有事实owner；投影只披露当前获准字段 [S58] | 取数、文档定位、科研引用、领域摘要；插件不能自报“用户指令/可信授权来源”或clean来擦除事实 |
| 版本/迁移 | API version/packageRevision与DB schema连续迁移 [S02,S24] | protocol/schema/database/projection版本分轴；注册schema摘要和authority revision参与冻结绑定；未知major或安全字段拒绝 [S39] | 各业务DB迁移由原owner实现；本轮不运行真实历史迁移 |
| 生命周期 | 懒激活、并发合并、失败隔离、撤权持久化、close drain [S16,S17] | 一次注册snapshot绑定generation；disable/revoke使新发现和旧prepared handle失效；已派发回执独立收束；如后续需要unload再补有限close契约 | 模块资源清理及状态恢复，不引入第二业务数据库owner |
| 事件订阅 | ChangeLog、ProjectionService原子cursor/catalog [S26,S27] | 需要时复用D03a的store/scope/stream/seq域、authority/schema、lease和有限buffer；增量失败重新快照；ACK不是成功 [S42] | 领域事件payload及事实生成；module change log不直接当跨端审计/授权流 |
| 错误/回执 | ToolCallStatus、ToolPlatformException、BusinessReceiptStatus [S11,S13,S33,S34] | 有界稳定错误码及phase/effect-known状态；原回执引用与可见投影分离；查询走原owner不重新执行 | 领域冲突原因；不把异常正文或业务秘密放IPC诊断 |
| 取消/并发/预算 | cancellation、replayKey去重、host task预算 [S13,S14,S17,S28] | 有限inflight/bytes/deadline由可信host配置；取消请求与已派发/已提交事实分离；模型/manifest不能提预算 | 业务安全取消点；取消不能回滚已发生效果，unknown必须核对 |

建议先限定三个可审阅接缝，名称仅为研究记号，不新增第二套最终DTO：

1. **注册目录快照**：由同一注册事实生成可模型选择的工具descriptor、schema版本/摘要、模块与注册generation；声明的read/write/outbound类别交可信注册器核定。筛选继承现有scope/category/modelSelectable。不给插件创建grant API。
2. **统一执行路由**：core传tool ID和schema符合的参数，host/core可信侧解析为已有registry handler；prepare返回opaque、一次性、绑定task/attempt/参数摘要/scope/authority/generation的引用。invoke消费前重验。model callId仅配对消息，不当执行身份。原handler、原业务owner、原ToolRegistry回执保留。[S05,S11–S14,S45,S46]
3. **受控结果投影与只读核对**：插件提供领域结果和schema；可信来源适配器从真实provider/输入谱系及当前事实绑定来源，接入既有HostAuthorizationFacts，不能将插件标签直接升级为权威。泛化_external业务名判断后，可信投影器依据允许字段/分类/用途/当前权生成模型材料，再经已有最终payload授权与审查入口；保留原回执引用和已验证objectRefs。[S58–S62] 核对能力仅在原owner已实现时公布，不存在则明确unsupported/unknown。无需先把所有产品函数、UI页面和动态插件安装器统一进来。

自动注册/发现不调用模型也不触发授予；无read权限时可以展示获准的能力元数据但不得取业务正文。拥有read只证明当前本机允许读取，进入模型上下文还必须过独立model和最终用途门禁。FullAllow沿已定范围内免风险重复询问，但无权/撤权/非法业务/缺必要分类事实仍拒绝；本研究不修改模式默认或旧grant迁移。[S15,S40,S41]

### 4.1 DATA/RELATION、operation、view 三层贡献不能漏掉

用户本轮明确要求数据结构注册，以及UI、插件、Agent core并行推进。现有 `ModuleOntology` 已汇集对象字段、关系、动作、流程；科研有自己的对象/关系/action声明，询价从原domain ontology/links/actions投影到同一API，因而数据注册研究必须与工具注册一起做。[S50–S53]

| 贡献层 | 当前源码与可继承语义 | 建议最小登记/校验 | 不产生的权限或副作用 |
| --- | --- | --- | --- |
| DATA/RELATION | ObjectTypeSpec字段类型/required/ref target/分类/title/versioned；RelationSpec from/field/to/many/queryTool [S19,S50–S53] | 模块限定type ID、data-schema版本/摘要；字段与ref target、relation端点/基数及read-query引用完整性；复用稳定ObjectRef。禁止未声明跨模块边和悬空target。发布前原子校验同一模块贡献集；未知安全字段拒绝 | 登记元数据不执行DDL、不导入数据、不建立scope、不给跨关系读取权；关系导航必须对目标重验权限 |
| operation | ActionSpec→tool/operationId，coverage，ToolSpec参数/result schema/effect [S05,S36,S50] | 操作ID、输入/输出schema、读写对象类型、effect、版本/CAS需求、取消/receipt能力；tool/query引用必须可解析且scope不会扩大 | action名字/description/handler存在不等于grant；business执行不从view按钮事件直接认定成功 |
| view | ModuleSection、ObjectPageSupport、SnapshotFact/BindingRef、UiActionRoute [S50,S55–S57] | 稳定route/view ID、允许的data bindings和operation引用；端侧把同一view contract映射为组件；模型投影和native view分别受用途限制 | UI渲染不能重写数据schema/业务验证/授权；local交互不强迫回模型；view不能通过display字段混入凭据 |

**数据模型登记、数据库DDL迁移、权限签发是三个独立边界。** DATA schema描述逻辑对象/关系及验证语义；DB schema由原存储owner及版本化迁移合同管理 [S24]；grant由可信authority管理 [S15–S17]。迁移脚本不从模型或任意manifest文本执行；登记一个对象类型也不会自动创建表或对现有库做ALTER。operation绑定数据schema，view绑定获准snapshot和operation，MCP/OpenAPI未来只能是这些事实的边界投影，不能各自成为第二份领域真源。

状态必须分清：

- **当前实现事实**：Dart ModuleRegistry/ToolRegistry + ModuleOntology对象存在；不是已运行的Rust DATA registry，也没有从ontology自动生成数据库与所有UI的证明。[S02,S06,S51]
- **已采纳设计方向**：v1.3.2采用Rust共用业务/存储/授权语义，并在module_api迁移条目提出Rust domain contracts、版本化wire DTO/IDL、端侧screen registry三层，替代Widget/raw DB的边界。[S54]
- **本轮待审具体建议**：由Rust领域注册表维护经校验的DATA/RELATION+operation贡献真源，并输出受限tool/view投影；原子注册、schema dialect、引用校验、版本/兼容策略及编码细节都需公共接口审阅后实验。本研究未授权或完成M03冻结，没有创建第二份最终schema。

并行工作依赖可收敛在这份候选贡献清单：插件线列真实DATA/RELATION/operation，Agent线消费通用tool投影及prepare/invoke/receipt，UI线消费获准view/route与bindings。三线共享事实定义，不能各写一套业务规则。当前共享目录 `module_api`/registry 不由本研究修改；未来由父线程明确唯一owner再接实施任务。UI/REA现有范围不扩。


## 5. 第三合成插件验收设计（全部 planned / not_run）

目标：在统一桥接冻结前发现隐藏的业务特判，而不是再做一个业务适配器。选用“设备借用”插件 `equipment_loan`：DATA有设备 `equipment` 和借用单 `loan`，虚构设备 `device-a`、借用单 `loan-a`、借用人主体引用 `actor-a`、工作区 `W`、版本 `r1`。RELATION为loan.equipment_ref→equipment（一对一从借用单视角、设备可有历史多单），borrower_ref指向host已允许的合成主体身份。所有内容纯合成。与科研/询价并列装入测试catalog；core源与适配层不得新增 `equipment_loan`、`research`、`inquiry` tool-name分支。noAgentBusinessSwitch必须同时覆盖现有AgentDispatch._external的moduleId来源分支；仅通过目录发现/handler执行不算满足。泛化来源识别由可信host绑定和既有事实owner承接，不能让新插件自报clean绕过标记。[S58,S59]插件仅实现公共注册、scope resolver、handler、必要的只读receipt接口。fake provider使用预设完整call，不启动真实模型服务；所有DB均临时合成。

**输入schema示例**（候选dialect仅使用现有受限子集；名字故意与type/id不同）：

```json
{"type":"object","properties":{"equipment_key":{"type":"string","minLength":1,"maxLength":64},"include_loans":{"type":"boolean"}},"required":["equipment_key"],"additionalProperties":false}
```

`equipment_loan.inspect_equipment` 为read；成功result.data schema：

```json
{"type":"object","properties":{"equipment_key":{"type":"string","minLength":1,"maxLength":64},"active_loan_count":{"type":"integer","minimum":0,"maximum":1},"status":{"type":"string","enum":["available","borrowed"]},"notes":{"type":"string","maxLength":128},"loan_keys":{"type":"array","items":{"type":"string","minLength":1,"maxLength":64},"maxItems":8}},"required":["equipment_key","active_loan_count","status"],"additionalProperties":false}
```

输入为 `{"equipment_key":"device-a","include_loans":false}`，handler原结果 `data={"equipment_key":"device-a","active_loan_count":0,"status":"available"}`，objectRefs为已解析的 `equipment_loan/equipment/device-a@r1`。include_loans=true仅返回当前scope内最多8个loan_keys及其已核引用，超限明确分页/截断信息由后续合同决定，不静默宣称完整。ObjectRef由公共引用schema编码，完整identity/project/revision/digest是否披露由当前用途与可信投影决定；禁止把 `{found:true, inquiry supplier ref}` 作为公共成功判据。readonly结果可能有0/1/N合法引用，由descriptor/result合同约束，不能永久固定“一条”。

manifest声明对象、工具、schema、读作用域、classification请求；不含grant/approved/policy owner字段。插件声称 `none` 不能覆盖宿主已知personal/credential事实。测试host有独立可信policy fixture，直接授予/拒绝测试scope所需能力；这属于隔离测试输入，不是manifest自授权或产品默认。模型、工具结果、插件声明均不能制造用户指令凭据。

另声明仅用于验收的 `borrow_equipment` 本机write和 `reconcile_operation` 只读核对能力：前者参数含equipment_key/expected_revision/borrower_key、额外字段拒绝；只接受当前available设备与获准借用人，CAS不匹配或已借出则零写；合法写的单事务更新设备status/revision、创建loan及其设备关系和原business receipt，后者完整绑定operation/request/tool/scope/domain identity。默认无write grant，只有可信测试issuer可在特定case发一次授权。没有模型真实调用和外部网络；外发只用计数器证明零发送。

设备DATA要求equipment_key（nonempty≤64）、label（合成显示名≤128）、status（available/borrowed）、revision（正整数）；loan要求loan_key、equipment_ref、borrower_ref、state（active/returned）、revision。逻辑ref的目标必须已登记，非任意字符串拼接。设备.label声明none；loan.borrower_ref及可选notes按可信fixture标personal；真实值仍受host分类/用途检查。borrower_ref目标为测试host预先登记且scope允许的actor类型，跨模块ref必须显式依赖和逐目标授权；不是依relation自动拿到用户资料。无DDL执行副作用。view贡献只声明equipment.list/equipment.detail及事实bindings、borrow_equipment动作引用；native视图和Agent使用同一operation，未知操作引用拒绝，不实施新UI。

write输入schema候选：

```json
{"type":"object","properties":{"equipment_key":{"type":"string","minLength":1,"maxLength":64},"expected_revision":{"type":"integer","minimum":1},"borrower_key":{"type":"string","minLength":1,"maxLength":64}},"required":["equipment_key","expected_revision","borrower_key"],"additionalProperties":false}
```

schema登记测试另外断言：重复type ID、悬空ref target、错误relation基数声明、operation引用未知type/tool、view引用未知binding/action均使本次贡献集整体不可发布；无部分可发现工具，其他模块保持可用。借用关系查询必须重新核目标及borrower的scope，不能经equipment关系遍历绕权。旧data schema版本的事件/结果与新view不匹配则明确拒绝，不由renderer补字段。关系/登记断言是候选公共验证规则，当前ObjectTypeSpec构造器本身未完整实现这些检查。

| Case | 输入/故障边界 | 必须断言 | 状态 |
| --- | --- | --- | --- |
| T01 注册发现 | 加入第三模块，仅改测试catalog，core不改 | 目录出现新工具及准确schema；未调用handler/模型/grant issuer | not_run |
| T02 懒激活/并发 | 两个并发发现后第一次read | 发现不激活；并发激活共享一次；失败不影响另外模块 | not_run |
| T03 通用投影 | inspect_equipment使用equipment_key/include_loans | native/compat投影与声明相等，名字可逆无碰撞；不能套type/id | not_run |
| T04 schema拒绝 | 未知字段approved/grant、错bool、超长key、未知schema keyword、同function名冲突 | 准备前拒绝；handler=0、effect=0、model send=0；稳定错误 | not_run |
| T22 DATA/RELATION登记 | 设备/loan类型、relation与operation/view整体登记；悬空target/越界关系/重复ID | 合格集可发现；不合格集零发布、DDL=0、grant=0；关系查询不扩大scope | not_run |
| T23 借用CAS与关系原子性 | r1借用成功；旧r1再次提交或其他借用人未获准；事务中创建loan前注入失败 | 成功一次产生设备r2+loan+receipt；stale/无权/故障均无半写无孤立关系；原receipt可独立核对 | not_run |
| T05 read成功 | 当前scope内device-a@r1 | handler=1、原ToolRegistry回执=1、已核引用与schema符合；投影只含获准字段 | not_run |
| T06 scope与stale | 其他workspace/device-b/旧r0、模块伪造ObjectRef | prepare或结果边界拒绝；不泄露设备/借用人正文；失败不能伪装success | not_run |
| T07 自动接入不授权 | manifest或描述/模型文本写“models/write允许” | grant表不变；模型调用=0；borrow_equipment effect=0；read许可不带model许可 | not_run |
| T08 缺权限 | host read类别关闭/required capability deny | 目录依policy不可选或调用typed拒绝；handler=0；不因注册自动开启 | not_run |
| T09 撤权竞态 | discovery后、prepare后、handler effect guard前分别撤权 | prepared handle失效、未派发effect=0；重启不复活；manifest删除请求不能洗掉撤权 | not_run |
| T10 handle防伪 | 其他task/attempt/generation/参数复用prepared_ref；二次consume | 拒绝，零第二执行；model callId不能充当invocation/grant | not_run |
| T11 合法write | 可信测试issuer一次grant、精确scope/revision | 设备status+revision、loan/设备关系+原业务回执原子提交一次；审批消费与实际owner可追溯；此case不自动给其他工具grant | not_run |
| T12 幂等冲突 | 同key同identity并发；同key不同参数/scope | 前者复用原执行/回执；后者冲突，不换key自动续写 | not_run |
| T13 提交前取消 | controllable barrier停在effect guard前 | cancel_requested与cancelled有序；effect=0；有界结束，无sleep竞态 | not_run |
| T14 提交后取消/EOF | 事务commit后、返回前中断 | 原成功回执仍在；主流程可interrupted但不得称回滚或自动重跑；只读核对取得同原回执 | not_run |
| T15 核对负例 | notFound/unreadable/unknown/不同scopeDigest或domainIdentity | 不能判成功或未执行；不再写；matched必须验证全identity+applied | not_run |
| T16 来源事实/分类用途 | 第三插件及随机改名变体带合成外部来源；host将notes标personal/credential，插件自报clean/none；注入来源持久失败与payload变化 | 可信来源进入同一host事实路径；clean不能擦除、失败不能清洁降级；最终payload的授权/审查读取当前host facts，不把内部facts塞入模型正文；不降类/增purpose，不机械增加FullAllow风险确认。详见T16子场景 | not_run |
| T17 结果伪造 | schema多字段、非法status/active_loan_count、伪receipt ID、额外ref | 失败且无伪success；只信registry/原owner receipt；原始异常不入IPC | not_run |
| T18 生命周期 | disable/unload请求与inflight交错 | 新准入关闭、generation失效、已派发回执drain；dispose恰一次仅在公共close契约实现后验，不把现有close当已支持unload | not_run |
| T19 版本 | 未知protocol major、未知安全字段、schema摘要变化 | 拒绝或明确unsupported；旧prepared冻结失效；无静默降级/默认放行 | not_run |
| T20 有界预算 | 合成超inflight/bytes/deadline；插件或模型试图提高 | 硬上界由host给定；typed拒绝，无无限队列；未执行计数准确 | not_run |
| T21 事件/撤权 | 同域重复、错store/scope/stream、过旧cursor、慢订阅 | 去重不重复apply；错域不混；有界补拉/快照；撤权清投影且不删原回执；ACK不作成功证据 | not_run |

T16子场景均为planned/not_run，合计仍为23个主case：

- **T16.a / 来源绑定等价**：equipment_loan及随机改名同构插件返回带合成外部来源的材料。由可信host fixture绑定真实provider与来源，不读取插件自填authority字段；断言invocation前标记及结果objectRef来源进入同一个HostAuthorizationFacts owner、按实际module/project/object身份计算source digest；不同模块不强求相同digest，但均不得因名称分流而漏记。名称替换无需增改Agent业务分支；测试当前基线时应明确暴露S58的缺口，不能绕过它使测试通过。
- **T16.b / 清洗与持久故障**：manifest、工具结果和模型文本声称clean/none，不能抹除已记录来源或降分类。分别在invoke前来源写入与返回引用写入处注入故障；前者不派发，后者保留已存在原工具回执并拒绝把内容当清洁材料送入下一模型请求。缺事实维持unknown，已锁存事实不因持久失败回退clean；不伪称已发生效果失败或重执行。
- **T16.c / 最终模型用途门**：以离线fake provider/reviewer核对实际编码payload的字节、请求摘要、scope及读取的host task facts；本机read通过不授model许可。模型类别关闭、用途不准、credential或外发unreviewed时零发送；payload及兼容变体发生变化须重新绑定/审查，不能复用另一payload的许可。无真实模型/网络。
- **T16.d / 模式与事实分离**：taint/unknown来源证据仍保留，但新版FullAllow在有效权限用途内不因taint单独增加风险确认；真实无权/撤权/用途禁止/必要内容事实缺失仍拒绝。旧requiresConfirmation布尔值不是新版ModeGrant规则真源，也不能反过来把FullAllow当来源清洗开关。[S41,S59–S62]

T18/T21为生命周期/事件公共面新设计的验收草案，不能冒充当前Dart或experimental支持。设备借用最小完整验收包含T01–T17/T19/T20/T22/T23（注册数据关系、发现、读取、拒绝、撤权、CAS、取消和原回执全部覆盖）；T18卸载与T21订阅只在该可选能力拟开放时成为对应发布门槛。分步实验可以先做read，但必须明确未完成write/CAS/receipt验收，不能据此声称公共插件完整通过。所有case使用可控barrier、假时钟和调用计数；禁止sleep决定时序、真模型、真设备或真实业务数据。新增第二个随机测试module/tool ID作为同一fixture参数，验证换名无需core改动。

## 6. 下一步与未解决问题

1. 本研究和父线程外部近邻研究一起审阅，再确定最小公共catalog/dispatch/projection边界；先不冻结M03。保留目前Rust/Dart writer的实验成果，暂停增加业务专用接线。
2. 需要明确首批支持的schema子集、trusted注册来源、结果投影/用途的可信事实入口（复用既有HostAuthorizationFacts与最终模型payload审查，泛化_external业务名来源分支），以及怎样把现有原业务receipt路由到统一核对。声明不能自授权限是前提，不是待决选项。
3. 源码可直接继承部分不需重建；跨语言生成/编码、DATA/RELATION统一登记、第三插件测试、通用unload、统一订阅与完整分类用途链均尚未实现。它们是设计/实施缺口，不是本只读研究的执行失败。
4. 文档验证仅核SHA/blob/行号、范围、JSON可解析和diff whitespace。没有运行产品测试；不能把阅读测试源码、旧CI或文档检查写成运行时通过。root负责独立审查、sole push/integration。

## 7. 固定源码证据清单

`existing`表示基线已存在机制，非全链验收通过；`gap`表示当前接口/调用链局限；`business`表示保留业务归属；`constraint`表示设计/审查来源；`experimental`仅指固定实验SHA。

| ID | 判定 | 源码事实 | 固定定位 |
| --- | --- | --- | --- |
| S01 | existing | V2模块声明ontology、sections、tools、searchSources、coverage；工具启动时激活前注册。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:packages/muyon_module_api/lib/src/module_v2.dart:12`（至L30） |
| S02 | existing | 重复module ID直接拒绝整个catalog构造；API/依赖/未知capability不兼容按模块标为不可用。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/app/module_registry.dart:14`（至L67） |
| S03 | existing | 真实启动注入InquiryBusinessModule和moduleCatalog；支持modules测试注入。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/app/bootstrap.dart:241`（至L252） |
| S04 | existing | 通用注册、registrar seal、失败withdraw；无逐业务tool名分支。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/app/module_host.dart:254`（至L280） |
| S05 | existing | 模块命名空间+模型function名冲突检查；handler懒激活；descriptor承载schema/effect/cancel。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/app/host_tool_registrar.dart:93`（至L157） |
| S06 | existing | 工具注册检查唯一identity/scope、参数schema及非空resultSchema。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/platform/tool_registry.dart:232`（至L276） |
| S07 | existing | schema是明确受限子集，未知keyword、非object根、深度>24、非法bounds拒绝。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/platform/tool_registry.dart:1211`（至L1299） |
| S08 | existing | 按available/scope/readonly/modelSelectable/category筛候选，随后产生模型投影。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/assistant/agent_task_factory.dart:53`（至L91） |
| S09 | existing | 同一注册descriptor通用投影native function和compat工具描述；无科研/询价特判。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/assistant/agent_task_factory.dart:217`（至L247） |
| S10 | existing | 模型候选受冻结集合约束，所有计划先prepare；参数完整才进入执行。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/assistant/agent_dispatch.dart:112`（至L174） |
| S11 | existing | prepare检查policy/available/scope/parameters/destination/preflight。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/platform/tool_registry.dart:359`（至L389） |
| S12 | existing | invoke执行边界重新检查policy、scope、generation、grant。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/platform/tool_registry.dart:924`（至L959） |
| S13 | existing | handler结果schema/ref检查；取消已触效返回interrupted；持久原回执及receiptFor。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/platform/tool_registry.dart:1069`（至L1155） |
| S14 | existing | 同replayKey同identity合并；异identity冲突。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/platform/tool_registry.dart:858`（至L907） |
| S15 | existing | host GrantPolicy决定；models/knowledge facade-pending拒绝，tools不直接授予V2，已撤权仍拒绝。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/platform/module_grants.dart:25`（至L71） |
| S16 | existing | 决策先记录；required denied或revocation不激活；ModuleResources拿受限capabilities。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/app/module_host.dart:430`（至L474） |
| S17 | existing | 撤权同步epoch失效/withdraw/cancel后持久化；失败fail-closed；关闭drain工具。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/app/module_host.dart:498`（至L559） |
| S18 | existing | ObjectRef拥有module/type/id/project/revision/contentDigest，不是inquiry.object形状。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:packages/muyon_module_api/lib/src/references.dart:12`（至L55） |
| S19 | existing | Sensitivity五值、默认unreviewed；字段声明本身不代表实际值已核。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:packages/muyon_module_api/lib/src/ontology.dart:6`（至L47） |
| S20 | gap | ToolSpec含resultSensitivity，但S05复制字段和ToolDescriptor没有该字段；此字段传递缺口不否定S59–S62既有来源事实及最终payload审查。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:packages/muyon_module_api/lib/src/tool_registrar.dart:55`（至L96） |
| S21 | existing | ContextRef检验项目绑定；ToolDescriptor为语言内JSON值schema，无resultSensitivity/purpose字段。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:packages/muyon_module_api/lib/src/context.dart:24`（至L96） |
| S22 | existing | scope按workspace、实时resolve、identity/revision/digest验证；目录不是授权。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/platform/scope_resolver.dart:55`（至L112） |
| S23 | existing | V2 ModuleScopeSource通过ScopeResolvable/session重新resolve目录候选。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/platform/scope_resolver.dart:118`（至L200） |
| S24 | existing | 数据库schema连续迁移和definitionDigest有合同；不是跨语言wire版本合同。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:packages/muyon_module_api/lib/src/storage.dart:18`（至L62） |
| S25 | gap | ModuleRuntime无通用dispose/unload；session dispose不等同模块卸载。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:packages/muyon_module_api/lib/src/module.dart:75`（至L99） |
| S26 | existing | 变更投影/游标原子入宿主库，catalog派生且使用前重验。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/platform/projection_service.dart:8`（至L80） |
| S27 | gap | 现有watch/onCommit和idle；没有公共跨进程订阅lease/ack/backpressure合同。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/platform/projection_service.dart:104`（至L112） |
| S28 | existing | 预算属于host配置，模型和工具不能提升；任务级steps/time/tokens/call caps已有。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/assistant/agent_budget.dart:1`（至L42） |
| S29 | business | 科研已V2，自带声明、注册、schema、searchSource；不需另写AI adapter。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:packages/research_module/lib/src/research_module.dart:24`（至L119） |
| S30 | business | 科研objects工具按真实范围读取并最多50条；业务对象类型与数据逻辑留在插件。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:packages/research_module/lib/src/module_tools.dart:12`（至L74） |
| S31 | business | 科研read_object支持多个对象类型并用session.resolve；参数type/id是此工具业务schema。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:packages/research_module/lib/src/module_tools.dart:75`（至L190） |
| S32 | business | 询价V2兼容适配器仍依赖HostToolRegistrar和host owner；不能复制为不可信插件的权限入口。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/app/adapters/inquiry_module.dart:30`（至L115） |
| S33 | existing | 业务回执全身份operation/request/tool/scope/domain；notFound并非未执行证明。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:packages/muyon_module_api/lib/src/business_receipts.dart:11`（至L111） |
| S34 | existing | 核对严格比较身份，BusinessReceiptLookup只读不approve/重执行。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:packages/muyon_module_api/lib/src/business_receipts.dart:144`（至L191） |
| S35 | business | 询价实现BusinessReceiptLookup；科研Runtime未声明此接口的直接证据另见S63，不能当两模块统一能力已闭合。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/app/adapters/inquiry_module.dart:159`（至L169） |
| S36 | existing | coverage是数据清单，支持notExposed/deferred，不等于运行时权限。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:packages/muyon_module_api/lib/src/coverage.dart:1`（至L65） |
| S37 | constraint | 已采纳目标：模块自声明、宿主审批回执账本、范围单入口；不是创建第二代理框架。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:docs/adr/0004-module-contract-v2.md:9`（至L22） |
| S38 | constraint | D2唯一模型网关；D5完整调用；D8摘要覆盖工具/能力快照。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:docs/adr/0005-model-adapter-and-agent-loop.md:64`（至L78） |
| S39 | constraint | 单一版本化schema及生成/编码映射尚须M03；版本分轴，未知安全字段不能忽略。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:docs/design/redesign-v1.3.2-20261014/Muyon-Redesign-Plan-v1.3.2-2026-10-14.md:586`（至L594） |
| S40 | constraint | 分类来源与用途限制，插件标签不能自降类或增加许可；credential正文与认证分离。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:docs/design/redesign-v1.3.2-20261014/Muyon-Redesign-Plan-v1.3.2-2026-10-14.md:790`（至L801） |
| S41 | constraint | D01a提案映射四轴与已定四模式；read不造grant、FullAllow不等于无权可执行；本文不冻模式wire。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:docs/contracts/redesign-v1.3.2/authorization-minimal-contract.md:18`（至L51） |
| S42 | constraint | 恢复合同草案：域/schema/current authority、持久游标、有界订阅、旧epoch真实回执另核。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:docs/contracts/redesign-v1.3.2/recovery-minimal-contract.md:30`（至L60） |
| S43 | experimental | Rust host start固定inquiry.object，schema固定type/id，不能宣称通用发现。 | `c4702eecaf50bbdfa3d93faefdadfb1915468b41:experiments/redesign/core-agent-lab/core/src/host_session.rs:34`（至L72） |
| S44 | experimental | 已有HostAuthorizer/HostToolPort接缝；ProjectedToolResult仍单inquiry ref。 | `c4702eecaf50bbdfa3d93faefdadfb1915468b41:experiments/redesign/core-agent-lab/core/src/host_session.rs:77`（至L121） |
| S45 | experimental | Dart host prepare固定inquiry.object并生成live prepared_ref。 | `c4702eecaf50bbdfa3d93faefdadfb1915468b41:apps/muyon/lib/assistant/core_agent_process.dart:461`（至L503） |
| S46 | experimental | host invoke重验、核对原ToolRegistry receipt、只投影受限结果；业务形状非公共合同。 | `c4702eecaf50bbdfa3d93faefdadfb1915468b41:apps/muyon/lib/assistant/core_agent_process.dart:507`（至L591） |
| S47 | experimental | 模型function映射硬编码inquiry.object；需公共catalog投影替换，非再加research分支。 | `c4702eecaf50bbdfa3d93faefdadfb1915468b41:apps/muyon/lib/assistant/core_agent_model.dart:28`（至L42） |
| S48 | experimental | 实验默认关闭、过渡集成、非M03和最终policy/store迁移。 | `c4702eecaf50bbdfa3d93faefdadfb1915468b41:experiments/redesign/core-agent-lab/HOST-CONTRACT.md:1`（至L7） |
| S49 | constraint | 范围/交付/验证/安全/证据诚实为自查要求；最终leader审查与集成。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:docs/tasks/REVIEW.md:1`（至L46） |
| S50 | existing | 已有ObjectTypeSpec/RelationSpec/ActionSpec数据关系动作三类声明；relation含from/field/to/many/queryTool。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:packages/muyon_module_api/lib/src/ontology.dart:69`（至L120） |
| S51 | existing | ModuleOntology汇集对象/关系/动作/flows/rules；当前是Dart元数据对象，不是统一跨语言DATA注册服务。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:packages/muyon_module_api/lib/src/ontology.dart:153`（至L187） |
| S52 | business | 科研声明关系及动作；保留领域关联与tool/operation绑定。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:packages/research_module/lib/src/module_declarations.dart:288`（至L367） |
| S53 | business | 询价从domain.ontology/links/actions投影数据结构、关系、动作，表明共同面可抽取。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/app/adapters/inquiry_module.dart:303`（至L371） |
| S54 | constraint | adopted设计提出Rust domain contracts+wire DTO/IDL+端侧screen registry，Query/Command代raw DB，manifest不是授权；具体schema待冻结。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:docs/design/redesign-v1.3.2-20261014/Muyon-Redesign-Plan-v1.3.2-2026-10-14.md:215`（至L223） |
| S55 | existing | view可继承SnapshotRef/BindingRef/SnapshotFact的事实与来源绑定，非任意业务对象直接渲染。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:packages/muyon_module_api/lib/src/ui/snapshot.dart:14`（至L57） |
| S56 | existing | 已有local/business/semantic动作路由与UI组件schema；不是领域schema或授权owner。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:packages/muyon_module_api/lib/src/ui/plan.dart:4`（至L43） |
| S57 | existing | ModuleSection拥有Flutter builder；新端应投影稳定route/view ID而不是搬Widget进core。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:packages/muyon_module_api/lib/src/module_v2.dart:66`（至L95） |
| S58 | gap | _external按effect/provider及inquiry/knowledge/research名称分流；命中后先记invocation来源，返回后记objectRefs，新本机read插件不会仅因V2登记而继承该来源路径。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/assistant/agent_dispatch.dart:468`（至L529） |
| S59 | existing | 独立于模型消息的HostSourceFact/HostTaskFacts及host-only事实库已存在；缺事实unknown，markExternal先锁存再持久化，失败不洗成clean。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/platform/grants/host_authorization_facts.dart:16`（至L109） |
| S60 | existing | preparePermission编码实际ModelRequest及兼容变体，将最终payload交给已有host model authority。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/assistant/agent_model_turn.dart:366`（至L389） |
| S61 | existing | 模型授权入口检查model类别/当前profile/scope，读取HostTaskFacts并对payload UTF-8字节进行内容审查，再重验policy。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/platform/grants/host_model_authorization.dart:52`（至L133） |
| S62 | existing | 兼容payload变体受绑定限制并重新内容审查/记录，不能沿用不同payload的批准。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:apps/muyon/lib/platform/grants/host_model_authorization.dart:260`（至L305） |
| S63 | business | ResearchRuntime的implements仅ModuleRuntime/ImportCapable/ScopeResolvable/ScopeCandidates，未声明BusinessReceiptLookup。 | `3836149416020a0ac58f9e7ca788c20e66688e0e:packages/research_module/lib/src/research_module.dart:122`（至L123） |
