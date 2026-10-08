# REG-4a 询价现有能力纯适配

## 目标、依赖与边界

将已有询价模块按 ADR-0004 BusinessModuleV2 接入，不改业务能力、字段、工具ID或 UI。不重复 REG-2 注册/激活/范围机制，不混入 REG-4b 导入或 REG-4c 新检索。依赖已合 REG-2、AUTH，代码可与 UI-3a 并行；主线联调使用本适配后的真实目录。

## 文件与现有复用

新增 ADR 已规定的 `apps/muyon/lib/app/adapters/inquiry_module.dart`、`apps/muyon/test/inquiry_module_adapter_test.dart`。复用 `app/inquiry_plugin.dart`、`app/module_host.dart`、`app/module_registry.dart`、`platform/business_tools.dart`、`platform/inquiry_write_tools.dart` 与 supplier_core Store；bootstrap 只切换适配入口，旧函数保留薄委托。不存在的 adapters 目录是拟新增，不称已实现。

## 接口、验收与测试

- `InquiryBusinessModule implements BusinessModuleV2`，使用既有 manifest/ontology/sections/auxiliarySchemas/registerTools/searchSources/coverage；`registerTools(ToolRegistrar)` 只把原 handler/spec/effect 接到既有宿主，不发审批或授予。构造依赖复用 InquiryPlugin 服务所有者，不再开一份领域数据库。
- `legacy_and_v2_catalog_match`：逐工具对比 ID、顺序、schema、effect、scope、destination、敏感字段、可用条件，数量相同且无重复注册。
- `scope_revision_and_store_effect_match`：同一真实 Store 的读写结果、粗范围/对象revision与回执新旧路径一致；qty10→12只在原审批后发生。
- `activation_and_shutdown_share_owner`：未激活拒执行，停用后排队拒绝、在途按既有规则结束；无双库/双关闭。
- 保持 `north_star_inquiry_test.dart`、`inquiry_write_tools_test.dart`、`scope_resolver_differential_test.dart`、module_host/registry_v2 回归和 AUTH 不变量。云 Linux CI 用公共 SQLite 测真正 handler；Web 展示夹具不能冒称真实领域写入。

## 实施顺序

- [ ] 固定原目录/真实 Store 行为快照和差分测试，验证新入口尚缺的失败。
- [ ] 最小 V2 适配，保留现有数据、连接及 handler 所有权；不得另造执行/授权内核。
- [ ] 运行新增 adapter 测试及上述已有宿主回归，再 `bash scripts/ci.sh`。
- [ ] 独立审查证明无行为变化；单独提交/推任务分支。回滚切回旧薄入口，数据库不回退清空。

## 通用门禁

本任务为待 leader 复核的派发草案，尚未开工；遵循[本批计划](../superpowers/plans/2026-10-08-ai-native-next-batch.md)。先运行新增行为回归取得有效失败，再最小实现、针对性复跑和独立审查；原始日志不提交，摘要进提交。云端 UI/业务流程验收通过并修复后可推进下一阶段；未覆盖能力登记待验收，原生及实机集中到 [R-1-AI-UI-final](R-1-AI-UI-final.md)，不逐片设实机前置。现有 Mac 截图例外只限已批准快照，不能自动沿用，见[备忘录](VERIFICATION-MEMO.md)。
