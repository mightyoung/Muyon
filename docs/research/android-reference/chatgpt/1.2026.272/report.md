# ANDROID-REFERENCE-01 · ChatGPT Android（com.openai.chatgpt 1.2026.272）静态分析报告

> 分析日期：2026-10-13（Asia/Shanghai）｜范围：仅 base APK 静态分析（用户已接受：缺 base__abi / base__density split，证书中等可信）｜无动态观察、无登录、无抓包。
> 分级：**A**=APK内可直接复核；**B**=多处A组合推断；**C**=官方文档（URL+访问日期 2026-10-13）；**D**=混淆名/孤立线索。客户端字段≠服务端行为。查不到的写“未知”。

## 一、一页结论
1. **UI框架（A）**：三层混合——① Jetpack Compose / Kotlin Multiplatform（composeResources：`com.openai.kmp.platform.design / charts / rich.text.editor`）；② **Valdi** 运行时（assets 下 80+ 个 `*.valdimodule`，zstd 压缩的 TS/JS 模块，`__ValdiNativeBridge`，含 valdi_tsx/valdi_navigation/valdi_webview）——大量业务页（记忆设置、个性化、金融、钱包、地图、全局搜索、协作编辑器）用它下发；③ WebView（latex.html、mapbox.html、Apps 小组件桥 `SkybridgeNative`）。
2. **工具状态四元组（A）**：每个工具有“进行中/已完成/失败/动作名”四条文案，如 Creating reminder / Created reminder / Couldn’t create reminder / Create reminder；canvas、邮件、日历、agent（Spawning/Waiting for/Resuming/Closing agent）同构。是“可见工具状态”的直接先例。
3. **生成式UI = DIL（A，最重要）**：模型写 DIL JSON →客户端 `DILCompiler.validateV1Json` + `DILPropertiesSchema` 校验→支持 JSON Patch 流式增量→在**沙箱JS realm**（全局名白名单、冻结、app data/constants 必须是序列化JSON）渲染为原生组件。**模型写的DIL只能触发白名单宿主动作**：`log_event, copy, copy_node, issue_new_turn, open_url, open_entity_detail, open_image_lightbox, open_file_citation`；“non-consuming actions cannot fall back to privileged actions”；URL 规范化为可信 HTTPS，否则“untrusted URL in payload.url”。即：生成UI不能直接调工具，只能“发起新一轮”交回模型。
4. **外部工具驱动UI（A+C）**：Apps/MCP 小组件跑在 WebView，桥 `SkybridgeNative`，宿主方法含 callTool 链路（`tools/call`、`tools/list`）、sendFollowupMessage、setWidgetState、requestDisplayMode、requestModal、requestCheckout、openExternal、requestConnectSheet。C：developers.openai.com/apps-sdk（iframe + JSON-RPC postMessage，`_meta.ui.visibility` 控制工具是否可被UI调用）。
5. **设备控制三分（A/C，严格分开）**：
   - **云端浏览器/Agent**（远程环境）：“Cloud browser”“Open cloud browser”“Browser screenshot %1$d of %2$d”“Agent mode”、站点逐一授权、Cookie清理即时登出。接管（Take over）文案**本包默认字符串里未找到**→A=未知，C=help.openai.com 11752874/20001280（接管期间不截屏，交还后尝试续跑）。
   - **手机本机能力**：日历（CalendarContract，读写；错误码含 `outcome_unknown`）、提醒、位置、相机、麦克风；短信只发现 `SENDTO smsto:` 意图（交给系统短信App，用户发送），未见直接 SmsManager（反编译覆盖不全，D）。无障碍服务 `ConversationScreenAccessibilityService`：`canRetrieveWindowContent=true, canTakeScreenshot=true`，**未声明 canPerformGestures**，用途文案“Share Screen 时读取屏幕文字与控件”→只读屏幕上下文，**不能推出整机操控**。
   - **连接器调用**：Gmail/日历/Drive/Slack 等服务端工具（Reading emails、Sending draft…）；权限档位“Always approve / Approve / 自动批准低风险”。C：help.openai.com 20001495（Always ask / Allow read / Allow low-risk / Allow all）。
   - 另有**遥控桌面**（Codex Remote / 控制Mac或PC），需硬件级设备解锁保护（A）。
6. **未知结果先核对（A）**：“Couldn’t confirm this request. Check its status and try again.”“Reconnected. We couldn’t confirm whether Orbit continued.”“Confirming the reconnect result…”“App connected, but %1$s couldn’t confirm the update”；本机日历错误码 `outcome_unknown`。
7. **安全暂停与接续（A）**：“Auto-review did not approve some recent actions, so your dot was paused”“We paused %1$s out of precaution… proceed or delete”“By continuing, you confirm that you’ve carefully reviewed the findings…”——自动审查→暂停→人工复核后恢复。
8. **记忆/人格（A）**：临时聊天不用不建记忆、群聊不用个人记忆（可有共享记忆）、分享不带记忆和自定义指令、“Memory almost full / Saved memory full”、“Retry with memory”、“%1$s updated assistant personality”、Personality 设置。

## 二、样本与工具清单
| 项 | 值 |
|---|---|
| 包/版本 | com.openai.chatgpt 1.2026.272（见 manifest.json） |
| 文件 | sample/chatgpt-base.apk |
| SHA-256 / 证书 | 见 manifest.json（47d8350a… / b24f4bfb…，中等可信，**用户已接受**） |
| Split | 缺 base__abi、base__density：无 native 库，图片资源不全 |
| 工具 | jadx 1.5.3（46455类，进程在约66%时退出，但已写出 49,421 个 .java，覆盖不全→“未找到”只能算未知），aapt（默认语言字符串 11,170 条），Python zstandard（本机解压 valdimodule，未上传），ripgrep，pandoc |
| 未做 | 动态运行、登录、抓包、Valdi 字节码逆向（只做字符串级） |

## 三、页面地图 / 流程 / 视觉样例
- 主体：聊天（模型/思考强度控制“Use this control to choose how much thinking…”）、项目、库（Library）、全局搜索、Canvas、GPTs、群聊（multiplayer）、Codex（任务运行/完成/需关注计数）、Pulse/定时任务（scheduled chat、automations）、设置（记忆、个性化、云端浏览器、连接器、数据控制）。
- 垂直模块（Valdi）：finance/wallet/wallet_approval、maps、health（olympic_*）、explore_feed、family。
- 工具调用流程（A文案+B）：动作名→“Creating…”进行中→“Created”回执 或 “Couldn’t…”失败→（需要时）批准卡“Approve / Always approve”→结果不确定时“Couldn’t confirm… Check its status”。
- 会话↔可视产物联动：Canvas 有 Create/Read/Update 三类工具状态（模型读写同一 canvas）；DIL 卡片 `open_file_citation / open_entity_detail` 回链对话来源；`issue_new_turn` 把卡片交互回写为新一轮对话；小组件 `sendFollowupMessage` / `setWidgetState`（C：更新模型可见上下文）。
- 视觉：设计系统 `ds_*` 图标（regular_24 等）、Material3；字体资源以 KMP design 资源为主（未逐一提取，D）。

## 四、机制证据表
| # | 机制 | 证据（evidence/snippets） | 级 |
|---|---|---|---|
| E1 | 三层UI框架 | 01 | A |
| E2 | 工具状态四元组 | 02 | A |
| E3 | DIL 宿主动作白名单 | 03 | A |
| E4 | DIL 沙箱（全局白名单、JSON序列化） | 04 | A |
| E5 | DIL 编译期 schema 校验 + JSON Patch | 05 | A |
| E6 | Apps 小组件桥 SkybridgeNative | 06 | A（方法名）/C（语义） |
| E7 | 无障碍只读屏幕上下文 | 07 | A |
| E8 | 本机日历/提醒 + outcome_unknown；短信仅意图 | 08 | A/D |
| E9 | 云端浏览器/Agent/Auto-review/Codex 权限 | 09 | A+C |
| E10 | 未知结果核对 | 10 | A |
| E11 | 记忆/人格/分享裁剪 | 11 | A |
| E12 | Canvas/小程序/自定义布局开关 | 12 | A |
| E13 | idempotencyKey/Token 字段（发布/分享类请求） | 13 | A字段/B用途；服务端行为未知 |

### 4.1 智能UI四分类：谁选呈现 / 谁供数据 / 谁校验交互 / 谁执行
| 类型 | 谁选择呈现 | 谁提供数据 | 谁校验交互 | 谁执行 |
|---|---|---|---|---|
| 静态结构化卡片（原生图表 kmp.charts、引用、地图、实体卡） | 模型/服务端选卡片类型（B）；客户端原生渲染（A） | 服务端检索/工具结果（B） | 客户端：仅复制/打开（A） | 客户端本地动作（A） |
| 交互组件（DIL widgets：DatePicker、Flow、FollowUpActionBar…） | 模型写 DIL（A：isModelWrittenDIL） | 模型+宿主注入 app data（A） | **客户端**：schema校验+宿主动作白名单+可信URL（A） | 宿主执行白名单动作；涉及工具的经 `issue_new_turn` 回模型（A/B） |
| 生成HTML/代码（Canvas、代码执行、DIL沙箱JS） | 模型（A/C） | 模型（A） | 沙箱隔离（A：DIL realm）；Canvas 预览沙箱细节未知 | 沙箱内运行；无宿主特权（B） |
| 外部工具驱动UI（Apps/MCP 小组件） | 第三方 MCP 服务端声明模板（C：_meta.ui.resourceUri） | 第三方服务端 structuredContent（C） | 宿主：工具可见性、批准卡、权限档（C）；客户端桥方法集（A） | 第三方服务端执行工具（C）；宿主仅转发（B） |

### 4.2 可见状态/预览/确认/取消/接管/重试/回执
| 环节 | 证据 | 级 |
|---|---|---|
| 可见状态 | 四元组文案；“Codex is working / needs your attention / finished” | A |
| 动作预览 | “Allow Codex to run this command? / change files?”；连接器批准卡（C 描述app+动作） | A/C |
| 确认 | Approve / Always approve；Auto-review低风险自动批准 | A |
| 取消/停止 | “Stopped: %1$s”；Cancel | A |
| 接管 | 云浏览器 Take over：A 未找到，C 有 | C |
| 重试 | Retry / Try again；“Retry with memory” | A |
| 回执 | “Created …”过去式状态；“Sent input to agent” | A（是否带对象ID/版本：未知） |

## 五、Muyon 映射
| ChatGPT机制 | book1/book2 | 建议 |
|---|---|---|
| 工具状态四元组 | T01–T03 工具页、R系列会话页；C3执行链 | 每个动作定义 4 条文案（进行中/成功回执/失败/动作名）为必填契约 |
| DIL 白名单宿主动作 | W01 产物、F05–F08 线框；book1 渲染/卡片模块 | **生成式卡片只能触发白名单动作**；任何带副作用动作必须转为“新一轮请求→宿主授权→确认” |
| DIL schema 校验 + JSON Patch | book1 卡片协议 | Rust core 定义卡片 schema，桌面/安卓两端共用校验 |
| Skybridge 小组件 | T 系列、连接器 | 外部UI经宿主桥；工具可见性默认仅模型，UI调用需显式声明 |
| outcome_unknown / Check its status | Q01–Q06；C5 核对链 | 结果未知独立状态，禁盲重试 |
| Auto-review 暂停→复核→恢复 | S01–S05 授权；Q 系列 | “安全暂停”状态与恢复确认页 |
| 无障碍只读 | S 隐私；book1 设备能力 | 若做屏幕上下文：只读、按次开启，与“操作手机”权限分开 |
| 本机能力 vs 云端 vs 连接器 | book1 执行位置模块 | 执行位置显式标签（本机/云端/第三方） |
| 记忆：临时聊天、群聊隔离、分享不带记忆、满额提示 | **S06 记忆与偏好** | 增补“临时会话”“记忆容量/满额”“分享时剔除记忆和指令” |
| Personality / custom instructions | **S07 助手身份** | 人格与指令分开存储；“已更新助手人格”回执；人格不影响授权（与Muse规格一致） |
| idempotencyKey 字段 | book1 执行/回执 | 佐证客户端生成幂等键的做法 |

## 六、建议与验收（九态，主线：卡片/工具动作）
| 状态 | 验收 |
|---|---|
| 正常 | 四元组状态完整；回执含 action_id、对象、版本 |
| 空态 | 无连接器/无记忆/无产物有说明与入口 |
| 错误 | “Couldn’t …”具体到动作；可重试 |
| 离线 | 未发出的动作排队并标注；已发出的进入“待核对” |
| 取消 | 显示“已停止：动作名”；已完成部分出回执 |
| 撤权 | 断开连接器/站点后续调用立即拒绝；排队动作作废 |
| 旧结果 | 卡片绑定版本；旧卡片按钮失效需重新生成 |
| 重复点击 | 同 action_id 只执行一次，返回原回执 |
| 恢复 | 重连后先“确认结果中…”，未知则提示查看状态 |

必须保留语义：宿主确定性授权（DIL白名单即宿主决定）；商业敏感信息按用途裁剪（分享不带记忆/指令）；确认绑定对象与版本；执行回执；防重复执行；未知结果先核对；撤权立即约束后续。

## 七、失败记录 / 未覆盖 / 下一步
- jadx 在 ~66% 退出（4.9万文件已写出），无障碍服务类、接管UI等未反编译出来→相关“未找到”按未知处理。
- Valdi 模块只做了字符串级分析，没还原控制流。
- SEND_SMS 权限的实际用途未知（只见到 smsto 意图）。
- Take over 文案不在默认字符串里，可能服务端下发或在 Valdi/WebView 中（D）。
- 无动态验证。

> **用户决定注记（2026-10-13 18:18）**：第五节中“屏幕上下文只读”与 S06“临时会话/记忆容量”两条建议已被用户否决（不做屏幕上下文读取；S06 不加临时会话、不设容量上限）；生成式卡片禁止直接副作用、本地幂等回执账本为强制项、授权四档（全部允许仅限个人账号）已确认。以 SUMMARY.md 为准。
