# T-3 首片：平台全局元数据只读自省

执行基线：fetch 后固定 develop `01404ae472451f55af5baa6ce76c95af72b0cbfc`。
任务分支 `task/t-3-platform-read-tools`；不合入 develop/main，PR 仅 draft。
参考集成任务 `af7c8a47af1ca2f26796aa197ba6dd8065d8a982`，不是已发布基线。
远端分支和开放 PR 初查无活跃 T-3；本工作区没有 AGENTS.md/.agents 技能。

## 交付及契约

新增 `apps/muyon/lib/platform/platform_tools.dart`、`apps/muyon/test/platform_tools_test.dart`。
任务书单独提交；必要 `app/bootstrap.dart` 登记单独最小提交。复用
FoundationRepository、ExecutionStore 的公开读取（后者委托 TaskRecords）、TransferService。
平台不是 BusinessModuleV2；以 `HostToolRegistrar` 的 `platform` 身份登记，manifest
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
悬空或项目任务通知不纳入。无关联通知是宿主全局通知。不扩张现有范围解析或权限。

## 明确未实现

旧 AgentExecutionRecord 有业务 ContextRef，不具有安全的宿主全局归属接口；不列举，
不读取 all()/answer() 或绕过私有字段。项目/选中对象平台查询、完整执行事件正文、
记忆/通知正文、paired devices/网络发现状态、记忆候选提议均另片。不提供数据库级
分页或扫描上限：现有列表接口会物化记录，本片限定返回数量及内容，不能冒称扫描有界。
需要严格扫描预算时应另片增加仓储公开接口，不临时访问 raw SQL。
不宣称完整 T-3 完成。

## 验证

测试先行，云端缺 Flutter/Dart，官方 SDK CONNECT 403 不绕过，使用现有 CI：
先推只有任务书与测试的提交，观察缺失平台工具的断言失败；之后实现并验证最终精确 SHA。
测试覆盖实际宿主登记、参数类型/未知字段/数量拒绝、两种范围拒绝、项目及悬空记录
排除、DB业务表前后不变、脱敏、数量/字符串边界、无文件/网络发送或监听、取消、
错误固定摘要及恢复。registry 自己的 tool_invocation_receipts 是契约要求的审计写入，
不冒称完整 invoke 零 DB 写；另直接测试 handler total_changes() 不变。
C-TOOL 用捕获 registrar 检查 spec、真实 registry 检查 schema/重名/封存；分析 info 仍失败。
命令：`flutter analyze --no-pub`（host）、`flutter test --no-pub test/platform_tools_test.dart`、
`bash scripts/ci.sh`（8个包 analyze、8套测试）。Linux 的 macOS golden 跳过不代表通过。
不得导出 MUYON_EVAL_REAL；原始日志不提交，摘要进提交说明。最终 diff 非作者独立复审，
核对 ls-remote 完整 SHA，跟 CI 至终态；不得把未执行检查写成通过。
