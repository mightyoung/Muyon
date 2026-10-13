# ANDROID-REFERENCE-01 · Claude Android（com.anthropic.claude 1.261009.20）静态分析报告

> 分析日期：2026-10-13（Asia/Shanghai）｜范围：仅 base APK 静态分析（用户已接受：缺 base__abi / base__density split，证书中等可信）｜不含动态观察、不含登录、不含网络抓包。
> 证据分级：**A**=本APK内可直接复核的文本/代码/资源；**B**=多处A证据组合推断；**C**=官方文档（标注URL与访问日期）；**D**=混淆名或孤立线索（只作线索，不作结论）。客户端字段≠服务端行为。

## 一、一页结论

1. **UI框架**：Jetpack Compose（含 Compose Multiplatform `composeResources/claude.theme.generated.resources` 字体资源），桌面小部件用 Glance；长回答Markdown原生渲染（代码高亮用 assets/peghl + highlight.min.js / token-highlight.js，数学用 LaTeX 渲染器，存在 `LatexRenderFailure`）。A。
2. **App ≠ Claude Code**：App内大量“Approve Plan / Allow for this session / Skip all approvals / Subagents / Background agent stopped / claude rc”文本属于**移动端对 Claude Code 远程会话（Remote Control / 云端 Code session）的遥控界面**，不是 App 聊天自身的权限模型。App聊天自身的工具确认是“Claude asks before using new tools or opening new sites / Approve / Deny tool call / Change tool permission”（连接器级）。A+C。**不得把Claude Code subagent/permissionMode规则套到App聊天。**
3. **防重复执行（最值得借鉴）**：本地Room表 `executed_client_tools(account_id, conversation_id, tool_use_id, executed_at)`，主键三元组 + `INSERT OR IGNORE` —— 客户端工具调用以 tool_use_id 幂等落账。A（结构）/ B（用途推断：防重放）。
4. **会话快照缓存**：`snapshot_headers`（leaf_message_id、facts BLOB、project_id）+ `snapshot_messages`（parent_message_id、fingerprint、complete_blocks）——树状消息（支持分支/版本“Version %1$s of %2$s”）+ 指纹增量校验 + “完整块数”支持流式中断后续传。A结构/B用途。
5. **记忆**：存在“记忆文件/记忆摘要/暂停/重置（含项目记忆）/无痕不入记忆/经典vs新版记忆/从聊天生成记忆/‘Updated memory, removed …’回执”。A（文本）；服务端如何生成与24h合成为C。
6. **压缩**：“Compacted conversation · saved %1$s tokens”“Conversation compaction failed”“%1$d%% of context window used”“Context cleared”，代码中有 `CompactionCleared`、`compaction_status`。A；API compaction 机制为C。
7. **Artifacts 与可视化分三类**（见四.3）：原生图表（Bar/Line/Scatter，原生Compose，静态展示+复制/分享）；WebView Artifact（JS开、文件/内容访问关、禁多窗口；来源白名单 claude.ai + www.claudeusercontent.com）；AI-powered / 可评论 Artifact 与 MCP Apps（`_claude_bridge` / `mcpAppBridge` JS桥 postMessage）——后者存在**副作用**（“可带你的姓名发评论给Claude且不先询问”被明确提示）。A。
8. **分享边界**：用了连接器、Claude Code 或高级Research的聊天不能分享；发布Artifact会公开且可能被搜索引擎收录（聊天仍私密）。A。这是“按用途裁剪敏感信息”的直接先例。

## 二、样本与工具清单
| 项 | 值 |
|---|---|
| 包名/版本 | com.anthropic.claude / 1.261009.20（versionCode 26100920），minSdk 32，targetSdk 37 |
| 文件 | sample/claude-base.apk，39,518,046 B |
| SHA-256 | 9807d321245e3a2ac2736e8c2e1b9215147ff566cea55431189e643d5786122a |
| 签名证书 SHA-256 | 305a1e8a432e5ec0c612b2465359c3b88e3c95d6253599ac6088562b818b64a0（CN=Android, O=Google Inc.——Play App Signing 典型形态；**中等可信，用户已接受**） |
| Split | requiredSplitTypes=base__abi,base__density 缺失；无 lib/（无原生库可析），不影响 dex/资源静态分析 |
| 工具 | jadx 1.5.3（23311类，162个反编译错误，已记录），aapt（资源字符串，默认locale 5283条），apksigner 0.9，ripgrep，REA 6.4.0（环境可用，本次以jadx直读为主），pandoc |
| 未做 | 动态运行、登录、抓包、split合并安装 |

## 三、页面地图 / 流程 / 视觉样例（基于字符串与包结构，A/B）
- 顶层包：chat、chatlist、conversation、project、artifact、artifactapp、connector、mcpapps、code、sessions、agentchat、settings、widget、shortcut、notification、stt/audio（语音）、usage/pro（订阅）、markdown、webview、deeplink。
- 主要页面：聊天列表（Search threads）→ 聊天页（模型选择底表、工具调用折叠“Tool calls (%1$d)/Used ^1 tools”、Thinking 状态、引用 Sources）→ Artifact 全屏（ArtifactFullScreen，Show in artifact / Open artifact）→ Artifacts 画廊（Search artifacts、My Artifact、发布/组织内分享/加到主屏 ArtifactAppActivity + PinnedReceiver）。
- 项目：项目文件/上下文、项目记忆；设置>记忆（Generate memory from chats、Pause、Reset、Manage summary）。
- Code 区：Remote Control（“Reconnecting to your computer…”、“Open the project … run claude rc”）、云会话、环境、分支/PR搜索、权限通知（layout `notification_ccr_permission_expanded`：从通知栏审批Code工具请求）。
- 视觉：字体体系 Anthropic Serif（正文/标题）+ Anthropic Sans（UI）+ Noto Serif（多语回退）+ JetBrains Mono（代码），“Code font / Transcript font / Transcript text size / Font style”可设置。
- 流程样例（Research）：触发→“plan created”→进行中（可取消“Research cancelling…”）→完成通知/中断/超时→结果含来源；高级Research聊天不可分享。

## 四、机制证据表
### 4.1 核心表
| # | 机制 | 证据 | 级 | 说明/边界 |
|---|---|---|---|---|
| E1 | 工具执行幂等 | snippets/01、02：executed_client_tools 主键+INSERT OR IGNORE | A/B | 仅证明客户端去重；服务端是否去重未知 |
| E2 | 消息树+快照 | snippets/01：snapshot_*，parent_message_id、fingerprint、complete_blocks | A/B | 版本/分支、增量同步、断流续显 |
| E3 | 离线/重连语义 | snippets/10：“Your message will send when you reconnect”“The rest of Claude’s reply will appear when you reconnect”“Reconnecting… Claude is still responding in the background”“Can’t retry while reconnecting. The session is unchanged.” | A | 未知结果先核对：重连中禁重试 |
| E4 | 记忆 | snippets/05 | A | 新旧记忆、暂停、重置、无痕排除、项目隔离 |
| E5 | 压缩 | snippets/06 + `CompactionCleared` | A | 用户可见“节省token”回执与失败态 |
| E6 | 工具/连接器授权 | snippets/08：Approve/Deny tool call、Change tool permission、Set all tools、“Claude will work and use your connectors without pausing for approval. This can put your data at risk.” | A | 连接器级 always/ask/never 风格；移除连接器后“Claude can no longer use it or its tools”=撤权立即约束 |
| E7 | Code远程权限 | Allow for this session、Skip all approvals、“This request can't be approved from your phone”、Auto mode默认 | A + C(code.claude.com/docs/en/permission-modes, remote-control，访问2026-10-13) | 仅属Claude Code；手机端不能选Bypass（C） |
| E8 | Artifact WebView | snippets/03、04 | A | JS开，file/content访问关，禁多窗口；来源白名单 |
| E9 | JS桥 | `_claude_bridge`、`mcpAppBridge`（@JavascriptInterface postMessage） | A | 消息协议细节为混淆代码，D线索 |
| E10 | 分享裁剪 | snippets/11 | A | 连接器/Code/高级Research聊天禁分享 |
| E11 | Research | snippets/09 | A | 取消/中断/超时三态+完成通知 |
| E12 | 长回答渲染 | assets peghl/highlight.js、LatexRenderFailure、Copy/Collapse、“%d branches” | A | 表格渲染细节未逐一核对（D） |

### 4.2 记忆 / 项目 / 压缩 / 子代理（分层）
- **App**（A）：记忆文件、摘要、暂停、重置、无痕；项目内记忆独立；压缩回执与上下文占比。
- **Web/帮助中心**（C，support.claude.com 文章 11817273、9519177，访问2026-10-13）：项目各自独立记忆与摘要；非项目记忆每24h合成；单聊可在首条消息前关闭记忆；Reset不可撤销。
- **API/SDK**（C，docs.anthropic.com/en/build-with-claude/compaction）：server-side compaction `compact_20260112`，触发阈值≥50K tokens，compaction块之前内容被丢弃。
- **Claude Code**（C，code.claude.com/docs/en/memory、sub-agents）：CLAUDE.md/MEMORY.md、子代理不继承主会话auto memory、permissionMode 继承规则。**仅适用于Code，不适用于App聊天。**

### 4.3 Artifacts / 可视化分类
| 类型 | 证据 | 分类 | 权限边界 |
|---|---|---|---|
| 原生图表 Bar/Line/Scatter | “Display chart / Failed to display chart / Chart debug info” | 静态展示（原生） | 仅复制/分享 |
| 普通 Artifact（文档/代码/HTML） | ArtifactFullScreen、WebView设置 | 客户端交互 | 沙箱源 claudeusercontent；无文件访问 |
| AI-powered Artifact | “Create apps … that use Claude inside the artifact”“Enable artifacts to use AI-powered artifacts” | 客户端交互+消耗模型调用 | 需开启能力；用户额度 |
| 可评论 Artifact | “can add comments with your name attached and send them to Claude without asking you first”“Artifact comment sent to Claude” | **工具副作用** | 先告知风险；发送后回执 |
| MCP Apps | mcpapps包：DomainValidationException、ModelContextTooLargeException、HandoffReadLimitExceeded | 工具副作用（外部服务） | 域名校验、上下文上限、读取限额 |
| 发布/主屏 | Publish Artifact、组织链接、仅本人Artifact可加主屏 | 外部可见副作用 | 明示公开范围；不可用/已删除时拒绝 |

## 五、Muyon 映射（book1 模块/链路 · book2 页面）
| Claude机制 | Muyon落点 | 动作 |
|---|---|---|
| executed_client_tools 幂等 | book1 执行/回执模块，链路C3（执行）C4（回执）；Rust core 本地账本 | 每个动作带 action_id，本地 `INSERT OR IGNORE` 账本；重复点击只返回已有回执 |
| snapshot 树+fingerprint+complete_blocks | book1 会话存储/同步；R系列会话页 R01–R08 | 消息树 + 版本切换（“第x/共y版”），断流按完整块续显 |
| 重连中禁重试 | Q01–Q06 确认/核对页；链路C5（未知结果核对） | “结果未知→先查询状态→再允许重试” |
| 记忆暂停/重置/无痕/项目隔离 | S06 记忆与偏好（已在Muse报告定义） | 增补“暂停”与“单次会话不入记忆”开关、项目范围隔离 |
| 连接器级 ask/allow/never；移除即失效 | S01–S05 授权设置；T01–T03 工具；链路C2（授权） | 宿主确定性授权；撤权即刻阻断后续读取/动作 |
| 分享裁剪（用连接器的会话禁分享） | D01 导出/分享；S 系列隐私 | 按用途裁剪：含商业敏感来源的会话导出需剔除或禁用 |
| Artifact 沙箱源 + 副作用提示 | W01 工作区/产物；F05–F08 线框 | 产物三分类显示徽标；副作用类必须确认绑定对象+版本 |
| 压缩回执 | R系列会话页 | 显示“已压缩·节省N token”+失败态+占比 |
| 字体体系/代码字体可调 | A01–A03 外观 | 正文serif/UI sans/代码mono，三项独立可调 |
| S07 助手身份 | — | Claude无独立“人格”页（仅风格/指令类线索，D）；S07按Muse报告规格保持：身份不得覆盖授权 |

## 六、建议与验收（九态）
以“执行动作（工具/产物副作用）”为主线：
| 状态 | 验收标准 |
|---|---|
| 正常 | 确认卡显示对象+版本+范围；执行后回执含action_id、时间、结果 |
| 空态 | 无记忆/无产物/无连接器时给出说明与入口（参照“No memory files yet…”） |
| 错误 | 失败可读原因+可重试；压缩失败/图表失败有独立文案 |
| 离线 | 消息排队“重连后发送”；进行中回复标注“后台继续” |
| 取消 | Research/动作支持取消中→已取消两段态；已执行部分出回执 |
| 撤权 | 移除连接器/关记忆后，下一次读取即被拒；排队动作作废并告知 |
| 旧结果 | 版本切换显示“第x/共y版”；对旧版本的确认失效需重确认 |
| 重复点击 | action_id 本地幂等账本，二次点击返回同一回执，不重复执行 |
| 恢复 | 重启后按快照+完整块续显；结果未知的动作先核对状态再允许重试 |

## 七、失败记录 / 未覆盖 / 下一步
- jadx 162 处反编译错误；大量 defpackage 混淆类（JS桥消息协议、Markdown表格/标题实现细节只到D线索）。
- 缺 abi/density split：无 native 库、无高密度资源，视觉样例仅为字符串/资源推断，无截图。
- 未动态验证：服务端是否二次去重、记忆生成时机、Research 实际流程。
- 下一步（待批）：ChatGPT 1.2026.272 同规范分析。
