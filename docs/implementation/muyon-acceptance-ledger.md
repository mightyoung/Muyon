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
| 2.1d | 有来源记忆：查看/修改/停用/删除/过期 | 🟡 | T：`personal_agent_test` 记忆用例；`dream_test`（停用后不进助手上下文；删除沿 lineage 传递并挡住同一 id 与已删除经验正文；范围收窄传递；过期与停用默认不返回） | 查看/修改界面 → B5；真实模型整理 M 未测 |
| 2.1e | 后台整理/Dream 不扩权 | 🟡 | T：`dream_test`（无档案不发网；显式档案才记 `caller=dream`；冲突不能接受；已注册写入工具不被调用，审批与回执表保持空） | 整理界面与由用户发起的运行 → B；启动流程不自动跑 Dream |
| 2.2a | 研究成果导入/手机阅读/论文/批注/检索/限定问答/引用回跳 | 🟡 | T：research 95 项、`search_test`、`qa_scope_test` | 引用锚 C3，批注 UI B2，R → W3 |
| 2.2b | 问题/方向/证据/实验/结论/卡/提纲关联，关系图/比较/报告 | 🟡 | T：research 95 项（迁入） | R → W3 |
| 2.2c | 执行过程、分支、接纳/否定理由、不确定性 | 🟡 | T：research run assessment | W3 链路验收 |
| 2.2d | 任务/实验导出到另一设备并导回 | 🟡 | T：任务包/结果包（迁入） | 授权语义 C6，R 双设备 → W3 |
| 2.2e | 完整研究包交换（不同本地 ID、分叉、重复导入） | 🟡 | T：`research_package_test` | 往返/分叉矩阵 → C4 |
| 2.3 | 询价完整业务 + 受控只读/计算工具 | 🟡 | T：supplier 467 + 3 跳过、inquiry 历史 309（见下方 W0 记录） | 写操作工具化 C5，存储接管 C1 |
| 2.4 | 原型业务 + 受限 WebView | ❌ | 契约 `RestrictedWebViewSpec`（T：`contract_v1_test`） | B3 |
| 2.5 | 设备互传、一对一聊天、五态独立 | 🟡 | T：`lan_trust_test`、`lan_security_test`、`transfer_states_test`（配对后 TLS 证书固定 + 发送方签名；`f1c27be` 起两端 `minimumTlsProtocolVersion` 为 TLS 1.3，重启后 5 分钟窗口内的消息 id 持久拒绝；送达/落盘/导入/已读/接纳五态独立；研究包接纳后只导入一次）；D：[威胁模型](lan-threat-model.md) | 真实双设备 R；一对一文字聊天界面 → B |

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
| 6.3 | 单写队列、首次导入意图+回执+对账、派生投影 | 🟡 | T：`projection_service_test`（幂等、重放、删除不复活、提交后自动追赶）、`import_recovery_test`（按回执绑定、冲突隔离、放弃前核对回执） | 模块写入变更记录 → C；检索索引已接 `onApplied`（`index_invalidation_test`） |
| 6.4 | 稳定身份、修订、引用锚（摘要+页码+引句） | 🟡 | 卡片修订 ID（research） | C3/C4 |
| 6.5 | 派生数据失效、一致备份恢复 | 🟡 | T：`backup_service_test`（冻结写队列+VACUUM INTO、文件清单 SHA-256、篡改/缺失/越界路径检出、关闭后恢复且旧数据移开不删）；`index_invalidation_test`（对象删除/撤回即从检索移除，取材前回模块核对） | 备份/恢复 UI → B；R → W3 |

## 七～十二、执行、记忆、模型、通信、体验、质量

| # | 需求 | 状态 | 已有证据 | 缺口 |
|---|---|---|---|---|
| 7 | 统一调用路径、审批防重放、中断解释、外部写先查后重试 | 🟡 | T：`tool_registry_test`（含效应点后取消/失败记为 interrupted）、`execution_recovery_test`、`outbound_ledger_test`、`mcp_adapter_test`；D：[调用路径审计](invocation-path-audit.md)、[工具选择评测](tool-selection-eval-2026-10-05.md)（离线规则 top-1 8/11，写入/外发误选 0，未切换生产策略）、[Jev 证据审查](jev-evidence-review-2026-10-05.md) | 审计缺口 G1–G5 归 C/D；MCP 服务器配置与“数据去向”界面 → B；Jev API 与 Laya 均未实测（M） |
| 8 | 记忆/经验/Dream、撤回传递 | 🟡 | 见 2.1d/e | 界面 → B；模型整理 M 未测 |
| 9a | 模型端点显式、凭据安全存储、无隐式回退 | 🟡 | T：`model_gateway_test`、`profile_routing_test` | M 真实端点 → W3 |
| 9b | PDF 文字层优先 + PaddleOCR | 🟡 | M：ONNX 参考推理（`public_services_validation.md`） | Flutter 原生 R 三端 → W3 |
| 9c | 关键词/全文/向量/组合检索、中文短词 | 🟡 | T：FTS5/向量；`retrieval_eval_test`（[300 篇评测](retrieval-eval-2026-10-05.md)：current recall@10 0.961，bigram 0.830，「泵」recall@5 为 0.714 对 0.000；结论仍保持 cjk-bigram + 单字扫描。18 篇历史结果仍在 [retrieval-eval-2026-10-04.md](retrieval-eval-2026-10-04.md)，普通测试不再改写报告） | 向量与真实论文 M 未测 → 待用户提供端点与论文后重测 |
| 9d | 限定资料问答：定位、断言支持、应答/拒答 | 🟡 | T：引用校验 | M 评测 → W3 |
| 10 | 发现/配对/授权/接收/导入分离，加密认证 | 🟡 | T：同 2.5；发现不授予信任、未配对/已撤销拒收、明文握手失败；`task_coordinator_test`（重复 offer、双方接受只执行一次、中途重启不二次执行、对端不可达为 unknown、较新结果保留；配对 TLS 投递任务信封不执行） | 双设备 R。内存 nonce 上限仍是 4096，另有重启后的 seen 文件与 5 分钟签名时间窗。启动流程尚未路由任务信封；业务执行仍属 C |
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

## W2-A 记录（2026-10-04，分支 `feat/a-agent`）

- A5 `d14fd71`：调用路径审计（缺口 G1–G7 及负责人见 `invocation-path-audit.md`）；取消/失败按效应点如实表述；模型出站记录 `outbound_requests`（主库 v5），记录失败则不发送。
- A6：`McpAdapter` 把 MCP 工具作为 network 效应工具接入宿主注册表；契约 `ToolDescriptor.description`。
- 宿主 106 通过 + 1 条件跳过；module_api 17；research 95；inquiry 310 + 1 跳过 + 1 已知 golden 差异；analyze 无问题。
- 未做：MCP 服务器配置持久化与连接界面（等 B 的设置页）；OCR 模型下载未纳入出站记录（G6）。

## W1-D 合入记录（2026-10-04，`develop@7a45815`）

- D1 `fdf781d`：设备身份（P-256 自签证书，私钥经 `FlutterLanSecretStore` 进系统安全存储）、指纹比对配对、撤销；TLS 证书固定 + 发送方 ECDSA 签名（指纹/nonce/消息 ID/长度/正文哈希）；明文通道移除。新依赖 `basic_utils`。
- D2 `7904df9`：五态独立；研究包接纳后经注入回调只导入一次，不授予执行权（含 G1-D）；索引随投影删除/撤回失效。
- D3 `afe96e7`：检索评测台与报告。
- 合并验证（`scripts/verify.sh`）：module_api 17、research 95、supplier_core 475 + 3 跳过、host 117 + 1 条件跳过、inquiry 310 + 1 跳过 + 已知 golden 差异；analyze 全部无问题。
- 审查意见（已转 D）：TLS 最低版本未显式 1.3；评测语料过小；双设备实机未验证。

## W2-D 自验收（2026-10-05，`feat/d-transfer`，合入前）

对照上表 D 负责的行。没有真实第二台设备，没有真实嵌入模型，没有 Jev 密钥，所以这些行保持 🟡，不标 ✅。T 不代替 R 或 M。

- R1 / R3：`f1c27be`。TLS 下限与持久防重放见 2.5、10。Dart 没有可移植的「仅 TLS 1.2」握手，测试锁的是共享 `lanTlsContext()`。
- R2 / R4：300 篇合成语料的报告只在 `MUYON_WRITE_EVAL_REPORT=1` 时写回。无该变量的 `retrieval_eval_test` 已通过，且不改写 `retrieval-eval-2026-10-05.md`。向量行保持 `not measured — needs real model`。
- D4：主库迁移 v6（`dream-and-transfer-tasks`，只追加，不改旧迁移）。`DreamService` 与 `dream_test` 6 项通过。`personal_agent.dart` 改为经 `memoriesFor` / `experiencesFor` 取上下文；`personal_agent_test` 与 `foundation_integration_test` 共 13 项通过。
- D5：`TaskCoordinator` 与 `task_coordinator_test` 3 项通过，含一次配对 TLS 投递。接收不执行。启动流程未接线。
- D6：离线规则评测见工具选择报告。Laya 未安装，记 not measured。Jev 只写了证据审查，未调用 API。
- 同一天 `origin/develop` 的 `4925b99` 是给 B、C 的审查意见，没有新的 D 任务，已合入。
- 已知未跑：本段写入时 `scripts/verify.sh` 尚未作为合入门禁重跑。下面的提交说明以当时的单套测试为准。
