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

- [x] 固定原目录/真实 Store 行为快照和差分测试，验证新入口尚缺的失败。
- [x] 最小 V2 适配，保留现有数据、连接及 handler 所有权；不得另造执行/授权内核。
- [x] 运行新增 adapter 测试及上述已有宿主回归，再 `bash scripts/ci.sh`。
- [ ] 独立审查证明无行为变化；单独提交/推任务分支。回滚切回旧薄入口，数据库不回退清空。

## 通用门禁

本任务已按本次派发执行；遵循[本批计划](../superpowers/plans/2026-10-08-ai-native-next-batch.md)。先运行新增行为回归取得有效失败，再最小实现、针对性复跑和独立审查；原始日志不提交，摘要进提交。云端 UI/业务流程验收通过并修复后可推进下一阶段；未覆盖能力登记待验收，原生及实机集中到 [R-1-AI-UI-final](R-1-AI-UI-final.md)，不逐片设实机前置。现有 Mac 截图例外只限已批准快照，不能自动沿用，见[备忘录](VERIFICATION-MEMO.md)。


## REG-4a 实施证据（2026-10-08）

基线 `5afb08f2b0d53ca5d8578e63073fea6ac385a8af`；独立 worktree `/private/tmp/reg-4a-inquiry-adapter`、任务分支 `task/reg-4a-inquiry-adapter`。不合并 develop/main，不改 UI recovery 分支、历史 AUTH 或数据集。

- 新增 `app/adapters/inquiry_module.dart`。V2 适配持有原 `InquiryPlugin`，三个数据库由 ModuleHost 打开并交给同一 Store/排他执行器。旧 `open`、`activateInquiry`、注册函数及 UI 壳继续兼容；迁移 SQL 和摘要不变。
- 原 17 个业务工具的 ID、询价内顺序、描述、schema、effect、scope、数据模块和注册守卫由固定目录夹具及旧/V2 注册参数差分锁定。`set_item_qty` 的既有宿主 effectIntent、原审批和回执内核保持；未扩展公用 ToolRegistrar 的授权能力。
- 全部源本体字段逐项比较，敏感分类锁定已接受的 ADR-0004 Q7 决策；未新开放动作、导入工具、检索服务、模型或云服务。
- 保留原范围枚举以守住全 entityTypes 及原顺序：现有 change-log 只覆盖五类，直接切换候选目录会丢对象。V2 ScopeResolvable 在同一真实 Store 上验证 revision 与 sha256(raw data)，保留枚举检查 ready/runtime。代价是 REG-4a 后这条宿主兼容范围桥仍存在；完整目录迁移不在本片。
- 有效 RED：询价不在 V2 catalog；失效 owner 仍枚举对象；撤销持久化失败后两个内部 channel 仍 available；已 ready 但宿主记录未落定时重复激活过早完成。均以最小适配修复并取得 GREEN。原 InquiryHome 预激活导航回归也已恢复。
- 真实 Store 差分：旧、新路径均在原宿主审批后才 qty10→12，回执和对象引用一致；失效 revision/digest 拒绝；已批准排队写入在 stopAdmission 后拒绝；会话不关共享 Store，服务所有者关闭幂等。
- 独立只读审查无 Critical；两个 Important（保留 owner 的 scope、激活时新增内部通道的生命周期）已补 RED→GREEN 回归。macOS Podfile/xcconfig 自动生成改动已排除。原始日志仅在 `/tmp/reg4a-*.log`，不提交。
- 本机针对性回归 116 项通过。完整 `bash scripts/ci.sh`：8/8 analyze、doctor 23 场景、7/8 测试套件通过，host 1140 passed/3 skipped；inquiry 281 passed/1 skipped/46 failed（screenshot_test 41、ontology_screenshot_test 5），整体 exit 1。最终并发边界修复后复跑 `flutter analyze --no-pub` 无问题、完整 host 套件 1141 passed/3 skipped。
- 46 个截图失败不套用其他 SHA 的 Mac 例外，不声称截图一致、整本机 CI 通过或三端验收通过。云 UI 用户暂缓，原生/实机最后；任务分支 Linux CI 按本次 SHA 单列结果，不能替代 Mac 截图验收。
