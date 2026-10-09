# T-3 下一片：宿主元数据范围解析隔离（设计草案）

状态：仅设计供审查，未派发产品实现；2026-10-09 fetch 后固定已发布 develop
`3b0adb9e5242dc4a598bf3be71a8252204a9a053`。独立文档分支
`docs/t-3-metadata-scope-design`，不合 develop/main。首片已进入该基线，
历史任务书的“待CI/不合入”是旧执行记录，不代表当前发布状态。

依据：[产品简报](../superpowers/specs/2026-10-04-muspace-product-and-architecture-overview.md)、
[ADR-0004 §10.1](../adr/0004-module-contract-v2.md)、[首片任务书](T-3-platform-read-tools.md)、
[审查要求](REVIEW.md)、[工具契约](../implementation/tool-platform-contract.md)。
执行计划：[最小实现草案](../superpowers/plans/2026-10-09-platform-metadata-scope.md)。
工作区没有 AGENTS.md，/workspace/.agents 为空。此文不更改既有授权与审计定义。

## 目标与冻结范围

使已实现的四个宿主全局元数据工具可以在同一 ToolRegistry 中 prepare/invoke，
且它们的范围解析不触发业务模块初始化、迁移、导入恢复或通知协调。其他工具继续使用
原来的范围解析及必要恢复。下一实现片只验证机制及真实宿主夹具；**不登记生产 bootstrap**。
生产接线须后续独立授权/审查，不因本设计或机制通过而自动开启。

工具 ID/schema、返回界限和 ObjectRef 语义完全沿用首片：
`platform.executions`、`platform.memories`、`platform.notifications`、`platform.device_status`；
仅 global，空 objectRefs/artifactRefs/changes；记录 ID 不成为引用。返回上限20，默认10，
事件数量上限100，返回字符串最长40，记忆仅已验证有效启用项，通知排除项目/悬空任务。
不新增正文、设备列表、记忆候选、仓储扫描预算、外传、端点、权限或模块契约/UI字段。

## 当前链路与问题证据

以下行号均指固定基线，不以旧任务书行号代替新代码：

1. `app/bootstrap.dart:263–272` 创建 registry，只传 scope 到共享 resolver。
2. `platform/tool_registry.dart:294–322` 检查类别/策略、可用性、支持范围、参数和 preflight，
   然后 resolveScope；`:335–346` 才过滤 dataModuleIds。
3. `platform/scope_resolver.dart:60–66` 对各来源先 prepare 再 enumerate；全局还读 knowledgeSources。
4. 来源准备触发 ModuleHost.activate。`app/module_host.dart:377/391` 写 ready/failed 登记，
   `:477–482` 执行 importPipeline 恢复、冲突通知、bridge.afterActivate；
   `app/legacy_module_bridge.dart:91–96` 科研协调已提交导入。
5. registry dispatch 会再次 prepare 核对 identity；随后 HostToolRegistrar._wrap 调用 link.activate。
   首片自己的 _PlatformLink 仅检查宿主可用性，不建立业务 runtime。

首片真实宿主空模块夹具的 `shared global prepare writes lifecycle records before a read handler runs`
已证明：prepare 尚未进入 handler 就增加 total_changes/module_registry failed，refs 最终为空。
此证据只证明激活记账；待恢复业务导入的效果需要新增确定性夹具，不声称已动态证明全部恢复。
正常 host.open 也有迁移、recoverInterrupted 等写入，不能把打开宿主前后差异归到一次读调用。

## 建议的最小接口与受信装配

保留构造参数 `resolveScope: Future<ResolvedAssistantScope> Function(AssistantScope)`。
新增可选宿主回调，**不进入 module_api/ToolSpec/模型 JSON**：

```dart
typedef HostToolScopeResolver = Future<HostScopeResolution?> Function(
  ToolRegistry registry, RegisteredToolInfo tool, ToolCallRequest request);
// tool 是 registry 当前 _Tool.info，不是 request 里自报的 provider/descriptor。
class HostScopeResolution {
  final String identityKey; // 本片唯一有效值 host_platform_metadata_v1
  final ResolvedAssistantScope scope;
}
// ToolRegistry(..., HostToolScopeResolver? hostToolScopeResolver)
```

回调 null 或返回 null：按原 resolver 继续，不改变旧调用 identity 计算。
回调认领时 registry 必须验证：identityKey 为上述固定值、实际 effect 为 read、request.scope
为 global、scope.requested 与 request 等价、scope.objects 为空；违例报
`invalid_scope_resolution`，不吞错或退回有副作用路径。已有支持范围/参数/preflight/策略检查在回调前，
回调错误沿原 prepare 错误传播，不以空范围替代错误。元数据分支不调用 ScopeResolver 或 knowledgeSources。

在现有 `platform/platform_tools.dart` 同一个Dart library内定义
`PlatformMetadataScopeBinding`（私有构造）和
`Future<HostScopeResolution?> resolve(ToolRegistry registry, RegisteredToolInfo tool, ToolCallRequest request)`。
将 `registerPlatformReadTools(...)` 返回值从 void 改为该 binding；装配函数只有在自己通过
真实 registrar 成功登记、封存后，才从 registry 取得这四个 descriptor 的**对象身份**并生成绑定。
不是公开的“按ID扫描绑定任意已注册工具”方法。登记失败不返回绑定；跨 registry 使用不能命中。

binding 认领须同时满足：回调中的registry与装配registry identical，descriptor 与该装配结果保存的对象 identical，providerId/moduleId
均为 platform，ID 为四个精确 ID 之一、effect=read、apiVersion 与绑定时一致、global。
同名同schema的其他 descriptor、仅前缀相同或模块自报 platform 均不认领，走既有检查/默认解析，
不能取得空refs通道。测试必须证明不是只比较字符串。descriptor 的字段与schema仍由现有
注册校验和 identityDigest保护；本片不把描述/schema声称为可信授权源。

宿主夹具先创建 registry（回调闭包初始 binding=null），再调用受信装配取得binding，最后赋给闭包；
初始化期间不对外发布 registry。生产目前仍没有此装配，bootstrap保持原样。
不让业务模块持有binding或新增registrar能力；HostToolRegistrar无需修改。
binding与装配函数共文件，避免跨Dart library调用私有构造器；不为此新增公开按ID扫描factory。

选择理由：提前初始化所有模块会改变启动成本和失败时机；让ScopeResolver“只枚举ready模块”
会漏对象并掩盖未恢复数据；在source层按dataModuleIds跳过prepare会改变所有业务范围语义。
这几种方案均不是本片最小改造。受信回调只隔离确知不消费业务对象的四项投影，默认解析
完整保留，代价是新增一处宿主内部接口和未来生产装配；它不是通用的“所有read纯化”框架。

## identity、授权、审计与取消

只在认领路径的 identityDigest 输入追加 `scopeResolution: host_platform_metadata_v1`。
没有认领时不追加 null/default 字段，保证旧业务 identityDigest、审批和收据兼容。
不改变授权键toolId、effect映射、grant、目的地、审批寿命/消耗、policyRevision、scopeDigest。
同一 invocation/replayKey 仍是相同调用的回执回放，数据变化不把已完成读回执变成自动重读；
需要新快照使用新的 invocation，不自行清空收据。

回调调用前保存当前实际 info、generation；认领路径 await 后核对 generation、登记身份、
availability、policyRevision，变动须拒绝，不能把等待前后的身份拼接。默认业务路径保持现有语义，
避免把合法的模块激活可用性更新误当全局generation违规。dispatch现有再次prepare、
identity比较、关闭/撤权、token检查保留。回调纯内存立即返回，不新增后台任务、超时或重试。
invoke 的预取消仍在 prepare 前拒绝，过程中取消由其 prepare 后/token及handler检查拒绝；
不声称不接收token的直接 prepare API可被取消。可恢复读取错误仍为固定摘要，新invocation可重试。

## 允许的副作用边界

| 场景 | 允许 | 不允许/验证边界 |
|---|---|---|
| 宿主打开/重启 | 原迁移、宿主恢复、设备ID初始化、既有收据恢复 | 不计作本次查询；完成后才能取快照，重启恢复不关闭 |
| 元数据 prepare | 内存身份/schema/权限判断、空refs解析 | 主库任何写入、模块open/activate/migrate/recover、knowledge枚举、通知、文件/网络变化 |
| 元数据 invoke | 既有 tool_invocation_receipts running/结果审计；既有上层任务事件另层核算 | approvals/grant审计/外传账本变化，记忆/已读/业务/模块登记写入，发现/监听/发送 |
| 直接元数据 handler | 公开只读接口投影及内存宿主可用性检查 | total_changes及全部文件字节变化；secret读、runtime激活 |
| 正常业务解析/激活 | 原初始化、条件恢复、冲突通知、已提交导入协调及生命周期登记 | 本片不新建授权例外；保留原协议/凭据，不重新commit已提交操作 |

读取自动授权只覆盖本片投影；模块恢复不是元数据查询例外。也不把所有业务read宣布为
端到端零写入。本片仅分离触发入口，不改变正常业务恢复是否需产品级确认的既有决定。

## 确定性验收矩阵

新建 `apps/muyon/test/platform_metadata_scope_test.dart`，保留原19测试和原副作用复现：

夹具装配明确如下：MuyonHost.open完成后保持其late final host.tools/scopeResolver不变；
另建受测registry复用host.foundation.database，并转发实际host.authorizationPolicy类别/版本。
其默认resolver使用新的ScopeResolver实例，复制host.scopeResolver的来源列表，每项用
实现同一ScopeSource接口的计数代理完整转发prepare/enumerate/resolve/resolvesDirectly，
workspaces复用host.workspaces，knowledgeSources计数后委托原公开callback。
该wrapper下仍是实际ModuleHost来源和知识来源，不能替换为返回空列表的假业务resolver。
元数据binding仅登记到受测registry。业务probe也登记到受测registry，模块源准备仍由host.modules执行；
未增加测试注入bootstrap或更改host.tools。称为“同宿主基础设施的集成夹具”，
**不是生产host.tools端到端接线证明**。B1模块fixture通过MuyonHost.open(modules: [...])
安装含importPipeline的可枚举ScopeCandidates模块，并在打开完成、未激活前预置intent/receipt；
模块activate/receipt/commit计数由fixture runtime提供，文件DB仍用真实StorageManager。
第二registry不在host.close管理集合中：夹具统一close先同步置isAvailable=false，
再await受测registry.close，最后await host.close；P4分别验证registry关闭与宿主可用性撤销。
不能只关闭共享DB，再把数据库异常声称为正确的生命周期撤权。

- P1：同一个真实 registry中手动登记四工具；每个prepare和invoke均返回global空refs，
  resolver/source.prepare/enumerate/knowledgeSources/ModuleHost激活计数为0。主库全表快照
  （invoke只排除tool_invocation_receipts）、模块DB与文件字节/监听状态/外传账本不变。
  prepare单独断言total_changes不变；invoke允许且核对准确收据，不只排除表后放任写入。
- P2：关闭read类别、错误schema、workspace/selectedObjects、预取消、宿主不可用拒绝；
  无业务初始化/恢复。原schema、脱敏、数量和字符边界、固定错误恢复测试全部保留。
- P3：相同ID但provider/module/effect错误、同值不同对象descriptor、跨registrybinding、
  相同前缀的第五工具及request参数伪造lane，不能命中；无覆盖登记、没有写/外传自动许可。
  伪造回调返回非空refs/错scope/错key/write路径必须明确拒绝，不能fallback掩盖。
- P4：Completer控制回调停点；等待期间toggle availability两次（generation改变但末态ready）、
  policy变化、受测registry.close、宿主isAvailable=false、token.cancel，均不能dispatch；
  首次prepare和dispatch再次prepare各设停点。
  成功prepare后撤去binding改变lane也必须identity冲突，无sleep、不增加50ms经验等待。
- P5：新invocation成功、重复并发及重开后完整invocation identity一致时回放一次既有收据；
  保持invocationId/replayKey/schema/generation/policy与原调用一致，参数/lane变更冲突，
  不声称任意重开或策略更新仍能回放。
  重开host的原恢复单独断言、快照从open完成后开始；prepare/invoke二次解析均不激活模块。
- B1：配置模块fixture的未完成ImportCoordinator intent和确定的模块receipt，在同宿主先读
  平台元数据确认pending/binding/notifications完全不变，再走正常业务read/global解析，
  验证receipt恢复为committed、绑定正确、commitImport计数0、模块首次激活1；再次正常解析不重复效果。
- B2：receipt冲突fixture走正常激活，验证原冲突状态/通知规则；科研已提交接收包夹具经正常
  afterActivate协调且恰一次。复用import_recovery_test/accepted_research_import_test的持久协议，
  新夹具直接预置已接收包/回执，不启动其LanNode或TransferService网络setup。
  用确定的receipt/状态断言；不能只spy recover被调用来冒称数据恢复已完成。
- B3：回调null和未认领工具的global/workspace/selectedObjects结果与旧resolver差分一致；
  原grant/审批一用一耗、stale_scope、scopeAuthority污染、destination拒绝及生命周期撤权回归不变。

新隔离夹具不新增网络请求/真实模型取证；既有accepted_research_import回归含loopback通信，
仅作为原有套件保留，不冒称所有宿主测试无网络。CI analyze的info仍失败。动态未运行不记通过。

## 文件归属与并行冲突

下一实现片建议只改 `platform/tool_registry.dart`、`platform/platform_tools.dart`，
新增 `test/platform_metadata_scope_test.dart`；
必要补 `test/tool_registry_test.dart` 的默认identity兼容测试。
不改scope_resolver/module_host/legacy bridge/import coordinator或业务模块恢复代码。
`app/bootstrap.dart` 仅后续生产接线片，当前与下一机制片均不动。

registry与AUTH、REG-2、模块撤权工作强冲突；platform_tools与T-3正文/分页工作强冲突；
bootstrap与AIUI/公共服务装配接线冲突。文档与研究/Q10/UI模块实现可并行。
远端仍保留多个旧REG/AUTH任务分支，名字存在不能证明活跃；后续派发前由父任务核实所有者、
开放PR和最新基线，独占这几个宿主文件，不以本次静态分支列表宣布无冲突。

## 审查裁定与最少问题

本设计不需要用户重新批准已确定的global元数据范围。建议父任务审查通过后派发**机制片**，
保留生产关闭；通过双CI和非作者复审后，再单独决定生产接线时间。
若要求同片上线，唯一需明确的范围问题是：是否把“生产bootstrap登记这四个global元数据工具”
加入下一实现片？当前答案按既有指令为否，不能因未回复而上线。
若审查者不同意允许既有工具收据写入，则应裁定为新审计产品决策，不能删除审计以换零DB写入。
本草案不触发实现，正常恢复行为也不是待本设计豁免的权限扩张。
