# Meta Muse 安卓客户端解析报告（ANDROID-REFERENCE-01 · 第二份）

- 样本：com.facebook.aura 11.0.0.8.164（versionCode 1061601403），来自用户提供的 Google Drive 链接，2026-10-13 16:32（北京时间）获取
- 方法：只做静态分析（清单、资源字符串、assets、jadx 反编译；`com.facebook.aura` 包下的类名**没有混淆**），并与 Meta 官方资料交叉核对。**没有运行，没有截图，所以没有 B 级证据**
- 证据等级：**A** 指固定版本包内的直接证据（类名、枚举、字段、文案、assets）；**A-线索** 指只能证明客户端存在这个接口或文案；**C** 指官方资料（带日期）；**D** 指推断
- 重要边界：Muse 的执行发生在**每个用户独立的云 VM** 上（A 加 C）。下文提到后台执行和云 VM，都只是在描述 Muse，**不能**直接变成 Muyon 的本机能力承诺

---

## 1. 一页结论

| 类别 | 结论 |
|---|---|
| **值得借鉴** | ① **记忆和身份就是用户可读可写的文件**：客户端直接读写 agent 工作区里的 `MEMORY.md`、`IDENTITY.md`、`SOUL.md`（A：`MemoryDataSource`、`IdentityViewModel`、`HatchFileOperations`）。界面提供“查看 → 编辑 → 预览确认 → 保存或放弃”（A：`startEditing / showReviewSheet / saveContent / discardChanges / hasUnsavedChanges`）。官方说用户可以检查、编辑、下载这些文件，也可以让 agent“忘记”（C）。② **审批档位很细**：允许一次、本会话、今天、始终，自动允许，拒绝，始终拒绝，超时；另有待批和近期记录快照、审批历史页（A：`ApprovalRecordDecision`、`ApprovalSnapshotJson`；文案 “Approvals history”）。③ **生效中权限可以单独查看和撤销**：按 会话 / 今天 / 长期 和 连接器 / 网络规则 / 临时授权 分组，带“Revoke access”（A：`ActivePermission*`）。④ **连接器数据保留方式写成枚举**：不同步 / 同步历史 / 主动且持久 / 主动但临时（A：`ConnectorConsentSyncCategory`），每个手机数据源的文案都写明“可让 agent 删除，或在系统设置里断开以停止同步”（A）。⑤ **接管浏览器用租约**：同一时间只有一个控制方，租约有到期时间；有“另一个任务正在控制”的冲突提示；VNC 默认只看、可切换成输入（A：`BrowserControlLease{taskId,takeoverId,controlOwner,controlExpiresAtMs}`、vnc.html viewOnly）。⑥ **未知结果有专门文案**：“Paste may have reached the browser. Check before trying again.”（A）。⑦ **分享前申报内容**：分享 Space 时要申报是否含个人信息、是否含聊天记录（A：`SpaceShareDisclosure`）。⑧ 目标、子目标做成一级对象，和对话、任务、产物相互关联（A：Goal* / GoalAssociation）。 |
| **需要调整** | ① Muse 的记忆是 Markdown 自由文本加“让 agent 去忘记”，**删除是尽力而为**。官方明确说删除消息后 agent 可能仍记得（C，A 文案也这么写）。Muyon 要的是“撤权立即约束后续读取”，所以应该用**结构化条目 + 来源 + 用途标签 + 可验证删除**，不能照搬。② 写文件的接口里只有覆盖、追加、建父目录这些参数，**没看到版本或 etag 字段**（A-线索）。Muyon 的记忆编辑必须带版本比对（CAS），对应第一册单元 12。③ “始终允许 / 自动允许”这类长期授权，在 Muyon 要按对象和用途收窄，并且能在 S04 一处撤销。 |
| **不宜采用** | 依赖云 VM 的能力：后台持续执行、子代理群、Confidential VM、VNC 远程浏览器、社区设备配对后可“审批动作”。这些不适合 Muyon 本机离线优先的第一期。**手机数据 MCP 服务端**（libmcp_server_jni，把通讯录、短信、通知等暴露给云端 agent）也不宜采用：Muyon 的数据本来就在本机，没必要再开一条外发通道。 |
| **无法确认** | 服务端怎样把 SOUL、IDENTITY、MEMORY 注入模型；记忆由谁、何时写入（“Summarize into memory”只能说明有手动入口）；审批有没有绑定对象版本，`approval_id` 有没有幂等；撤销后对已缓存上下文的影响；“来源”是否覆盖记忆条目（只看到 “Sources / View sources” 文案）。 |

**关于 soul（研究问题的答案）**：**找到了直接证据（A）**。客户端代码引用 `SOUL.md`，并读取它的修改时间；身份页的文案分区有 **CREATURE / SOUL / VIBE**，空态写着“No identity configured yet.”；入门流程有“Agent personality / Customize your agent / Edit name / Regenerate name”。系统文件分区有 CONFIG / ACTIVITY / HEARTBEAT / MEMORY / SYSTEM / WORKSPACE。由此能确认三点：**可见的身份或人格设定存在，以文件形式保存，用户可以查看，至少身份文件可以编辑**。但这些文件的内容结构、服务端是否把 SOUL 当作行为约束，都**未知**。官方提到 agent 会“edits itself”（C，research.meta.ai 2026-09），这也只是佐证。

---

## 2. 样本身份与工具环境

| 项 | 值 | 等级 |
|---|---|---|
| 名称 / 包名 | Muse / com.facebook.aura | A |
| 版本 | 11.0.0.8.164，versionCode 1061601403 | A |
| SDK | minSdk 29，targetSdk 36，compileSdk 37 | A |
| ABI / split | 只有 arm64-v8a。`requiredSplitTypes` 为空，说明 base **可以单独安装**；可能还有可选的语言、密度 split，但都不是必需的 | A |
| 文件 | 42,279,886 B；SHA-256 `c7e788b5df855912dffbefc4c017f2e621b54aaeef954424f56339bd994fcefa` | A |
| 来源 | 用户提供的 Google Drive 文件夹（原文件名 base(1).apk），获取于 2026-10-13 16:32（北京时间） | — |
| 签名 | 证书 SHA-256 `a16bbe0247a738bc8f09fef50d890dc177ec875a83a121f877329b1b89667e99`；DN `CN=Meta Platforms Inc., OU=Meta Mobile, O=Meta Platforms Inc., L=Menlo Park, ST=California, C=US` | A |
| 是否 Meta 签名 | **可信**：与 APKMirror 上 Muse from Meta 的公开签名摘要完全一致（第三方参考数据，2026-09），DN 也是 Meta | A + C |
| UI 框架 | **Jetpack Compose**（大量 `*ScreenKt` 类，有 androidx.compose）；服务端驱动的 **Bloks** 模板（assets/json/bloks_*）；WebView 用于 noVNC 的 VM 浏览器、HTML Spaces、docx/pptx/表格查看器。**没看到 React Native、Hermes、Litho**（A：dex 包前缀里找不到） | A |
| 原生库 | agentic runtime、MCP SDK（2025-06-18 移动版）、MobileMCPRegistry、mcp_server_jni、vesta（Confidential VM 客户端）、tigon（网络） | A |
| 字体 | Optimistic 系列（Regular、Medium、Bold、可变字重）、optimistic_ai_vf、Roboto Mono、Caveat | A |
| 工具 | jadx 1.5.3（有 138 个方法反编译失败，不影响本次结论）、aapt、apksigner 0.9、gdown | — |

**同一文件夹里的其他文件（已核验，按要求未分析）**

| 文件 | 包名 / 版本 | 签名 | split 情况 |
|---|---|---|---|
| base(3).apk | com.anthropic.claude 1.261009.20（26100920），minSdk 32，targetSdk 37 | 证书 SHA-256 `305a1e8a…64a0`，DN `CN=Android, O=Google Inc.`（很像 Google Play 应用签名生成的密钥） | **缺必需的 split**：`requiredSplitTypes=base__abi,base__density`，包里没有 lib/，**单独装不上** |
| base(4).apk | com.openai.chatgpt 1.2026.272（2627220），minSdk 32，targetSdk 37 | `b24f4bfb…473c`，同样是 Google Inc. 形式的 DN | 同上，缺 abi 和 density split |
| base(2).apk | WorkBuddy 2.6.1 | 和已有样本 SHA-256 相同 | 重复，已删除 |
| base.apk | ai.x.grok.bot 1.14.1 | Google Inc. 形式的 DN | 不在研究范围内，挪到 /workspace/android-ref/_extra/，没分析 |

Claude 和 ChatGPT 的证书还**没有找到公开参照**，归属待核。

---

## 3. 页面地图与关键流程（轻量）

```
导航（A：BuiltInItemType EXPLORE/GOALS/LIBRARY/SETTINGS + 对话主页；deeplink 路由键）
├─ 对话 chat/thread：消息、审批卡（“Review the approval request in chat”）、浏览器任务卡、来源 Sources
├─ 状态（点头像进入，C 加 A：HatchStatusScreen）
│   ├─ 活动 Activity：按天的时间线、动作和权限记录、任务详情
│   ├─ 即将执行 Upcoming：定时任务、提醒（TaskCategory DAILY/WEEKLY/…）
│   ├─ 身份 Identity：CREATURE / SOUL / VIBE，可编辑，保存前要预览确认
│   ├─ 记忆 Memory：MEMORY.md 的查看、编辑、预览确认、保存或放弃
│   └─ 系统文件：CONFIG / ACTIVITY / HEARTBEAT / MEMORY / SYSTEM / WORKSPACE
├─ 目标 Goals：目标和子目标、完成记录、和产物关联（先在对话里澄清目标）
├─ 资料库 Library：产物（置顶、最近、分享）、文件
├─ 探索 Explore 和 Spaces（HTML 小应用、发布和分享时要申报内容）
├─ 电脑和浏览器：AgentComputerScreen（看画面、接管、停止、剪贴板）
└─ 设置：连接器、设备权限、生效中权限、审批历史、Confidential VM 的 PIN 和恢复、订阅
```

**流程 1：查看并纠正记忆**
资源：`MemoryViewModel`、`MemoryDataSource(MEMORY.md)`，文案 “Open memory file? / Add memory / Summarize into memory”。
结构（示意）：Markdown 全文 → 点编辑 → 改正文 → 弹出预览确认 → 保存，或放弃修改。
Muyon 对应：建议新增 **S0x“记忆与偏好”**。**修正**：改成结构化条目，每条带来源、用途、最后使用时间；“编辑”提交时带版本号（CAS）；删除后要立即从检索索引里剔除，并留下回执。

**流程 2：审批一次外部动作**
资源：`ApprovalSnapshotRecordJson`、`ApprovalRecordDecision`，文案 “Allow once / Allow always / This action wasn't recognized…”。
结构：对话内审批卡加通知（前台或后台提醒）→ 选择档位 → 进审批历史。
Muyon 对应：**T03 动作审批详情**。**支持**档位化（一次 / 本会话 / 今天）；**修正**：“始终允许”要限定到具体对象、用途和连接器，并且审批卡必须由宿主根据 `{approval_id, 对象, 版本}` 渲染；**补充**：允许“始终拒绝”，以及“未识别的动作要高亮提醒”。

**流程 3：查看和撤销生效中的权限**
资源：`ActivePermissionsScreen`、`ActivePermissionLifetime/Kind/ScopeType`，文案 “Revoke access”。
Muyon 对应：**S04 权限与数据使用记录**。**支持并补充**：按有效期、类型、范围分组；撤销后立即作用于后续读取和动作（这是 Muyon 必须保留的语义；Muse 撤销后服务端怎么处理**未知**）。

**流程 4：接管 agent 的浏览器**
资源：`BrowserControlLease`、`BrowserControlConflictDialog`、vnc.html 的 viewOnly / isInputEnabled。
Muyon 对应：第一期没有远程浏览器。这里借鉴的是**接管与冲突的语义**，可以用到 T02“执行中动作的人工接管”：单一控制方、租约到期、冲突时明确提示。

**视觉（轻量，A）**：品牌字体是 Optimistic 可变字重，代码块用 Roboto Mono，手写风格用 Caveat；Compose 加 341 个颜色资源。具体字号刻度**未提取**（主题在混淆代码里），所以只给原则：品牌字体只用于标题，正文用系统字体（Muyon 中文环境）。

---

## 4. 机制证据表

| # | 主张 | 等级 | 位置 | 局限 |
|---|---|---|---|---|
| M1 | 记忆以 MEMORY.md 形式存在，客户端能读写 | A + C | status/repo/MemoryDataSource(+Kt) MEMORY_FILE_PATH；C：Meta 帮助中心“How Muse handles your privacy…”（2026-09） | 写入时机和格式未知 |
| M2 | 身份、人格文件 SOUL.md、IDENTITY.md，可以编辑 | A | status/viewmodel/IdentityViewModel(+Kt)；文案 SOUL / VIBE / CREATURE | 内容结构和模型如何使用未知 |
| M3 | 文件操作走网关，作用在 VM 工作区 | A | gateway/HatchFileOperations：stat/read/readFileFromVm/write/delete | 没有版本字段（线索） |
| M4 | 审批有 8 种决定档位、来源分服务端或本地 HITL、前台或后台提醒 | A | gateway/ApprovalRecordDecision/Origin/AttentionMode | 看不到服务端执行过程 |
| M5 | 审批快照里有待批和近期记录、exclusive、scope | A | ApprovalSnapshot*Json | 不能证明绑定了对象版本 |
| M6 | 生效中权限分有效期、类型、范围，可以撤销 | A | agentpermission/pastapprovals/* | 撤销后的服务端行为未知 |
| M7 | 连接器数据同步分 4 类 | A | connectorconsent/ConnectorConsentSyncCategory | 各类保留期限未知 |
| M8 | 手机数据由本地 MCP 服务端提供给 agent（通讯录、短信、通知、通话、日历、健康、位置、照片） | A + A-线索 | libmcp_server_jni.so；LocalConnectorConsentType；工具描述文案 | 调用链没跟踪 |
| M9 | 浏览器接管靠租约 | A | browsertask/BrowserControlLease；vmbrowser/* | — |
| M10 | VNC 默认只看，需要时可切换成输入 | A | assets/vmvnc/vnc.html | — |
| M11 | 剪贴板粘贴有回执，并有“可能已到达，请核对”的未知态文案 | A | vmbrowser/BrowserClipboardPasteReceiptJson；文案 | — |
| M12 | 后台执行要用户明确开启 | A + C | 文案 “Run in background? … until you turn it off” | 背后是云 VM |
| M13 | Confidential VM（PIN、托管、远程证明） | A + C | confidentialvm/*；C：research.meta.ai 2026-09，官方称“later this year” | 本版是否默认启用未知 |
| M14 | 删除消息后 agent 可能仍记得；有“forget”技能 | A + C | 文案；C：帮助中心 | 遗忘是尽力而为 |
| M15 | 分享前申报是否含个人信息或聊天记录 | A | HatchFileOperations.shareSpace → SpaceShareDisclosure | — |
| M16 | 目标、子目标和产物关联 | A | library/Goal*、GoalAssociation | — |
| M17 | 子代理任务可见 | A-线索 | 文案 “Subagent tasks”；HatchSubAgentUiModel | 调度方式未知 |
| M18 | 审批检查在模型之外执行（Sentinel） | C | Meta 帮助中心；WIRED 2026-09 | 客户端看不到 |

**六类信息的区分（问题清单要求）**

| 类别 | Muse 的证据 | 用户能否纠正、撤销、限制 |
|---|---|---|
| 用户显式设置 | agent 名字、人格、头像、语音（入门流程，A）；feed 指令可编辑（“Edit feed instructions”，A） | 可以编辑（A） |
| 系统推断 | “Your Muse learns over time which decisions need your sign-off”（C）；AUTO_ALLOW（A） | 可以在审批管理里改（A 加 C） |
| 会话摘要 | “Summarize into memory”（A-线索） | 进 MEMORY.md 后可编辑（A） |
| 长期记忆 | MEMORY.md（A 加 C） | 可编辑，可以让 agent 忘记；删除是尽力而为（C） |
| 检索材料 | 连接器数据，分 4 种同步方式（A）；“Sources”（A-线索） | 可以断开、要求删除（A 文案） |
| 任务状态 | 活动时间线、即将执行、浏览器任务、子代理（A） | 可以停止任务、释放控制（A） |

---

## 5. Muyon 映射

| Muse 机制 | Muyon 页面 / 模块 | 落在哪一层 | 支持 / 修正 / 补充 | 合同和测试 |
|---|---|---|---|---|
| 记忆文件可视可改 | 新增 S0x 记忆与偏好（建议放在 S04 旁边）；第一册单元 15（知识索引）、11（scope、撤销） | Rust 存储加双端页面 | **补充**；**修正**为结构化条目、CAS 编辑、带来源 | 编辑冲突测试；删除后检索不再命中；导出包含记忆 |
| 身份和人格（SOUL / IDENTITY） | 设置 → 助手身份（第二册暂无） | Rust 配置加 UI | **补充**，可选 | 人格设定**不能**覆盖授权规则（测试：人格里写“自动付款”不生效） |
| 审批档位 | T03、第一册单元 11、12 | Rust 授权引擎；双端渲染宿主组件 | **支持**；**修正**：始终允许必须限定对象和用途 | 版本变化后旧审批失效；连点只执行一次；超时转 DENIED |
| 生效中权限和撤销 | S04 | Rust（单元 11 实时撤销） | **支持** | 撤销后下一次读取立即被拒；缓存投影被清除 |
| 连接器同步分类 | S03 连接器详情 | Rust 加平台适配层 | **补充**：把“不同步 / 仅历史 / 持续”作为用户选项 | 改成不同步后不再拉取，已有数据按选择保留或删除 |
| 未知结果文案 | 全局错误恢复 | Rust 回执合同（单元 12） | **支持** | 未知态先核对 |
| 接管租约 | T02 | Rust 执行器 | **补充**（本机多执行器时） | 两处同时接管 → 冲突提示 |
| 分享前申报 | 导出、分享（单元 19） | Rust 导出冻结 | **补充**：自动检测是否含商敏、个人信息、聊天记录并要求确认 | 含商敏时必须裁剪后再预览 |
| 目标和子目标 | W01 工作台 / R08 科研写作大纲 | Rust 对象模型 | **补充**（以后可选） | — |
| 后台执行、云 VM | — | — | **不采用**（第一期） | — |

### 5.1 新增页面规格（用户已于 2026-10-13 批准纳入 Muyon 页面提案；编号暂定，待并入第二册）

#### S06 记忆与偏好
- **定位**：查看、纠正、限制和删除助手长期使用的信息。灵感来自 Muse 的 MEMORY.md 页，但改为结构化条目，不是一份可以随意编辑的自由文本
- **入口**：设置 → 记忆与偏好；对话中“已记住”提示的链接；A03 范围面板的“使用了哪些记忆”
- **手机布局（Compose）**：顶部是搜索和筛选（类型：我告诉过的 / 系统推断的 / 会话摘要；用途；项目）；列表按类型分组，每条显示一行正文、来源图标、用途标签、上次使用时间；点开进入详情（底部弹层），有全文、来源链接（回到原消息或文档）、用途开关、版本历史，以及“编辑 / 停用 / 删除”
- **桌面布局（Electron）**：左边列表，右边详情；批量选择后可以停用或删除
- **状态**：正常；空态（“还没有记忆，可以手动添加或在对话里告诉我”）；加载失败（可重试，本机数据仍可用）；离线（完全可用，记忆在本机）；编辑中（有未保存提示）；冲突（版本不一致时提示合并或覆盖）；已停用（灰显，不参与检索）；已删除（留回执，可在撤销期内恢复）
- **合同（Rust 内核）**：`MemoryItem{id, kind: explicit|inferred|summary, text, source_refs[], purposes[], project_scope, version, created_by, last_used_at, status}`；`update(id, expected_version, patch)` 按版本比对写入，版本不对就返回冲突；`set_purposes(id, purposes)`；`disable / delete(id)` 返回回执，并**同步**从检索索引和缓存投影里剔除；`list_usage(id)` 列出使用记录
- **按用途裁剪**：用途包括 科研、询价、写作、通用；商敏条目默认只用于所属项目，模型请求只带当前用途允许的条目（第一册单元 11、14）
- **验收**：
  - 正常：对话中说“记住 X”后出现一条显式条目，来源指向那条消息
  - 撤权：关闭某条的“询价”用途后，下一次询价请求的上下文里**不再包含**它（检查外发账本）
  - 版本绑定：桌面和手机同时编辑同一条，后保存的一方收到冲突提示，不会静默覆盖
  - 重复点击：连点删除只生成一张回执
  - 旧结果：已删除条目在历史回答里显示为“来源已删除”
  - 恢复：重开后保留未保存的编辑草稿
  - 离线、错误、取消：取消编辑恢复原文；所有操作都不依赖网络

#### S07 助手身份
- **定位**：设置助手的名字、头像、语气、回答风格。借鉴 Muse 的 SOUL / IDENTITY / VIBE，但**只影响表达，不影响授权和执行**
- **布局**：预览卡（头像、名字、一句示例回复）；字段包括名字、语气（简洁 / 详细 / 正式 / 随和）、回答语言、格式偏好（是否多用表格、标题层级）；还有“恢复默认”
- **状态**：默认（还没设置）；编辑中；保存前预览；保存失败（保留草稿）；离线可用
- **合同**：`AssistantPersona{version, name, tone, style_flags, updated_at}`，`update(expected_version, patch)`；内核在拼提示词时把它放在**授权规则之后、不能覆盖授权规则**的位置；人格字段经过白名单过滤，任何“自动执行、跳过确认”之类的指令一律无效
- **验收**：在人格里写“付款不用问我”，付款仍然弹出宿主审批（必测）；修改后的新会话立即生效，旧会话标出“人格版本 vN”；两端并发修改时提示冲突；恢复默认会生成回执

---

## 6. 建议与验收

1. **记忆与偏好页（双端）**：按分区列出“我告诉过的 / 系统推断的 / 摘要来的”条目，每条显示来源、用途、上次使用时间；支持编辑、删除、“不再用于某用途”。
2. **助手身份**：可选的名字、语气，只影响表达，不进入授权判断。
3. **审批卡**：档位为 一次 / 本会话 / 今天 / 限定对象长期；附“始终拒绝”；未识别的动作高亮提醒。
4. **权限中心（S04）**：生效中权限分组展示，一键撤销并显示撤销回执。
5. **连接器同步选择（S03）**。
6. **分享和导出前的内容申报**。

| 验收场景 | 期望 |
|---|---|
| 正常 | 新记忆有来源，能在记忆页找到 |
| 空态 | “还没有记忆，你可以手动添加” |
| 错误 | 保存失败时保留编辑内容并可重试 |
| 离线 | 本机记忆照常可读可改，不依赖网络 |
| 取消 | 放弃编辑恢复原文 |
| 撤权 | 撤掉“用于某用途”后，该用途的检索立即不再返回这条 |
| 旧结果 | 两端同时编辑时，后提交的一方提示冲突 |
| 重复点击 | 保存和审批幂等 |
| 恢复 | 重开后，未保存的编辑提示恢复或放弃 |

必须保留的语义：人格、记忆和模型生成的内容**都不能**代替宿主授权；记忆条目也要按用途裁剪。

---

## 7. 失败记录、未覆盖项与下一步

- Drive 第一次访问返回 401，用户改成公开分享后，第二次下载成功
- jadx 有 138 个方法反编译失败（如 `IdentityViewModel.fetchFileDatesInternal`），用字段和方法名补位
- 没有运行、没有截图；没有看服务端；记忆文件的真实内容没见过（也不应该去读真实用户数据）
- Claude 和 ChatGPT 的样本**缺少必需的 abi 和 density split**，证书也没有公开参照。静态 dex 分析能做，但运行不了

**需要用户决定**
1. Claude 和 ChatGPT：是否接受“只有 base、缺 split”的样本，只做静态 dex 和资源分析；或者补传完整的 split 集合（.apks / .xapk，或 split_config.arm64_v8a.apk 加密度 split）
2. Claude 和 ChatGPT 的证书归属：是否接受“Google Play 应用签名形式的 DN、与包名一致”作为中等可信
3. ~~是否新增两页~~：用户已批准，见 5.1（S06、S07）
