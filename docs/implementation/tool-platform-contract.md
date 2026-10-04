# 公共工具平台契约

实现为 App 原生 Dart 调用，不依赖 OMX runtime。现有科研 `ContextRef` 和 `PermissionDecision` 保持不变。

## 接入

`FoundationRepository` 的版本迁移调用 `installToolRegistrySchema(Database)`，创建审批审计和防重放索引；宿主持有 `ManagedDatabase`，注册表不关闭数据库。个人任务和会话仍由 FoundationRepository 管理。

```dart
final tools = ToolRegistry(database: database, resolveScope: resolveScope);
tools.register(
  providerId: 'public.knowledge',
  descriptor: descriptor,
  dataModuleIds: {'knowledge'},
  handler: (ToolCallContext context) async => result,
);
final preview = await tools.prepare(request);
// 仅受信宿主 UI 在展示并确认准确内容后调用；不得注册为模型工具。
final approvalId = await tools.approve(preview);
final result = await tools.invoke(request.withApproval(approvalId),
    cancellation: cancellation);
```

`list()` 返回不可变 `RegisteredToolInfo` 列表；`inspect(toolId)` 返回元数据或 null；`setAvailability(toolId, available: ..., reason: ...)` 更新可用性并使旧预览失效。注册必须提供真实执行闭包，平台不硬编码候选业务实现。

## 数据范围

`AssistantScope.global()` 没有虚拟项目；`workspace(id)` 指定宿主工作区；`selectedObjects(refs, workspaceId: ...)` 指定既有 `ObjectRef`。providerId 与数据 moduleId 独立。

宿主 `Future<ResolvedAssistantScope> resolveScope(AssistantScope)` 验证当前绑定、对象可见性、存在性及版本，并枚举准确 refs。global/workspace 经注册的 `dataModuleIds` 缩小范围；selectedObjects 不得扩张或静默丢弃不支持的对象。选中引用没有 revision/digest 时允许宿主补齐；显式旧版本拒绝。预览保存实际 refs，执行前重新解析并比较摘要。业务闭包必须只访问解析后的对象；注册表不能拦截任意 Dart 代码绕过此约束直接读数据库。

## 参数与结果

沿用 `ToolDescriptor`。参数 schema 根节点必须为 object，支持 type、properties、required、additionalProperties、items、enum、minimum/maximum、minLength/maxLength、minItems/maxItems、description/title；不支持的关键词在注册时拒绝。默认拒绝未知字段，不做类型转换；数值必须有限且整数在安全范围内，深度、数组、对象和字符串有界。该验证器是明确的 JSON schema 子集。

`ToolCallRequest` 包含 invocationId、toolId、scope、parameters，以及可选 destination、idempotencyKey、approvalId。输入数据深度不可变。`PreparedToolCall` 暴露 request、info、resolvedScope、parameterDigest 和 identityDigest。

`ToolCallResult` 包含 status、summary、data、objectRefs、artifactRefs、executionId。默认结果引用必须属于当前精确范围，artifactRefs 默认禁止。新建对象或宿主制品的工具必须提供 `validateResult(scope, result)`，验证持久归属及允许的目标；该宿主回调承担结果边界。成功结果同时验证 resultSchema（如提供）。

## 审批与恢复

read 每次校验范围；write/external 必须受信宿主确认。export/network 映射 external，并要求明确 destination。`approve` 返回 Future<String> 随机 opaque ID，绑定工具/provider/版本/schema、范围、参数摘要、目标、调用和幂等身份。默认有效期 2 分钟，最大 10 分钟。

tool_approvals 持久记录 issued/expires/consumed；批准消费与 running 防重放收据在同一个数据库事务完成。注册表新实例不接受旧 session 的未消费批准；重启需要重新确认。模型文本、参数中的 userConfirmed、其他调用的批准均不能授权。

同 invocationId、幂等键、完整身份重复调用返回持久结果；身份变化拒绝。同键并发执行一次。重启发现只有 running 收据时返回 interrupted，禁止盲目重放；用户检查实际结果后才能另建操作。摘要采用排序 JSON 的 SHA-256，仅用于内部身份，不宣称 RFC 8785。

`ToolCancellationToken` 支持 cancel/whenCancelled/throwIfCancelled。`ToolCallContext.write(database, body)` 在排队事务内重新检查取消与审批有效期。外部工具在异步准备之后、执行副作用之前调用 `context.checkBeforeEffect()`。已完成的外部副作用无法撤销；取消会丢弃后续结果。持久收据提供防重放保护，不承诺跨外部服务原子提交。
