# Muyon Android 整体改造审查报告（Claude，2026-10-21）

## 结论

| 判断对象 | 结论 | 一句话理由 |
| --- | --- | --- |
| 允许合并 `codex/muyon-android-refactor` | **REQUEST CHANGES** | 未发现 P0/P1；有 4 个 P2 需在合并前修复或显式降级说明（其中 2 个当前生产路径即可触发）。 |
| 整体产品 / 发布验收 | **INSUFFICIENT EVIDENCE（维持 PARTIAL/HOLD）** | 生产价格证明、真实 provider/tool-loop、真机/x86/16KiB 内核、最终候选的视觉变体、发布包体与模型许可均无证据或有阻断。 |

已有证据的内部一致性良好：最终候选的源码树、设备日志哈希、54 个测试方法清单与源码完全一致，Rust 测试在本环境独立复跑通过。问题集中在**跨层语义不一致**（Rust 与 Kotlin 对“取消后结果”的处理相反）、**恢复路径只在测试中存在**、以及**需求表面已实现但实际不生效**（智能体“指令”）。

---

## 1. 审查对象、范围与环境

| 项 | 值 |
| --- | --- |
| 远端分支 HEAD | `30c033cd8542f566d40e9248bcc498e7efce7fc6`（`docs(review): hand off whole Android refactor audit to Claude`） |
| 本轮代码/证据截止 | `e7dfe69998064af9a338bc2884af327ed8f6ed1e` |
| APK 源码 | `79dca05ba6ff84dbc8a60d0838951aec6720227a`；`79dca05b..HEAD` 只改 `docs/`（已核对 `git diff --name-only`） |
| `origin/develop` | `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`；`merge-base` 与之相同（分支领先 283 个提交） |
| 本地工作区 | 新克隆，`git status` 干净；未触碰原作者工作区与 macOS xcconfig |
| 环境 | Linux 云端工作区，cargo 1.97.0，python3；**无 Android SDK/adb/设备** |

差异规模：

| 范围 | 文件 | 新增行 | 本次审查覆盖 |
| --- | --- | --- | --- |
| 重点 `cebc6876..e7dfe699` | 383 | 38,216 | `crates/`（全部 14.9k 行源码与测试）、`apps/muyon_android` 产品代码（重点文件逐行，其余抽查）、证据目录 |
| 全量 `origin/develop...HEAD` | 1,225 | 121,666 | 另含继承部分：`experiments/redesign`（+34.9k）、`.github/workflows`（+1.4k）、`apps/muyon`（Flutter，+0.5k）、`docs/tasks`（+50k） |

**未检查范围（单列）**：`experiments/redesign/*` 三个被 `muyon-core` 依赖的实验 crate 仅审查了被调用的接口（`check_text`、`DeepSeek` 编解码、`encode_registered_request`），未逐行审计；`.github/workflows`、`apps/muyon`（Flutter）、`ml-native/*.cpp` JNI 原生代码、`OcrGeometry.kt` 几何细节、`SupplierScreen.kt`/`ResearchScreen.kt` 交互细节未逐行审；所有 UI 视觉与设备行为**未复验**（无设备）。因此“继承问题 vs 本轮问题”的区分只对已审文件有效。

执行的命令与退出码：

| 命令 | 退出码 | 结果 |
| --- | --- | --- |
| `cargo test --workspace --locked --no-fail-fast` | 0 | 143 次执行 / 16 个有测试的 suite 全部通过（与记录一致） |
| `cargo clippy --workspace --all-targets --locked -- -D warnings` | 0 | 通过 |
| `python3 -m unittest discover -s apps/muyon_android/checks -p 'test_*.py'` | 0 | 4/4 |
| `sha256sum` 6 份设备日志 vs `suite-manifest.json` | — | 6/6 一致 |
| 源码 `@Test` 方法 vs manifest selector | — | 54 = 54，逐名一致 |
| `git rev-parse 79dca05b:crates` | — | `911c4754…`，与 `candidate.json` 一致 |
| 独立探针测试（见附录 A，外置 crate，未改仓库源码） | 0 | 复现 F1、F3、F8 |

未能复验：APK/test APK 本体哈希与设备已安装哈希（文件位于作者机 `/private/tmp`，远端不可得）；Android 构建、lint、设备方法、截图；模型资产（仓库只含 notice，模型须本地提供）。这些只能按“已有记录”对待，不是本次实测。

---

## 2. 问题清单（按严重度）

严重度口径：P0 数据损坏/越权/费用失控；P1 当前生产路径的错误结果或丢数据；P2 合并前应修的跨层缺陷、需求缺口或证据不足；P3 改进项。每条标注【类型】：确定 bug / 设计风险 / 需求缺口 / 验证不足。

### P0 / P1

无。未发现可绕过授权的写入路径、重复业务写入、未知费用保留被释放，或价格证明缺失时仍能外发的路径。

### P2

#### F1【确定 bug，当前为潜伏】取消发生在远程请求已完成之后，子任务永久卡在“结果未知”，且答案被丢弃、占用活跃名额

- 位置：`crates/muyon-core/src/agent/owner.rs:550`（`cancel_trusted` 对任何状态都写 `cancelled=1`，包括 `completed`）；`crates/muyon-core/src/agent/workflow.rs:796-797`（`cancel_requested && status != "cancelled"` 一律判为 `unknown`）；`workflow.rs:534-547`（`unknown` 计入 2 个活跃子任务上限）。
- 触发：AI 子任务的请求已由 owner 结算为 `completed`，但 UI 尚未轮询到；用户此时停止根任务或子任务。
- 影响：owner 记录 `completed`、已扣费 66 微元、hold 已释放；workflow 却显示“结果未知，请查询原请求”，结果为 null。再次取消、再次观察均无法脱离。两个这样的子任务即让该根任务永久无法再派生（`workflow_child_limit`）。与清单“取消后的迟到结果不改变已停止事实 / 提交后不能因取消抹掉事实”的方向相反：这里是**已发生的事实被取消抹成未知**。
- 复现：附录 A `probe_cancel_after_completion_strands_run_unknown_and_drops_answer`、`probe_stranded_unknown_occupies_active_slot`（均实测）。
- 为何潜伏：生产 `HostedCostVerifier` 为 `None`，远程子任务全部 `blocked`，当前不可达；一旦接入价格证明即触发。
- 最小修复：`cancel_trusted` 只对 `prepared/reserved/unknown/tool_pending` 置 `cancelled`；`observe_remote_chain` 中 `observation.status=="completed" && attempted` 优先于 `cancel_requested`（可另标“取消前已完成”）。
- 回归：上述两个探针改为断言 `completed` 且结果保留；另加“取消与结算交错”的两种顺序。

#### F2【确定 bug（跨层不一致），当前为潜伏】Kotlin 在本地取消后丢弃已收到的完整响应，Rust 本可结算

- 位置：`apps/.../chat/ProductChatRuntime.kt:184`（`allowed()` 含 `request !in cancelled`）与 `:193`（`if (allowed()) port.settle(...)`）。对照 `owner.rs:599-623`：`settle_response` 已能把已取消请求结算为 `cancelled` 并记录真实费用；`tests/agent_workflow.rs:103-110` 也按此语义测试。
- 触发：HTTP 写出后、响应读完前，用户取消、切换项目（`updateScope`）、会话释放或 Service 关闭。
- 影响：已拿到完整响应字节，却不结算 → 请求永久 `unknown`、全额 hold 永久占用累计预算、该会话被 `conversation_original_outcome_required` 永久阻塞。owner 没有任何“查询 provider 原结果”的通道，`query_original` 实际上无法解决。
- 最小修复：响应完整读取后**无条件** `port.settle`（Rust 侧已处理取消与配置变更）；只有读取中断才保留 unknown。
- 回归：Kotlin 侧在 `exchangeConnected` 的离线字节流测试中加“写出后取消→完整响应→settle 得到 cancelled、held=0、charged=usage”。

#### F3【确定 bug，当前生产可触发】附件上传的重启恢复与 GC 只存在于测试，生产从不调用；中断的上传永久残留

- 位置：`crates/muyon-core/src/blobs.rs:755`（`reconcile_blobs_after_restart`）、`:795`（`collect_blobs`）在 FFI 与 Android 中**零调用**（已全仓 grep）；`ProductService.kt:28` 每次 Service 创建都是新的随机 epoch；`blobs.rs:566-568` 旧 epoch 的上传不能被新 epoch 中止；`ResearchFileHost.kt:44-45` 注释称“uploads remain recoverable”。
- 触发：选择 PDF/目录/ZIP 后，上传或确认前进程被杀、Service 重建，或用户离开页面（`close()` 有意不 abort）。
- 影响：staging 文件（单个最多 150 MiB）与 `copying/pinned` 行、旧 reader pin 永久残留；新 epoch `abort_upload` 返回 `InvalidAuthority`。磁盘只增不减，“残留可解释且可恢复”在生产不成立。
- 复现：附录 A `probe_interrupted_upload_is_orphaned_after_epoch_change`（实测：重启后 state 仍 `copying`，abort 被拒，文件仍在；只有未接线的 reconcile 能清理）。
- 最小修复：在 `ProductCore::open` 成功取得 owner 锁后调用 `reconcile_blobs_after_restart`（锁本身证明旧 owner 已退出）；GC 作为显式维护入口或空闲时调用。
- 回归：设备方法“上传中 kill Service→重开→staging 清理、业务数据不变”；Rust 侧把探针纳入正式测试。

#### F4【需求缺口】智能体“指令”可编辑、可保存、可展示，但从不进入任何模型请求

- 位置：`agents/AgentLibraryScreen.kt:112`（编辑）、`:315-316`（详情页展示）；`MainActivity.kt:84-87` 只把智能体映射为 `conversationKey/title`；`chat/ChatScreen.kt:129-130` 的 `chat_prepare` 只发送 `draft`。全仓 `instructions` 只出现在目录与列表页。
- 影响：用户为“单 agent”写的角色与指令对行为零影响，界面也未说明。群组已有“不会自动执行多智能体任务”的诚实说明（`AgentLibraryScreen.kt:143`），单 agent 缺同等说明。属于“看起来像已实现”。
- 最小修复（二选一）：在 Rust `prepare_chat` 由宿主拼入 system 消息（必须在外发预览中逐字展示并计入成本证明）；或在编辑器与详情页明确“指令暂不用于模型请求”。
- 回归：外发预览字段包含/不包含指令的设备断言。

### P2（发布/验收层面，不阻塞合并）

#### F5【设计风险】APK 435,831,129 字节；模型首次使用再复制一份

- 证据：`candidate.json`；`LocalModels.kt:22,31-60` 把约 330 MB 资产复制到 `noBackupFilesDir`。设备上约 2×330 MB 常驻；超过常见应用商店基础包限制，需要资产分发方案。
- 模型许可：`assets/notices/LOCAL_MODELS.txt` 自述 GGUF “未记录转换器或源仓库版本”，许可声明来自 GGUF 自带元数据。自声明元数据不是许可证明，本次未能独立核实上游许可；发布前需取得上游原始模型与转换链的可追溯来源。

#### F6【验证不足】最终候选只在 320×640、字号 1.0 下跑过；200% 字号、宽屏深色、键盘展开的证据属于更早的 `07fd4509`

- 证据：`docs/design/android-reference-20261021/muse-final/README.md` 的变体运行绑定 `07fd4509`；`07fd4509..79dca05b` 改动了 17 个产品文件，含 `ChatScreen.kt`、`ConversationRichText.kt`、`AgentWorkflowSurface.kt`、`ChatPresentation.kt`。最终截图仅两张 320×640。旋转与返回未见针对新工作流界面的设备断言。
- 需要：在最终候选上重跑 200% 字号、宽屏深色、IME 展开与旋转，至少覆盖展开的执行记录、长任务名与多任务下拉。

### P3

| # | 类型 | 位置 | 问题与建议 |
| --- | --- | --- | --- |
| F7 | 设计风险（潜伏） | `owner.rs:333-338`；`ProductChatRuntime.kt:78-82` | 一次工具回合完成后，该会话之后的普通聊天永远返回 `chat_tool_history_review_required`（测试 `agent_tools.rs:199-204` 明确如此设计），但 Kotlin 将其映射成笼统的 `chat_operation_unavailable`。建议显式提示“请新建会话”或提供重新审阅历史的路径。 |
| F8 | 确定 bug（文案） | `workflow.rs:276-289` | 重启时从未执行的本地子任务也被标为“运行中断，请查询原请求”，但它没有原请求可查（探针实测 `remote_request_id=null`）。本地任务应标“已中断，可重新创建”。 |
| F9 | 确定 bug（潜伏） | `AgentWorkflowSurface.kt:270` | 远程子任务完成后的结果对象没有 `summary` 字段，界面会直接展示原始 JSON（含 token 数与 provider id），违背“原始参数按需展开”。应取 `answer` 字段展示。 |
| F10 | 设计风险（性能） | `LocalModels.kt:31-40`；`LocalResearch.kt:30,59-60` | 每次检索都对约 330 MB 模型重新 SHA-256，并重新加载 GGUF；索引同样。现有计时（加载 448 ms）未包含此哈希成本。建议进程内缓存校验结果与运行时。 |
| F11 | 设计风险（潜伏） | `owner.rs:570-574` | 搜索结果为空时结算费用记 0。若供应商按请求计费，会低估累计花费。应由未来的 `SearchPriceVerifier` 合同明确空结果计费。 |
| F12 | 验证不足（文档） | `ACCEPTANCE-MATRIX.md:7,13,38`；`product-device/final/` | 矩阵仍写 26/26、21/21、127 次 Rust 执行，指向旧候选 `7b063cb`/`07fd4509`，没有工作流、OCR、embedding 的行。另：143 次执行中 `business_worker` 二进制通过 `#[path]` 重复运行库内 15 个单元测试，唯一测试函数为 128 个。 |
| F13 | 设计风险（a11y） | `AgentWorkflowSurface.kt:152`、`:74`、`:111` | 技能开关无可读标签（TalkBack 只读“开关”）；错误文案末尾直接拼接机器错误码。证据截图 `01-local-child-result.png` 中有空白条目与方框字形，需确认是刻意的测试数据还是字体回退缺陷；名称不可见时应回退为“未命名记录”。 |
| F14 | 确定 bug（文案） | `AgentWorkflowSurface.kt:98`；`workflow.rs:352-360` | “执行过程 · N项任务”把根任务本身计入（1 个根 + 1 个子任务显示“2项任务”）。 |
| F15 | 设计风险 | `ConversationRichText.kt:83-90` | 模型回复中的链接文字可与目标地址不同，点击直接打开，且允许 `http`。建议展示真实域名或点击前确认，并只允许 `https`。 |
| F16 | 设计风险 | `AndroidManifest.xml:3` | `targetSdk 36` 下仅 `allowBackup="false"` 不阻止设备间迁移；业务库与私有 PDF 可能被迁移。如不希望，应补 `dataExtractionRules`（lint 已提示）。 |
| F17 | 设计风险（资源） | `crates/muyon-android-ffi/src/lib.rs:627-639`；`research.rs:407` | ZIP 清单与封存把最多 150 MiB 的归档整读入 `:core` 进程内存；设备证据仅为小样本。需在设备上测一次上限规模。 |

---

## 3. 需求覆盖

状态口径：已实现 / 部分 / 未实现 / 证据不足 / 外部阻塞。“证据”指本次读过的代码与测试；设备结果均为“已有记录，未复验”。

| 需求 | 状态 | 证据 | 缺口 | 阻塞可恢复 |
| --- | --- | --- | --- | --- |
| 科研：论文添加、手填 PDF 元数据、私有附件 | 已实现 | `research.rs`、`blobs.rs`；设备 PDF/PRIVATE 方法（记录） | F3 中断残留 | 是 |
| 科研：ZIP/目录导入，快照不可变 | 已实现 | Rust 解码后逐成员比对 Kotlin 上传（`research.rs:403-427`），抵消平台 ZIP 解析差异；`archive.rs` 13 个测试 | F17 规模未测 | 是 |
| 供应商 CRUD、删除/恢复、持久身份 | 已实现 | `business.rs` CAS、原回执、history；14 个测试 | 设备双击确认未专测（矩阵已列） | 是 |
| 手动 UI 与模型工具共享业务与授权边界 | 已实现 | 两条路径都经 `prepare_envelope`→`issue_grant_trusted`→`execute`；工具计划不能走普通 `confirm`（`ProductService.kt:267`） | — | — |
| 布局 WorkBuddy / Muse 视觉 / Claude 字体 | 证据不足 | 仅 `07fd4509` 的截图与变体；最终候选两张 320×640 截图 | F6 | 是 |
| 单 agent、群组、会话切换 | 部分 | 会话隔离有设备方法（记录）；群组说明诚实 | F4 指令不生效 | 是 |
| 对话默认简洁，费用/参数/技术记录按需展开 | 部分 | 执行记录默认折叠，原始记录二次展开 | F9、F13 | 是 |
| 子任务生命周期、隔离、工具限制、技能管理 | 部分 | 独立子会话（`workflow.rs:553-557`）、工具目录收窄并在结算时复核（`owner.rs:586-598`）、2 活跃/8 总数、技能停用拒绝创建/执行 | F1、F8；停用技能不影响已绑定待确认的远程子任务 | 是 |
| 本地工具任务 / 手动 AI 子任务 / 自动派生的区分 | 已实现（前两者）；自动派生未实现 | UI 文案与 README 边界一致 | 自动派生、并行推理、父任务综合 | 需新开发 |
| 过程展示只用真实事件，不伪造思考 | 已实现 | 事件全部由宿主写入，`origin` 标注；请求 `thinking:disabled`，`reasoning_content` 非空即拒绝（`owner.rs:848-853`） | — | — |
| 外发预览、确认绑定原请求、累计预算 | 已实现（离线） | payload 摘要、一次性确认、全局累计 hold/charged | F2；价格证明缺失 | 外部阻塞 |
| unknown/pending 只查不重发 | 已实现 | owner 状态机、`claim_dispatch` 先写 unknown 再外发 | “查询原请求”在 provider 侧无实现 | 设计待定 |
| embedding 与 OCR 为真实离线推理并接入业务 | 已实现（模拟器记录） | 真实 GGUF/ONNX 加载与校验；检索时逐源核对论文版本与附件摘要 | F5、F10；PDF 文本层未用 | 部分外部 |
| 真机 / x86_64 运行 / 16KiB 内核 | 证据不足 | 仅静态 16KiB 对齐 | 全部 | 需设备 |
| 真实 provider / tool-loop / 生产价格证明 / I04 | 外部阻塞 | verifier 为 `None`，本次未尝试 | 全部 | 需授权 |

---

## 4. 分领域判断

- **业务/数据**：实现质量高。pending 先持久化再执行、执行事务内同时写效果/history/回执并消耗授权，提交后再校验尾部；存储错误一律变为 unknown 且不重放。供应商 CAS 与 create 必须 `expected_revision=0`（`contract.rs:443`）。未发现重复写入路径。
- **权限/外发**：价格证明缺失时确实无法预留与外发（`confirm_trusted` 要求 reserved>0）；模型无确认入口；工具越权调用保持 unknown 并保留 hold。跨层问题见 F2：Rust 设计“取消后仍结算”，Kotlin 却丢弃响应。另，`productRequestOwnedBy` 在所有 owner 记录为空时视为拥有（`ProductSendGate.kt:71`），重新配置会清空这些记录；目前只影响同一应用内的会话，风险低。
- **恢复/并发**：flock 单 owner、Service 前任排空、新 epoch 使旧任务只读，这些成立。缺陷在于附件恢复未接线（F3）与取消/完成交错（F1）。事件窗口每根任务保留 256 条，`after_seq` 早于窗口时不会提示缺口（代码阅读所得，未复现，当前 8 个子任务上限下难以触发）。
- **模型**：模型与字典哈希、维度、归一化、CTC 解码、BGR 通道顺序（与 PaddleOCR 实际预处理一致）均有校验；检索结果在每次搜索时对权威库复核，删除/换版本不会产生幽灵结果。风险在包体、许可来源与每次重哈希（F5、F10）。
- **UI**：诚实性好，没有伪造思考或完成状态；群组说明清楚。可访问性与潜伏的原始 JSON 展示需修（F9、F13、F14）。视觉验收证据未覆盖最终候选（F6）。

---

## 5. 证据核对

- 已确认：`79dca05b` 的 `crates` 树等于 `candidate.json`；其后只有文档提交；6 份日志哈希与 manifest 一致；54 个 selector 与源码逐名一致，无 `@Ignore`/`Assume`；非 picker 日志 `OK (49 tests)`，5 个 picker 各 `OK (1 test)`；两轮失败诊断保留，根因确为 `optString("error")` 把 JSON null 读成字符串 `"null"`，以及测试 fixture 分页超过 Service 上限 1..10，修复对应根因、断言未放宽。
- lint 33 个警告：21 个 `UseKtx`、6 个 `AutoboxingStateCreation`、3 个 `GradleDependency`、3 个 `ApplySharedPref` 等为风格或小性能项，不影响合并；`DataExtractionRules`（对应 F16）与 `MissingApplicationIcon` 影响发布。
- 测试与实现镜像：工作流测试主要通过公开 API 驱动真实 SQLite，覆盖面不错；但没有覆盖“完成后取消”“取消后到达完整响应”“重启后上传残留”，正好对应 F1–F3。

---

## 6. 合并前建议（最小集合）

1. 修 F1、F2，并把附录 A 探针改为正式回归测试。
2. 接线 F3 的 `reconcile_blobs_after_restart`。
3. F4 至少补 UI 说明；若要接入指令，需同时进入外发预览与成本证明。
4. 更新 `ACCEPTANCE-MATRIX.md` 至最终候选，并注明 143 次执行对应 128 个唯一测试函数（F12）。

发布前另需：F5 包体与许可来源、F6 最终候选视觉变体、真机与 16KiB 内核运行、生产价格证明与 live 验收、I04。本报告不授权、也未执行任何付费调用、密钥读取、I04 重试或数据删除。

---

## 附录 A：探针（外置 crate，依赖本仓库 `crates/muyon-core`，未改仓库源码）

```rust
// F1：完成后取消 → 永久 unknown
o.claim_dispatch(&plan.request_id, &cfg.id, "g").unwrap();
assert_eq!(o.settle_response(&plan.request_id, &answer()).unwrap().status, "completed");
let c = act(json!({"action":"cancel","run_id":root}));
for id in c["remote_request_ids"].as_array().unwrap() { o.cancel_trusted(id.as_str().unwrap()).unwrap(); }
let run = l.observe_remote_chain(&sc, &child, &o.request_chain(&plan.request_id).unwrap()).unwrap();
// 实测输出：owner status=completed cancelled=true；run status="unknown" result=null；
// 再次取消仍为 unknown；两个这样的子任务后新建子任务返回 workflow_child_limit；held=0 charged=66
```

```rust
// F3：中断上传在新 epoch 下无法清理
let upload = s1.begin_upload("proj").unwrap().upload_id;   // epoch-1
s1.append_chunk(&upload, &vec![7u8; 65536]).unwrap();      // 之后进程退出
let s2 = BusinessStore::open_existing(&p, "ws", "epoch-2").unwrap();
// 实测：state=copying；abort_upload → Err(InvalidAuthority)；staging 文件仍在（65536 字节）；
// 仅 reconcile_blobs_after_restart() 能清理（aborted=1, removed_staging=1），而生产从不调用它
```

```rust
// F8：从未执行的本地子任务在重启后显示“请查询原请求”
// 实测：status="unknown" reason="query_original_no_replay" remote_request_id=null can_control=false
```
