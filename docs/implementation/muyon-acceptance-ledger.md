# Muyon 需求→证据验收账本

依据：用户 2026-10-04《Muyon 总体需求》12 节；计划见 [并行开发计划](../superpowers/plans/2026-10-04-muyon-parallel-dev-plan.md)。

证据类别：**D** 文档审查 · **T** 自动测试 · **B** 平台构建 · **M** 真实模型 · **R** 真机业务。状态：✅ 已有对应证据 · 🟡 部分 · ❌ 未实现 · ⏳ 未验证（有实现无证据）。
规则：只有对应类别的证据存在才能标 ✅；T 不能代替 R，B 不能代替 R，固定语料 M 不等于普遍正确。每次合入更新本表，写明证据位置。

## 二、业务功能

| # | 需求 | 状态 | 已有证据 | 缺口 → 负责/阶段 |
|---|---|---|---|---|
| 2.1a | 主对话/专题对话、桌面并排、手机独立页 | 🟡 | T：`responsive_shell_test`、`personal_agent_test` | R 三端 → W3 |
| 2.1b | 当前页面/选中对象范围、切换项目同步 | 🟡 | T：`foundation_scope_test`、`qa_scope_test` | 切换项目同步的 UI 测试 → B4 |
| 2.1c | 执行可视（目标/进度/设备/等待/错误/产物），关闭聊天保留 | 🟡 | T：`execution_recovery_test` | 执行面板 → B4 |
| 2.1d | 有来源记忆：查看/修改/停用/删除/过期 | 🟡 | T：`personal_agent_test` 记忆用例 | 停用、撤回传递派生数据 → D4/B5 |
| 2.1e | 后台整理/Dream 不扩权 | ❌ | 只读重复候选（`memory_review.dart`） | D4 |
| 2.2a | 研究成果导入/手机阅读/论文/批注/检索/限定问答/引用回跳 | 🟡 | T：research 95 项、`search_test`、`qa_scope_test` | 引用锚 C3，批注 UI B2，R → W3 |
| 2.2b | 问题/方向/证据/实验/结论/卡/提纲关联，关系图/比较/报告 | 🟡 | T：research 95 项（迁入） | R → W3 |
| 2.2c | 执行过程、分支、接纳/否定理由、不确定性 | 🟡 | T：research run assessment | W3 链路验收 |
| 2.2d | 任务/实验导出到另一设备并导回 | 🟡 | T：任务包/结果包（迁入） | 授权语义 C6，R 双设备 → W3 |
| 2.2e | 完整研究包交换（不同本地 ID、分叉、重复导入） | 🟡 | T：`research_package_test` | 往返/分叉矩阵 → C4 |
| 2.3 | 询价完整业务 + 受控只读/计算工具 | 🟡 | T：supplier 466 + 3 跳过、inquiry 历史 309（见下方 W0 记录） | 写操作工具化 C5，存储接管 C1 |
| 2.4 | 原型业务 + 受限 WebView | ❌ | 契约 `RestrictedWebViewSpec`（T：`contract_v1_test`） | B3 |
| 2.5 | 设备互传、一对一聊天、五态独立 | 🟡 | T：设备协议 12 项 | **明文无认证** → D1/D2 |

## 三～六、设计与架构

| # | 需求 | 状态 | 已有证据 | 缺口 |
|---|---|---|---|---|
| 3.1 | 双入口：页面可完整操作、助手结果回页、页面开对话 | 🟡 | 资料页→专题对话已有 | `ModuleSession.objectPage` 契约已加，模块实现 → C/B |
| 4.1 | 唯一入口 `apps/muyon`、契约 `muyon_module_api` | ✅ | D：W0 重命名提交 `525324e` | — |
| 4.2 | 依赖/版本不符只禁用该模块 | ✅ | T：`module_registry_test` | 设置页显示原因 → B1 |
| 5.1 | 模块注册 ID/版本/必要与可选依赖 | ✅ | T：`contract_v1_test` | — |
| 5.2 | 通知/进度声明 | ❌ | — | 有真实需求时加入契约（A） |
| 6.1 | 主库 + 每模块业务库 | 🟡 | T：`storage_manager_test` | 询价 `ai-jobs.sqlite` 等自开库 → C1 |
| 6.2 | 宿主统一建库/升级、漂移阻止启用 | 🟡 | T：`storage_manager_test`、`storage_recovery_test`、`schema_catalog_test`（每次打开按真实状态登记，高版本/漂移/迁移失败记为 blocked 且不改库） | 设置页展示目录与阻止原因 → B；R → W3 |
| 6.3 | 单写队列、首次导入意图+回执+对账、派生投影 | 🟡 | T：`projection_service_test`（幂等、重放、删除不复活、提交后自动追赶）、`import_recovery_test`（按回执绑定、冲突隔离、放弃前核对回执） | 模块写入变更记录 → C；检索索引消费 `onApplied` → D |
| 6.4 | 稳定身份、修订、引用锚（摘要+页码+引句） | 🟡 | 卡片修订 ID（research） | C3/C4 |
| 6.5 | 派生数据失效、一致备份恢复 | 🟡 | T：`backup_service_test`（冻结写队列+VACUUM INTO、文件清单 SHA-256、篡改/缺失/越界路径检出、关闭后恢复且旧数据移开不删） | 备份/恢复 UI → B；检索索引失效 → D；R → W3 |

## 七～十二、执行、记忆、模型、通信、体验、质量

| # | 需求 | 状态 | 已有证据 | 缺口 |
|---|---|---|---|---|
| 7 | 统一调用路径、审批防重放、中断解释、外部写先查后重试 | 🟡 | T：`tool_registry_test`、`execution_recovery_test` | 审计 A5，MCP 适配 A6，Jev/Laya 评估 D6 |
| 8 | 记忆/经验/Dream、撤回传递 | ❌/🟡 | 见 2.1d/e | D4 |
| 9a | 模型端点显式、凭据安全存储、无隐式回退 | 🟡 | T：`model_gateway_test`、`profile_routing_test` | M 真实端点 → W3 |
| 9b | PDF 文字层优先 + PaddleOCR | 🟡 | M：ONNX 参考推理（`public_services_validation.md`） | Flutter 原生 R 三端 → W3 |
| 9c | 关键词/全文/向量/组合检索、中文短词 | 🟡 | T：FTS5/向量 | 评测台 D3，混合检索按结论 |
| 9d | 限定资料问答：定位、断言支持、应答/拒答 | 🟡 | T：引用校验 | M 评测 → W3 |
| 10 | 发现/配对/授权/接收/导入分离，加密认证 | ❌ | — | D1/D2/D5 |
| 11 | 统一设计系统（Folio DESIGN.md）、窄屏/大字体/键盘 | 🟡 | D：[DESIGN.md](../design/DESIGN.md)；T：320–1280 宽、200% 字号 | 宿主/科研主题统一 → B1 |
| 12 | 科研完整链、失败矩阵、三端构建/实机 | ❌ | B：Android APK（开发签名，历史） | W3；需用户提供 macOS(Xcode)/Windows/Android 设备 |

## W0 记录（2026-10-04）

- 基线 `c162a9c`、重命名 `525324e`（`develop` 分支）。重命名后：module_api 10、research 95、host 73 + 1 条件跳过，analyze 无问题。
- 修复两处既有测试问题（非产品代码）：
  - inquiry 8 个测试替身未跟随 `AppState.llm({cancellation})` 签名更新，导致编译失败；
  - supplier `SIGKILL` 用例在 `flutter test` 下用 `flutter_tester` 启动子进程，且新 SDK 的 `dart run` 在 stdout 前缀 `Running build hooks...`。
- 已知未解决：inquiry `screenshot_test.dart / desktop settings` golden 差异（迁入时已记录，原代码复现）。

## W1-A 记录（2026-10-04，分支 `feat/a-storage`）

- A1 `63356f5`：目录由 StorageManager 回调统一登记（含此前未登记的 `inquiry_jobs`、`public_knowledge` 与主库自身）。主库 v3。
- A2 `79a448d`：`ProjectionService` 把模块变更记录投影到 `object_catalog`；契约 `record` 增加可选 `summary`。
- A3 `733f273`：`BackupService.create/verify/restore`，`StorageManager.quiesce`。
- A4 `34b8e39`：`ImportCoordinator.recover/abandon`；主库 v4。
- 宿主 91 通过 + 1 条件跳过；module_api 17；research 95；analyze 无问题。
- 未做：启动时主动扫描未打开的模块库（目录在该库下次打开时修正，避免为对账额外打开业务库）；备份/恢复与目录状态的界面；`ManagedDatabase.raw` 仍可被模块绕过队列写入（靠契约与审查约束）。
