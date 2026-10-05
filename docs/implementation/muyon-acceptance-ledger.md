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
| 2.1d | 有来源记忆：查看/修改/停用/删除/过期 | 🟡 | T：`personal_agent_test` 记忆用例；`dream_test`（停用后不进助手上下文；删除沿 lineage 传递并挡住同一 id 与已删除经验正文；范围收窄传递；过期与停用默认不返回）；`memory_page_test`；D：[记忆与整理接口](dream-ui-api.md) | 记忆页已能查看/修改/停用/删除/过期（develop `9a87ab5`，B 的界面）。范围收窄还没有界面。真实模型整理 M 未测 |
| 2.1e | 后台整理/Dream 不扩权 | 🟡 | T：`dream_test`（无档案不发网；显式档案才记 `caller=dream`；冲突不能接受；已注册写入工具不被调用，审批与回执表保持空）；`memory_page_test`；D：[记忆与整理接口](dream-ui-api.md)（`MuyonHost.open` 只构造 `DreamService`，不调用 `run()`） | 整理区已能由用户发起运行、接受和撤回（develop `9a87ab5`）。启动流程不自动跑 Dream。真实模型整理 M 未测 |
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
| 7 | 统一调用路径、审批防重放、中断解释、外部写先查后重试 | 🟡 | T：`tool_registry_test`（含效应点后取消/失败记为 interrupted）、`execution_recovery_test`、`outbound_ledger_test`、`mcp_adapter_test`；D：[调用路径审计](invocation-path-audit.md)、[工具选择评测](tool-selection-eval-2026-10-05.md)（140 题。离线规则 top-1 54/140，其中精确 id 28/28，中文/中英/释义为 0；写入/外发误选 0，弃权质量 26/26，本次规则延迟 3.330 ms，费用 0，未切换生产策略。Laya `laya==0.3.27`，检查点 `convaiinnovations/laya-multilingual` 修订 `1720e3e3357cfe1e281542e223f8273b0890ca34`，4 线程，进程内 CPU、无监听端口：校准阈值 0.95，留出集 top-1 46/93，误写 0，p50 439.113 ms，p95 817.457 ms。ONNX 未导出）、[Jev 证据审查](jev-evidence-review-2026-10-05.md) | 审计缺口 G1–G5 归 C/D；MCP 服务器配置与“数据去向”界面 → B；Jev API 未调用；Laya 的概率不是授权，生产策略未切换；ONNX 未导出 |
| 8 | 记忆/经验/Dream、撤回传递 | 🟡 | 见 2.1d/e | 记忆页和由用户发起的整理已在 develop `9a87ab5`。范围收窄、经验列表管理界面还没有。模型整理 M 未测 |
| 9a | 模型端点显式、凭据安全存储、无隐式回退 | 🟡 | T：`model_gateway_test`、`profile_routing_test` | M 真实端点 → W3 |
| 9b | PDF 文字层优先 + PaddleOCR | 🟡 | M：ONNX 参考推理（`public_services_validation.md`） | Flutter 原生 R 三端 → W3 |
| 9c | 关键词/全文/向量/组合检索、中文短词 | 🟡 | T：FTS5/向量；`retrieval_eval_test`（[300 篇评测](retrieval-eval-2026-10-05.md)：current recall@10 0.961，bigram 0.830，「泵」recall@5 为 0.714 对 0.000；结论仍保持 cjk-bigram + 单字扫描。18 篇历史结果仍在 [retrieval-eval-2026-10-04.md](retrieval-eval-2026-10-04.md)，普通测试不再改写报告） | 向量与真实论文 M 未测 → 待用户提供端点与论文后重测 |
| 9d | 限定资料问答：定位、断言支持、应答/拒答 | 🟡 | T：引用校验 | M 评测 → W3 |
| 10 | 发现/配对/授权/接收/导入分离，加密认证 | 🟡 | T：同 2.5；发现不授予信任、未配对/已撤销拒收、明文握手失败；`task_coordinator_test`（重复 offer、双方接受只执行一次、中途重启不二次执行、对端不可达为 unknown、较新结果保留；配对 TLS 投递任务信封不执行）；`task_host_test`（两台宿主回环：一次 offer 不执行，双方接受后只有较低设备 id 的注入执行器跑一次，关闭对端后查询为 unknown，本地状态不被改成失败或完成）；`chat_backend_test`（文字经配对 TLS：`sent` 不自动重发也不改成失败，显式 `retryText` 后对方去重并回 `delivered`；离线不落行；撤销配对后历史仍在且拒绝再发；包内 `message` 进聊天且 `imported` 仍为 false；文字不进工具注册表、记忆或经验） | 双设备 R。内存 nonce 上限仍是 4096，另有重启后的 seen 文件与 5 分钟签名时间窗。聊天界面 → B，接口见 [chat-backend.md](chat-backend.md)。科研导入的 `onAccepted` 已由 C/E 接到人工接纳之后。替换执行器之前，设备页点「授权执行」会因默认执行器拒绝而把任务记为失败 |
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
- 门禁 `scripts/verify.sh` 退出码 0：analyze 五个包无问题。module_api 17，research 95，supplier_core 478 + 3 跳过，host 131 + 1 条件跳过，inquiry 310 + 1 跳过，另有 1 个已知 golden（脚本只放行 `screenshot_test.dart: desktop settings`）。普通测试没有改写评测报告。

## D-R5～D-R7 自验收（2026-10-05，`feat/d-transfer`，合入前）

仍没有真实第二台设备，没有 Jev 密钥，所以 2.1d、2.1e、2.5、7、10 保持 🟡。T 不代替 R。Laya 这次是本机进程内实测，不是生产切换。

- D-R5：`MuyonHost.open` 在 `TransferService` 旁构造 `TaskCoordinator`，把配对通道上的任务信封交给 `receive`，设备页显示所有权与状态。收到 offer 不执行。`task_host_test` 通过。合入 `origin/develop` 之后，`onAccepted` 由人工接纳触发科研导入，那条路径是 C/E 的。
- D-R9：文字聊天在传输库 `chat_messages`。`chat_backend_test` 3 项通过。接口见 `chat-backend.md`。界面仍属 B。没有真实第二台设备。
- D-R6：仓库外 `~/.cache/muyon-eval` 的 Python 3.12 虚拟环境，`laya==0.3.27`、`torch==2.14.1`。`LAYA_THREADS=4`，并在加载前 `torch.set_num_threads(4)`。只把合成题集送给模型。第一次下载在磁盘写满时失败（`No space left on device (os error 28)`，检查点 643.84 MB）。腾出空间后重测成功，数字见工具选择报告，没有手改延迟。ONNX 未导出：wheel 里没有 `scripts/export_onnx.py`，且检查点落地后数据卷只剩约 1.6 GiB。应用依赖没有加入 Python、PyTorch 或 Laya。
- D-R7：合成题集 28 个启动时注册的工具、140 题。报告只在 `MUYON_WRITE_EVAL_REPORT=1` 时重写。Jev 仍是证据审查，未调用 API。LLM 端点未设置，记 not measured，这次运行也不发送提示词。
- 给 B 的界面清单在 `dream-ui-api.md`。`revert` 会按运行开始时的快照重写全部记忆、经验和墓碑，包括快照之后用户自己的修改。
- 同步了 `origin/develop` 的 `4b90b3b`。其中 `9a87ab5` 是 B 的记忆页和由用户发起的 Dream，D 没有改这些界面。`bootstrap.dart` 在 B 构造 `DreamService` 之外，只追加了 `TaskCoordinator`。范围收窄和经验列表的管理界面仍然没有。
- 2026-10-05 `scripts/verify.sh` 日志在 `d884aef` 上每一行都是 ok，按脚本规则这就是退出码 0。进程结束后没有另存退出码。analyze 七个包通过。module_api +17，muyon_ui +6，prototype +24，research +140，supplier_core +478 加 3 个跳过，host +209 加 1 个跳过，inquiry +320 加 1 个跳过再减 1。inquiry 被标成 ok，脚本只放行 `screenshot_test.dart: desktop settings`。
- D-R8 阶段 1 已实测，门禁 1 失败，Kaggle 没有开始，`.env` 没有打开。`laya==0.3.27`，检查点 `convaiinnovations/laya-multilingual` 修订 `1720e3e3357cfe1e281542e223f8273b0890ca34`，4 线程，CPU，离线。留出折 93 题 top-1 28、写入/外发误选 3、弃权 57、p50 681.188 ms。对抗误选 1，否定集误选 1。误选是 `adversarial-delete`→`knowledge.delete`（1.0）、`chinese-transfer-export`→`transfer.send`（0.6122）、`misleading-delete-as-search`→`knowledge.delete`（0.9997）、`negation-ocr-download`→`ocr.install_models`（0.9615）。数字在仓库外 `~/.cache/muyon-eval/stage1-metrics.json`。
- D-R8b 阶段 1 重做已实测，门禁 1b 失败，Kaggle 没有开始，`.env` 没有打开。同一检查点、4 线程、CPU、离线。没有短名单；选项是 17 个只读工具加 `none`，键是工具 id。阈值只在 2240 行合成训练集上拟合，结果是 1.0；`noul` 在留出折上是 20 对 27，已丢掉。留出 93 题 top-1 27、写入/外发误选 0、弃权 84。其中 26 题期望写入或联网，在只读规则下不可能算对；27 分是 18 道 none 的正确弃权加 9 道置信度 1.0 的精确 id。对抗 10/10、否定集 24/24，误选都是 0。只做选择的 p50 662.748 ms，p95 991.612 ms。留出折上另扫一遍阈值，最高 29/93，没有用来拟合。数字在 `~/.cache/muyon-eval/stage1b-metrics.json`，摘要在工具选择报告的「阶段 1b」。生产策略没有切换。`laya-readonly-v1` 的过滤测试在 focused `selection_eval_test` 里通过。
- D-R9b：`acceptChat`、`rejectChat`、`retryText`、`deleteChat` 改为 `(peerFingerprint, messageId)`。两个对方共用同一个 `messageId` 时，各自的操作只改自己那一行；不存在的一对仍是 `消息不存在`。focused `chat_backend_test` 4 项通过。接口见 `chat-backend.md`。
- 2026-10-05 `scripts/verify.sh` 在 `e4ab83c` 上退出码 0。analyze 七个包通过。module_api +17，muyon_ui +6，prototype +24，research +185，supplier_core +478 加 3 个跳过，host +220 加 1 个跳过，inquiry +320 加 1 个跳过再减 1。inquiry 被标成 ok，脚本只放行 `screenshot_test.dart: desktop settings`。
- D-R8c：用户已确认 Kaggle 手机验证。可比子集是留出题里只读选择器能回答的 67 题（只读 49、none 18）。阶段 1b 在这 67 题、阈值 1.0 上是 27/67，误选 0；chinese、mixed、paraphrase 各 0/12。D-R6 没有逐题记录，同一子集的基线尚未重测，门禁 2 还不能下结论。决定阈值改为训练验证折重加权，不在 140 题上拟合。验证折 448 行留在本机，上传 1792 行。67 题里 12 道英文精确 id 在训练集中没有对应格子。私有数据集 `amurdaddy/muyon-laya-tool-choices` 已就绪，私有内核 `amurdaddy/muyon-laya-tool-finetune` 第 1 版已推送，状态 `RUNNING`。没有推到 Hub。权重和 SHA-256 还没有。生产策略没有切换。阶段 3 未开始。
- D-R8c 补充：引用选项说明的那版训练集不能拿去训练。内核 `amurdaddy/muyon-laya-tool-finetune` 已删除，随后查询状态是 403。新生成器种子 `20261007`，2467 行（计划 2360 加通过检查的种子 107；18 行种子因复述选项文本未并入）。标签 read 1797、none 670。满选项 1469/2467。评测 5-gram 最大 Jaccard 0.4167。选项文本最长公共子串 7，二元组 Jaccard 最大 0.2。验证折 494 行的格子覆盖 `none|zh`、`read|zh`、`read|mixed`、`read|en`，没有对不上的目标格子。`test_stage2_data.py`、`test_stage2_threshold.py`、`test_kaggle_submit.py` 通过。满选项头长 494 token，16 项都分得开，`head_max_len` 512 没有截断。新文件还没有重新上传，微调还没有重新开始。生产策略没有切换。阶段 3 未开始。
