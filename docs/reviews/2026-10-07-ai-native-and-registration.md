# AI 原生基础与插件注册机制评估

日期：2026-10-07 · 基线：`develop@ecbf120`（K-2a 未合入）· 性质：评估与决定记录 · 决定：用户 2026-10-07 同意（§6）

## 0. 结论

**底座扎实，但 Agent 还不是业务核心；插件注册机制既不普适也不快速。**

- 已有的 AI 原生底座：统一工具注册表（参数校验、范围、一次性审批、防重放回执）、出站账本、对象引用与对象页、询价本体驱动的通用只读查询、分级授权（[ADR-0002](../adr/0002-graded-assistant-authorization.md)）、内核 v2 设计（[ADR-0005](../adr/0005-model-adapter-and-agent-loop.md)）。
- 差距：插件能被助手“查”的不少，能被助手“做”的很少；工具由宿主硬编码而不是插件声明；范围模型挡住多步业务；询价模块内另有一套 AI；插件接入要改宿主十几个文件。

## 1. 业务插件对 Agent 的开放程度（实测）

| 插件 | 业务操作 | 开放给助手的工具 | 覆盖 |
|---|---|---|---|
| 询价 · 读 | 本体查询、比价、预算、匹配、数据质量 | 13 个只读工具（`supplier_core/lib/src/agent_tools.dart`，经 `platform/business_tools.dart:179-200` 注册） | 好 |
| 询价 · 写 | 27 类写操作（`award`、`createSpecRequest`、`setParam`、`restore`、`mergeInto`、`applyQuotationImport`、`resolveConflict`……） | 4 个（`platform/inquiry_write_tools.dart`） | 约 15% |
| 科研 · 读 | 项目、文档、卡片、运行、提纲、关系 | `research.objects`（标题子串）+ 公共 `knowledge.search` | 弱 |
| 科研 · 写 | 16 类（`saveNote`、`addOutline`、`assessRun`、`acceptRun`、`exportTask`、`importResult`、`exportReport`……） | 0 | 无 |
| 原型 | 列表、详情、版本、反馈 | 2 个只读（`platform/prototype_tools.dart`） | 弱 |
| 平台 | 记忆、对话、执行记录、通知、设备、工作区 | 仅 `knowledge.*`、`transfer.*`、`ocr.*`、`embedding.*` | 部分 |

## 2. 显著问题

1. **写操作基本未开放**：多数业务动作只能在界面完成。
2. **工具由宿主硬编码**：宿主 21 个文件 import 业务包（`platform/`、`services/` 下 8 个）；询价未实现 `BusinessModule`，不在注册表、没有 `objectPage`。
3. **范围模型挡住多步业务**（E-1 核实）：只读工具只支持全局范围、写入工具只支持选中范围；选中范围钉住修订号，写一次后下一次调用失败（`business_tools.dart:62-70`、`:164-172`）。
4. **两套助手**：`supplier_core` 的 assistant / ai_jobs 等约 5,700 行，加 `inquiry_module` 的“问数据”“AI 任务”，经宿主网关跑自己的循环，工具、确认、任务中心各自一套。
5. **内核弱**：自定义 JSON 协议、非流式、4 轮、逐轮确认（K-2、K-3 解决中）。
6. **Agent 看不到平台自身**：执行记录、记忆、通知、设备不可查询。
7. **没有主动性**：无后台 / 定时任务（第四阶段）。
8. **真实模型证据少**：E-1 只跑了夹具。

## 3. 插件注册机制（实测）

| 环节 | 现状 | 证据 |
|---|---|---|
| 契约 | 清单、库结构、`routes`、`activate`；运行时必须实现导入三件套与 `openSession` | `muyon_module_api/lib/src/module.dart` |
| 登记 | 注册表校验 API 版本、依赖、循环（好），但名单写死 | `app/bootstrap.dart:142` |
| 激活 | 每个模块一份约 50 行的相同激活代码，宿主类型强转（`as ResearchRuntime`） | `bootstrap.dart:229-360` |
| 能力授予 | 写死在启动代码（科研 `{knowledge, models, tools}`，原型空集） | `bootstrap.dart` |
| 工具 | 宿主替模块写 | `business_tools.dart` 等 |
| 范围解析 | 契约有 `ModuleSession.resolve`，助手范围解析却绕过它直接读模块库 | `business_tools.dart:42-170` |
| 导航 | `routes` 已声明但宿主从未使用；首页、壳层、对象页按模块名 `switch` | `object_pages.dart:66-69`、`platform_shell_home.dart:46-70` |
| 检索、索引 | 科研检索适配与索引失效写在宿主里 | `search_service.dart:88`、`research_search_adapter.dart`、`index_invalidation.dart` |
| 询价 | 专用 `InquiryPlugin`（382 行）+ 两个授权类 | `app/inquiry_plugin.dart` |

宿主提到科研的文件 21 个、询价 14 个、原型 6 个：新增一个插件要改宿主十几处。

**评价：** 不普适（插件能力不在契约里，取决于宿主替它写了什么）；不快速（复制激活代码 + 各处补分支）；门槛错位（简单插件被迫实现导入与会话，而“可被助手调用”反而不是契约要求）；Flutter 发布版不能运行时加载 Dart 代码，“快速”不能只靠原生模块。

## 4. 新机制：契约 v2 + 三层插件

**L1 原生模块（编进应用）**：模块自己声明一切，宿主一行登记。

```dart
abstract interface class BusinessModule {
  ModuleManifest get manifest;          // id、版本、依赖、申请的平台能力
  ModuleSchema get schema;
  ModuleOntology get ontology;          // 对象类型、字段、关系、标题字段、图标、敏感属性
  List<ModuleSection> get sections;     // 二级导航（取代未使用的 routes）
  void registerTools(ToolRegistrar r);  // 读 / 写 / 外传工具：schema、效果、范围、处理
  List<SearchSource> get searchSources;
  Future<ModuleRuntime> activate(ModuleResources resources);
}
// 可选能力接口：ImportCapable、ExchangeCapable、ObjectPages、ResultRenderers、PublishChecks
```

宿主通用 `ModuleHost.activate(id)`；能力按清单申请、按策略授予；范围解析统一走 `ModuleSession.resolve`；新增模块只加登记一行。

**L2 声明式插件（运行时接入，免发版）**：MCP 服务器或 OpenAPI 服务，工具自动注册为外传类，受 ADR-0002 约束；可附只读本体声明接入数据中心。现有 MCP 适配器是雏形。

**L3 内容插件（WebView）**：现原型插件；内容原样展示，不访问业务数据。

**配套**：脚手架；契约合规测试套件（`muyon_module_api/testing`：库结构迁移可执行；工具有 schema 与效果；对象类型可解析并有页面或写明没有；**能力覆盖清单**——业务操作有工具或写明不开放理由；敏感属性已声明）；CI 门槛“示例模块宿主零改动”。

## 5. 任务

| 编号 | 内容 | 依赖 | 阶段 |
|---|---|---|---|
| REG-1 | ADR-0004：契约 v2、三层插件、合规测试套件；并入原 DC-1 的本体声明 | — | 二 |
| REG-2 | 通用模块激活；能力按清单授予；宿主不再按模块名分支 | REG-1 | 二 |
| REG-3 | 科研、原型迁到契约 v2；科研工具补齐 | REG-2 | 二 |
| REG-4 | 询价改造成 `BusinessModule`；询价写工具补齐；并入询价自带 AI（工具化，由 K-3 循环驱动） | REG-2、K-3 | 二 |
| REG-5 | 示例模块、脚手架、合规测试进 CI，验收宿主零改动 | REG-3 | 二 |
| S-1 | 范围模型：只读工具支持选中范围；宿主批准的写入后按回执推进修订号；同一任务可先读后写 | K-3 | 二 |
| T-3 | 平台自省工具（执行记录、记忆、通知、设备只读；记忆写入只能“提议”） | REG-2 | 二 |
| REG-6 | 声明式插件（MCP / OpenAPI + 只读本体） | REG-5 | 三 |

顺序：K-2a → K-2b、K-3 与 REG-1 并行 → REG-2 → REG-3、REG-4、T-3 → S-1、AUTH-1 → UI-3、UI-4。AUTH-1 要先于大量开放写工具。

## 6. 用户决定（2026-10-07）

1. **采用**注册机制 v2（REG-1～REG-5），连同 S-1、T-3 前移到第二阶段。
2. **支持**三层插件；声明式插件（REG-6）放第三阶段。
3. **能力覆盖作为 CI 硬门槛**：每个业务操作必须有对应工具，或在模块的能力覆盖清单中写明不开放的理由。
