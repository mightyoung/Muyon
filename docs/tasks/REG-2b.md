# REG-2b 通用模块激活、能力授予与范围单点

分支 `task/reg-2b-module-host` · 依据：[ADR-0004](../adr/0004-module-contract-v2.md) §4（接口草案）、§5（范围解析）、§6（宿主侧）、§10.1 REG-2、§10.3（不改的测试与兼容面）· 执行：`implementer-sonnet`（leader 派发）· 审查：leader（`reviewer-sonnet-high`）· 阶段：第二阶段 · 与 REG-2a 并行

## 背景
宿主现在按模块名分支、直接依赖模块包（ADR-0004 §2.2）。REG-2 让宿主只认契约：`module_api` 增加 v2 类型，宿主通过统一的激活入口、能力授予和单一的范围解析使用模块。v1 模块经 `LegacyModuleBridge` 继续工作。**本任务不迁移任何业务模块**，那是 REG-3、REG-4 的事。

## 只做这些
1. `packages/muyon_module_api`：按 §4 加入 v2 类型（`BusinessModuleV2` 与清单、`ModuleOntology`（含敏感属性类别 `personal` / `commercial` / `credential` / `none`，Q7）、`ToolRegistrar`、§4.5 的可选能力接口）。签名以 ADR 为起点，可以按实现需要调整，但要在提交说明里逐条列出与 ADR 的差异。保持 v1 公共面不变。
2. 宿主：
   - `apps/muyon/lib/app/module_host.dart`：`ModuleHost.activate(id)`（§6.1），以及失败隔离（§6.5）；
   - `apps/muyon/lib/app/module_catalog.dart`：唯一的模块登记处（§6.3），每个模块一行；
   - `app/module_registry.dart` 的 `ModuleRegistry` 接受 `apiVersion` ∈ {1, 2}（Q9）；
   - `HostToolRegistrar`（§4.4）：模块声明工具，宿主执行；不向模块暴露任何写回执、审批或 `outbound_*` 的接口；
   - `platform/scope_resolver.dart`（§5.2）：先写**差分测试**，证明新解析器与旧的 `resolveAssistantScope` 等函数在现有模块上的结果逐项一致，再替换旧函数体；
   - `module_grants` 表，主库迁移 **10**（REG-2a 用 9）；能力申请与授予按 §6.2；
   - 首页、菜单、对象页按声明驱动（§6.4）；v1 模块经 `LegacyModuleBridge` 提供同样的声明。
3. 测试：激活与失败隔离、`{1,2}` 版本接受与拒绝、注册器不暴露写账接口（编译期或反射断言）、范围解析差分测试、`module_grants` 迁移、首页 / 菜单 / 对象页在 v1 桥下与现状一致。

## 不做
- 不迁移科研、原型、询价（REG-3、REG-4）；不改界面外观；不做 S-1 的范围推进；不碰 REG-2a 的外传账本文件（`outbound_ledger.dart`、`mcp_adapter.dart`、`inquiry_web_authority.dart`、`inquiry_hub_authority.dart`、`public_tools.dart` 的 `transfer.*`）。
- §10.3 列出的测试一律不改，必须原样通过（含 `north_star_inquiry_test`、`inquiry_*`、`personal_agent*_test`、`foundation_scope_test`、`tool_registry_test`）。

## 冲突约定
后合入 `develop` 的一方，如果迁移号冲突，按 develop 重新编号，并在回报里说明。

## 验证
- 变异：(a) 让 `ModuleRegistry` 接受 `apiVersion = 3`；(b) 让范围解析对某个模块返回不同的结果；(c) 让一个模块激活时抛错。对应测试必须失败（c 要验证其他模块仍然可用）。结果写进提交说明。
- `flutter analyze`（`packages/muyon_module_api`、`apps/muyon`，info 也算失败）；`muyon_module_api` 全量测试；宿主全量 `flutter test`；`bash scripts/ci.sh` 的 analyze 部分。

## 回报
分支与提交哈希、改动文件、与 ADR §4 签名的差异清单、迁移号、验证摘要行、变异结果、没做或不确定的地方。
