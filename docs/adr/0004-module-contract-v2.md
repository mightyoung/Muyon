# ADR-0004 模块契约 v2 与三层插件

日期：2026-10-07 · 状态：**已采纳**（用户 2026-10-07：§12.1 Q1～Q13 全部按建议）· 任务：[REG-1](../tasks/REG-1.md) · 阶段：第二阶段（[ADR-0003](0003-phase2-scope.md) 2026-10-07 修订）· 约束：[ADR-0002](0002-graded-assistant-authorization.md)（已采纳，其 §3 硬性底线本文一律不放宽）、[ADR-0005](0005-model-adapter-and-agent-loop.md)（已采纳）· 来源：[AI 原生与注册机制评估](../reviews/2026-10-07-ai-native-and-registration.md)（用户 2026-10-07 决定见其 §6）、[路线图](../superpowers/plans/2026-10-07-roadmap-phase2-4.md) §3.1、[深度研究报告](../reviews/2026-10-05-muyon-deep-review-and-optimization.md) §6.4.1、[v4 审阅](../reviews/2026-10-07-design-v4-review.md) §4

本文只做设计，不改代码。行号基于本分支 `bff8d46`（自 `ecbf120` 起 `apps/`、`packages/` 无变更，已用 `git diff` 核对）。路径省略前缀者：`module_api` = `packages/muyon_module_api/lib/src/`，`host` = `apps/muyon/lib/`。不确定处标“待核实”。

## 1. 背景与目标

用户 2026-10-07 决定：采用注册机制 v2；支持三层插件（原生模块 / 声明式插件 / 内容插件）；能力覆盖作为 CI 硬门槛（评估 §6）。现状的核心问题是：**插件能被助手“用”到什么程度，取决于宿主替它写了什么**；新增一个插件要改宿主十几处（§2.2）。

目标：

1. 模块自己声明一切——清单、本体、工具、分区、检索源——宿主一行登记（§4、§6）；
2. 工具由模块注册，**审批、回执、账本仍只归宿主**，模块不能绕过 `ToolRegistry`（§4.4）；
3. 范围解析只有一个入口 `ModuleSession.resolve`，并支持 S-1（§5）；
4. 能力覆盖可机读、可在 CI 判定（§8）；
5. 三层插件各有明确的信任边界和清单（§7）；
6. 询价、科研、原型迁移不破坏现有测试，尤其 `north_star_inquiry_test` 与 `inquiry_*`（§10）。

非目标：不改界面（UI-8/UI-9 在第三阶段）；不实现声明式插件（REG-6，第三阶段）；不实现授权表与内容审查（AUTH-1/AUTH-2）；不改 ADR-0005 的任务载荷键与 `stage`。

## 2. 现状

### 2.1 逐项现状

| 环节 | 现状 | 依据 |
|---|---|---|
| 契约 | `BusinessModule` 四个成员：`manifest`、`schema`、`routes`、`activate`；`ModuleManifest` 只有 id、API 版本、包修订、依赖；`ModuleRuntime` 必须实现导入三件套 `receipt` / `prepareImport` / `commitImport` 与 `openSession`；`ModuleSession` 有 `resolve`、`objectPage`、`flush`、`dispose` | `module_api/module.dart:8-13`、`:15-31`、`:50-58`、`:60-68` |
| 登记 | 名单写死 `ModuleRegistry([ResearchModule(), PrototypeModule()])`；注册表校验 API 版本（`supportedApiVersion = 1`）、依赖、循环，失败模块标为不可用并给原因；**询价不在注册表** | `host/app/bootstrap.dart:142`；`host/app/module_registry.dart:7`、`:29`、`:19-44` |
| 激活 | 三份各约 50 行的激活代码：`_activateInquiry`、`_activateResearch`、`_activatePrototype`。共同点：并发合并（`_activating ??=`）、失败写 `module_registry` 表并清除记忆以便重试。差异：科研与原型走 `registry.require` → `storage.open` → `module.activate`，并做类型强转 `as ResearchRuntime` / `as PrototypeRuntime`；询价走 `InquiryPlugin.open`，自己打开 **三个库**（`inquiry`、`inquiry_jobs`、`inquiry_hub`），不经 `ModuleResources` | `bootstrap.dart:229-266`、`:273-320`、`:330-366`、`:291`、`:347`；`host/app/inquiry_plugin.dart:169-171` |
| 能力授予 | 宿主启动时登记五项能力（`knowledge`、`models`、`ocr`、`transfer`、`tools`）；授予集合写死在激活代码里：科研 `{knowledge, models, tools}`，原型空集。模块没有“申请”这一步，授予也不留记录 | `bootstrap.dart:214-218`、`:288`、`:344`；`module_api/capabilities.dart:13-24` |
| 工具注册 | 宿主替模块写：`registerBusinessTools(host)` 注册询价 13 个只读工具（循环注册 12 个 `agentTools`，`agent_tools.dart:57-161`；另有 `inquiry.object`）与 `research.objects`，并调用 `registerInquiryWriteTools`（4 个写入）与 `registerPrototypeTools`（2 个只读）；公共服务另有 14 个（`knowledge.*`、`embedding.*`、`ocr.*`、`transfer.*`）；两个询价内部通道；MCP 工具 | `bootstrap.dart:213`；`host/platform/business_tools.dart:179-387`（循环 `:185-287`，`research.objects` `:288-346`，`inquiry.object` `:347-387`）；`host/platform/inquiry_write_tools.dart:62-279`；`host/platform/prototype_tools.dart:46-190`；`host/services/knowledge/public_tools.dart:26-55` 及 14 处 `register(`；`host/platform/mcp_adapter.dart:159-183` |
| 范围解析 | 注册表构造时注入 `resolveScope: (scope) => resolveAssistantScope(host, scope)`；该函数**直接读各模块的库**：询价逐表 `SELECT`、科研遍历项目 / 文档 / 条目并对文档**读文件算 SHA-256**、原型调 `prototypeScopeRefs`，再并入知识库文档；`ModuleSession.resolve` 不参与 | `bootstrap.dart:156-159`；`business_tools.dart:45-177`（询价 `:53-76`，科研 `:77-128`，文件哈希 `:99-112`，原型 `:129-131`，知识库 `:132-137`） |
| 范围模型 | 询价只读工具只支持全局范围；写入工具只支持选中范围；选中范围逐项比对钉住的修订号 / 摘要，不等即 `StateError` | `business_tools.dart:197`、`:161-176`；`inquiry_write_tools.dart:85`；`host/platform/tool_registry.dart:170-177` |
| 导航 | `ModuleRoute` 已声明，**宿主从未读取**（全仓只有定义与两处实现）；首页卡片、模块菜单、激活分支都按模块名硬编码 | `module_api/module.dart:33-37`；`host/screens/platform_shell_home.dart:43-60`；`host/app/app_shell.dart:249-263`、`:516-517`、`:520`、`:536`、`:591`、`:611-635` |
| 检索与索引 | 科研检索适配器（`ResearchSearchAdapter extends SearchService`）、`SearchService._scope` 只认 `research`；索引失效的“取材前核对”按模块名 `switch`（科研三类、询价实体表）后经 `followProjections` 回调接入 | `host/services/knowledge/research_search_adapter.dart:13-26`；`host/services/search/search_service.dart:86-93`（`:88`）；`host/services/knowledge/index_invalidation.dart:8-36`；`bootstrap.dart:171-177`；`host/services/knowledge/knowledge_service.dart:66-71`、`:109-115` |
| 变更日志与目录 | 已经是契约驱动：模块在事务内写 `muyon_change_log`，宿主 `ProjectionService` 增量读取并写 `object_catalog`；但目录只有标题摘要，没有修订号与摘要列；询价的触发器不写 `content_digest` | `module_api/change_log.dart:31-100`；`host/platform/projection_service.dart:53-102`；`host/workspace/workspace_repository.dart:35`；`inquiry_plugin.dart:86-91` |
| 对象页 | `openModuleObjectPage` 要求工作区绑定存在，再按模块名 `switch` 取运行时；原型没有绑定，该函数对原型永远返回 `null`；调用方对科研特判，询价走 JSON 回退页 | `host/platform/object_pages.dart:37-44`（绑定检查）、`:64-75`（`:70-72` 的注释写明原型没有绑定）；`host/screens/platform_shell.dart:149-150`、`:251-290` |
| 设备交换 | 科研任务包 / 结果包的收发、核验后导入由宿主两个科研专用类处理，`TaskCoordinator` 的执行器与回调直接绑它们 | `host/app/research_task_bridge.dart:21-29`、`:67`、`:102`、`:159`；`host/app/accepted_research_imports.dart:53-64`；`bootstrap.dart:169-170`、`:201-212` |
| 询价专用 | `InquiryPlugin`（382 行：迁移、`Store.attach`、`InquiryRuntime.attach`、`InquiryHostModels`）+ 两个授权类，各自在构造时向 `ToolRegistry` 登记 `modelSelectable: false` 的“记录通道”，再由模块的应用闭包经 `prepare → 复核 → approve → invoke` 走完一次受宿主约束的外部效应 | `inquiry_plugin.dart:37-224`、`:227-368`；`host/app/inquiry_hub_authority.dart:9-46`、`:60-143`；`host/app/inquiry_web_authority.dart:9-45`、`:59-148` |

### 2.2 宿主按模块名分支或直接依赖模块包的位置

实测：`apps/muyon/lib` 下 **21 个文件** import 四个业务包之一（`research_module`、`inquiry_module`、`prototype_module`、`supplier_core`），其中 **14 个** import 三个模块包（与评估 §3 的“21 个文件”一致）。

| 类别 | 文件 | v2 去处 |
|---|---|---|
| 登记与激活 | `app/bootstrap.dart`、`app/module_registry.dart`、`app/inquiry_plugin.dart` | `app/module_host.dart`、`app/module_catalog.dart`（§6.1、§6.3） |
| 工具硬编码 | `platform/business_tools.dart`、`platform/inquiry_write_tools.dart`、`platform/prototype_tools.dart` | 各模块的 `registerTools`（§4.4） |
| 范围 | `platform/business_tools.dart:45-177` | `platform/scope_resolver.dart`（§5） |
| 对象页 | `platform/object_pages.dart`、`screens/platform_shell.dart` | `ObjectPages`（§4.5） |
| 导航 / 首页 / 壳层 | `screens/platform_shell_home.dart`、`app/app_shell.dart`、`app/research_tools_page.dart` | `ModuleSection`（§6.4） |
| 检索 / 索引 | `services/search/search_service.dart`、`services/knowledge/{research_search_adapter,index_invalidation,knowledge_service}.dart`、`services/documents/document_parser.dart` | `SearchSource`（§4.5）；后两者 import 的具体符号待核实 |
| 设备交换 | `app/research_task_bridge.dart`、`app/accepted_research_imports.dart`、`screens/devices_page.dart` | `ExchangeCapable`（§4.5） |
| 询价授权 | `app/inquiry_hub_authority.dart`、`app/inquiry_web_authority.dart` | `HostChannel`（§4.4）；类名与构造器作为兼容面保留（§10.3） |
| 仅 `supplier_core` | `assistant/agent_eval/agent_eval.dart`、`screens/chat/transfer_chat_backend.dart`、`services/transfer/transfer_service.dart`（局域网实现） | 不属于模块边界，随“合并两套传输”处理（路线图 §4，第三阶段） |

另有按模块名字符串比较或分支的位置二十余处（`grep "moduleId == '"` 等）：集中在 `business_tools.dart`、`inquiry_write_tools.dart`、`prototype_tools.dart`、`index_invalidation.dart`、`search_service.dart:88`、`research_search_adapter.dart:21,40`、`accepted_research_imports.dart:80`、`app_shell.dart` 与 `platform_shell.dart`。

### 2.3 设计里必须处理的事实

1. **v1 接口被现有测试以 `implements` 固定，不能给它们加抽象成员。** `module_registry_test.dart:5-26` 的 `_Module implements BusinessModule` 只实现四个成员；`import_recovery_test.dart:10` 的 `_Runtime implements ModuleRuntime`；`ManagedDatabase` 至少在 7 个测试文件里被实现（如 `memory_page_test.dart:14`、`research_runtime_test.dart:10`）。这些测试必须保持不改，所以 v2 只能**新增接口与可选参数**（§4.6）。
2. **`tools` 能力就是完整的 `ToolRegistry`。** `bootstrap.dart:218` 把 `host.tools` 登记为能力，`:288` 授予科研；`register` / `approve` / `invoke` 都是公开方法（`tool_registry.dart:82`、`:221`、`:269`），`approve` 只靠注释约束（`:219-220`）。科研包源码里没有取用它（`grep` 无 `require<` 调用，待核实测试里的用法），但能力一旦授予就是能力。v2 必须消除。
3. **全局范围解析是全量扫描，且每次工具执行重做多次。** 询价逐表全扫、科研每个文档读文件算哈希（`business_tools.dart:56-76`、`:99-112`）；一次写入工具的执行至少 4 次 `prepare`（`personal_agent.dart:293` 提议、`:367` 确认时复核，`tool_registry.dart:236` `approve`、`:275` `invoke`、`:387` `_dispatch`），只读至少 3 次，每次都调 `resolveScope`（`:170`）。
4. **`ModuleSession` 按单个工作区项目绑定，所以范围解析绕过了它。** `ResearchRuntime.openSession` 要求绑定里的项目存在（`research_module.dart:369-376`），`resolve` 对其他项目的引用返回 `null`（`:397-400`）；询价根本没有会话。此外：科研 `_resolve` 的 `switch` **没有 `project` 类型**（`:411-505`，宿主范围里却有科研项目，`business_tools.dart:79-98`）；两个模块的 `resolve` 都**回显请求里的引用**（`research_module.dart:408`，`prototype_module.dart:85,91,101`），不返回当前修订号与摘要。
5. **目录没有版本信息。** `object_catalog` 只存 5 列（`workspace_repository.dart:35`），变更日志里有修订号与摘要列，询价的触发器不写摘要（`inquiry_plugin.dart:88-91`）。所以目录只能当“候选清单”，不能当真相。
6. **外传类工具不入出站账本。** `outbound_requests` 的列绑定模型 profile（`profile_id`、`model_id` 非空，`outbound_ledger.dart:16-34`），只有模型网关写它（`model_gateway.dart:124`；`grep` 未见其他写入点，待核实）。MCP 调用、询价的网页 / 资料中心通道目前只留 `tool_invocation_receipts` 回执（`tool_registry.dart:11-15`）。ADR-0002 §3.4 要求“出站账本照常逐条入账”，v2 不能把这个缺口带进“模块注册的外传工具”（§9.1、§12.1 Q4）。
7. **询价通道的“复核”对话框由模块界面提供。** 两个授权类的 `run` 接收 `review` 回调，再自己 `approve`（`inquiry_hub_authority.dart:93-106`，`inquiry_web_authority.dart:94-106`）；回调来自 `inquiry_module`（`features/hub/hub_confirmation.dart:8`，`features/ai/assistant_confirmation.dart:6,19,41`）。这些通道 `modelSelectable: false`，助手不会走到；但“授权只能由用户在宿主界面给出”（ADR-0002 §3.1）对它们现在是靠“模块是自家代码”成立（§7.2）。
8. **Folio 有第二套助手与第二套授权。** `Store.ask` 自带工具循环（`assistant.dart:101-150`），写入工具 `create_record` / `update_record` / `delete_record` / `restore_record`（`assistant_actions.dart:118-121`）经模块自己的确认框后直接 `store.save` / `delete` / `restore`（`assistant_actions.dart:354-364`），只留模块私有的回执（`:342-343`）；`AssistantPermission.bypass` 让“按策略批准的写入不弹窗”（`assistant_actions.dart:11-13`，设置在 `app_state.dart:451-458`）。这条路径没有宿主 `tool_invocation_receipts` 回执、没有 ADR-0002 的授权审计、`bypass` 不绑定范围。
9. **科研 / 原型的对象摘要算法已与宿主重复实现。** 例如科研条目的摘要在宿主与 `_resolve` 里各算一遍并要求一致（`research_module.dart:441-452` 注释，`business_tools.dart:114-126`）。迁移必须保持**算法逐字节一致**，否则已存的引用（任务载荷、知识库 `source`）会变成“已过期”（§5.2、§11）。

## 3. 决定概览

| # | 决定 |
|---|---|
| D1 | **v2 是新增接口，不改 v1**：`BusinessModuleV2 implements BusinessModule`，`ModuleManifest` 只加可选参数；API 版本 2；过渡期 v1 / v2 并存（§4.6）。 |
| D2 | 模块在清单里**申请**能力，宿主按策略授予并**记录**（`module_grants`）；v2 模块拿不到 `ToolRegistry`，`tools` 能力对 v2 一律拒绝；`models` 能力换成经闸门与账本的门面（§6.2）。 |
| D3 | 模块通过 `ToolRegistrar` **声明**读 / 写 / 外传工具与受宿主约束的“记录通道”；`prepare`、审批、回执、账本、授权解析只在宿主；模块没有任何调用 `ToolRegistry` 的入口（§4.4）。 |
| D4 | `ModuleSession.resolve` 是“某个引用现在是否存在、版本是什么”的**唯一权威**；宿主单点 `ScopeResolver` 以目录为候选、以 `resolve` 为真相（§5）。 |
| D5 | **S-1**：读工具可用于选中范围；宿主依“已批准写入的成功回执”并经 `resolve` 复核后推进钉住的修订号；写入后的对象与新建对象按声明并入范围；同一任务可先读后写（§5.3）。 |
| D6 | `ModuleOntology` 声明对象类型、字段（含**敏感属性**三态）、关系、动作、流程、示例问法；既喂数据中心的 6 项检查，也喂 ADR-0002 的内容审查（§4.3、§9）。 |
| D7 | 导航、首页、对象页、检索源改为**按声明驱动**；宿主 `platform/`、`services/`、`screens/` 不再 import 模块包（§6.4、§6.3）。 |
| D8 | 通用 `ModuleHost.activate(id)` 取代三份激活代码；失败隔离语义不变（§6.1、§6.5）。 |
| D9 | **能力覆盖清单**：每个模块用 Dart 常量声明“业务操作 → 工具 id 或不开放理由”；操作面由 `analyzer` 读源码枚举（无运行时反射），双向比对，成为 CI 硬门槛（§8）。 |
| D10 | 三层插件：L1 原生模块（编进应用，与宿主同等信任）、L2 声明式插件（远端服务，一律按外传类，不接触本机业务数据）、L3 内容插件（WebView，不访问业务数据）（§7）。 |
| D11 | 询价分三步迁移：先“宿主侧适配”保持全部兼容面，再补工具，最后把 Folio 自带 AI 工具化并在宿主模式下隐藏其对话助手（§10.4）。 |
| D12 | **不放宽 ADR-0002 §3**：任何模块注册的写入 / 外传工具都只能经 `ToolRegistry.prepare → 一次性审批 → invoke`；v2 的所有新机制只收紧（§9.1）。 |

## 4. 契约 v2 接口草案（Dart，示意，非最终签名）

### 4.1 兼容原则

- 不改 v1 任何抽象成员的数量与签名（§2.3-1）。新增的都是**新接口、可选参数、可选能力接口**。
- 宿主用 `is` 检查可选接口，用清单里的 `features` 声明交叉校验：声明了就必须实现，实现了没声明则宿主不使用。
- 所有新增数据类沿用 `module_api` 现有风格：构造时 `Map` / `List` / `Set` 冻结、JSON 可序列化（`freezeJsonMap`，`module_api/context.dart:7`）。

### 4.2 `BusinessModuleV2` 与清单

```dart
abstract interface class BusinessModuleV2 implements BusinessModule {
  @override ModuleManifest get manifest;      // apiVersion == 2
  ModuleOntology get ontology;                // §4.3；无业务对象的模块给 ModuleOntology.empty
  List<ModuleSection> get sections;           // 取代 routes；v2 模块的 routes 返回 const []，宿主不读
  List<AuxiliarySchema> get auxiliarySchemas; // 额外物理库（询价：inquiry_jobs、inquiry_hub），默认 const []
  void registerTools(ToolRegistrar registrar);// §4.4；宿主在启动时调用，不等激活
  List<SearchSource> get searchSources;       // §4.5
  CapabilityCoverage get coverage;            // §8.2
}

class ModuleManifest {                        // 在现有构造器上只加可选命名参数（缺省 = v1 行为）
  ModuleManifest({
    required this.id, this.apiVersion = 1, this.packageRevision = '0.1.0',
    List<String> requiredDependencies = const [], List<String> optionalDependencies = const [],
    this.displayName, this.tagline, this.iconKey,
    Set<CapabilityRequest> capabilities = const {},   // 申请的平台能力
    Set<ModuleFeature> features = const {},           // 声明实现了哪些可选接口
    this.network = NetworkPolicy.none,                // 该模块的外传工具可去哪些目的地
  });
}
class CapabilityRequest { final String id; final bool required; final String reason; }
enum ModuleFeature { importPipeline, exchange, objectPages, publishChecks, resultRenderers }
class NetworkPolicy {                                 // 只能收紧：宿主在 prepare 前比对工具的 destination
  const NetworkPolicy({this.fixedHosts = const {}, this.publicWeb = false});
  final Set<String> fixedHosts; final bool publicWeb;  // publicWeb：任意公网 https，仍受既有 SSRF 检查
  static const none = NetworkPolicy();
}
class ModuleSection {                                 // 导航分区的声明（界面改造在第三阶段，ADR-0003）
  final String id, label; final String? tagline, iconKey, group;  // group：分区归属，UI-8 / UI-9 消费
  final int order; final bool requiresWorkspace;
  final Widget Function(BuildContext context, ModuleSectionHost host) builder;
}
class AuxiliarySchema { final String id; final ModuleSchema schema; }   // 物理库 id 沿用 `^[a-z][a-z0-9_]*$`
```

`ModuleResources` 增加可选命名参数 `auxiliary: Map<String, ManagedDatabase>`（默认空）；`ModuleCapabilities` 增加 `Set<String> get denied`（便于模块降级）。`Future<ModuleRuntime> activate(...)` 不变；不支持导入的 v2 模块用 `module_api` 提供的 `NoImportRuntime` mixin 实现导入三件套（返回 `UnsupportedError`，行为同 `prototype_module.dart:54-65`），并**不**在 `features` 里声明 `importPipeline`，宿主据此不调用导入协调器。

可选的子接口：`abstract interface class ExclusiveDatabase implements ManagedDatabase { Future<T> exclusiveAsync<T>(FutureOr<T> Function(Database) body); }`，由宿主的 `ManagedConnection` 实现（`storage_manager.dart:11`、`:57`），询价的 `Store.attach(backgroundExecutor: …)` 用它（`inquiry_plugin.dart:179-184`）；`ManagedDatabase` 本身不动。

### 4.3 `ModuleOntology`（含敏感属性）

在 `supplier_core/ontology.dart` 已有结构的基础上（`Kind`、`FieldSpec`、`ObjectType`、`LinkType`、`Rule`、`ActionType`，`:15-109`；`ontology` / `links` / `rules` / `actions` 常量，`:659-717`；类型与字段已由 `ontology_test` 对照校验器），**抽成与业务包无关的契约类型**放进 `module_api`，询价侧写一个适配器把 `supplier_core` 的常量映射过去（`supplier_core` 不依赖 `muyon_module_api`，保持不变）。数据中心稿的声明形状（`ontology.entities`、`relations[].query`、`actions[]`、`flows[]`、`sensitive: true`、`examples[]`，见[数据中心稿](../design/v4/Muyon%20Data%20Center.dc.html)的检查项文案）一一对应：

```dart
enum Sensitivity { unreviewed, none, personal, commercial, credential }  // 默认 unreviewed = “未标记视为未检查”
class OntologyFieldSpec {                                     // 不叫 FieldSpec：避免与 supplier_core 同名类冲突
  final String name, label, description; final FieldKind kind; final bool required;
  final Map<String, String>? values; final String? target;   // 同 supplier_core
  final Sensitivity sensitivity;                              // 默认 Sensitivity.unreviewed
}
class ObjectTypeSpec {
  final String name, label, description, iconKey, titleField; // titleField ∈ fields
  final List<OntologyFieldSpec> fields;
  final bool inGlobalScope;      // 是否参与全局 / 工作区范围枚举（§5.2）；原型：page / version / feedback 为 true
  final bool versioned;          // resolve 是否返回 revisionRef
  final ObjectPageSupport page;  // ObjectPageSupport.unbound | bound | none(reason)
}
class RelationSpec { final String name, from, field, to; final bool many; final String? queryTool; } // queryTool：只读接口的工具 id
class ActionSpec   { final String name, label, description; final String? tool; final String? operationId; final String? humanOnlyReason; }
class FlowSpec     { final String name, label; final List<FlowStep> steps; }          // step 绑定 tool 或 action
class ExampleSpec  { final String question; final List<String> expectTools; }          // 示例问法与期望工具
class ModuleOntology {
  final List<ObjectTypeSpec> objectTypes; final List<RelationSpec> relations; final List<ActionSpec> actions;
  final List<FlowSpec> flows; final List<ExampleSpec> examples; final List<RuleSpec> rules;
  static const empty = ModuleOntology(...);   // 原型（WebView 内容，v4 稿：数据中心显示“不适用”）
}
```

要点：

- **敏感属性三态**：`unreviewed`（默认，数据中心第 5 项检查视为“未检查”）/ `none`（已审阅，不敏感）/ 具体类别。类别词表 `personal`、`commercial`、`credential` 同时作为 ADR-0002 / ADR-0005 `dataCategories` 的取值来源（§9.1）。**合规套件要求每个字段都已审阅**（不得是 `unreviewed`），这是比“数据中心可发布”更早的构建门槛（评估 §4）。
- 询价现状里**没有任何敏感标记**（`ontology.dart` 无此概念；`grep` 命中的 “sensitive” 均为大小写不敏感之意，待核实）。字段初稿由 REG-4 给出，**最终划分需用户确认**（§12.1 Q7）。
- `ontology.dart:104-109` 与 `:707` 的注释“Agents only read; each action is carried out by a person”会随 REG-4 补写入工具而不再成立；`describe` 工具把 `actions` 讲给模型听，REG-4 必须同步改文案（相关 `ontology_test` 是否钉住该文案待核实）。
- 本体声明**不含实例数据**；实例浏览与遮盖是 DC-3 的事（第三阶段）。

### 4.4 `ToolRegistrar`：模块声明，宿主执行

```dart
abstract interface class ToolRegistrar {           // 只在 BusinessModuleV2.registerTools 内有效；返回后封存
  String get moduleId;
  void read(ToolSpec spec, ModuleToolHandler h);               // effect = read
  void write(WriteToolSpec spec, ModuleToolHandler h);         // effect = write
  void external(ExternalToolSpec spec, ModuleToolHandler h);   // effect = export | network
  HostChannel channel(ChannelSpec spec);                       // modelSelectable = false 的受约束通道
}
class ToolSpec {
  final String name;                 // 模块内唯一；宿主拼成 `<moduleId>.<name>`，即 toolId
  final String description;          // 给人与模型看；不构成授权，处理方式同 ToolDescriptor.description（context.dart:90）
  final Map<String, Object?> parameterSchema, resultSchema;      // 受限 JSON Schema 子集（tool_registry.dart:489-504 的关键字表）
  final Set<AssistantScopeKind> scopes;   // 读：默认 global / workspace / selectedObjects；写：默认 selectedObjects
  final List<String> operations;     // 覆盖清单里的 OperationSpec.id（§8.2）
  final bool supportsCancel;
  final List<ToolExample> examples;  // 合规套件执行用的夹具参数（读纯度、范围泄漏，§8.1）
  final Map<String, Sensitivity> resultSensitivity; // 结果字段路径 → 类别（内容审查用，§9.1）
}
final class WriteToolSpec extends ToolSpec {
  final Set<String> targetTypes;    // 被改写的类型
  final Set<String> createsTypes;   // 会新建的类型
  final Set<String> deletesTypes;   // 会删除的类型（A4）
  final Set<String> affectsTypes;   // 副作用会改到的其他类型，如 award 回写预算行、mergeInto 改指向的引用方（A5）
}
// ToolCallResult 增加可选字段 `changes: List<ObjectChange>`，ObjectChange{ref, op: upsert | delete}；`objectRefs` 语义不变，`changes` 供范围推进使用（§5.3）
final class ExternalToolSpec extends ToolSpec { final ToolEffect effect; final DestinationRule destination; }
typedef ModuleToolHandler = Future<ToolCallResult> Function(ModuleToolContext ctx);
abstract interface class ModuleToolContext {       // 包装 ToolCallContext（tools.dart:125），再加模块运行时
  ToolCallContext get call;                        // request、resolvedScope、cancellation、checkBeforeEffect
  Future<T> runtime<T extends ModuleRuntime>();    // 宿主已确保模块激活；失败时不会调用 handler
}
abstract interface class HostChannel {             // 把 InquiryWebAuthority / InquiryHubAuthority 的共同骨架收归宿主
  Future<T> run<T>(ChannelRequest request, Future<T> Function(EffectGuard guard) effect,
      {required ToolCancellationToken cancellation,
       ChannelReview? review});                      // 第二阶段：由模块界面传入，同今天；宿主界面接管在 UI-9 之后（§9.1）
}
```

**宿主实现 `HostToolRegistrar(moduleId, ToolRegistry)` 强制：**

| 规则 | 做法 |
|---|---|
| 身份 | `toolId = '<moduleId>.<name>'`，`providerId = moduleId`，`descriptor.moduleId = moduleId`；toolId 须满足 ADR-0005 §4.2 的函数名编码（`.`→`__` 后 ≤ 64 字符且全局无冲突，`llm_selection_eval.dart:100-121`），宿主启动时检查冲突 |
| 效应不由规格自报 | 效应由调用的方法决定（`read` / `write` / `external`）；`ToolRegistry._dispatch` 对非读工具必须有未消费的一次性审批（`tool_registry.dart:344-367`），模型发起的调用因此没有绕行入口（对模块代码的约束见下文第 3 条） |
| 封存 | `registerTools` 返回后，registrar 再收到调用即抛错；v2 模块运行期不能追加工具（声明式插件走宿主自己的适配器，§7.3） |
| 范围 | `dataModuleIds` 固定为 `{moduleId}` ∪ 清单 `requiredDependencies`；`supportedScopes` 取 `spec.scopes`；写工具缺省只支持选中范围 |
| 结果校验 | 默认 `validateResult`：结果引用须属于已解析范围，写入工具再加“被写对象所属项目 ⊆ 选中对象的项目”——即把 `validateInquiryWriteResult`（`inquiry_write_tools.dart:38-57`）泛化为宿主默认；模块只能在其上加严 |
| 目的地 | 外传工具必须带 `destination`（`tool_registry.dart:163-169`）；宿主先按 `DestinationRule` 与清单 `network` 比对再 `prepare`，不符直接 `blocked`；MCP 适配器里“已批准目的地须等于该服务器”的检查（`mcp_adapter.dart:213-219`）升格为宿主检查，handler 内保留作纵深 |
| 可用性 | 模块激活失败 / 关闭时，宿主对其全部工具 `setAvailability(false, reason)`（`tool_registry.dart:126-139`，与两个授权类 `disable()` 同法，`inquiry_hub_authority.dart:49-53`）；今天失败时工具仍“可用”，handler 里才 `StateError(host.inquiryError…)`（`business_tools.dart:203-205`），模型会白白提议 |
| 懒激活 | 宿主在分发前 `await ModuleHost.activate(moduleId)`，取代每个 handler 开头的 `await host.activateInquiry()`（`business_tools.dart:201`、`inquiry_write_tools.dart:90`、`prototype_tools.dart:47-54`） |

**“模块不能绕过宿主审批调用写工具”——准确表述**（用户要求的核心不变量；不夸大为结构性隔离）：

1. **模型发起的调用**：到达 handler 的唯一路径是 `ToolRegistry.invoke → _dispatch`，其中写入 / 外传工具必须消耗一次性审批，并先落 `tool_invocation_receipts` 的 `running` 回执（`tool_registry.dart:319-379`，审批检查 `:344-367`）。宿主不暴露任何跳过它的入口；
2. v2 模块拿不到 `ToolRegistry`，也没有 `invoke` 形式的门面——助手是工具的唯一调用方；`tools` 能力对 v2 模块一律 `capability_denied`（§6.2）；
3. **但 handler 是模块自己的函数，模块代码持有它的引用**（`registerTools` 里传入的闭包；`_Tool.handler` 只是宿主私有字段，`tool_registry.dart:59`，并不使模块“得不到”）。所以第 1 条保护的是“模型与助手的路径”，**不是对模块代码的结构性隔离**：L1 与宿主同等信任（§7.2），这条靠评审规则 R-L1-3 与 lint 保证。新增一条**评审项**（不是自动门槛，REG-5 写入 REVIEW.md）：模块不得在 `registerTools` 之外直接调用写 / 外传工具的 handler；handler 宜写成 `registerTools` 内的局部闭包或不导出的私有函数，使这类调用在代码审查里显眼；
4. 模块**自己界面里**的用户操作（点击“定标”）不是工具调用，仍直接走领域函数——这是用户本人的动作，不经助手；模块**不得**把“模型输出”直接变成写入而不经上述两种之一（R-L1-3）；
5. 需要外部效应的模块代码（网页读取、资料中心发布）只能经 `HostChannel.run`：宿主依次 `prepare` → **复核** → `approve` → `invoke`。**第二阶段的复核回调仍由模块传入**，与今天一致（`inquiry_hub_authority.dart:93-106`、`inquiry_web_authority.dart:94-106`，回调来自 `inquiry_module`）；宿主在第二阶段保证的只有**审批签发、回执与账本**，不保证复核界面是宿主自有的；宿主自有的复核界面在 UI-9 之后接管（§9.1、§12.1 Q3）。助手发起的路径不使用通道（`modelSelectable: false`）。

回执、账本不由模块写：`HostToolRegistrar` 不暴露任何写 `tool_invocation_receipts` / `tool_approvals` / `outbound_*` 的接口。

### 4.5 可选能力接口

| 接口 | 契约 | 宿主侧消费者 | 说明 |
|---|---|---|---|
| `ImportCapable`（`features: importPipeline`） | v1 的导入三件套原样（`module.dart:51-56`、`files.dart:15-86`） | `ImportCoordinator`、`app_shell.dart:320-420` 的导入流程 | 只对声明了的模块调用 |
| `ExchangeCapable`（`exchange`） | `Set<ExchangeKind> kinds`（如 `research-task`、`research-result`）；`inspect(envelope)` 核验、`accept(envelope, session)` 导入。**传输、配对、核验落盘留在宿主**，模块只解析与导入 | 通用 `ExchangeRouter` 取代 `ResearchTaskBridge` / `AcceptedResearchImports` 对 `host.research` 的直接引用（`bootstrap.dart:169-170`、`:201-212`） | `TransferItem` 等宿主类型须先抽成与宿主无关的 `ExchangeEnvelope`；接口形状在 REG-3 随科研迁移定稿（待核实） |
| `ObjectPages`（`objectPages`） | `Future<ObjectPageLease?> open(BuildContext, ObjectRef)`；`ObjectPageLease { title, page, dispose() }`（即 `ModuleObjectPage` 的泛化，`object_pages.dart:9-21`）；**不要求工作区绑定** | `openObject` 与对象页入口 | 修复原型对象页永远打不开（绑定检查，`object_pages.dart:37-44`），即路线图 §7 的“无绑定 objectPage”；返回 `null` 时宿主回退到通用页 |
| `SearchSource` | `id`、`objectTypes`、`list(IndexScope)`（当前可索引的引用 + 本机文件或文本 + 摘要）、`confirm(ObjectRef)`（取材前核对，等价于 `resolve` 且摘要一致） | `KnowledgeService`（统一索引）、`index_invalidation` | 取代宿主里的 `ResearchSearchAdapter` 与 `confirmIndexedSource` 的按名 `switch`；`SearchService` 的科研专用部分随 REG-3 移入科研包 |
| `ResultRenderers`（`resultRenderers`） | `Map<String, ToolResultRenderer>`：toolId → 对话内卡片 | UI-4 助手栏（第三阶段） | 第二阶段只定义接口，宿主不消费 |
| `PublishChecks`（`publishChecks`） | `Future<List<PublishCheckResult>> run(PublishContext)`：模块自加的检查与“去哪里改”提示 | 数据中心（DC-1，第三阶段） | 6 项基础检查由宿主从 `ModuleOntology` 与注册表**自动**产出，不需要模块实现（§9.3） |

签名骨架（示意；`ImportCapable` 的方法即 v1 导入三件套，不重复）：

```dart
abstract interface class ExchangeCapable {
  Set<ExchangeKind> get exchangeKinds;                                   // 如 'research-task'、'research-result'
  Future<ExchangeVerdict> inspect(ExchangeEnvelope envelope);            // 核验：接受 / 拒绝(原因)；不落盘
  Future<void> accept(ExchangeEnvelope envelope, ModuleSession session); // 宿主核验并落盘后调用，幂等
}
abstract interface class ObjectPages {
  Future<ObjectPageLease?> open(BuildContext context, ObjectRef ref);    // 不要求工作区绑定；null = 无页面
}
class ObjectPageLease { final String title; final Widget page; final Future<void> Function() dispose; }
abstract interface class SearchSource {
  String get id;
  Set<String> get objectTypes;
  Future<List<IndexableItem>> list(IndexScope scope);                    // IndexableItem{ref, filePath | text, contentDigest}
  Future<ObjectView?> confirm(ObjectRef ref);                            // 取材前核对；null = 已不存在或摘要不符
}
abstract interface class ResultRenderers {
  Map<String, ToolResultRenderer> get renderers;                         // toolId → (BuildContext, ToolCallResult) → Widget
}
abstract interface class PublishChecks {
  Future<List<PublishCheckResult>> run(PublishContext context);          // PublishCheckResult{id, passed, fixHint}
}
```

### 4.6 与 v1 的兼容与过渡

| v1 | v2 处理 |
|---|---|
| `BusinessModule` | 不改。新增 `BusinessModuleV2 implements BusinessModule`；v2 模块仍须实现 `routes`（返回空表），宿主不读 |
| `ModuleManifest` | 只加可选命名参数（§4.2）；`module_registry_test`、`contract_v1_test` 的构造调用原样可用 |
| `ModuleRuntime` | 不改；`NoImportRuntime` mixin 供不做导入的新模块使用 |
| `ModuleSession` | 不改成员；`resolve` 的语义加严（§5.1）；新增可选接口 `ScopeResolvable { Future<ModuleSession> openScopeSession(); }`（跨项目、无绑定的解析会话，§5.1） |
| `ManagedDatabase` | 不改；新增子接口 `ExclusiveDatabase` |
| `ModuleRegistry.supportedApiVersion = 1` | 改为 `supportedApiVersions = {1, 2}`（该常量仅在 `module_registry.dart:7,29` 使用，测试以 `apiVersion: 99` 断言“不可用”，不受影响）。`apiVersion: 2` 但未实现 `BusinessModuleV2` → 标为不可用，原因 `Declared API v2 without BusinessModuleV2` |
| 过渡 | REG-2～REG-3 期间 v1 模块（科研、原型）继续走宿主里的硬编码路径（`LegacyModuleBridge`，仅登记工具与对象页的旧 `switch`），逐个迁到 v2 后删除；REG-5 之后一个阶段（第三阶段末）移除 v1 路径与 `routes`（§12.1 Q9） |

## 5. 范围解析与 S-1

### 5.1 `ModuleSession.resolve` 成为唯一入口

对 `resolve` 的**契约加严**（每个 v2 模块都要满足，合规套件逐条检查，§8.1）：

1. 返回的 `ObjectView.ref` 是**规范的当前引用**：`versioned` 类型必须带当前 `revisionRef`，凡声明有内容摘要的类型必须带 `contentDigest`；不得回显请求（修正 §2.3-4 的回显问题）；
2. 引用里钉住的 `revisionRef` / `contentDigest` 与当前不符 → 返回 `null`（科研已如此，`research_module.dart:404-407`）；
3. 凡 `ObjectTypeSpec.inGlobalScope` 或 `ObjectPageSupport != none` 的类型都必须可解析（补科研 `project`）；
4. 不需要工作区绑定：模块实现 `ScopeResolvable.openScopeSession()`，返回可解析**任意项目**引用的会话（科研：以未限定项目的 `WorkbenchStore` 按 `ref.nativeProjectId` 分派，`store.scoped` 已有，`research_module.dart:374`；询价：`store.get` + 版本 + 行摘要；原型：已不依赖绑定，`prototype_module.dart:77-109`）。原有 `openSession(binding)` 不变，继续服务模块自己的页面；
5. 摘要算法与今天宿主里的实现**逐字节一致**（§2.3-9）。科研文档摘要今天是“每次读文件现算”（`business_tools.dart:99-103`），而 `resolve` 用库里存的 `sha256` 列（`research_module.dart:413-420`）——**二者语义不同**（磁盘被改而库未更新时，宿主能发现、模块发现不了）。每个类型在 `ObjectTypeSpec` 里声明 `verifyOnDisk`，REG-3 逐类型定（待核实，§11）。

### 5.2 宿主 `ScopeResolver`

取代 `resolveAssistantScope` 的函数体，**同名顶层函数保留为薄包装**（§10.3，`inquiry_write_tools_test.dart:82`、`business_tools_test.dart:102`、`north_star_chain.dart:281` 在用）：

| 步 | 做什么 |
|---|---|
| 1 候选 | `selectedObjects`：请求里的引用；`workspace` / `global`：从 `object_catalog` 取候选（先 `ProjectionService.idle(moduleId)` 等同步，`projection_service.dart:112`），只取 `inGlobalScope` 类型，按工作区绑定过滤，并带知识库文档。目录滞后可能把**已删除**的对象仍列为候选，因此第 2 步 `resolve` 返回 `null` 即剔除，目录永远不是真相 |
| 2 核实 | 按模块分组调 `openScopeSession().resolve(ref)`，批量并发；结果缓存键 = 引用身份 + 该模块 `projection_cursors.last_applied_seq`（`projection_service.dart:73-79`），模块无新提交则不重算。这去掉了今天每次 `prepare` 的全表扫描与文件哈希（§2.3-3） |
| 3 组装 | `ResolvedAssistantScope(requested, objects: 规范引用)`；钉住的修订号 / 摘要不符 → `scope_mismatch`（语义同 `tool_registry.dart:170-177` 与 `assistant_scope.dart:57-70`） |
| 4 过滤 | `dataModuleIds` 过滤同 `tool_registry.dart:178-192` |

行为保持：对现有夹具，新旧实现产出的 `ResolvedAssistantScope` **相等**（REG-2 用差分测试逐一断言后才删旧实现）。缓存可能让“刚写入的对象”晚一拍出现在全局范围：写入由 §5.3 的回执推进补上，不依赖目录。目录滞后导致的漏项只会少给，不会多给（待核实性能收益与现有测试是否断言“全局范围含摘要”，`foundation_scope_test`、`tool_registry_test`）。

### 5.3 S-1 如何落在契约上

| 项 | 契约机制 |
|---|---|
| **读工具支持选中范围** | `ToolSpec.scopes` 对读工具缺省三种范围齐全；注册时宿主要求读工具若不含 `selectedObjects` 须在覆盖清单写明理由。**数据边界**：`ToolRegistry` 只能校验**结果引用** ⊆ 范围（`tool_registry.dart:414-424`），校验不到 `data` 里的自由 JSON，所以由合规套件的**范围泄漏检查**兜底（§8.1 C-SCOPE：夹具里放一个选中、一个未选中的对象，在选中范围调用读工具，结果的序列化 JSON 里不得出现未选中对象的 id）。询价 13 个读工具逐个归类：通过的开放选中范围，不通过的保持仅全局并写明理由（REG-4） |
| **按回执推进修订号** | 每个任务在载荷里记 `scopeAdvances`（**只新增键**，不改 ADR-0005 §8.2 的既有键）。一次写入工具成功（`succeeded`，且该次一次性审批已消耗并有回执）后，宿主取结果的 `changes`（缺省由 `objectRefs` 视作 upsert），**逐个再经 `resolve` 复核**，仅当 `resolve(ref)` 仍等于 handler 返回的引用（修订号、摘要都对）才推进：① 身份在当前钉住集合内 → 换成新的规范引用；② 不在集合内 → 仅当类型 ∈ 该工具声明的 `createsTypes`、且引用的项目 ⊆ 选中对象的项目（同 `validateInquiryWriteResult` 的规则）才**并入**，并标注来源回执；③ **副作用对象**（`award` 回写预算行、`mergeInto` 改指向的引用方等）：handler 须把它们列入 `changes`，类型须 ∈ `affectsTypes`；宿主同样 `resolve` 复核后推进（在集合内）或并入（同②的项目规则）；**并入范围的副作用对象须在确认卡上可见**（随 UI-3 / UI-4 落地）；④ **删除**：仅当 `op = delete`、类型 ∈ `deletesTypes`、且 `resolve(ref) == null` 才移出；否则仍保持钉住，下一次 `prepare` 报 `stale_scope`。**未声明的保守失败**：结果里出现类型不在 `targetTypes` / `createsTypes` / `deletesTypes` / `affectsTypes` 之内的对象，或副作用对象未被列出，宿主不推进，范围保持旧钉住，下一次 `prepare` 以 `stale_scope` 失败，需用户重新确认；这使“漏声明”变成可见的失败而不是静默放行。推进写 `scope_advance` 事件（K-4 的 `task_events` 增一个类型，ADR-0005 §6.5 同样允许补充） |
| **绝不推进的情形** | 失败 / 取消 / `blocked`；`interrupted`（效应可能已发生）——此时标记范围“不确定”，下一次 `prepare` 以 `stale_scope` 失败，需用户重新确认；只读工具的结果；模型文本；handler 声称的引用在 `resolve` 里对不上（说明写完后对象又被别处改了——保留 `stale_scope` 保护，不替别人的改动背书） |
| **先读后写同一任务** | 任务从选中范围开始：读工具在选中范围内可用（上两项），写入经审批后范围随回执推进，下一步的读与写看到新版本。**一步内**多个写入沿用 ADR-0005 §6.3：批内前项使后项范围变化 → 后项 `stale_scope` 失败并“失败即停”，不自动重试；推进作用于**之后的步骤**，二者不冲突 |
| **仍不支持** | 从全局 / 工作区范围起步的任务直接写入（需要把目标并入范围）。让确认卡把调用的目标列为“加入范围并批准”是授权语义变化，留给 UI-3 / UI-4（§12.1 Q5） |

### 5.4 与 AUTH-1 的接缝

ADR-0002 §4 的授权表以 `scope_digest` 绑定范围，同时 §5 Q1 允许写入“始终允许”并把范围选为“当前项目或当前工作区”。若授权按**逐对象钉住的摘要**匹配，每次写入后（S-1 推进）授权都会失效。所以 AUTH-1 须把授权匹配用的范围键定义为**粗粒度的范围身份**（范围种类 + 工作区 id / 项目 id 集合），逐对象的修订钉住只保留在一次性审批的 `identity_digest` 里（`tool_registry.dart:204`、`:257`）。AUTH-1 尚未成文，此处为对其提出的要求（待核实）。

## 6. 宿主侧

### 6.1 `ModuleHost.activate(id)`

```dart
class ModuleHost {
  Future<ModuleState> activate(String id);        // 幂等；并发合并；失败可重试；失败不抛，写状态
  ModuleState state(String id);                   // inactive | activating | ready | failed(reason) | closed
  T? runtime<T extends ModuleRuntime>(String id); // 取代 host.research / host.prototype / host.inquiry 的类型强转
  Stream<ModuleStateChange> get changes;
  Iterable<ModuleSection> sections();             // §6.4
  Future<void> close();                           // 依赖逆序，先于存储关闭
}
```

激活步骤（取代 `bootstrap.dart:229-366` 的三份代码）：

| 步 | 做什么 | 现状对应 |
|---|---|---|
| 1 | `registry.require(id)`；先激活 `requiredDependencies`，`optionalDependencies` 存在则激活 | `module_registry.dart:32-41` |
| 2 | 能力：`GrantPolicy.decide(manifest.capabilities)`；必需能力被拒 → `failed: capability_denied`（原因入状态）；可选被拒则降级；写 `module_grants`（§6.2） | `bootstrap.dart:286-289`、`:342-345` |
| 3 | 打开主库与 `auxiliarySchemas`（`storage.open(id, schema)`，同一连接复用，`storage_manager.dart:162`）；文件网关 `modules/<id>/files` | `bootstrap.dart:277-280`、`:338-341`；`inquiry_plugin.dart:169-171` |
| 4 | 模块声明了变更日志（库里有 `muyon_change_log`）→ `projections.watch(id, connection)` | `bootstrap.dart:250-253`、`:281`、`:335` |
| 5 | `module.activate(resources)` → `ModuleRuntime` | `:282-291`、`:336-347` |
| 6 | 按 `features`：`importPipeline` → `ImportCoordinator.recover` 并通知冲突；`exchange` → 注册路由；`searchSources` → 登记到 `KnowledgeService` | `bootstrap.dart:299-307` |
| 7 | 状态写 `module_registry`（`ready` / `failed` + 原因） | `bootstrap.dart:254-260`、`:292-298`、`:312-317`、`:348-358` |

**工具在启动时登记，不等激活**（`registerTools` 由 `MuyonHost.open` 对所有可用的 v2 模块调用，handler 靠“分发前确保激活”懒激活），这与今天 `registerBusinessTools(host)` 在 `open` 里一次性登记（`bootstrap.dart:213`）的时机一致，助手始终看得到完整候选集。

兼容访问器：`MuyonHost.research` / `prototype` / `inquiry`、`researchError` / `prototypeError` / `inquiryError`、`activateResearch()` / `activatePrototype()` / `activateInquiry()` 保留为 `ModuleHost` 的薄委托，直到 REG-5（14 个宿主文件与多数测试在用，§10.3）。`inquiry` 返回的对象继续暴露 `runtime.state`、`close()`。

### 6.2 能力申请与授予

| 项 | 设计 |
|---|---|
| 申请 | `ModuleManifest.capabilities`：`{id, required, reason}`；未登记的能力 id → 注册表标为不可用（早失败） |
| 策略 | 宿主代码里的静态策略表（第二阶段不做用户界面）：`knowledge` → `auto`（门面，只能读写**本模块**的索引源）；`models` → `auto`（门面，见下）；`ocr` → `auto`；`transfer` → 仅当 `features` 含 `exchange`；`tools` → **对 v2 一律拒绝**（用 `ToolRegistrar` 取代）。v1 模块在 REG-3 前保持现有授予（科研 `tools` 随科研迁移撤销，§10.2） |
| 记录 | 新表 `module_grants(module_id, capability, requested TEXT CHECK(requested IN ('required','optional')), reason, decision TEXT CHECK(decision IN ('granted','denied')), policy, decided_at)`，主键 `(module_id, capability)`；设置页后续展示（UI-7，第三阶段）。宿主库迁移编号与 K-2 / AUTH-1 的迁移协调（待核实，当前库版本 6，`workspace_repository.dart:20`） |
| `models` 门面 | v2 模块拿到的不是 `OpenAiModelGateway`（今天 `bootstrap.dart:215` 把整个网关交出去，调用方自备 `beforeSend`），而是 `ModuleModels`：每次请求带 `caller = 'module:<id>:<操作>'`，一律经 ADR-0005 §7 的 `ModelRequestGate` 与出站账本；模块无法关闭闸门。询价今天的路径 `InquiryHostModels.createClient` → `gateway.request(caller: 'inquiry', beforeSend: …)`（`inquiry_plugin.dart:324-367`）在 REG-4 改接此门面，确认对话框仍由宿主提供（`app_shell.dart:50`） |
| 撤销 | 授予记录可被宿主撤销：模块转 `failed: capability_revoked`，工具不可用（与 §4.4 可用性同路径） |

### 6.3 单一登记处与边界

- **登记处**：新增 `apps/muyon/lib/app/module_catalog.dart`，唯一允许列出模块构造器的地方（`bootstrap.dart:142` 的名单迁入）。新增模块 = 该文件加一行 + `apps/muyon/pubspec.yaml` 加一行依赖 + 根 `pubspec.yaml` 的 `workspace:` 加一行 + CI 脚本的包清单（REG-5 让 `scripts/ci.sh` 按目录发现包，见 §8.4）。“宿主零改动”按此精确定义（§12.1 Q1）。
- **边界**：`apps/muyon/lib/{platform,services,screens,assistant}` 不得 import `research_module`、`inquiry_module`、`prototype_module`；`app/` 下仅 `module_catalog.dart` 与 `app/adapters/**`（宿主侧适配，如询价，§10.4）可以。以 `test/import_boundary_test.dart` + **只减不增的基线清单**实现。**实测基线：`platform/`、`services/`、`screens/`、`assistant/` 内 8 个文件 import 三个模块包**（`platform/prototype_tools.dart`、`screens/platform_shell.dart`、`screens/devices_page.dart`、`services/documents/document_parser.dart`、`services/knowledge/{index_invalidation,knowledge_service,research_search_adapter}.dart`、`services/search/search_service.dart`），REG-3 / REG-4 逐个清零；**其余 6 个在 `app/`**（`bootstrap`、`app_shell`、`accepted_research_imports`、`research_task_bridge`、`research_tools_page`、`inquiry_plugin`，合计 14）：`bootstrap` 的名单迁入 `module_catalog.dart`，`inquiry_plugin` 迁入 `app/adapters/`，其余四个（科研交换与壳层页面）随 REG-3 的 `ExchangeCapable` / `ModuleSection` 搬进科研包或改为按声明驱动，REG-5 时 `app/` 里只许 `module_catalog.dart` 与 `app/adapters/**` import 模块包。`supplier_core` 另列一份基线（`app/inquiry_hub_authority.dart`、`app/inquiry_web_authority.dart`、`business_tools`、`inquiry_write_tools`、`agent_eval`、`transfer_chat_backend`、`transfer_service` 在用，§2.2）。

### 6.4 导航、首页、对象页、检索按声明驱动

| 面 | 今天 | v2 |
|---|---|---|
| 首页卡片 | 三张硬编码卡（`platform_shell_home.dart:43-60`） | 遍历 `sections()`；文案取 `displayName` / `tagline`，与今天逐字一致以保持界面不变 |
| 模块菜单 / 工作区 | `app_shell.dart:516-517` 的 `PopupMenuItem` 与 `_open` 按名分支（`:249-263`） | 同上；`requiresWorkspace` 决定是否走绑定 |
| 对象页 | `_runtimeFor` 的 `switch`（`object_pages.dart:64-75`）+ 必须有绑定（`:37-44`） | `ModuleHost.runtime(id)` + `ObjectPages.open`；不要求绑定的类型直接打开；`platform_shell.dart:149-150` 的科研特判与 `:251-290` 的询价回退合并为“先 `ObjectPages`，再通用页” |
| 检索 / 索引 | `ResearchSearchAdapter`、`confirmIndexedSource` | `SearchSource.list/confirm`；`confirmIndexedSource` 变为对 `ScopeResolver.confirm(ref)`（即 `resolve` + 摘要）的包装，函数签名保留（`index_invalidation_test` 不改） |
| 设备交换 | `ResearchTaskBridge` / `AcceptedResearchImports` | `ExchangeRouter` + `ExchangeCapable` |

界面外观不变；UI-8 / UI-9 在第三阶段再按 `ModuleSection.group` 改版（ADR-0003）。

### 6.5 失败隔离

不变：单个模块激活失败只写自己的状态与 `module_registry` 行，其余模块与宿主照常；下一次 `activate` 重试（`bootstrap.dart:262-265`、`:309-319`、`:355-365` 的语义）。新增：失败即把该模块所有工具置为不可用并带原因（§4.4）；注册表对版本 / 依赖 / 循环的校验与 `unavailable` 映射原样保留（`module_registry_test` 不改）。

## 7. 三层插件

### 7.1 对照

| | **L1 原生模块** | **L2 声明式插件** | **L3 内容插件** |
|---|---|---|---|
| 形态 | Dart 包，编进应用，`BusinessModuleV2` | MCP 服务器或 OpenAPI 服务 + 清单（可附只读本体） | 一个页面 / 一份构建目录，在受限 WebView 里展示 |
| 代码在哪运行 | 本机，应用进程内 | **对方服务器**；本机只有宿主的适配器 | WebView（沙箱） |
| 免发版 | 否（Flutter 发布版不能运行时加载 Dart 代码，评估 §3 已采纳的前提） | 是，运行时在设置中接入 | 是，导入即用（现原型） |
| 读本机业务数据 | 自己的库；经范围读他人数据须声明依赖 | **不能**：只收到模型填的参数（`supportedScopes = {global}`、`dataModuleIds = {}`，`mcp_adapter.dart:180-181`） | **不能** |
| 工具 | 读 / 写 / 外传 / 通道 | 一律外传类，目的地 = 服务器源 | 无；只有声明的桥接通道（`restricted_web.dart:6-39`），且桥接载荷仍走工具 / 授权通路 |
| 授权 | ADR-0002 分级（读自动、写入询问、外传询问） | ADR-0002 外传类：新端点逐次询问、已授权端点可选“本次对话”；内容审查接口适用 | 无工具，故无授权；导航只在声明根内（`allowsNavigation`） |
| 凭据 | 宿主密钥库，模块不见明文 | 只存密钥库引用（`McpServerConfig.credentialRef`，`mcp_adapter.dart:12-36`）；描述、结果、URL 查询参数一律脱敏（P0-S2：`maskSecret`、`maskedEndpoint`、`redactEndpoint`，`:160`、`:85-117`、`:230-242`） | 不接触 |
| 失败影响 | 隔离；该模块不可用 | 工具不可用；撤销即 `setAvailability(false)` | 页面不可用 |
| 阶段 | 第二阶段（REG-2～5） | **清单现在定义，实现在第三阶段（REG-6）** | 已有；v2 只补“数据中心显示‘不适用’”（`ModuleOntology.empty`） |

### 7.2 L1 原生模块：信任与评审规则

L1 与宿主**同等信任**：编进同一个二进制，能 import 任何东西。v2 不是沙箱，而是让“正确的做法是默认做法、越权需要刻意绕”：不给 `ToolRegistry`、不给裸网关、边界由 lint 测试守住。因此第三方原生模块 = 源码审查进仓（走 [REVIEW.md](../tasks/REVIEW.md) 安全清单），不存在“不审查的 L1”。评审规则（追加进 REVIEW.md 的模块条目，REG-5 做）：

- R-L1-1：模块包的 `pubspec` 依赖 ⊆ 清单依赖 + 白名单（`muyon_module_api`、`muyon_ui`、`flutter`、`sqlite3` 与模块自己的核心包）；不得 import `package:muyon/`；
- R-L1-2：不得自行联网或调模型，须经 `HostChannel` / `ModuleModels`；
- R-L1-3：不得把模型输出直接变成业务写入——只能经已注册的写工具，或经用户在界面里的明确操作；
- R-L1-4：新增 `notExposed` 覆盖条目须写理由并经 leader 复核（§8.2）；
- R-L1-5（评审项，非自动门槛）：不得在 `registerTools` 之外直接调用写 / 外传工具的 handler（§4.4 第 3 条）。

### 7.3 L2 声明式插件：清单与信任边界（REG-6 实现）

清单 `muyon.plugin.json`（JSON；字段在 REG-6 定稿前可增，不可删）：

```jsonc
{
  "schema": "muyon.plugin/1",
  "id": "acme_erp",                         // ^[a-z][a-z0-9_]{1,31}$，与 McpServerConfig.id 同规则
  "name": "ACME ERP", "version": "1.2.0",
  "kind": "mcp",                            // "mcp" | "openapi"
  "endpoint": "https://erp.acme.example/mcp",  // https，或回环 http（沿用 mcp_adapter.dart:18-29）；不得含 userinfo、fragment、凭据查询参数
  "auth": { "type": "bearer", "credentialRef": "<密钥库引用>" },   // 令牌绝不进清单
  "tools": { "include": ["search_orders", "get_order"] },         // 白名单；缺省 = 列出全部但默认全部停用，由用户逐个启用
  "dataCategories": ["customer_contact"],   // 仅用于展示与审计，**从不用来放行任何东西**；对应 Sensitivity 词表
  "ontology": { "entities": [], "relations": [], "actions": [], "flows": [], "examples": [] },  // 可选；同 ModuleOntology 的 JSON 形式，只读
  "manifestDigest": "sha256:…"              // 宿主在接入时计算并钉住
}
```

OpenAPI 的转换规则：`operationId` → 工具名；请求体 / 参数 → `parameterSchema`（仅受限子集，超出则该工具跳过并列出原因，同 `McpAdapter` 的 `skipped`，`mcp_adapter.dart:164-187`）；`servers[0]` 必须满足与 `endpoint` 相同的限制；只支持 bearer；**所有方法（含 GET）按外传**，因为 URL 与参数会带出数据。

**信任边界（做 / 不做）：**

| 能做 | 不能做（宿主强制） |
|---|---|
| 提供工具；描述与结果仅作**不可信文本**展示（`ToolDescriptor.description` 注释，`module_api/context.dart:90`；描述截断 500 字并脱敏，`mcp_adapter.dart:160-177`）；附只读本体供数据中心展示结构与示例问法 | 注册 `read` / `write` 效应的工具（效应一律 `network`，`ToolAccessLevel.external`，`tools.dart:163-168`）；声称自己“只读”不被采信，包括 MCP 的 `readOnlyHint` |
| 收到模型填的参数。**注意**：模型会把它读到的业务数据抄进参数——`dataModuleIds = {}` 只阻止宿主把范围对象交给 L2，**挡不住这条路径**；兜底是 ADR-0002 的外传内容审查接口（§9.1）加每次调用的询问；清单的 `dataCategories` 只是展示，不能当作“这个插件不会收到敏感数据”的证据 | 收到本机业务对象或任何范围内的数据由宿主直接交付（`dataModuleIds = {}`）；读取本机文件、库、其他插件的工具 |
| 经 ADR-0002 授权后外传 | 提供本机界面、`registerTools` 之外的运行时追加工具（`tools/list` 变化 → 新工具默认停用，须用户重新确认；清单摘要变化同理） |
| 被用户随时停用 | 修改自己的授权；使用 `HostChannel`；提供检索源 / 导入 / 变更日志；让数据中心同步其**实例**数据（只可同步结构与描述） |

附加加严（只收紧，不涉及放宽任何底线）：**外部内容污染**——**外部内容**指三类：L2 工具的结果、联网读取的网页、**导入或抓取的第三方文本**（供应商文件、报价导入、采购来源）。它们进入任务后，任务标记为被污染（`ToolCallResult` 加可选字段 `provenance = external`）。**谁来设置**：宿主在结果来自 L2 工具或任何 `network` 效应工具时强制设置，不信 handler 自报；携带导入第三方文本的结果（读工具也可能带）由模块按工具声明（`ToolSpec.resultProvenance`），宿主据声明设置，且只能声明为更严；**污染后，该任务里的写入 / 外传一律逐次确认，“始终允许”类授权不再适用**。这是对 ADR-0002 §5 Q1 / Q2 已确认放行范围的收紧（不触及 §3 底线），须经用户确认（§12.1 Q11）。**这比 Folio 现状更严**：Folio 只在使用网页后才退回逐次确认（`AssistantAppTools.requireApproval`，`assistant_actions.dart:81-84`；`ask_page.dart:286` 的 `externalContent` 只在网页工具被用时置位），导入文本不触发——而导入文本同样可作提示注入的载体（Q12）。具体接入 `ModelRequestGate` / `GateDecision` 与 AUTH-1 的授权解析，由 AUTH-1 落实（待核实其接口）。

### 7.4 L3 内容插件

维持现状：内容原样展示，不访问业务数据；清单即 `RestrictedWebViewSpec{entry, allowedRoots, bridgeChannels}`（`restricted_web.dart:6-22`），导航只在声明根内、仅 `https` / `file`（`:18`、`:24-36`），页面到宿主的消息只通过声明的通道（`:38`），通道载荷仍走工具 / 授权通路（`:3-4` 注释）。由 L1 模块**托管**（今天是 `PrototypeModule`），所以 L3 的“代码”只是数据。v2 对它只有两处影响：原型的 `ModuleOntology.empty` 使数据中心显示中性的“不适用”（[v4 提示词第四轮](../design/v4/prompts/claude-design-prompt-round4.md)的用户决定）；原型的写操作（导入版本、记录反馈）进覆盖清单。

## 8. 契约合规测试套件与能力覆盖清单

### 8.1 套件与检查项

位置：`packages/muyon_module_api/lib/testing.dart`（导出 `runModuleContractSuite`）+ `lib/src/testing/`。套件为每个检查注册 `test()`；**宿主钩子**（工具模式检查器 `_Schema.check`、`structureDigest`）由宿主的 `test/module_conformance_test.dart` 注入，所以套件不依赖应用包。`lib/testing` 依赖 `flutter_test`，需把它从 `dev_dependencies` 提到依赖或改用 `test_api`（待核实）。每个模块包自带一份测试调用套件；宿主再对 `registry.modules` 跑一遍。

| # | 检查 | 判定方法 | 级别 |
|---|---|---|---|
| C-MANIFEST | id 合规；`apiVersion == 2`；`features` ⇔ 实现的接口一致；申请的能力都是宿主已登记的；依赖可解析 | 纯断言；宿主侧用真实 `ModuleRegistry` | 阻断 |
| C-SCHEMA | 迁移可执行：空库逐版升级到最新；从每个中间版本升级到最新，结构摘要与新建库一致；主库与每个 `auxiliarySchemas` 都测 | `sqlite3.openInMemory()` + 注入的 `structureDigest`（`storage_manager.dart:139`）；`ModuleSchema` 构造器已校验版本连续（`module_api/storage.dart:23-52`） | 阻断 |
| C-CHANGELOG | 夹具里对每个 `inGlobalScope` 类型新增 / 修改 / 删除一条，`ModuleChangeLog.since` 产生对应 `upsert` / `delete`；回滚时不留记录（`contract_v1_test.dart:37-44` 的同款） | 模块提供 `ModuleTestHarness { seed(); mutate(type); sampleRef(type) }` | 阻断 |
| C-ONTOLOGY | 每个类型有标签、图标键、`titleField ∈ fields`；关系两端存在；`queryTool` 是已注册的读工具；动作的 `tool` 是已注册的写 / 外传工具或写了 `humanOnlyReason`；`flows` 的步骤指向存在的工具；示例的 `expectTools` 存在 | 与 C-TOOL 的注册捕获交叉 | 阻断 |
| C-SENSITIVE | 所有字段 `sensitivity != unreviewed` | 遍历 `ontology` | 阻断 |
| C-RESOLVE | 对每个 `inGlobalScope` / 有页面的类型：样本引用 `resolve` 得到的 `view.ref` 与请求同身份、`versioned` 类型带修订号、有摘要的类型带摘要；改动后旧摘要 `resolve` 返回 `null`；不存在的 id 返回 `null`；无需工作区绑定（`openScopeSession`） | 夹具 | 阻断 |
| C-PAGE | `page != none` 的类型 `ObjectPages.open` 对样本返回非空；`none` 必须有理由 | 夹具 | 阻断 |
| C-TOOL | 用 `FakeRegistrar` 捕获 `registerTools`：名称合规、无重复、编码后无冲突；描述非空；参数模式通过注入的检查器；读工具有 `resultSchema`（缺则警告）；写工具缺省仅 `selectedObjects`；每个工具 `operations` 非空或为 `synthetic`；registrar 封存后再调用抛错；**并包含 `tool_descriptions_test` 的规则**：描述长度 20–200 字、不含禁用词（`无需确认`、`直接执行`、`已授权`）、非读工具须含效应词（`写入`、`修改`、`删除`、`导出`、`发送`、`下载`、`联网` 之一，`apps/muyon/test/tool_descriptions_test.dart:16-40`） | 纯断言 | 阻断 |
| C-READPURE | 读工具不改库、不写文件：对每个 `ToolExample` 运行 handler，前后比较 `SELECT total_changes()`、变更日志序号与模块文件目录的文件清单 | 夹具 | 阻断 |
| C-SCOPE | **范围泄漏**：对声明了 `selectedObjects` 的读工具，夹具里放选中 A 与未选中 B，在选中范围调用，结果 JSON 序列化后不得含 B 的 id | 夹具；弥补 `ToolRegistry` 只验引用不验 `data`（§5.3） | 阻断 |
| C-COVERAGE | §8.2 | analyzer + 注册捕获 | 阻断 |
| C-IMPORTS | 模块包 `pubspec` 依赖与 import 满足 R-L1-1 | 读 `pubspec.yaml` 与 `lib/**` 的 import 行（脚本） | 阻断 |
| C-LIFECYCLE | `openSession` 两次互不影响；`dispose` 后再用抛错；`activate` 抛错时宿主标记失败且不影响他人（宿主侧） | 夹具 + 宿主 | 阻断 |
| C-PUBLISH | 声明 `publishChecks` 的模块返回的检查项名称不与 6 项基础检查重名 | 断言 | 阻断 |

### 8.2 能力覆盖清单：格式与操作枚举

**单一来源是模块包里的 Dart 常量**（不另存 JSON，避免两份真相），位置 `packages/<module>/lib/src/coverage.dart`，经 `BusinessModuleV2.coverage` 暴露：

```dart
const coverage = CapabilityCoverage(
  version: 1,
  surfaces: [   // 被枚举的“业务操作面”：Dart 库 URI + 类 / 扩展名
    Surface('package:supplier_core/src/inquiries.dart', 'Inquiries'),
    Surface('package:supplier_core/src/quote_excel.dart', 'QuoteExcel'),
    // …… 35 个 `extension … on Store`（grep 实测），询价每个文件一项
  ],
  operations: [
    Operation(id: 'inquiry.award', kind: OpKind.write,
      members: {'Inquiries.award', 'Inquiries.withdrawAward'}, tools: ['inquiry.award']),
    Operation(id: 'inquiry.quote_import', kind: OpKind.write,        // 计划 / 应用两步
      members: {'QuoteExcel.planQuotationImport', 'QuoteExcel.applyQuotationImport'},
      tools: ['inquiry.plan_quote_import', 'inquiry.apply_quote_import']),
    Operation(id: 'inquiry.library.replace', kind: OpKind.external,
      members: {'Exchange.replaceFrom'},
      notExposed: NotExposed(NotExposedKind.dangerousIrreversible, '覆盖整库，须由本人在“恢复”页确认并留安全备份')),
  ],
);
```

- `OpKind`：`query`（只读）/ `write` / `external`（导出、网络）/ `internal`（纯实现细节，如 `Store.close`，须写理由）。
- `NotExposedKind`：`humanOnly`、`secretHandling`、`dangerousIrreversible`、`privilegedSystem`、`notBusiness`、`deferred(taskId)`。`tools` 与 `notExposed` **互斥**；`notExposed.reason` ≥ 15 字。

**操作面如何枚举而不靠脆弱的反射：**

1. 模块只声明 `surfaces`（库 + 类 / 扩展名，粗粒度，几十行）；
2. CI 测试用 `package:analyzer`（仅 dev 依赖，只在 `dart test` 里运行，不进应用）解析这些库，列出每个 surface 的**公开成员**（方法、getter、setter，排除下划线与 `@visibleForTesting`）→ 集合 S。这是 AST 级读取，不是 `dart:mirrors`（Flutter AOT 不可用）也不是正则；
3. 所有 `Operation.members` 的并集为 M。**要求 S = M，且每个成员恰属一个操作**：新增公开方法而未归类 → 红灯；清单里写了不存在的名字 → 红灯；
3a. **操作面自动发现**（防止漏登记整个 surface）：测试同时扫描模块包 `lib/` 与其核心包中**每个以宿主 / 业务宿主类型为目标的公开扩展或类**（如 `extension … on Store`、`WorkbenchStore`），要求它们出现在 `surfaces`，或出现在 `notBusiness` 清单（附理由）；**`Store` 自身的公开方法**（`save`、`delete`、`restore`、`markResolved` 等，`store.dart`）同样必须归类，不因“不在扩展里”而漏掉；
4. 对每个操作：`tools` 里的 id 都必须出现在 C-TOOL 的注册捕获里；效应与 `kind` 匹配（`write` 操作只能由 `write` 工具承载，`query` 只能由读工具，反之不可）；`notExposed` 的操作不得同时有工具；
5. 反向：模块注册的每个工具必须被至少一个操作引用，或在规格里标 `synthetic`（如 `describe` 一类通用工具）——孤儿工具红灯；
6. `deferred(taskId)` 受**棘轮**约束：基线文件 `coverage.deferred.baseline` 记录条数，只允许减少，增加则 CI 失败（防止用“稍后”掏空硬门槛；§12.1 Q8）。

规模估计（`grep` 实测，待逐项核实）：`supplier_core` 中 `extension … on Store` 共 **35 个**，公开成员约 **102 个**，其中会写库或写文件的约 35 个（含通用的 `save` / `delete` / `restore`，评估 §1 记 27 类写操作）；询价现已开放 4 个写工具（`inquiry_write_tools.dart:100,158,216,248`）。科研的操作面分散在 `WorkbenchStore`（`research_module/lib/src/core/store.dart`：`saveProject` `:387`、`saveNote` `:396`、`saveTask` `:437`、`acceptRun` `:472`、`assessRun` `:479`、`startManualRun` `:505` 等）、`OutlineStore`、`CardStore`、`ResearchExchange` 等，完整 `surfaces` 列表由 REG-3 实测（待核实）。

若 `analyzer` 进入 workspace 受阻（依赖钉版本、离线构建、`supplier_core` 体量下的耗时，待核实），降级为**受约束的源码扫描**（`extension … on Store {` 块内的非下划线成员声明，按缩进与分号规则），并保留“S = M 双向比对”这一判据——比对本身会暴露扫描漏项。REG-5 开头先做半天的 spike 决定用哪个。**spike 的第一项风险是 `analyzer` 与 Flutter SDK（当前 CI 钉 3.47.5，`ci.yml`）捆绑的 Dart / `analyzer` 版本冲突**；spike 失败时**向用户报告并由用户决定**，不静默降级（降级方案也只是备选，用户确认后才采用，§12.1 Q13）。

### 8.3 CI 硬门槛如何成立

- 套件是普通 `test()`，随 `scripts/ci.sh` 的各包 `flutter test` 与宿主 `test` 运行；**任何失败即整体失败**（`ci.sh` 无 allow-list，其头部说明第 2 条），不需要新增 workflow；
- 宿主 `test/module_conformance_test.dart` 对 `ModuleRegistry.modules` 的每个 v2 模块调用套件，因此**新增模块自动被测**，不能漏跑；
- REVIEW.md 增一条必做：覆盖清单的 diff（尤其新增 `notExposed`、`deferred`）须 leader 复核；
- 示例模块（§8.4）长期留在 `catalog` 里，保证套件本身不退化。

### 8.4 “示例模块宿主零改动”验收

**精确定义**：新增模块相对基线的 `git diff --name-only` 只允许包含：`packages/<new>/**`；根 `pubspec.yaml` 的 `workspace:` 一行；`apps/muyon/pubspec.yaml` 的依赖一行；`apps/muyon/lib/app/module_catalog.dart` 的一行（含其 import）。`scripts/ci.sh`、`verify.sh` 的包清单在 REG-5 改成按 `packages/*/pubspec.yaml` 发现，此后不再是改动点。

**验收方法（可重复，不靠人眼）：** REG-5 提供 `tool/new_module.dart <id>`（脚手架：生成包骨架、清单、一个对象类型、一个读工具、一个写工具、覆盖清单、套件调用）与 `scripts/verify_zero_host_change.sh`：在干净检出里用脚手架生成临时模块 `probe_mod`，**只**按上面四处允许点自动改文件，然后运行 ① `flutter analyze`；② 宿主 `module_conformance_test`；③ 一个端到端测试（夹具模型调用 `probe_mod.add_note` → 需要审批 → 批准 → 回执 → 对象出现在全局范围与目录；再调 `probe_mod.list_notes`）；最后断言 `git status --porcelain` 的改动文件集合 ⊆ 允许集合。该脚本进 CI。随库交付的 `example_module`（记事本，对象类型 `note`）是同一脚手架的产物，兼作文档。

## 9. 与已有 ADR、数据中心的衔接

### 9.1 ADR-0002：逐条对照与内容审查

**模块注册的写 / 外传工具如何进入分级授权**：`registrar.write` / `external` 登记的工具与今天手写登记的工具在 `ToolRegistry` 里没有区别——操作类别由效应映射（`write` → 写入，`export` / `network` → 外传，`tools.dart:163-168`），授权键是 `toolId`，目的地与范围在 `prepare` 里算出（`tool_registry.dart:148-217`）；AUTH-1 在 `prepare` 签发审批前查授权表（ADR-0002 §4），命中即由宿主代签并消耗，回执记 `grant_id`。v2 对 AUTH-1 唯一的新增要求是 §5.4 的范围键与 §7.3 的外部结果污染，其余不需要特判模块。

| §3 硬性底线 | v2 如何保持 |
|---|---|
| 1 授权只由用户在宿主界面给出 | registrar 不暴露授权写入口；模块注册的工具、描述、本体、覆盖清单都不能授予或扩大权限；`HostChannel` 的复核回调在第二阶段仍由模块（询价界面）传入（现状，§2.3-7；宿主只保证审批签发、回执与账本），**助手发起的路径不使用它**（通道 `modelSelectable: false`）；宿主自有的复核界面在 UI-9 之后接管（§12.1 Q3） |
| 2 授权绑定工具 + 范围 + 目的地 | toolId = `<moduleId>.<name>` 是授权键，**改名等于新工具、旧授权失效**（安全方向）；宿主在 `prepare` 前比对 `destination` 与清单 `network`（只收紧）；范围键见 §5.4 |
| 3 新远程端点逐次询问；内容审查 | L2 一律外传类；L1 外传工具须声明 `DestinationRule` |
| 4 一次性审批、防重放回执、出站账本 | 写入 / 外传仍只经 `ToolRegistry`；**外传类工具入出站账本是现状缺口**（§2.3-6）：v2 要求“记不进账就不发送”同样适用于 `external` 与 `HostChannel`——在 `_dispatch` 的外传路径上、调 handler 之前先写账本。因 `outbound_requests` 列绑定模型（`outbound_ledger.dart:16-34`），新建 `outbound_tool_requests`（形状与时机见 §12.1 Q4）（id、tool_id、invocation_id、destination、payload 摘要与大小、状态 CHECK 同现有六值、起止时间）并在界面与 `recent()` 合并展示；REG-2 建表与接口，AUTH-1 追加 `grant_id`（§12.1 Q4） |
| 5 授权可撤销、立即生效 | 模块 / 工具 `setAvailability(false)` 使 `generation++`，在途的 `PreparedToolCall` 作废（`tool_registry.dart:126-139`、`:226-228`） |
| 6 四类开关只能收紧 | 类别由 `ToolAccessLevel`（由方法决定的效应）映射，模块无法自报“读” |

**敏感属性与内容审查接口**（ADR-0002 §4 的 `OutboundContentReviewer`：输入为工具 / 端点 / 发送内容 / 范围 / 来源对象引用）：v2 提供两层数据——① 对象级：来源对象引用 → 类型 → `ObjectTypeSpec.fields` 里 `sensitivity` 非 `none` 的字段集合（“可能包含”）；② 字段级：外传工具的 `ToolSpec.resultSensitivity`（结果字段路径 → 类别）与 L2 清单的 `dataCategories`。不把 `x-sensitivity` 之类扩展写进 JSON Schema，因为 `_Schema.check` 只认固定关键字（`tool_registry.dart:489-504`）。类别词表同时是 ADR-0005 §7.1 `ModelRequestFacts.dataCategories` 的取值来源（该字段今天是常量，`personal_agent.dart:242`；由宿主按消息成分与结果引用计算）。审查器只能收紧的规则不变；`dataCategories` 只能使审查更严，不得用来跳过询问。审查器本身不属于本 ADR。

### 9.2 ADR-0005

- **工具模式用于原生工具调用**：`ToolSpec.parameterSchema` 就是 `parameters`（受限子集，根为 object，ADR-0005 §4.2）；v2 额外保证编码后的函数名无冲突（§4.4）。ADR-0005 提示评测器至今发空 schema（`llm_selection_eval.dart:134`），真实 schema 的效果由 E-1 测量，描述质量因此成为模块作者的责任——合规套件只查“非空与合法”，不判好坏。
- **不受影响**：`stage`、`requestDigest`、`toolCall`、`toolIdentityDigest`、`round`、`protocolCorrections`（ADR-0005 §8.2）；候选工具冻结（`modelSelectable: false` 的通道不进候选）；批量确认卡与失败即停（§5.3 已说明）。
- **新增的唯一载荷键**：`scopeAdvances`（§5.3）；事件类型 `scope_advance`（K-4 的补充，同 ADR-0005 §6.5 对 §6.4.4 清单的补充方式）。
- **模块内部的模型调用**（如询价“智能导入”的多次 JSON 抽取）经 `ModuleModels` 门面进入 `ModelRequestGate`，`caller = 'module:inquiry:extract_offers'`；在 K-2 的 `AlwaysConfirmGate` 下每次请求仍逐次确认（与今天 `InquiryHostModels` 的对话框等价），AUTH-1 后按授权放行。

### 9.3 数据中心：6 项检查如何由声明支撑

6 项检查的文案取自[数据中心稿](../design/v4/Muyon%20Data%20Center.dc.html)（入口见 [v4 README](../design/v4/README.md)，用户决定见 [v4 审阅 §4](../reviews/2026-10-07-design-v4-review.md)）（对象与属性、关系查询接口、动作、流程、敏感属性、示例问法评测）。v2 让前 5 项成为**可由宿主自动判定**的静态检查，第 6 项由 DC-1 的评测执行：

| 检查 | 声明依据 | 判定（宿主，自动） |
|---|---|---|
| 对象与属性已声明 | `ontology.objectTypes[].fields` | 每个类型 ≥ 1 字段，`titleField` 有效；询价另由既有 `ontology_test` 对照校验器 |
| 关系已声明查询接口 | `relations[].queryTool` | 每条关系指向已注册、效应为读的工具 |
| 动作已声明参数与确认方式 | `actions[].tool` / `operationId` | 工具已注册；参数取自 `parameterSchema`；**确认方式由效应决定**（写 → 审批，外传 → 外传审批），不由模块自报；或写 `humanOnlyReason` |
| 业务流程已声明 | `flows[]` | 步骤绑定的工具 / 动作都存在 |
| 敏感属性已标记 | `fields[].sensitivity` | 无 `unreviewed`（与 C-SENSITIVE 同判据；稿上“未标记视为未检查”） |
| 示例问法评测 | `examples[]` | 静态：`expectTools` 存在；动态：DC-1 用 E-1 / `selection_eval` 的夹具跑通过 / 未命中 |

`PublishChecks` 只用于模块自加的检查。“同步到助手知识库”按对象类型决定同步范围：本体与描述可同步；**含非 `none` 敏感字段的实例不同步**（稿上的“敏感属性剔除数”）。原型：`ModuleOntology.empty` + 不声明 `publishChecks` → 数据中心显示“不适用”，与 v4 的用户决定一致。DC-1～3 在第三阶段，本 ADR 只保证声明可读、判据可算。

## 10. 迁移与拆分

REG-1（本文）→ REG-2 → REG-3 / REG-4 / T-3 并行 → S-1 → REG-5（路线图 §3.1）。K-3 是 REG-4c 与 S-1 的前置（范围推进挂在 K-3 的循环里）。REG-2 与 K-3 无文件交集，可并行。

### 10.1 总表

| 任务 | 前置 | 做什么 | 不做 |
|---|---|---|---|
| **REG-2** 通用激活、能力清单授予、范围单点 | REG-1 | `module_api` 新类型（§4）；`app/module_host.dart`、`app/module_catalog.dart`；`ModuleRegistry` 接受 {1,2}；`HostToolRegistrar`；`platform/scope_resolver.dart`（差分测试后替换旧函数体）；`module_grants` 迁移；**外传账本**：新建 `outbound_tool_requests`，把现有四条外传通道全部接入——MCP（`mcp_adapter.dart:318` 的 `HttpClient`）、`inquiry_web_authority.dart`、`inquiry_hub_authority.dart`、`public_tools.dart` 的 `transfer.*`（`transfer.export/import/listen/stop/send`）；每条通道各一条测试：“账本写不进去则什么都不发送”（Q4）；首页 / 菜单 / 对象页按声明驱动（对 v1 模块经 `LegacyModuleBridge`） | 不迁移任何业务模块；不改界面外观 |
| **REG-3** 科研、原型迁 v2，补科研工具 | REG-2 | 见 §10.2 | 询价 |
| **REG-4** 询价改造成 `BusinessModuleV2`，补写工具，并入自带 AI | REG-2；4c 需 K-3 | 见 §10.4 | 导航换壳（UI-9） |
| **FOLIO-BYPASS**（Q12 获批后；与 REG-2 同批） | — | 宿主模式下把 Folio 存储的 `assistant_permission = bypass` 按 `confirmWrites` 读取：改 `packages/inquiry_module/lib/src/app/app_state.dart:451-457` 的 `assistantPermission` getter（`_isHosted`，`:47,:77`）；`ask_page.dart:220` 的 `autoApprove` 因此恒为假。新增测试 `packages/inquiry_module/test/assistant_permission_hosted_test.dart`：宿主模式下存储 `bypass` 后写入仍先询问；非宿主模式行为不变（`assistant_permissions_test` 不改） | 不隐藏助手（那是 4c） |
| **T-3** 平台自省工具 | REG-2 | 宿主自有，用同一 registrar（`moduleId: 'platform'`）：执行记录、记忆、通知、设备只读；记忆写入只提议——写入 `MemoryReviewService` 的候选（`bootstrap.dart:149`），仍须用户在收件箱确认。覆盖清单门槛不适用，C-TOOL 适用；`ObjectRef` 命名空间与是否进入范围解析由 T-3 定 | 不进 `BusinessModuleV2` |
| **S-1** 范围模型 | K-3、REG-2；REG-4 提供询价读工具的归类 | `assistant/scope_advance.dart`；`personal_agent.dart` 在 K-3 的 `_advance` 内调用；任务载荷 `scopeAdvances`；读工具 `scopes` 放开；C-SCOPE | 全局起步直接写入（Q5） |
| **REG-5** 示例模块、脚手架、合规入 CI | REG-3、REG-4（至少 REG-3） | `packages/example_module`、`tool/new_module.dart`、`scripts/verify_zero_host_change.sh`、`ci.sh` 按目录发现包、`import_boundary_test`、`module_conformance_test`、REVIEW.md 模块条目 | — |
| **REG-6**（第三阶段） | REG-5 | §7.3 | — |

### 10.2 REG-3 细则

| 范围 | 内容 |
|---|---|
| 科研 | `ResearchModule implements BusinessModuleV2`：本体取自 `_resolve` 的类型（`document`、`entry`、`outline`、`section`、`task`、`run`、`card`，加补上的 `project`，`research_module.dart:411-505`）；`ScopeResolvable`（跨项目）；工具：搬 `research.objects`（`business_tools.dart:288-346`），补读（项目 / 文档 / 条目 / 运行 / 提纲 / 关系）与写（评估 §1 列的 16 类中，本机写入——`saveNote`、`addOutline`、`assessRun`、`acceptRun` 等——开放为 `write`；`exportTask`、`exportReport`、`importResult` 涉及文件与设备，按 `export` 效应或 `notExposed` 逐项判，清单与理由由 REG-3 提出、leader 复核）；`searchSources`；`ImportCapable`；`ExchangeCapable`（接口形状在此定稿）；覆盖清单；撤销 `tools` 能力 |
| 原型 | `PrototypeModule implements BusinessModuleV2`；本体 `page` / `version` / `feedback`；`ObjectPages` 不要求绑定（修复 S6 的前置）；工具：搬 `prototype_tools.dart` 两个读工具；写操作进覆盖清单（建议 `add_feedback` 开放为 `write`，其余——选目录导入版本、删除——`humanOnly`，§12.1 Q10） |
| 宿主 | 删除 `platform/prototype_tools.dart`、`business_tools.dart` 的科研部分；`object_pages.dart`、`index_invalidation.dart`、`search_service.dart`、`research_search_adapter.dart` 改为通过声明或搬进科研包；`bootstrap.dart` 的 `_activateResearch` / `_activatePrototype` 退化为委托 |
| 可拆 | 体量大时拆 REG-3a（契约迁移 + 工具 + 本体）与 REG-3b（`ExchangeCapable` 与检索源搬迁），leader 派发时定 |
| 新增测试 | 套件对两个模块全绿；科研新工具各有范围 / 审批 / 回执用例；`project` 类型可解析；原型对象页无绑定可开；差分测试 `ScopeResolver` |

### 10.3 必须保持不改的测试与兼容面

**不得修改的测试**（REG-2～REG-5 全程；若确需改，须在任务说明写明理由并经 leader 审查，同 ADR-0005 §8.4 的约定）：

| 测试 | 依赖的行为 |
|---|---|
| `apps/muyon/test/module_registry_test.dart` | `_Module implements BusinessModule` 四成员；`apiVersion: 99` 不可用；依赖 / 循环 / 重复 id 的判定 |
| `packages/muyon_module_api/test/contract_v1_test.dart`、`contracts_test.dart`、`assistant_scope_test.dart` | v1 数据类的构造与冻结语义 |
| `apps/muyon/test/north_star_inquiry_test.dart` + `integration_test/support/north_star_*.dart` | `host.activateInquiry()`、`host.inquiry!.runtime.state.store`、`host.tools.list()` 含 `inquiry.compare_quotes` / `project_budget` / `create_inquiry`（`north_star_chain.dart:152-157`、`:200`、`:206-237`）、`resolveAssistantScope(...)`、`AssistantScope.selectedObjects`（`:281-293`）、工具回执与 `accessLevel`（`:440-505`） |
| `apps/muyon/test/tool_registry_test.dart`、`foundation_scope_test.dart`、`business_tools_test.dart`、`prototype_tools_test.dart`、`prototype_wiring_test.dart` | `ToolRegistry` 全部语义；全局 / 选中范围结果；工具 id 与描述 |
| `apps/muyon/test/inquiry_*`（`inquiry_hub_authority`、`inquiry_hub_ui`、`inquiry_plugin`、`inquiry_shared_models`、`inquiry_web_authority`、`inquiry_web_task_stop`、`inquiry_write_tools`） | 下方“询价兼容面” |
| `research`：`research_object_open_test`、`research_task_flow_test`、`accepted_research_import_test`、`index_invalidation_test`、`search_test`、`projection_service_test`、`import_recovery_test`、`packages/research_module/test/*`、`packages/prototype_module/test/*` | 对象页入口、任务收发、导入回执、索引失效、检索、投影、导入恢复 |
| `packages/inquiry_module/test/*`、`packages/supplier_core/test/*`（含 `ontology_test`、`assistant_*`、`ai_*`） | 询价 UI 与领域；Folio 自带助手在非宿主模式下行为不变 |
| `tool_descriptions_test`、`chat_backend_test`、`agent_eval_test`、`selection_eval_test`、`llm_selection_eval_test`、`north_star_cross_tool_test`、`storage_recovery_test`、`credential_redaction_callers_test`、`acceptance_failure_matrix_test`、`widget_test` | 工具描述规则与注册顺序；聊天后端；评测夹具里的工具 id 与选择；`host.research` / `researchError` 等访问器与激活失败语义（`acceptance_failure_matrix_test.dart:49-62`）；凭据脱敏调用方；宿主启动 |
| 同属 ADR-0005 §8.4 的守护集合 | `personal_agent*_test`、`assistant_cancel_test`、`outbound_ledger_test`、`model_gateway_test` 等 |

**询价兼容面**（现有测试直接引用，路径与符号保留；实现可以搬走，旧路径留 `export` 薄壳）：

| 符号 | 引用处 |
|---|---|
| `MuyonHost.open`、`activateInquiry()`、`inquiry`（含 `.runtime.state`、`.close()`）、`inquiryError` | `inquiry_plugin_test.dart:15-48`、`inquiry_hub_ui_test.dart:29-188`、`inquiry_*_authority_test.dart`、`north_star_chain.dart:152-157` |
| `InquiryPlugin.schema`（静态）、`InquiryHostModels`、`InquiryModelApprovalPreview` | `inquiry_write_tools_test.dart:241`（`host.storage.open('inquiry', InquiryPlugin.schema)`）；`inquiry_shared_models_test.dart:140` 等处（构造 `InquiryHostModels`、持有 `InquiryModelApprovalPreview`） |
| `InquiryHubAuthority(registry)`、`InquiryWebAuthority(registry)`、`toolId` 常量与 `run` 行为 | `inquiry_hub_authority_test.dart:128`、`inquiry_web_authority_test.dart:157`、`inquiry_web_task_stop_test.dart:142,238` |
| `validateInquiryWriteResult` | `inquiry_write_tools_test.dart:507,522` |
| `resolveAssistantScope(host, scope)` | `inquiry_write_tools_test.dart:82`、`business_tools_test.dart:102`、`north_star_chain.dart:281` |
| `ResearchSearchAdapter` | `search_test.dart:36` |
| `openModuleObjectPage` | `research_object_open_test.dart:336,350` |
| `MuyonHost.activateResearch()` / `activatePrototype()`、`research` / `prototype` 访问器、`researchError` / `prototypeError` | `acceptance_failure_matrix_test.dart:49-62`、`accepted_research_import_test.dart:22,277`、`business_tools_test.dart:74` |

保持这些符号的办法：旧文件 `app/inquiry_plugin.dart`、`app/inquiry_hub_authority.dart`、`app/inquiry_web_authority.dart`、`platform/business_tools.dart`、`platform/inquiry_write_tools.dart` 在 REG-4 之后仍存在，内容为薄壳或委托（authority 类的构造器保持“传入 `ToolRegistry`”，内部改用 `HostChannel`）。REG-5 之前不删。

### 10.4 询价迁移专节（最高风险项）

**现状要点**：`InquiryPlugin` 不是 `BusinessModule`，打开三个库（`inquiry_plugin.dart:169-171`），`Store.attach` 用 `exclusiveAsync`（`:179-184`），变更日志靠 SQL 触发器（`:62-127`）；`InquiryRuntime`（`inquiry_module.dart:17-48`）与 `AppState` 在 `inquiry_module` 包里，**该包只把 `muyon_module_api` 当 dev 依赖**（`pubspec.yaml`）；`InquiryHostModels` 依赖宿主的 `ModelProfile`、`OpenAiModelGateway`、`MethodChannelSecretStore`（`inquiry_plugin.dart:14-17`）。所以询价的 v2 模块**第一步只能做成宿主侧适配**，而不是纯包模块。

| 步 | 内容 | 前置 | 要点 |
|---|---|---|---|
| **REG-4a 宿主侧适配** | 新增 `app/adapters/inquiry_module.dart`：`InquiryModule implements BusinessModuleV2`（`ModuleSchema` 取自 `InquiryPlugin.schema`；`auxiliarySchemas` = `jobsSchema`、`hubSchema`；`ExclusiveDatabase`）；`InquiryPlugin` 保留为运行时句柄；`ModuleHost.activate('inquiry')` 取代 `_activateInquiry`；`ScopeResolvable` 会话：`resolve` = `store.get` + `version` + `sha256(data)`（与 `business_tools.dart:55-76` 逐字节一致，差分测试守护）；本体适配器（映射 `ontology.dart`）；`registerTools` **原样搬入**询价现有 13 个读工具与 4 个写工具（**id、描述、模式、处理函数与注册顺序都不变**——`tool_descriptions_test` 与评测夹具依赖它们；`research.objects` 随 REG-3 归科研）；两个授权类改为 `HostChannel` 之上的薄类（`review` 回调仍由模块传入，与今天一致）；`resolveAssistantScope` 变薄包装 | REG-2 | **纯搬运、零行为变化**：`north_star_inquiry_test` 与全部 `inquiry_*` 此时必须无需改动即全绿；`module_registry` 表仍写 `inquiry` / `ready`（`bootstrap.dart:254-260`）；`projections.watch('inquiry', …)` 保持（`:250-253`） |
| **REG-4b 补写工具** | 按覆盖清单把其余写操作逐批开放（§8.2 的归类初稿，每批各带测试）。**“计划 / 应用”两步**：`planQuotationImport` / `applyQuotationImport`、`planOffer` / `applyOffers`、`planParamFill` / `applyParamFill`、`planAttributeMigration` / `applyAttributeMigration`、`refreshPlan` / `applyRefresh`、`planSpecResponses` / `applySpecResponses`、`proposeFromList` / `createProjectFromProposal`——领域层本来就分了两步，计划是读（结果带摘要，存为模块工件，`ArtifactRef`），应用是写（参数含该摘要，审批绑定摘要，应用前复核计划未过期）。**直接写**：`award` / `withdrawAward`、`setParam` / `clearParam` / `confirmParams`、`createSpecRequest` / `saveClauses` / `chooseProduct` / `clearChoice` / `setClauseResponse` / `addItemsToBudget`、`mergeInto` / `redirectMerged`、`resolveConflict`、`delete` / `restore` / `markResolved`、`copyProject`。**不开放（理由入清单）**：`replaceFrom`、`exportEncryptedTo`、`syncWithFolder`（覆盖整库 / 凭据 / 外部文件夹，`humanOnly` 或 `dangerousIrreversible`）；文件导出类（`exportTo`、`exportSelection`、各 `export*` Excel / PDF）逐个判为 `export` 工具或 `humanOnly`。每个新写工具沿用现有模式：写明期望旧值（`from_*`），不符则拒绝，使“批准的预览就是实际发生的事”（`inquiry_write_tools.dart:14-17`）；`describe` 工具与 `ontology.actions` 文案同步更新（§4.3） | 4a | 现有 4 个写工具的 id 与行为不变（`create_inquiry` 等，`inquiry_write_tools.dart:100,158,216,248`），`north_star_chain.dart:297-319` 在用 |
| **REG-4c Folio 自带 AI 工具化** | 见下表 | K-3、4b | （宿主模式下 `bypass` 按 `confirmWrites` 读取的过渡已由 FOLIO-BYPASS 提前到 REG-2 同批，若 Q12 获批；4c 再彻底禁用并隐藏对话助手）先“加”后“减”：新增宿主工具并行存在，旧页面在非宿主模式与宿主模式下的用户流程不变；最后一步才在宿主模式隐藏对话助手 |

**Folio 自带 AI 的清点与去向：**

| 功能 | 现在 | 去向 |
|---|---|---|
| “问数据”对话 | `ask_page.dart` 调 `Store.askWithEvidence`（自带工具循环，`assistant.dart:101-150`）+ `AssistantAppTools`（写）+ 采购 / 网页 / 导航工具（`ask_page.dart:206-227`），自有 `AssistantPermission` 三档与确认框 | **宿主助手（K-3 循环）取代**：工具已由 4a / 4b 提供；宿主模式下隐藏该入口与 `AssistantPermission` 设置，`bypass` 在宿主模式下禁用（Q3）；非宿主模式（独立运行与 `inquiry_module` 自测）保持不变，故 `ask_page_test`、`assistant_permissions_test`、`supplier_core` 的 `assistant_*_test` 不受影响（后者需核实隐藏开关的默认值为“可见”） |
| 智能导入报价（`AiTask.offerExtraction`） | `extractOffers` → 复核页 → `applyOffers`（`material_import.dart`、`material_import_page.dart`） | 计划 / 应用工具对：`inquiry.extract_offers`（效应读，内部经 `ModuleModels` 请求模型，逐次过闸门与账本）+ `inquiry.apply_offers`（写，绑定提案摘要）；复核页保留给用户直接使用 |
| 按清单建项目（`listProposal`） | `proposeFromList` → `list_review` → `createProjectFromProposal` | `inquiry.propose_project_from_list` + `inquiry.create_project_from_proposal` |
| 读技术条款 / 提取技术参数（`clauseReading` / `parameterExtraction`） | `spec_extract`、`spec_request` 的 `planParamFill` / `applyParamFill`、条款保存 | 同样的计划 / 应用对 |
| 联网取证（`web_search` / `web_fetch` / `web_product_rows` / `web_extract`） | `AssistantWebTools` 经 `InquiryWebAuthority` | 阶段二可只开放为 `external` 工具中的最小子集，其余覆盖清单标 `deferred('REG-4c')`（Q8） |
| 资料中心发布 | `InquiryHubAuthority` 通道 | 保持**通道**，不作为助手工具（发布是远端写入，仍由用户在资料中心页面确认） |
| AI 任务中心 / 断点续做 | `AiJobStore`（`ai_jobs.dart:32-250`）：库内步骤日志、`ai_applied:<id>` 回执（`app_state.dart:109-112`、`:134`）、`commitAiTask` 同事务入库 | 阶段二**保留为模块私有机制**，不并入 K-4 的 `tasks`；计划工具被中断时返回 `interrupted` 并带 job id，续做是以同一入参重新调用并带 `resume_job_id`；并入统一任务中心列入第三阶段 |

**询价特有风险与对策：**

| # | 风险 | 对策 |
|---|---|---|
| I1 | 三个库，`ModuleResources.database` 只有一个；`exclusiveAsync` 不在 `ManagedDatabase` | `auxiliarySchemas` + `ExclusiveDatabase`（§4.2）；`storage.open` 对同一 id 复用连接（`storage_manager.dart:162`），`bootstrap.dart:252` 的二次打开语义不变 |
| I2 | 进入注册表后新增失败模式（版本、依赖校验） | 询价无依赖、`apiVersion: 2`；故意失败的路径用 `inquiry_plugin_test` 同款覆盖 |
| I3 | 全局范围摘要必须与旧实现一致 | 差分测试：同一夹具库上新旧 `ScopeResolver` 输出相等；询价摘要沿用 `sha256(row.data)`、修订号 `row.version` |
| I4 | 双重授权：Folio 自带写入确认 + `bypass` | 4c 在宿主模式禁用 `bypass`，并隐藏对话助手；`bypass` 的临时按 `confirmWrites` 读取**提前到 REG-2 同批（若 Q12 获批，任务 `FOLIO-BYPASS`，§10.1）**；其余用户直接操作的页面（定标、导入复核）仍是用户本人动作 |
| I5 | 复核对话框来自模块界面（§2.3-7） | 第二阶段不动；助手发起路径不经通道；Q3 建议 UI-9 收归宿主 |
| I6 | `ontology` 的“动作只读”表述与新写工具矛盾 | 4b 同步改文案与 `describe` 输出，补测试 |
| I7 | 变更日志触发器不写 `content_digest`（`inquiry_plugin.dart:88-91`） | 摘要靠 `resolve` 现算，不依赖日志；是否补列留给 REG-4（待核实对既有迁移摘要 `definitionDigest` 的影响——改迁移会改库摘要，须新增迁移而非改旧迁移） |
| I8 | 询价 v2 模块位于宿主侧而非纯包 | 第三阶段抽 `inquiry_host_adapter` 包（需要 `ModuleModels` 等抽象就绪），Q2 |

## 11. 风险

| # | 风险 | 缓解 |
|---|---|---|
| R1 | 契约面大，REG-2 与 K-3 / AUTH-1 并行时迁移编号、`tool_registry.dart`、`bootstrap.dart` 冲突 | REG-2 只在 `tool_registry.dart` 增加最少接口（外传账本钩子）；迁移编号由 leader 派发时统一分配；每个任务开头 rebase |
| R2 | 差分测试通过但缓存失效逻辑有漏洞，导致范围里出现过期引用 | 缓存键含模块投影游标；关键路径（`prepare` 的第 2、3 次）仍按钉住的引用 `resolve` 复核，缓存只用于枚举候选 |
| R3 | `analyzer` 不可用 / 过慢 | §8.2 的降级方案与半天 spike |
| R4 | 覆盖清单被“理由”或 `deferred` 掏空 | 理由类别枚举、≥ 15 字、leader 复核、`deferred` 棘轮（Q8） |
| R5 | 读工具在选中范围泄漏范围外数据（`data` 不受宿主校验） | C-SCOPE；不通过的工具不开放选中范围 |
| R6 | 敏感属性划分不当（漏标 → 审查失效；多标 → 数据中心体验差） | 默认 `unreviewed` 让漏标显性；初稿由 REG-4 提出，用户确认（Q7） |
| R7 | 科研文档摘要“现算 vs 库存”语义差异（§5.1-5）造成过期误判或漏判 | 每类型声明 `verifyOnDisk`，REG-3 逐类型定；差分测试覆盖磁盘被改场景 |
| R8 | 外传账本缺口（§2.3-6）延期，使 v2 外传工具“能发不能记” | REG-2 把“账本写入失败则不调用 handler”作为外传分发路径的前置条件，缺表时 `external` 工具注册失败而不是静默放行 |
| R9 | 迁移期 v1 / v2 并存的双份路径增加维护面 | 严格排期：REG-3 完成即删 `LegacyModuleBridge`；基线清单只减不增 |
| R10 | 范围推进被利用来“洗白”被篡改的对象 | 只在已批准写入的成功回执后推进，且必须 `resolve` 与 handler 返回一致；`interrupted` 不推进（§5.3） |

## 12. 待决问题

### 12.1 交用户决定（附建议）

> **用户决定（2026-10-07）：Q1～Q13 全部按「建议」一栏执行。** Q7 的字段划分已于 2026-10-08 确认：按 [GROK-3 初稿](../reviews/2026-10-07-inquiry-sensitivity-draft.md)执行，并采纳 leader 对 U1～U10 的建议——各类备注、供应商名称与别名、供应商地址（单位地址）、评价/定标说明与询价地点、附件 id、参数依据原文为 `none`；项目客户名与合同号为 `commercial`；项目负责人与询价人姓名为 `personal`；税号、银行账户目前不是字段，日后加入时税号为 `commercial`、银行账户为 `credential`；公司资料中心令牌为 `credential`（在系统安全存储，不属于询价字段）；Q10 的科研导出 / 导入清单已于同日确认（按 [GROK-1 静态核实](../reviews/2026-10-07-adr-0004-static-checks.md) §7 的建议：`exportReport`、`exportClaimDrafts` 开放为本机导出，仍需逐次确认；`exportTask`、`exportResult`、`exportSkillExperiment`、`importResult`、`importTask`、`importResearch` 与设备收发暂不开放，在覆盖清单里记为 `deferred`；本机库写入按 Q10 开放）；Q13 的 spike 失败时回报用户。

| # | 问题 | 建议 |
|---|---|---|
| Q1 | “宿主零改动”的定义：允许 `module_catalog.dart` 一行、两个 `pubspec.yaml` 各一行（Dart 工作区与依赖的必需项）、CI 脚本自动发现包（REG-5 一次性改）。是否接受？ | **接受**。纯“一行登记”做不到：Dart 工作区要求依赖声明；该定义可由脚本判定（§8.4） |
| Q2 | 询价的 v2 模块第二阶段位于 `apps/muyon/lib/app/adapters/`（因依赖宿主模型类型），第三阶段再抽成独立包。是否接受？ | **接受**。强行第二阶段抽包要先设计 `ModuleModels` / 设置桥的完整抽象，会拖慢 REG-4 且增加 `inquiry_*` 回归面 |
| Q3 | 产品行为变化：宿主模式下**隐藏 Folio 自带的对话助手**并**禁用其 `bypass` 档**；用户转用宿主助手（已拥有同样的询价工具）。UI-9 之后把两处模块界面里的“复核对话框”收归宿主 | **同意**。现状是第二套更弱的授权路径（无回执、无审计、`bypass` 不绑范围，§2.3-8）；保留会让 ADR-0002 的底线在询价里形同虚设 |
| Q4 | 外传账本：底线（出站必入账）已由 ADR-0002 §3.4 定下，不是新问题；**待定的只有表结构与时机**——新建 `outbound_tool_requests`（不改绑定模型的 `outbound_requests`），REG-2 建表并接入 MCP、询价网页、询价资料中心、`transfer.*` 四条通道，AUTH-1 再加 `grant_id` | **同意**。晚补则 L2（REG-6）上线时缺口扩大；每条通道的“写不进账则不发送”测试是合入条件 |
| Q5 | 是否允许写工具从全局 / 工作区范围起步（确认卡把目标列出并“加入范围并批准”）？S-1 第二阶段不做 | **第二阶段不做**，在 UI-3 / UI-4 设计确认卡时一并定；S-1 的“选中范围先读后写”已覆盖主路径 |
| Q6 | 选中范围下读工具的数据边界：严格（只返回选中对象）还是允许沿声明关系取一跳邻居？ | **严格** + 泄漏测试（C-SCOPE）。邻居读取扩大了授权含义，需要 UI 展示“将读取的关联对象”，留后 |
| Q7 | 敏感属性：类别词表 `personal` / `commercial` / `credential` 是否合适？询价字段初稿（联系人电话 / 邮箱 / 地址 → `personal`；单价、成本、毛利、合同额、成交价 → `commercial`；其余 `none`）由 REG-4 提出，**最终划分由用户确认**（先于 DC-3） | 采用该词表与初稿；确认时间点放在 REG-4b 合并前 |
| Q8 | 覆盖清单的 `deferred(taskId)` 理由与只减不增的棘轮是否接受？ | **接受**。没有它，网页取证、导出类等大批操作要么被迫仓促开放、要么被迫写不诚实的“不开放”理由 |
| Q9 | v1 契约（`routes`、v1 路径）的移除时点：REG-5 之后一个阶段（第三阶段末）。`supportedApiVersions = {1,2}` 期间不接受新的 v1 模块 | **接受** |
| Q10 | 原型 `add_feedback` 是否开放为写工具（本机、低风险）；科研 16 类写操作里导出 / 导入类（涉及文件与设备）逐项开放还是先 `notExposed` | 原型：**开放**；科研：本机写入开放，导出 / 导入类由 REG-3 逐项提出清单，经用户在派发前确认 |
| Q11 | **外部内容污染规则**：外部内容（L2 结果、联网网页、导入的供应商文本）进入任务后，该任务里“始终允许”类授权不再适用，写入 / 外传一律逐次确认。这收紧 ADR-0002 §5 Q1 / Q2 已确认的放行 | **接受**——只收紧，不碰 §3 底线；注意触发范围含导入的第三方文本，比 Folio 现状（仅网页，`ask_page.dart:286`）更严 |
| Q12 | **`bypass` 过渡处理**：REG-4c 之前，宿主模式下是否由宿主桥接把 Folio 的 `assistantPermission == bypass` 一律按 `confirmWrites` 读取？（`assistant_actions.dart:13`、`app_state.dart:451-458`、`ask_page.dart:220` 的 `autoApprove: permission == bypass`、`:286`） | **是**，作为立即可做的小任务。风险说明：在此之前，导入的供应商文本经提示注入可以驱动**未确认的写入**；这些写入可由回收站恢复（可恢复，但不是无害） |
| Q13 | 把 `analyzer` 作为 dev 依赖加入 workspace（版本钉死、离线构建、与 Flutter SDK 的版本绑定）；spike 失败时是否改用降级扫描器？ | 允许 REG-5 做半天 spike；**失败不自动降级**，回报用户决定 |

### 12.2 留给后续任务核实（不需要用户拍板）

1. `analyzer` 是否能进 workspace、对 `supplier_core` 的解析耗时；降级扫描器的规则（REG-5 spike）。
2. 套件 `lib/testing` 对 `flutter_test` 的依赖形态。
3. `structureDigest` 在套件中的可达方式（今天在应用包里，`storage_manager.dart:139`）。
4. 询价 13 个读工具逐个的选中范围归类与泄漏检查结果（REG-4a / S-1）。
5. 科研各类型 `verifyOnDisk` 取值；宿主与模块摘要算法一致性的差分测试覆盖面。
6. `foundation_scope_test`、`tool_registry_test` 是否断言全局范围含摘要。
7. `document_parser.dart:6`、`knowledge_service.dart:7` 从 `research_module` 取用的具体符号。
8. 询价 `ontology` 文案与 `ontology_test` 的耦合；`describe` 输出是否被其他测试钉住。
9. `ExchangeCapable` 的 `ExchangeEnvelope` 与 `TransferItem` / `TaskOffer` 的映射（REG-3b）。
10. 宿主库迁移编号与 K-2 / AUTH-1 的协调；`module_grants`、`outbound_tool_requests` 的建表迁移。
11. 隐藏 Folio 助手的开关默认值与 `inquiry_module` / `supplier_core` 自测的关系。
12. AUTH-1 对授权“粗粒度范围键”“外部结果污染”的接口形态（§5.4、§7.3）。
13. 科研操作面的完整 `surfaces` 清单与写操作条数（评估记 16 类，本文未逐项核对）。
14. 询价写操作条数：评估记 27 类，本文按 `extension … on Store` 实测约 35 个写成员（含通用 `save` / `delete` / `restore`），口径差异需 REG-4b 开工时对齐。
15. 出站账本是否另有写入点（本文 `grep` 只见网关，§2.3-6）。

## 13. 后果

- 新增模块只需写模块包并登记一行（外加依赖声明）；助手能“用”到什么，由模块自己声明，覆盖缺口在 CI 里红灯而不是靠人记得补。
- 科研、原型、询价的助手能力面从“读为主、写 4 个”扩大到“覆盖清单里除明确不开放者之外的全部”；写入与外传仍逐次或按 ADR-0002 授权放行，一次性审批、防重放回执与账本一个都不少，外传账本缺口被补上。
- 第二阶段工期已按评估调整为约 9–10 周；本文把最危险的询价迁移拆成“纯搬运 → 补工具 → AI 工具化”三步，每步都以 `north_star_inquiry_test` 与 `inquiry_*` 全绿为合入条件。
- 代价：`module_api` 公共面显著变大；v1 / v2 并存期有双份路径；覆盖清单与敏感属性标记是持续的维护负担——换来的是可机检的契约，而不是靠约定。
- 声明式插件（REG-6）与数据中心（DC-1～3）建立在本契约上，其清单与检查项已在此定形，第三阶段开始前再写一份范围 ADR（ADR-0003 的约定）。
