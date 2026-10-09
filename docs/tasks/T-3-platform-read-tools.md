# T-3 首片：平台全局元数据只读自省

执行基线：fetch 后固定 develop `01404ae472451f55af5baa6ce76c95af72b0cbfc`。
任务分支 `task/t-3-platform-read-tools`；不合入 develop/main，PR 仅 draft。
参考集成任务 `af7c8a47af1ca2f26796aa197ba6dd8065d8a982`，不是已发布基线。
远端分支和开放 PR 初查无活跃 T-3；本工作区没有 AGENTS.md/.agents 技能。

## 交付及契约

新增 `apps/muyon/lib/platform/platform_tools.dart`、`apps/muyon/test/platform_tools_test.dart`。
任务书单独提交；本片暂不改 `app/bootstrap.dart`，原因见下方集成阻断。复用
FoundationRepository、ExecutionStore 的公开读取（后者委托 TaskRecords）、TransferService。
平台不是 BusinessModuleV2；以装配函数在隔离 registry 中经 `HostToolRegistrar` 的 `platform` 身份登记，manifest
不申请能力、依赖、网络或端点，使用宿主生命周期 link，不激活业务模块。registrar 登记后封存。
每个 ToolSpec 声明具名 query operation，按 C-TOOL 核对，不引入覆盖清单门槛。

| ID | 参数 object（未知字段拒绝） | 成功 data |
|---|---|---|
| `platform.executions` | 可选整数 limit，1–20，默认 10 | items: 全局个人任务的 state、updatedAt、eventCount（上限100） |
| `platform.memories` | 同上 | items: 全局已验证、有效、启用记忆的 kind、revision、updatedAt |
| `platform.notifications` | 同上；可选 boolean unreadOnly，默认 false | items: 无关联或关联全局个人任务的 read、createdAt |
| `platform.device_status` | 空 object | listening: boolean；只读已有 TransferService.listening |

每个读工具有严格 resultSchema、supportsCancel=true，数量上限20；字符输出只有
固定枚举和规范 UTC 时间（最长40字符）。不返回任意数据库字符串、记录ID、提示词、
回答、错误详情、记忆正文/来源/血缘、通知标题/正文、路径、指纹、设备列表或模型端点。
结果只表示调用时的有限元数据快照，不用于业务引用或授权。错误固定摘要、空 data，
取消按现有 token 处理。新 invocation 可在可恢复读取错误消除后重试；不改现有收据语义。

## ObjectRef 与范围

首片不产生平台 ObjectRef：objectRefs/artifactRefs/changes 均为空。
保留未来命名空间 `moduleId: platform`，但不注册对象类型、目录或范围来源，记录ID
不是 ObjectRef。仅声明 global 范围，workspace 和 selectedObjects 在 registry prepare
阶段拒绝，闭包再次检查。Global 在本片仅指宿主全局元数据，不能读取项目对象：
任务须自身 scope 为 global；记忆经 memoriesFor(global)；通知关联任务须可证 global，
悬空或项目任务通知不纳入。无关联通知是宿主全局通知。不扩张现有范围解析或权限；宿主类别开关仍由 registry 执行，隔离测试也断言关闭 read 后四工具均在解析前拒绝。

## 明确未实现

旧 AgentExecutionRecord 有业务 ContextRef，不具有安全的宿主全局归属接口；不列举，
不读取 all()/answer() 或绕过私有字段。项目/选中对象平台查询、完整执行事件正文、
记忆/通知正文、paired devices/网络发现状态、记忆候选提议均另片。不提供数据库级
分页或扫描上限：现有列表接口会物化记录，本片限定返回数量及内容，不能冒称扫描有界。
需要严格扫描预算时应另片增加仓储公开接口，不临时访问 raw SQL。
不宣称完整 T-3 完成。

## 宿主集成阻断（实现前独立复核确认）

现有 `ToolRegistry.prepare` 先调用 `resolveScope(scope)`，之后才按 dataModuleIds
过滤。`ScopeResolver.resolve` 无条件 prepare/enumerate 所有模块；现有 bootstrap
resolveScope 未收到 tool 身份，因此 platform global 调用也会触发业务模块激活、
初始化与恢复写入，部分恢复可能写通知。不把这类写入自创为用户只读授权例外。

本片交付纯 handler 与同 registrar 的装配函数及隔离测试，**暂不在生产 bootstrap
登记**。测试的 registry 只解析 global 的空对象元数据范围，避免激活业务模块，仍使用
真实 ToolRegistry 的 schema、范围、取消与审计路径。整条 invoke 只有既有工具收据写入；
直接 handler DB total_changes 与完整文件字节均须不变。生产接线须另片提供能按工具
身份选择纯元数据范围解析的安全接口并测试；该修改涉及 registry/resolver，超出本片。
不能宣称平台工具已可在生产助手调用，也不宣称完整 T-3 或端到端验收已完成。

### 精确链路与复现分类

基线代码：`tool_registry.dart:322` 调用全局 resolver，`:335–346` 才过滤
allowed dataModuleIds；`scope_resolver.dart:60–66` 先 prepare 每个 source；
`module_host.dart:249–250` 的 source.prepare 委托 activate（legacy 同样如此），
`:368–385` 激活成功/失败都可写 module_registry。

- **初始化/恢复**：成功激活在 runtime ready 后通常被缓存（module_host.dart:316），
  建库/迁移、ModuleRuntime 激活和恢复在首次激活发生；不应为了表面零写入禁用恢复。
  激活失败则可重试，后续 prepare 可再次写失败记录，不保证仅一次。
- **条件业务副作用**：module_host.dart:468–474 的 importPipeline 恢复及
  legacy_module_bridge.dart:123–134 的科研 afterActivate 可能改导入/绑定状态、
  协调已提交业务导入并生成通知。静态确认调用路径；本片不伪造真实待恢复业务数据库
  来声称已经动态复现全部恢复副作用。
- **读取 handler**：新增四个 handler 只投影公开只读接口，直接调用前后
  total_changes 和所有文件字节不变；该证明不能替代范围解析链的验证。
- **工具审计**：真实 registry invoke 仍按契约写 tool_invocation_receipts，
  不是记忆、通知或业务写入；隔离 registry 测试比对其余全部主库表。

最小实际链复现写在 platform_tools_test 的
`shared global prepare writes lifecycle records before a read handler runs`：
MuyonHost.open(modules:[]) → 宿主 registry 登记测试只读 probe（dataModuleIds={platform}）
→ 仅 prepare(global)，尚未执行 handler。基线的固定 legacy sources 仍尝试三模块激活（测试按实际 source IDs 断言），
module_registry 出现 failed，total_changes 增加；resolved refs 最后为空。
develop 在开发期间更新到 `36a516af6af92679fc47b79a1d4679c37258d030`；
REG-3a 迁移改变了 scope source 名单，复现按实际 source IDs 检查，不锁死旧三模块名单。
共享 resolver 先 prepare 后过滤的链路未改变；本分支仍保留原冻结基线。
此空目录夹具不改 notifications/execution_records，也没有工具收据，精确区分失败
激活记账与读取 handler/业务恢复副作用。`d71e212` 的精确 push CI 已动态通过
该复现（基线实际三 source）；目录兼容小修和新增授权测试仍待最终 SHA 的 CI。

### 后续隔离补丁建议（未实施，交父任务协调文件归属）

在 registry 增加可选的**受信宿主工具身份感知范围解析回调**，同时传入实际注册
provider/descriptor 与 request；缺省保留现有 resolveScope 行为。bootstrap 只对
受信 platform 身份、这四个精确 read tool ID、global 范围选择纯元数据解析（空refs），
其他路径继续现有模块恢复与范围解析。不要让模型参数、仅字符串前缀或任意 module
自行选择纯解析通道；write/external/项目/选中调用保持旧控制。

另片测试：平台准备/调用不触发任何 source.prepare/迁移/恢复；业务工具仍正常恢复；
平台两种窄scope拒绝且不先做恢复；伪造provider/ID/effect不能走纯通道；参数、审批、
取消、重复调用/重启收据和旧范围差分测试保持。跨 prepare/dispatch 的身份或策略变化
仍须失效，不能新增授权或模型端点。本片未修改 registry/resolver/bootstrap。

## 验证

测试先行，云端缺 Flutter/Dart，官方 SDK CONNECT 403 不绕过，使用现有 CI：
先推只有任务书与测试的提交，观察缺失平台工具的断言失败；确认范围解析副作用后，
验收改为隔离纯元数据 registry，暂缓生产 bootstrap 登记；之后实现并验证最终精确 SHA。
测试覆盖真实 registrar 的隔离登记、参数类型/未知字段/数量拒绝、两种范围拒绝、项目及悬空记录
排除、DB业务表前后不变、脱敏、数量/字符串边界、无文件/网络发送或监听、取消、
错误固定摘要及恢复。registry 自己的 tool_invocation_receipts 是契约要求的审计写入，
不冒称完整 invoke 零 DB 写；另直接测试 handler total_changes() 不变。
C-TOOL 用捕获 registrar 检查 spec、真实 registry 检查 schema/重名/封存；分析 info 仍失败。
命令：`flutter analyze --no-pub`（host）、`flutter test --no-pub test/platform_tools_test.dart`、
`bash scripts/ci.sh`（8个包 analyze、8套测试）。Linux 的 macOS golden 跳过不代表通过。
不得导出 MUYON_EVAL_REAL；原始日志不提交，摘要进提交说明。最终 diff 非作者独立复审，
核对 ls-remote 完整 SHA，跟 CI 至终态；不得把未执行检查写成通过。

## 验证记录（摘要，无原始日志）

| 精确提交 / 运行 | 观察结果 |
|---|---|
| `d27f3ab7fd2b8998fa7ff33caf92917da182e9d2` / [37967888628](https://github.com/mightyoung/Muyon/actions/runs/37967888628) push | 预期红灯：8/8 analyze；host +1264 ~3 -10，10个新测试均在缺失 platform.executions 登记断言失败；FAILED(test:host) |
| `d71e21245451f6d135da654b71591e0b29f8d4fd` / [37969716642](https://github.com/mightyoung/Muyon/actions/runs/37969716642) push | completed/success；CI SUMMARY OK，analyze 8/8、test 8/8；host +1282 ~3（新增18个），doctor 23场景及门禁回归通过，Laya四组脚本通过 |
| `d71e21245451f6d135da654b71591e0b29f8d4fd` / [37969780240](https://github.com/mightyoung/Muyon/actions/runs/37969780240) PR组合（base 36a516…） | completed/failure；analyze 8/8；host +1300 ~3 -2：旧三source名单断言（actual只有inquiry）与既有 `timed out planning confirmation cannot later send`（cancelled预期，actual waitingConfirmation）；其余7套通过 |

目录兼容小修不锁死旧source名单；新增第19个测试验证关闭宿主read类别后四工具在解析前
拒绝且零DB写入。两项均已经非作者静态复审；最终完整SHA的push及PR组合CI尚待验证。
既有规划超时测试含50ms固定等待，基线到36a516源码未改；本片不修改它、不推断根因，
保留该失败证据并交父任务/原执行者处理。Linux macOS字体golden跳过保持原结论。
本地Flutter/Dart不可用；未把本地未执行的analyze/测试记为通过。未改production bootstrap。
