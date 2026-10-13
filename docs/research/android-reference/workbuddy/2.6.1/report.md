# WorkBuddy 安卓客户端解析报告（ANDROID-REFERENCE-01 · 第一份）

- 样本：com.tencent.workbuddy.app 2.6.1（versionCode 852），应用汇，2026-10-13 13:04（北京时间）获取
- 方法：只做静态分析（资源、清单、签名、Dart AOT 字符串、内置资产）；**第二轮（2026-10-13 13:25 后）用 blutter 恢复了 Dart 常量和枚举值名**。**没有安装运行，也没有真机截图**；本文没有 B 级证据
- 证据等级：**A** 指固定版本包内的直接证据；**A-线索** 指混淆后的字符串或接口路径，只能证明“包里有这个文案或标识”，不能证明调用点、触发条件或服务端实现；**C** 指官方或商店资料；**D** 指推断或待核假设
- 图片说明：`evidence/visual/` 里是从 APK 内置资源直接渲染的图（SVG 转 PNG，或原样拷贝的 PNG），**不是截图**；文中的布局图都是**示意**，尺寸均为**估计**

---

## 1. 一页结论

**关键事实（A）**：WorkBuddy 安卓端是 **Flutter** 应用，只有一个 MainActivity，键盘弹起时整窗缩放（adjustResize）。富内容预览（Mermaid、HTML）走 webview_flutter。也就是说，它和 Muyon 现在的 Flutter 技术栈是同一类。所以下面的借鉴只针对**页面组织和交互语义**，不能拿来证明“原生 Compose 一定更好”；同样也不能反过来说明应该放弃已定的 Compose 路线。是否调整路线由用户决定，本文不建议改。

| 类别 | 结论 |
|---|---|
| **值得借鉴** | ① 底部 5 个 Tab：任务、频道、发现、自动化、我的（A：tab-*-outline/filled 图标）。“任务”是首页一级对象，对话从属于任务。② 视觉以黑白灰为主，加少量青绿强调色（#00C29A、#13B2BF；A：SVG 色值统计）。明暗两套插图各自独立设计（A）。这与 Muyon 第二册“黑白灰 + 深青强调”的方向一致，**支持**现方案。③ 输入区很重：加号、附件、语音、模型选择、**权限模式盾牌**、发送和停止是同一个按钮位（A：input-* 图标、“权限模式”等文案线索）。④ 运行位置“本机电脑 / 云端”在新建任务时选，可以切换（A-线索：HomeRunLocationSheet、“新建任务可切回电脑”“切换云端”“云端不可恢复”）。⑤ 工具过程用步骤图标区分代码、调研、设计、网站、视频等类型（A：tool-process-wb-*）。⑥ 产物区可以调宽度，文件和代码产物分开，可“保存到本机”（A-线索）。⑦ 状态文案完整：排队、队列满、排队超时、重连中、设备离线、“暂时无法确认消息状态”、积分用尽暂停、用户停止（A-线索）。 |
| **需要调整** | ① 它的执行发生在云端或用户自己的电脑上，手机端主要是**遥控和查看**（C：官方称“补齐远程移动操控”；A-线索：电脑端未响应、请到电脑端授权）。Muyon 是本机离线优先，所以“切回电脑”要改成 Muyon 自己的“执行位置”语义（S02），不能照搬成跨设备能力。② 底部 5 个 Tab 里，频道和自动化是 IM 与企业场景。Muyon 第一期建议改成 助手 / 任务 / 资料（科研、询价）/ 我的 四个，自动化以后再加。③ 吉祥物动画（Rive 状态机）和 liquid glass 着色器不符合第二册“避免无意义持续动画”的要求，最多用在空态。 |
| **不宜采用** | 以“确认执行命令？”“确认按此计划执行？”为代表的**纯 UI 确认弹窗**。我们看不到它背后有没有宿主侧的对象和版本绑定，Muyon 不能把弹窗当授权。积分、会员、分享到朋友圈等运营组件也不采用。 |
| **无法确认** | 正文最大宽度、各页面实际用哪套字号（blutter 只恢复出常量表，取不到调用点）；任务和对话在服务端的关系；审批是否绑定版本；撤权后是否立刻限制读取。这些都要靠**实机观察（B）**或官方资料补。 |

**第二轮新增（blutter，A-线索）**：①字号以 12/13/14/16/17 为主，行高取整到像素（12→16、13→18、14→20/21/22、16→22/24、17→24、20→28、28→38），字重 400/500/600 三档；间距 4 的倍数，以 16、20 为主水平内边距。②流式滚动有 `streamingFollow / returnToBottom` 状态，即“跟随到底 / 用户上滑后出现回到底部”。③发送链路有**未知结果核对**状态建模：`provenNotSent / dispatchAmbiguous / acceptedAwaitingEcho`、`safeRetryRequired / reconcilePending`、`resubmitWithheld`，失败阶段含 `duplicateTerminal / traceMismatch / ledgerWriteFailed`；另有 `staleGeneration / superseded` 过期守卫和 `standard / fullAccess` 权限模式。这些和 Muyon“防重复执行、未知结果先核对、确认绑定版本”的语义高度对得上，可以**支持**第一册单元 12 的设计；但它们只是客户端枚举名，**不能证明** WorkBuddy 服务端真的这样实现。

**结论**：WorkBuddy 最值得学的是“**任务优先的信息架构、重输入区、执行位置显式化、完整的等待/离线/排队文案体系、黑白灰青绿配色**”。业务授权语义仍以 Muyon 第一、二册为准。

---

## 2. 样本身份与工具环境

| 项 | 值 | 等级 |
|---|---|---|
| 名称 / 包名 | WorkBuddy / com.tencent.workbuddy.app | A |
| 版本 | versionName 2.6.1，versionCode 852 | A |
| SDK | minSdk 24（Android 7.0），targetSdk 36，compileSdk 36 | A |
| ABI / 包形态 | 只有 arm64-v8a；单个完整 APK，不是 split，没有缺失的 split | A |
| 文件 | 293,687,392 B；SHA-256 `5ce904337ba2821fb1cdb7965075445746d198bc82d40b12d6842d24f1da34e3` | A |
| 来源 | 应用汇详情页 https://www.appchina.com/app/com.tencent.workbuddy.app → 官方下载链接 → CDN（对象名就是文件 MD5，二者一致） | C/A |
| 获取时间 | 2026-10-13 13:04（北京时间） | — |
| 签名 | 只有 v2 签名，校验通过；1 个签名者，RSA 3072；DN `CN=(Tencent), OU=(Tencent), O=(Tencent), L=(Shenzhen), ST=(GD), C=(CN)`；证书 SHA-256 `2b450095dd8ee48eb22387f3bcd349f485e2866b3f97e3d3925a152647b66f14`；生效时间 2026-04-01 | A |
| 是否腾讯签名 | **中等可信，用户已于 2026-10-13 确认接受此判断并继续使用本样本**。DN 是签名方自己填的；网上找不到这张证书的公开官方参照。它和微信的证书（0FE4FF85…3C7C）不同，但腾讯各产品本来就分开签名，这一点不能用来否定。正面证据：两家商店都署名腾讯；包内有大量腾讯内部 SDK（qimei、turing、bugly、beacon、rmonitor、mars xlog、TIM IM、itlogin 内网登录、QQ 互联、企业微信 SDK）；官方说移动端 2026-07 发布，证书 2026-04 生成，时间对得上 | A + C + D |
| 加固 | 没看到商业加固壳；Dart 是 release 混淆构建；资源名做了混淆 | A |
| 框架 | Flutter（libflutter.so、libapp.so，Dart snapshot hash 78da37fe…）；webview_flutter；Rive；KaTeX（flutter_math_fork）；mermaid.min.js；包内附带的技术评估文档写的是 Flutter 3.41.5 + go_router 17（StatefulShellRoute）+ get_it + flutter_quill | A（文档只能证明当时做过评估，不能证明最终全都采用） |
| 工具 | blutter（github.com/worawit/blutter，commit 4a60ac64，2026-08-18；按 Dart 3.11.3 自动编译）、rea 6.4.0、jadx-headless-mcp 0.7.1（SHA 与 REA 内置审计值一致）、jadx 1.5.3、apktool 2.7.0、apksigner 0.9、aapt、OpenJDK 21、rsvg/ImageMagick | — |

---

## 3. 页面地图、关键流程与视觉样例

### 3.1 页面地图（从资源和标识反推，等级 A-线索 / D）

```
底部 Tab（A：home-tab/tab-{tasks,channel,discover,automation,mine}-{outline,filled}.svg）
├─ 任务 ─ 任务列表（置顶、搜索任务、归档、批量；drawer-menu-{pin,unpin,rename,delete,batch}）
│        └─ 任务对话 ChatPage（A-线索）
│             ├─ 顶栏：标题 / 运行位置（本机·云端）/ 侧栏开合（sidebar-left/right、wb-sidebar-*）
│             ├─ 消息流：用户消息、助手 Markdown（表格可复制/放大/海报/分享；代码可运行 markdown-code-run）、工具过程卡（tool-process-wb-*）、任务状态卡（task-card-status-running/success/warning）
│             ├─ 产物区：文件/代码产物，可调宽度，cloud-artifact-jump 跳转，preview/{markdown,html,code,diff,document,video}
│             └─ 输入区：+ / 附件（图片、相机、文档、腾讯文档、微信文件、项目资产、技能、专家、定时）/ 语音 / 模型 / 权限模式 / 发送·停止
├─ 频道 ─ 团队 IM（TIM）、成员、话题、提及（与 Muyon 第一期无关）
├─ 发现 ─ 助理 / 连接器 / 专家 / 知识库 / 项目 / 技能（discover-*.svg；capability-center/*）
├─ 自动化 ─ 定时任务列表 / 详情（暂停、试运行、编辑、删除）
└─ 我的 ─ 账号、会员积分、设置（/settings/{font-size,memory,notifications,privacy,storage,voice,account-deletion,my-shares}）、关于、实验室
抽屉 / 顶部：搜索、消息中心、应用切换（drawer-top-*）；电脑管理（已连接的电脑、离线、切换中）
底部弹层（A-线索，Sheet 类名）：ModelSheet、SkillSheet、AttachmentSheet、HomeRunLocationSheet、LocalDeviceManageSheet、TaskFormSheet、ArtifactFileSheet、KnowledgeBasePickerSheet、TencentDocsPickerSheet、LoginSheet 等 40 多个
```

**规律（D，依据是 40 多个 *Sheet 命名）**：二级选择一律用底部弹层（模型、技能、专家、连接器、附件来源、运行位置），不跳新页面，主上下文保持不动。Muyon 手机端可以照这个做：A03“本次上下文与使用范围”、S02 执行位置都做成弹层。

### 3.2 视觉体系

| 维度 | 发现 | 等级 |
|---|---|---|
| 色彩（代码常量） | 875 个颜色常量（含第三方包）里有 129 级中性灰；深色模式可能用 iOS 系统灰阶 #1C1C1E/#2C2C2E/#3A3A3C/#8E8E92/#AEAEB2（D：按色值推断）；浅色背景用 #F7F8FA/#F5F6F7/#FAFAFA；强调色是青绿 #00C29A/#00A885，浅底 #DFF7F1，深底 #0F3D30 | A（blutter 常量）+ D |
| 色彩（图标） | 图标大多是单色 #000，运行时着色（D）；有显式色值的主要是中性灰（#131313、#434343、#666666、#B5B5B5、#DEDEDE、#ECECEC、#F5F5F5、#FAFAFA）；强调色是青绿 #00C29A / #1DBF41 / #13B2BF；警告橙 #FA8619；蓝 #1677FF 用得很少 | A |
| 暗色 | 空态和加载失败插图各有 light/dark 两版（浅色 #DEDEDE/#FAFAFA，深色 #454545/#2E2E2E）；登录页视频和海报也分 light/dark | A |
| 字体 | 只内置了阿里妈妈数黑体 Bold（品牌标题用），**正文没有内置中文字体**，推断用系统字体（D）；数学用 KaTeX 字体；另有 Material、Cupertino 图标字体 | A |
| 字号、行距 | const TextStyle（排除框架默认后约 205 个）：字号 12/13/14/16/17 为主，另有 15/18/19/20/24/28；**行高按像素取整**：12/16、13/18、14/20（也有 21、22）、15/26、16/22 或 24、17/24、18/24、19/24、20/28、28/38；字重 w400/w500/w600 为主，w700 少量；标题加微负字距（-0.14～-0.19，约等于字号×-0.01）；17pt/-0.41 是 iOS 正文体例。有“字体大小”设置页 | A（blutter 常量） |
| 正文宽度 | 没找到明确的 maxWidth 常量 | 未知 |
| 间距、圆角 | EdgeInsets 常量 355 个：全部是 4 的倍数（加上 1、2、6、10、14 的微调），水平内边距以 16、20 为主，其次 12、24；圆角常量有 4、8、12、16、20、24 等 | A（blutter 常量） |
| 图标网格 | 主要是 16、20、24 三种 viewBox（分别 146、89、85 个），描边多为 2px；说明有小、中、大三档图标尺寸 | A |
| 动效 | Rive 吉祥物状态机（runtime-contract.json：眨眼、目光、形状）；Lottie“深度思考”动画；liquid_glass 着色器 | A |

视觉样例（全部从资源渲染，**不是截图**）：`evidence/visual/icon-sheet.png`（Tab、输入区、任务状态、工具、执行位置图标）、`empty-error-light-dark.png`（空态和失败插图的明暗两版）、`login_hero_*_poster.png`。

### 3.3 状态处理（文案线索，A-线索；命中情况见 `evidence/snippets/11-ui-string-clues.tsv`）

- **键盘**：adjustResize（A）；有输入区最大化/最小化按钮（input-maximize/minimize-24，A）
- **长内容**：表格放大和复制，代码运行，Mermaid、KaTeX 渲染；“输入最大化”对应长输入
- **流式滚动（新增）**：枚举 `idle / streamingFollow / returnToBottom` 和 `idle / seeking / pinned`，A-线索。推断（D）：生成时跟随到底，用户上滑就停止跟随，并出现“回到底部”；这正好对应第二册 A01“流式不抢滚动、离开底部后提示新内容”，**支持**。
- **消息块结构（新增）**：`completedHeader / processGroup / answer / attachmentGroup / artifactGroup / auxiliaryCard / progress / actionRow / divider`；过程组可以 `expanded / expandedPaused / collapsed`。推断：一条助手回复由“完成头 + 过程组（可折叠）+ 正文 + 附件组 + 产物组 + 操作行”组成。
- **输入区禁用原因（新增）**：`networkOffline / deviceOffline / channelDisconnected / historyLoadFailed / attachmentUploading / submissionBusy / waitingForReply` 等 11 种。推断：输入框不可用时会说明具体原因。
- **流式和等待**：SSE（text/event-stream、[DONE]，A-线索）；“正在思考”“深度思考中...”“生成中…”“停止回复”；排队：“队列中 / 取消排队 / 队列已满 / 排队等待超时”
- **错误**：“加载失败，请稍后重试”“请检查网络后重试”“加载项目失败，下拉重试”“发送超时，请稍后重试”“部分会话发送失败”“N 个文件上传失败”
- **离线和未知结果**：“重连中...”“当前设备已离线”“电脑端未响应”“**暂时无法确认消息状态**”。最后这条和 Muyon 的“未知结果先核对”在语义上相近，但它背后怎么核对**未知**
- **空态**：“暂无任务 / 暂无云端任务 / 暂无文件产物 / 暂无记忆内容 / 暂无搜索结果”，配明暗两版插图
- **停止和暂停**：“任务已被用户停止”“积分用尽，任务已暂停”“继续执行”

### 3.4 三条完整流程（资源 → 页面结构 → 交互 → Muyon 对应页面）

**流程 1：提问 → 生成任务 → 看进度**
- 资源：tab-tasks、wb_chat_add / wide-new-chat、HomeRunLocationSheet、ModelSheet、input-permission-shield、Button-send/stop、task-card-status-*、tool-process-wb-*
- 结构（示意）：`[顶栏: 标题 | 本机/云端 ▾ | ⋯] / [消息流 + 工具过程卡(可折叠) + 任务状态卡] / [附件条] / [＋ | 输入框 | 🎤 | 模型▾ 🛡 | ▶/■]`
- 交互（D）：新建任务时选运行位置和模型 → 发送 → 发送键变成停止键 → 流式过程以步骤卡展示，状态卡显示运行中、成功或警告 → 可以停止或继续执行
- Muyon：**A01** 助手对话 + **T01/T02**。**支持**第二册里“在途任务条紧贴标题”“生成结束但工具仍在执行”的区分；**补充**一点：发送和停止共用一个按钮位，权限模式盾牌常驻输入区，并且可以点开看本次授权范围（链到 A03/S04）。注意：盾牌只是展示授权，真正的授权仍由宿主做

**流程 2：打开产物 → 预览 → 保存或继续编辑**
- 资源：cloud-artifact-jump、ArtifactFileSheet、files/file-*.svg、/preview/{markdown,html,code,diff,document,video}、“调整产物区宽度”“保存到本机”“已编辑文件”、editor_sdk（libeditor_sdk_ffi.so，约 180MB）
- 结构（示意）：手机端点产物卡 → 全屏预览（顶部：返回 | 文件名 | 分享·更多）；平板/宽屏是对话加可调宽度的右侧产物区
- 交互（D）：可以预览 diff；“已编辑文件”说明 agent 修改过的文件会单独标出来；可以回到对话继续让它改
- Muyon：**R07 保存预览与提交结果**、**R06 人工草稿编辑**、桌面 **F03**。**支持**“打开产物不新建副本”；**补充**两点：diff 预览要当作版本确认的视觉载体，产物区宽度要在桌面端（Electron）保存。“保存到本机”在 Muyon 里走第一册单元 19（本机导出：冻结准备、分阶段授权、账本）

**流程 3：历史与搜索 → 回到任务**
- 资源：drawer-top-search、“搜索任务”“暂无搜索结果”、/team/search/messages、drawer-menu-pin/rename/delete/batch、archive.svg、“复制任务 ID”
- 结构（示意）：任务列表顶部是搜索；列表项支持置顶、重命名、归档、批量；点进去回到原任务
- Muyon：**A02 历史与全局搜索**。**支持**“回到原对象，不另建平行记录”；**补充**“复制任务 ID”作为排障和回执入口，但要防止把敏感内容一起复制出去

（第 4 条，执行位置切换：HomeRunLocationSheet、LocalDeviceManageSheet、“已连接的电脑 / 暂无已连接的电脑 / 切换中 / 云端不可恢复”→ Muyon **S02 模型与执行位置**。Muyon 只有本机这一个执行器，但可以照搬“执行位置必须在任务上明确标出来”这条原则。）

### 3.5 blutter 补充：状态与机制线索（A-线索，全部是混淆后的枚举值名，见 `evidence/snippets/17-enum-state-clues.txt`）

| 主题 | 恢复出的值 | 说明（D 推断） | 对 Muyon |
|---|---|---|---|
| 发送与未知结果 | provenNotSent / dispatchAmbiguous / acceptedAwaitingEcho；safeRetryRequired / reconcilePending / confirmationUnavailable；resubmitWithheld / safeRetrySubmitted / historyRefreshed；idle / inFlight / awaitingEcho / canResend | 发送后不确定是否到达时，会区分“确认没发出 / 投递不明 / 已受理等回显”；不明的时候先刷新历史对账，暂缓重发（resubmitWithheld），只在安全时才重试 | **支持**第一册单元 12、第二册状态机里“未知结果先核对、不重复执行”。建议 Muyon 把这三态写进 Rust 回执合同 |
| 执行管线 | precheck → conversationCreate → sessionConnect → promptDispatch → promptWait → responseStream → recovery → render；失败：duplicateTerminal / traceMismatch / ledgerWriteFailed | 客户端分阶段记录失败点；有“重复终态”“trace 不一致”“账本写入失败”，说明客户端有本地账本或去重逻辑 | **补充**：T02 活动详情可按阶段展示失败点；“重复终态”检测可作为 Muyon 回执完整性的测试用例 |
| 流恢复 | queued / reconnecting / replaying / finalizing | 断线后会重连并重放流 | **支持**第一册单元 13（SSE、重连） |
| 过期守卫 | accepted / staleGeneration / failed；synced / deferred / failed / superseded | 旧一代的响应会被丢弃或标记为已取代 | **支持**“旧结果、版本变化后旧决定失效”。看不到它绑定的是对象版本还是请求代次 |
| 权限 | 权限模式 standard / fullAccess；none / apply / confirmThenApply；answer / cancel / permissionResolve；applied / awaitingAuth / targetUnavailable | 输入区盾牌对应“标准 / 完全访问”两档；部分动作“先确认再应用”；对话里可以回答、取消或处理权限请求 | **修正**：Muyon 不应提供笼统的“完全访问”模式，授权要按对象和用途给。“先确认再应用”可借鉴为 T03 的交互形态 |
| 回合 | terminal / unresolved / active / pendingUserTurn | 回合会处于“未决”状态 | **支持**“未知”终态单独建模 |
| 生成式小组件 | resultMissingWidgetCode / finishedInputMissingWidgetFields | 有模型生成小组件（ai-widget），客户端会校验字段完整性 | **支持**“生成 UI 只能用白名单组件，并由宿主校验” |

### 3.6 路由模式（A-线索，`evidence/snippets/18-route-patterns.txt`）
带参数的路由大多属于团队 IM（/team/channels/:channelId/…、/team/direct/:peerUserId/…），此外有 /task-join/:conversationId、/project-apply/:projectId。普通路由有 /chat、/automation、/automation/detail、/mine、/mine/about、/mine/lab、/settings/*（字体大小、记忆、通知、隐私、存储、语音、注销、我的分享）、/preview/{markdown,html,code,diff,document,video,plain-text}、/search、/projects。说明：任务对话用 conversationId 标识，产物预览有独立路由，可以深链。

---

## 4. 机制证据表

| # | 主张 | 等级 | 版本 | 位置 | 局限 |
|---|---|---|---|---|---|
| M1 | 客户端是 Flutter，单 Activity，adjustResize | A | 2.6.1 | lib/arm64-v8a/libflutter.so、libapp.so；manifest MainActivity | — |
| M2 | 富内容（Mermaid、HTML 预览）可能走 WebView | A-线索 | 2.6.1 | assets/js/mermaid.min.js；dex 里的 webview_flutter pigeon 类；路径 /html_preview | 没看到调用点 |
| M3 | 底部 5 个 Tab：任务、频道、发现、自动化、我的 | A | 2.6.1 | assets/icons/home-tab/* | 顺序和默认 Tab 未知 |
| M4 | 输入区有权限模式入口 | A-线索 | 2.6.1 | input-permission-shield(-alert).svg；文案“权限模式” | 有哪些模式、语义如何，未知 |
| M5 | 执行位置分本机电脑和云端，可以切换 | A-线索 + C | 2.6.1 | HomeRunLocationSheet、LocalDeviceManageSheet；文案；C：商店描述“云上、本机双模式” | 调度机制未知 |
| M6 | 流式输出用 SSE | A-线索 | 2.6.1 | libapp.so 里的 “text/event-stream”“[DONE]”“/v2/chat/completions” | 不证明服务端协议细节 |
| M7 | 有排队、队列取消、超时 | A-线索 | 2.6.1 | /v2/chat/queue/{status,cancel}；文案 | — |
| M8 | 有“无法确认消息状态”类的未知态 | A-线索 | 2.6.1 | 文案“暂时无法确认消息状态” | 核对机制未知 |
| M9 | 有记忆页，可查看、添加、导入 | A-线索 | 2.6.1 | /settings/memory、/api/memory/profile；“我的记忆 / 添加到记忆 / 导入记忆 / 记忆已更新” | 存储方式和用途限定未知（这部分留给 Muse/Claude 篇对照） |
| M10 | 有审批流（项目加入、企微审批、操作审批） | A-线索 | 2.6.1 | “等待审批 / 审批失败 / 免审批直接加入”、wecom-approval-info.svg | 是否绑定对象和版本未知 |
| M11 | 危险操作有确认弹窗 | A-线索 | 2.6.1 | “确认执行命令？”“确认按此计划执行？”“此操作将永久删除该定时任务” | **只能证明有 UI 确认，不能证明有宿主授权** |
| M12 | 配色是黑白灰加青绿，明暗两套 | A | 2.6.1 | SVG 色值统计；*-light/-dark 插图 | 运行时主题令牌未知 |
| M13 | 正文用系统字体，品牌标题用数黑体 | A + D | 2.6.1 | FontManifest.json | 实际字号行距未知 |
| M14 | 技术选型做过 go_router StatefulShellRoute 评估 | A（附带文档） | 2.6.1 | assets/images/tech_evaluation_report.md | 是评估结论，不等于最终实现 |
| M16 | 字号、行高、字重常量体系（行高按像素取整） | A（blutter） | 2.6.1 | snippets/14-textstyle-consts.tsv | 读不到调用点 |
| M17 | 间距按 4 的倍数，主水平内边距 16/20 | A（blutter） | 2.6.1 | snippets/15-spacing-radius.txt | 同上 |
| M18 | 流式跟随和回到底部状态 | A-线索 | 2.6.1 | snippets/17 `_sVd` | 触发阈值未知 |
| M19 | 发送未知结果的三态和对账 | A-线索 | 2.6.1 | snippets/17 `Xvd/Yvd/Zvd/otd` | 不证明服务端幂等实现 |
| M20 | 失败阶段含 duplicateTerminal / ledgerWriteFailed | A-线索 | 2.6.1 | snippets/17 `nTb/TNc` | 账本内容未知 |
| M21 | staleGeneration / superseded 过期守卫 | A-线索 | 2.6.1 | snippets/17 `_BPc/WMc` | 绑定的是什么未知 |
| M22 | 权限模式 standard / fullAccess；confirmThenApply | A-线索 | 2.6.1 | snippets/17 `afc/bfc` | 各档语义未知；**不等于宿主授权** |
| M15 | 手机端定位为远程操控电脑 / 云端 | C | 2026-07 发布报道 | 0rg.cn 2026-07-22 文章（第三方转述，可信度一般） | 需要官方原文佐证 |

另外，按约定只报告位置、不读不用：`assets/flutter_assets/assets/keys/aisee_public_key*.pem`（从文件名看是**公钥**）、`assets/agconnect-services.json`（华为推送配置，一般含客户端 API key）、`assets/*.bks`（HMS 信任库）、`timpush-configs*.json`。风险：客户端配置泄露，属于常见做法，但不应模仿成“把密钥放进包里”。

---

## 5. Muyon 映射

| WorkBuddy 机制 | Muyon 页面 / 模块 | 落在哪一层 | 支持 / 修正 / 补充 | 涉及合同和测试 |
|---|---|---|---|---|
| 任务作为一级 Tab | T01、A01、W01（F02、F07） | Compose 底部导航 / Electron 侧栏 | **修正**：手机端 Tab 建议改成“助手·任务·资料·我的”，第二册 W01 的“工作台”放在桌面端更合适 | 导航合同；深链恢复测试 |
| 二级选择用底部弹层 | A03、S02、Q03 筛选 | Compose ModalBottomSheet / Electron Popover | **补充** | 弹层关闭后上下文不丢的测试 |
| 输入区权限模式盾牌 | A01 输入区 → S04 | Compose / Electron 展示；授权判定在 Rust 内核（第一册单元 11） | **补充**：只读展示当前授权范围，点开能看撤权入口 | 撤权后盾牌状态在 1 帧内更新；生成的卡片不能改它 |
| 执行位置显式化 | S02、T02 | Rust 内核执行器加平台适配层 | **支持**：S02 已有；**修正**：Muyon 不承诺跨设备 | 执行位置字段持久化测试 |
| 发送和停止共用按钮位 | A01 | 双端 UI；取消请求进 Rust 状态机 | **补充**，并遵守第二册“请求取消不等于已停止” | 停止后显示“取消中”，执行器确认后才进终态 |
| 工具过程分类型步骤卡 | T02、A01 | 语义 UI 合同（第一册单元 09、10） | **支持** | 步骤卡来自宿主事件，不来自模型文本 |
| 产物区（可调宽度、diff 预览、保存到本机） | R06、R07、F03 | Electron 分栏；导出走第一册单元 19 | **补充** | 版本确认绑定 diff 的哈希 |
| 排队、离线、未知态文案 | 全局错误恢复组件 | Rust 状态（第一册单元 12、13）加双端文案 | **支持**“未知结果先核对” | 未知态时禁止重试按钮，直接执行核对 |
| 发送三态（未发出、不明、已受理）和对账 | 第一册单元 12、13；A01 发送状态 | Rust 回执合同加双端展示 | **支持并细化** | 断网、杀进程、超时三类注入测试：不明状态禁止自动重发，先对账 |
| 过期守卫 | 第二册状态机 | Rust 内核 | **支持** | 旧代响应到达时不改写 UI，不触发执行 |
| 输入区禁用原因 | A01 | 双端 UI | **补充** | 每种原因有可见说明和下一步 |
| 字号和间距体系 | 设计令牌 | 双端令牌 | **补充** | 令牌表：text.body = 15 或 16 / 行高 24 等（估计取值，见 6.6） |
| 明暗插图、黑白灰青绿 | 设计令牌 | 双端令牌映射 | **支持** | 对比度测试 |
| 记忆页 | 设置 → 记忆（第二册暂无单独页） | Rust 存储加 S 系列页面 | **补充**：建议新增“记忆与偏好”页，放 S04 旁边，等 Muse/Claude 篇看完再定 | 删除、纠正、限定用途测试 |

---

## 6. 具体建议与验收

**建议 1：手机端信息架构（Compose）**。底部 4 个 Tab：助手、任务、资料、我的。助手页顶部固定标题、执行位置、范围标签；在途任务条可展开。二级选择统一用底部弹层。
**建议 2：输入区（双端）**。左边是加号（附件、来源），中间是多行输入并可最大化，右边是语音、模型、授权盾牌、发送/停止。中文组字时 Enter 不发送。
**建议 3：任务状态卡和步骤卡**。只消费 Rust 内核发出的事件，状态枚举对齐第二册（排队、运行、等待、完成、失败、已取消、**未知待核对**）。
**建议 4：产物区（Electron）**。右侧分栏、宽度可调并持久化；修改类产物默认显示 diff；“保存/提交”按钮由宿主组件提供，绑定 产物 ID + 版本哈希。
**建议 5：状态文案库**。参考上面的分类，建立一份统一的“错误恢复组件”文案表，每条都有对应的下一步动作。
**建议 6：视觉**（第二轮补充具体刻度，A 常量加 D 取舍）：正文 15 或 16，行高 24；次要文字 13/18；说明文字 12/16；标题 17/24 或 20/28，大标题 28/38；字重只用 400、500、600；间距 4、8、12、16、20、24、32；圆角 8、12、16。黑白灰中性色阶约 8 级（估计），一个强调色（深青），警告、错误单独用颜色；空态插图做明暗两版；正文用系统字体；品牌字体只用于标题。

| 验收场景 | 期望 |
|---|---|
| 正常 | 提问 → 任务卡出现 → 步骤流式更新 → 完成后打开产物，不产生副本 |
| 空态 | 任务、产物、记忆、搜索都有明暗两版插图和一个主操作 |
| 错误 | 显示原因和可执行的下一步（重试、换位置、看详情）；部分失败可以逐项重试 |
| 离线 | 草稿保留；未发出的消息不显示为已发送；只展示有读取权限的缓存 |
| 取消 | 点停止 → 显示“取消中” → 执行器确认后进入“已取消”；没确认的保持“未知待核对” |
| 撤权 | 盾牌立刻更新；后续读取和动作立刻被拒；缓存里的敏感投影清除 |
| 旧结果 | 历史结果标“历史”；版本变化后旧的审批失效，需要重新确认 |
| 重复点击 | 审批和提交带 operationId 做幂等，连点只执行一次并返回同一张回执 |
| 恢复 | 重开或旋转后恢复草稿、阅读位置和在途任务；未知结果先对账，再决定显示什么 |

**必须保留的语义（不能被 WorkBuddy 式 UI 替代）**：宿主确定性授权；商敏信息按用途裁剪；确认绑定对象和版本；执行回执；防重复执行；未知结果先核对；撤权立即生效。WorkBuddy 的确认弹窗、盾牌、状态卡**只当作展示层参考**。

---

## 7. 失败记录、未覆盖项与下一步

**失败和限制**
- 应用汇的 http 下载链接在盒子上 80 端口不通，改用同一主机的 https，成功
- 魅族网页下载按钮已停用（需要客户端），没有使用
- blutter（commit 4a60ac64）第一次运行报错 `Cannot find libflutter file`（只解出了 libapp.so），补解 libflutter.so 后成功：Dart 3.11.3，snapshot 78da37fe…，与包内评估文档的版本一致。限制：库名、类名、函数名**完全混淆**，只能读常量对象、枚举值名和字符串池，**拿不到组件树、调用点和条件分支**；页面结构仍是推断，不是完整 UI 还原
- 没有真机或模拟器，没有截图，没有 B 级证据
- 签名只能判到“中等可信”（没有公开的官方证书参照）

**未覆盖**：精确字号和行距、流式滚动策略、长列表虚拟化、平板布局细节、审批和版本绑定、记忆用途限制。

**下一步（需要用户决定）**
1. 用户已决定不做动态观察：真实截图（B 级）和流式、键盘的实测仍然缺失，相关结论保持 A-线索或 D。
2. Meta Muse：等用户通过 Google Drive 提供 APK 后再开始。
