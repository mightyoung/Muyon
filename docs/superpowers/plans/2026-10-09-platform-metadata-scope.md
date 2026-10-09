# Platform Metadata Scope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在真实registry内隔离四个宿主global元数据工具的范围准备，保留正常业务恢复。

**Architecture:** 可选受信宿主回调认领已装配的实际descriptor对象，未认领路径沿用原resolver。
认领结果为global空refs且带固定identityKey，审批/审计/取消仍走原registry控制。
机制与确定性集成测试先交付，生产bootstrap另片。

**Tech Stack:** Dart、Flutter test、现有SQLite ManagedDatabase、ToolRegistry、HostToolRegistrar。

**Spec:** [T-3-metadata-scope.md](../../tasks/T-3-metadata-scope.md)，执行前须独立审查通过。

## Global Constraints

- 基线固定 `3b0adb9e5242dc4a598bf3be71a8252204a9a053`；实施前fetch更新与所有者协调，不强推。
- 仅四精确platform读ID、global、空ObjectRef；limit默认10/最大20、事件数100、字符串40。
- 不改bootstrap、正常恢复/模块代码、UI契约、权限/端点，不读secret、不发送或发现设备。
- 元数据prepare零DB写，invoke只允许既有工具收据；旧业务identity输入不追加default字段。
- analyze info仍失败；不提交原始日志；云端SDK官方403不绕过，未执行不算通过。

## Review Focus

- descriptor同值异对象或跨registry复制必须不认领：Task 2/P3。
- availability false→true期间generation变化不能让等待中的prepare成功：Task 1/P4。
- pending导入中存在已提交receipt，元数据不恢复而正常业务恢复且不重复commit：Task 3/B1。
- receipt回放返回旧快照，新查询需要新invocation：Task 3/P5。
- 上层task事件/host.open写入与工具调用边界分开计数：Task 3/P1/P5。

---

### Task 1: 可选宿主范围解析入口与identity

**Files:** Modify `apps/muyon/lib/platform/tool_registry.dart`；Test
`apps/muyon/test/platform_metadata_scope_test.dart`、`apps/muyon/test/tool_registry_test.dart`。

**Interfaces:** Produces `HostScopeResolution(identityKey:, scope:)`、
`HostToolScopeResolver = Future<HostScopeResolution?> Function(ToolRegistry, RegisteredToolInfo, ToolCallRequest)`，
以及构造参数 `HostToolScopeResolver? hostToolScopeResolver`；消耗现有默认resolveScope。

- [ ] 写P4、P3坏回调和B3 identity兼容红灯：错误key/refs/scope/effect拒绝，null保持旧identity；
  Completer停点核generation双切换、policy改变、受测registry关闭、宿主不可用和取消的拒绝。
- [ ] 在apps/muyon运行 `flutter test --no-pub test/platform_metadata_scope_test.dart test/tool_registry_test.dart`，
  确认失败为缺失新接口/行为，不能把环境失败作RED。
- [ ] 在现有preflight后调用可选回调；非null验证受限shape、认领generation快照，
  identity仅该分支追加scopeResolution。原fallback/授权/再次prepare/审计不变，不新增schema迁移。
- [ ] 同命令转绿，并 `flutter analyze --no-pub`；摘要记录实际结果。
- [ ] 提交 `feat(t-3): isolate host metadata scope resolution`，原始日志不入库。

### Task 2: 受信四工具绑定

**Files:** Modify `apps/muyon/lib/platform/platform_tools.dart`（binding与装配同library）；
Test `apps/muyon/test/platform_metadata_scope_test.dart`。

**Interfaces:** 消耗Task1类型；产生 `PlatformMetadataScopeBinding`（私有构造），
方法 `Future<HostScopeResolution?> resolve(ToolRegistry registry, RegisteredToolInfo tool, ToolCallRequest request)`；
`registerPlatformReadTools`保留现有具名参数，返回该binding，调用者可忽略返回值。

- [ ] 写P2/P3红灯：真实四descriptor命中，同值替身、跨registry、错误provider/module/effect、
  第五ID、伪造参数均不命中；窄scope/类别禁用/schema在解析前拒绝。
- [ ] 运行 `flutter test --no-pub test/platform_metadata_scope_test.dart test/platform_tools_test.dart` 取得有效RED。
- [ ] 装配成功封存后捕获四个实际descriptor对象生成私有binding；只按规格多重条件认领，
  返回固定key/global空refs，不暴露按ID扫描任意登记项的公共binding构造。
- [ ] 同命令转绿，确认原19测试及旧共享prepare副作用复现保持；`flutter analyze --no-pub`。
- [ ] 提交 `feat(t-3): bind metadata scope to trusted host registrations`；bootstrap不登记。

### Task 3: 同宿主隔离、正常恢复及回放验收

**Files:** Test `apps/muyon/test/platform_metadata_scope_test.dart`；只复用
`test/import_recovery_test.dart`、`test/accepted_research_import_test.dart`和既有宿主夹具，不改生产恢复代码。

**Interfaces:** 消耗Task2 binding，受测第二registry闭包初始null→受信装配返回binding；
复用真实host DB/授权策略、ModuleHost来源与ImportCoordinator，计数代理完整转发ScopeSource。
按规格夹具装配，不改late final host.tools/scopeResolver，不声称生产registry端到端证明。
统一关闭顺序为isAvailable=false→受测registry.close→host.close，不以共享DB异常替代撤权断言。

- [ ] 写P1/P5/B1/B2红灯：隔离前控制夹具明确可触发prepare写入；pending+模块receipt/冲突/科研包
  是直接预置的确定持久状态，新夹具无sleep/网络（不照搬accepted_research的网络setup）。
  元数据先查询不恢复，正常业务后查询恢复且commit计数0；保留反例。
- [ ] 运行 `flutter test --no-pub test/platform_metadata_scope_test.dart`，确认测试区分隔离与旧共享路径。
- [ ] 完成同宿主测试装配和快照、spy、停点；若暴露机制问题仅回Task1/2最小修复再复审，
  不删除恢复、不放宽副作用断言、不修改已有测试挑绿。
- [ ] 运行 `flutter test --no-pub test/platform_metadata_scope_test.dart test/platform_tools_test.dart test/tool_registry_test.dart test/import_recovery_test.dart test/accepted_research_import_test.dart test/scope_resolver_differential_test.dart test/module_lifecycle_regression_test.dart`。
- [ ] 提交测试及摘要，非作者review最终diff，正常push独立task分支；核ls-remote完整SHA，
  跟精确push/PR `bash scripts/ci.sh`至终态（8包analyze、8套test、gate/doctor/Laya），
  保留所有失败，最终PR只draft，不合develop。

## 交接与后置

本设计阶段只提交这两份文档，不执行上述checkbox。自查：每个规格P/B编号均归入Task1–3，
类型与返回值一致，正常恢复与旧授权回归有测试归属，无默认开启生产入口。
执行前父任务确认宿主文件归属并审查规格；本设计不要求用户重新选择既有执行方式。
生产bootstrap接线、仓储扫描预算、记忆提议、项目/选中查询另派，不能随机制实现并入。
