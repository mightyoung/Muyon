# REG-1 模块契约 v2 与三层插件（ADR-0004）

分支 `task/reg-1-contract-v2-adr` · 执行：Sonnet 5.5 子代理（leader 派发）· 审查 leader · 阶段：第二阶段（[ADR-0003](../adr/0003-phase2-scope.md) 2026-10-07 修订）· 性质：**只写设计文档，不改代码**

## 背景
见 [AI 原生与注册机制评估](../reviews/2026-10-07-ai-native-and-registration.md)（必读）。用户 2026-10-07 决定：采用注册机制 v2；支持三层插件（原生模块 / 声明式插件 / 内容插件）；能力覆盖作为 CI 硬门槛。

## 交付
`docs/adr/0004-module-contract-v2.md`，状态“提议”，包含：
1. **现状**：逐项写清当前注册、激活、能力授予、工具注册、范围解析、导航、检索与索引、对象页的实际做法，带 `文件:行号`；列出宿主中按模块名分支或直接依赖模块包的位置。
2. **契约 v2 接口草案**（Dart）：`BusinessModule`（manifest、schema、ontology、sections、registerTools、searchSources、activate）；`ModuleManifest` 的能力申请；`ModuleOntology`（对象类型、字段、关系、标题字段、图标、**敏感属性标记**——供数据中心与 ADR-0002 内容审查使用）；`ToolRegistrar`（模块注册读 / 写 / 外传工具，宿主仍负责审批、回执、账本，模块不能绕过 `ToolRegistry`）；可选能力接口（`ImportCapable`、`ExchangeCapable`、`ObjectPages`、`ResultRenderers`、`PublishChecks`）；`ModuleSession.resolve` 成为范围解析的唯一入口。说明与 v1 的兼容策略（API 版本 2，过渡期如何同时支持）。
3. **宿主侧**：通用 `ModuleHost.activate(id)`（取代三份激活代码）、能力按清单申请并按策略授予（记录到模块状态）、单一登记处、导航 / 首页 / 对象页 / 检索如何改为按声明驱动、模块失败隔离不变。
4. **三层插件**：L1 原生模块（编进应用；Flutter 不能运行时加载 Dart 代码的约束）；L2 声明式插件（MCP / OpenAPI 服务 + 可选只读本体，运行时在设置中接入，工具一律按外传类受 ADR-0002 约束，凭据与令牌沿用 P0-S2 的脱敏）；L3 内容插件（WebView，不访问业务数据）。各层的信任边界与能做 / 不能做的事。
5. **契约合规测试套件**（`muyon_module_api/testing`）：检查项清单与判定方法；**能力覆盖清单**的格式（模块的每个业务操作 → 工具 id 或“不开放 + 理由”）以及它如何成为 CI 硬门槛；示例模块“宿主零改动”的验收方法。
6. **与已有 ADR 的衔接**：ADR-0002（模块注册的写 / 外传工具如何进入分级授权；敏感属性与内容审查接口）；ADR-0005（工具 schema 用于原生工具调用；`stage`、载荷键不受影响）；数据中心（v4 设计稿的 6 项检查如何由 `PublishChecks` 与本体声明支撑）。
7. **迁移与拆分**：REG-2～REG-5、S-1、T-3 的边界、顺序、每项要改的文件与测试；哪些现有测试必须保持不改（至少 `module_registry_test`、`contract_v1_test`、`north_star_inquiry_test`、`tool_registry_test`、`inquiry_*` 与 `research` 的现有测试）；询价接入的特殊风险（`InquiryPlugin`、两个授权类、Folio 自带 AI 工具化）。
8. **风险与待决问题**（交用户决定的单独列出，附建议）。

## 约束
- 只新增这一个 ADR 文件；不改代码、测试或其他文档。
- 行号基于本分支实际代码；不确定的写“待核实”。
- 不得提出放宽 ADR-0002 §3 硬性底线的设计；模块注册的工具不得绕过宿主审批、回执与出站账本。

## 验证
抽查 `文件:行号` 引用；相对链接全部可解析。

## 回报
分支与提交哈希；章节目录；待决问题。
