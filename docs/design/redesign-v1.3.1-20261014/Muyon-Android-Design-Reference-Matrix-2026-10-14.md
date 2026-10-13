# Muyon Android 设计参考矩阵
## 供 Claude Design 需求书使用 · 2026-10-14

核验时间：2026-10-13 UTC（北京时间 2026-10-14）。仓库来源固定于 PR #69 的当前提交 **190ddd88359a4f1a8f21f8d62d9186eb474137e9**；本轮核对时 PR 仍 open、未合并。没有读取旧版含敏感值正文，没有运行 APK、真实账号、模型或动态实验，也没有修改仓库。

## 先给设计师的六条结论

1. **WorkBuddy 借信息层次**：把任务、对话、产物做成可相互定位的对象；输入区保持易达，短选择用底部弹层，复杂范围编辑用全屏页。不要把图标清单当成真实导航顺序或精确布局。
2. **Muse 借个人助手的可理解性**：助手身份可预览、可修改；长期记忆可查看来源、修正和限制用途。身份、长期记忆、聊天记录、历史检索与授权不能合成一个“大脑开关”。
3. **Claude 借阅读与成果的关系**：正文、UI、代码建立不同排版角色；对话内可视化与独立产物有不同入口；Research 把进展、来源、结果分层；长执行采用摘要→明细→对象/产物的阅读路径。
4. **ChatGPT 借动作反馈的语法**：每个 Muyon 动作自行定义“动作名／进行中／成功／失败”；再补“等待决定、结果未知、核对中”等独立语义。成功必须来自宿主回执，不能由自然语言或漂亮卡片宣告。
5. **Android 的可用性优先于竞品外观**：48dp 触摸目标、200% 字体、IME 与系统栏 insets、按实际窗口调整的布局、TalkBack 语义必须进入设计交付。不要按手机型号或固定截图宽度决定布局。
6. **所有线框都是原创提案**：图旁固定注明“Muyon 原创设计示意，使用合成数据；非竞品截图，非已实现功能”。不复制 Anthropic、Optimistic 等私有字体、品牌图形或 APK 资源。字体优先系统回退；确需开源字体时另核许可证。

这六条是设计取舍，不是四款 App 的实测结论。下面给出每一条的证据上限。模式 UI 以用户最新决定的四档及默认 Auto 为准，不能回退到旧报告中的档位组成与限制；其余未决事项也不能由竞品研究擅定。

## 证据怎样读

各原报告对 A/B/C/D 的用法并不一致：WorkBuddy/Muse 的 B 表示动态观察，Claude/ChatGPT 的 B 表示多条静态证据推断。因此本矩阵不用一个字母混合评级，改为：

- **静态直接**：本次读到仓内摘录的字符串、字段、资源清单或有限代码。能证明摘录包含什么，不证明已运行、真实截图或服务端端到端行为
- **报告分析**：报告作者的归纳，本轮没有完整 APK、全部控制流或动态证据可独立重建
- **官方行为/指导**：本轮重新打开的 Android Developers 文档，只说明 Android/Compose 的建议或平台条件；不是四款 App 的实际行为
- **未知**：资料不足、缺包、反编译失败、缺调用点或未运行
- **Muyon 提案**：为了 Muyon 形成的原创页面、文案与交互要求，遵守现行产品合同，不因竞品报告的一句话自动变成新能力

**共同限制**：四 app 研究没有真机运行截图；Claude 缺必需 ABI/density split 且有反编译错误；ChatGPT 也缺 split，jadx 约 66% 中止；Muse 有方法反编译失败。WorkBuddy 的视觉资源目录未提交，本轮查询 evidence 目录只返回 snippets，icon-sheet.png 固定提交取件为 404；报告提到的资源渲染图也不是截图。未发现某功能不等于产品没有它。

## 26 条高价值参考矩阵

表内 Fxx / Mx / Ex 是原报告或 findings-index 的编号；EX-01 等为执行摘要 evidence 文件编号；AND-xx 是本矩阵对官方文档的索引。每一行同时列出报告与具体证据入口。

| ID / 设计主题 | 精确报告与证据 ID | 本轮可核证内容 | 必须保留的边界 | Muyon 原创采纳方向 |
|---|---|---|---|---|
| WB-01 · 任务型导航 | [WorkBuddy §3.1、M3][WB-R]；[F08 图标清单][WB-F08] | 静态直接：tasks/channel/discover/automation/mine 各有 outline/filled 图标，另有任务状态与搜索/归档图标 | 实际排序、默认入口、可见条件未知；“任务优先”是报告分析，没有首页截图 | T01 任务列表与 A01 对话互链；导航按 Muyon 业务定义。不要原样搬企业频道、发现或五 Tab，更不要把四 Tab 草案写成竞品事实 |
| WB-02 · 短选择留在当前上下文 | [WorkBuddy §3.1][WB-R]；[F06 Sheet/Page 名称][WB-F06] | 静态直接：ModelSheet、AttachmentSheet、HomeRunLocationSheet、ArtifactFileSheet 等标识存在 | 命名不能证明所有二级页都采用底部弹层，也不能证明实际高度/过渡动画 | 模型、附件来源等短选择可用 BottomSheet；A03 复杂范围按 v1.3 全屏展开。关闭后回到原输入和阅读位置 |
| WB-03 · 输入区与执行信息 | [WorkBuddy §3.1、3.3][WB-R]；[F08][WB-F08]、[F11][WB-F11] | 静态直接：附件、语音、模型、权限盾牌、发送、停止图标；权限模式、设备离线等文案 | 图标不证明同屏位置、按钮共用切换时序或宿主授权。运行地点类文案不赋予 Muyon 跨设备执行能力 | A01 主要操作靠近输入区；模式用可读文字与可访问状态，盾牌只辅助。任务显示真实执行位置，停止生成与取消任务分开 |
| WB-04 · 过程与成果分层、保留阅读锚点 | [WorkBuddy §3.3][WB-R]；[F17 消息块/滚动枚举][WB-F17] | 静态直接：processGroup/answer/attachmentGroup/artifactGroup、expanded/collapsed、streamingFollow/returnToBottom | 没有触发阈值和完整 UI 树；不证明何时折叠或滚动恢复的实际行为 | A01 使用正文、可折叠活动摘要、附件与产物独立区。用户离开底部后不抢滚动；提供新内容提示和返回底部；不能折叠掉待决定/未知结果 |
| WB-05 · 类型刻度、间距可作候选种子 | [WorkBuddy §3.2、M16/M17][WB-R]；[F14 TextStyle][WB-F14]、[F15 spacing/radius][WB-F15] | 静态直接：16/24、17/24、20/28 等字号/行高组合；常见 16/20 水平边距及多种圆角常量 | 常量没有组件调用点，可能含共享库；不是屏幕测量。并非所有值都是 4 的倍数，正文 maxWidth 未知，不能直接换算成 Android 物理 px | 可提出 Muyon 4dp 基础节奏、系统正文与少量字重；具体 sp/dp、最大阅读宽度、圆角由原创方案与字体缩放测试确定 |
| MU-01 · 身份页可预览、可纠正 | [Muse §1、§3、M2][MU-R]；[F06 文件引用][MU-F06]、[F08 文案][MU-F08] | 静态直接：IDENTITY.md、SOUL.md 引用及身份视图模型；CREATURE/SOUL/VIBE、Agent personality 等文案 | 文件内容、服务端注入方式、每个字段的编辑能力和实际布局未知；不要把内部文件名变成用户必须理解的心智模型 | S07 用名字、头像、语气、语言/表达偏好与示例回复预览。保存/放弃保留草稿；身份只影响表达，权限仍独立 |
| MU-02 · 可管理的长期记忆 | [Muse §3 流程1、M1/M3][MU-R]；[F06][MU-F06]、[F08][MU-F08] | 静态直接：MEMORY.md 读写引用、saveContent/writeFile、discardChanges；有 Add memory/Summarize into memory 文案。预览确认流程为报告分析 | 所见 writeFile 参数未列版本，不等于服务端无并发防护；文件自由编辑不证明逐条来源或可验证删除 | S06 结构化记忆条目显示来源、类型、用途和实际状态；编辑使用现有 MemoryRecord revision/CAS，冲突保留草稿。不能由模型“已记住”替代持久回执 |
| MU-03 · 生效权限与历史分开 | [Muse §3 流程2/3、M4–M6][MU-R]；[F07 枚举][MU-F07]、[F08][MU-F08] | 静态直接：pending/recent approvals、不同决定值、SESSION/TODAY/DURABLE、ActivePermission 类型；审批历史和撤销文案 | 客户端结构不证明服务端参数绑定、即时撤权或各路径覆盖；不复制其八种决定为 Muyon 模式 | S04 显示生效范围与撤销状态；T03 管理当前待决定动作。历史决定与当前权限分开，模式按 Muyon 最新合同；不把“允许本批”变成长期开关 |
| MU-04 · 个人助手首页的时间与来源层次 | [Muse §3、M7/M14/M16][MU-R]；[F07][MU-F07]、[F08][MU-F08]、[F09 路由][MU-F09] | 静态直接：activity/goals/library/memory 路由、Goals/Add a subgoal/Sources；同步类别和“删消息可能仍留记忆”文案 | 源删除后所有派生数据的实际清理与来源覆盖未知；路由存在不证明首页实际导航；云 VM 后台能力不能外推 Muyon | A01/T01 展示当前关注、活动和需处理项；S06 区分读记忆、自动记忆、保存聊天、检索历史。清理显示真实进度；不添加承诺持续后台运行的装饰状态 |
| CL-01 · 字体角色分离 | [Claude §3 视觉][CL-R]；[F01/F14、snippet12 字体/渲染资源][CL-F14] | 静态直接：serif、sans、Noto Serif、JetBrains Mono 资源文件；报告分析正文/UI/代码角色 | 资源存在不证明每个页面真正用哪套字体、字号、行距或中文回退；设置文案/组件映射需更完整证据 | 原创设计可用 UI sans、可选阅读 serif、代码 mono 的角色分离；中文正文优先系统可读性。禁拷贝 Anthropic 字体，标题不靠过度装饰制造品牌相似 |
| CL-02 · 长答案的阅读结构 | [Claude §1、E12][CL-R]；[F14、snippet12][CL-F14] | 静态直接：highlight.min.js、peghl、token-highlight.js 资源；Markdown/LaTeX/折叠描述属于报告分析 | 没有完整标题/表格/公式组件树或实际排版测量，不能宣称已经还原 Claude 阅读界面 | A01 设计标题、段落、列表、引用、代码、表格、公式的规范与失败回退。长代码可横向阅读/复制，长表提供详情视图；有真实来源链接 |
| CL-03 · 对话内可视化是独立内容类型 | [Claude §4.3、F11][CL-R]；[snippet07 可视化文案][CL-F11] | 静态直接：Bar/Line/Scatter、Display chart、Failed to display chart、Inline visualizations 等文案 | “原生 Compose 图表且只有复制/分享”的完整实现是报告分析，单文案不能证明所有动作边界 | A01 内嵌图表具标题、单位、来源、数据时间与可访问摘要；失败时提供表格/文字等替代。不能把示例数字渲染为真实结果 |
| CL-04 · 产物能力要显式区分 | [Claude §4.3][CL-R]；[F11、snippet07][CL-F11] | 静态直接：interactive、AI-powered、可评论产物、公开发布、组织链接及风险提示文案 | 不同能力的可用账号、触发条件及端到端约束未运行；不能只凭 WebView 外观判定无副作用 | W01/A01 产物卡沿用 Muyon“静态／交互／可调用能力”徽标，按钮写真实效果；手机打开独立预览，宽窗可并列。预览、修改草稿、实际提交分别展示 |
| CL-05 · Research：进度、来源、结果三层 | [Claude E11/F13][CL-R]、[执行摘要 §2.5][EX-I]；[snippet09][CL-F13]、[EX-02][EX-02] | 静态直接：规划、取消中、取消、中断、超时文案；ResearchStatusResponse 中 headline/status/timestamps/total_sources/top_source_domains/agent_summaries | 字段不等于截图和轮询机制的实测；来源计数不等于已核验文献数；不得把 Code 子代理行为混到普通研究 | R01–R08 科研业务与 A01/T02 任务联动：摘要优先显示目标和阶段；来源可展开；完成后链接同一研究产物。未知总数不用虚假百分比，取消请求与效果分开 |
| CL-06 · 折叠执行摘要可追溯 | [执行摘要 §0/§1][EX-R]；[EX-01 文案][EX-01]、[EX-03 UI字段][EX-03] | 静态直接：工具计数/耗时/步骤文案，collapsible/summary_pending，toolUseId、isError、isStopped、isWaitingForUser、codeArtifactLink 等字段 | 连续块如何分组为报告分析；四布尔值不证明状态互斥；“完成”文案不证明真实效果。PostTurnSummary/agents 大量属于 Code 远程会话 | A01 概括“动作数、需关注项、成果”；T02 展开动作、Attempt、状态、真实回执。摘要为派生视图，重试不冒充新动作，迟到回执不得被旧摘要/折叠丢弃 |
| CL-07 · 上下文压缩应是边界状态 | [Claude E5/F06][CL-R]、[执行摘要 §0][EX-R]；[snippet06][CL-F06]、[EX-03][EX-03] | 静态直接：Compacted conversation、节省 token、context window、压缩失败文案；follows_compaction/compaction_tokens 等字段 | 不证明 App 摘要内容、压缩算法、可恢复范围或不会丢输入；公开 API 也不自动证明 App 内部行为 | A01/T02 用低干扰分隔与可展开说明表示压缩/失败；记忆更新另列。未送达输入保留独立状态；不展示隐藏推理，估算 token 明示估算 |
| GPT-01 · 动作反馈有固定语法 | [ChatGPT E2/F02][GPT-L]；[snippet02][GPT-F02] | 静态直接：Creating/Reading/Updating、Created canvas/reminder、Couldn’t create、Create 等动作状态文案 | 提交片段并未为每一工具保留完整四项；“每个工具同构四元组”是报告归纳；Created 字符串不是实际持久回执 | 为 Muyon 每个业务动作定义四文案，再补等待/未知/核对。状态与按钮动词一致；成功色/勾只在真实回执成立后显示，错误保留用户输入 |
| GPT-02 · 生成卡与宿主动作解耦 | [ChatGPT E3–E5/F03–F05][GPT-L]；[snippet03][GPT-F03]、[04][GPT-F04]、[05][GPT-F05]；[AUTH GPT-04][AUTH-GPT-04] | 静态直接：允许动作/不可信 URL/不可回退特权动作等符号或文案、schema/JSON Patch 标识、少量 sandbox 代码 | 大多为解压字符串，无法据此证明完整执行前门控、所有路径或有效隔离。不能从报告推导 Muyon 一律强制回模型 | 宿主提供受控按钮、数据身份与 schema 校验；纯本机筛选立即响应，受控业务动作可直达 Rust 核验。重新理解或生成才请求模型，未知组件/过期动作有明确禁用原因 |
| GPT-03 · unknown 是可见的结果 | [ChatGPT E10/F10][GPT-L]；[snippet10][GPT-F10] | 静态直接：重连核对、不能确认是否续跑、请核对状态、不能确认变更等文案 | 跨 Orbit、连接器、登录等不同路径；不能拼成普通聊天通用状态机，也不证明查核一定成功 | A01/T02/D01 把“请求已受理、执行器已停、业务效果”分轴。未知显示最后核对时间及原因；禁盲重派发，保留原意图和已知回执 |
| GPT-04 · 旧卡片与决定不能盲复用 | [AUTH-TRACE-02 ChatGPT][AUTH-GPT-R]；[GPT-02 摘要比较片段][AUTH-GPT-02] | 静态直接：Orbit 路径 SHA-256、参数摘要计算调用、保存状态与 equality 比较线索 | 规范化方法和不匹配分支不完整；不能说所有工具完整实现参数绑定，更不能据此证明外部效果幂等 | Muyon 按自身合同绑定稳定意图、参数、对象版本与当前权限。旧卡重验；冲突保留草稿并展示差异。全部允许中重验不等于新增风险审批 |
| AND-01 · 触摸目标 | 官方 [Compose API defaults，Minimum touch target sizes][AND-01] | 官方指导：可交互元素至少 48dp；小控件可能由 Compose 扩展触摸区，仍须防相邻区域重叠 | 48dp 是可点击区域，不要求图标图形本身放大到 48dp；默认组件不能代替实际测试 | 输入操作、来源按钮、摘要展开、关闭/返回均标注触摸框；大字体时保持可达。相邻按钮不共享误触区域 |
| AND-02 · 文字缩放 | 官方 [Android 14 Features，Non-linear font scaling to 200%][AND-02] | 官方行为/指导：Android 14 起支持最大 200% 非线性字体缩放；文字用 sp，并在最大字体下测试 | 不能将 fontScale 当唯一线性倍数，也不能把 padding 用 sp；固定高度不应裁断大字 | 交付 100% 与 200% 关键页面；标题、模式行、权限范围、底部按钮可重排，正文不靠缩小字号塞入；长中文/英文/数字都验 |
| AND-03 · Edge-to-edge 与键盘 | 官方 [About window insets][AND-03]、[Set up edge-to-edge][AND-03b] | 官方行为：在 Android 15+ 且 target SDK 35 条件下默认强制 edge-to-edge；系统栏、缺口和 IME 需正确处理 insets | 不能只写“Android 15 一律如此”而省略 target 条件；不能硬编码状态栏/键盘高度。本轮不指定 Compose 依赖版本 | A01 输入区、BottomSheet、长表单确认栏随 IME 可达；背景可延伸，重要控件留安全区。验手势/三键导航及横屏 |
| AND-04 · 实际窗口驱动布局 | 官方 [Use window size classes][AND-04] | 官方指导：按 app 可用窗口而非设备标签布局；宽度界线含 600/840/1200/1600dp，高度独立分类且会动态变化 | 小平板/大手机不保证固定档；中宽但矮的横屏不应机械双栏。断点是布局指导，不是 Muyon 所有面板的最小可读宽度 | 手机先列表后详情；足够宽高时对话＋产物或列表＋详情并列。折叠/旋转/分屏保持对象、选中项与草稿，不新建任务 |
| AND-05 · 导航形态随窗口变 | 官方 [Build adaptive navigation][AND-05] | 官方指导：紧凑窗口常用底部 navigation bar，较大窗口常用 rail；NavigationSuiteScaffold 可按 WindowSizeClass 动态切换 | Material 默认切换还考虑高度与 tabletop posture；不能用唯一屏宽 if 强行概括所有姿态 | 同一组 Muyon 顶级目的地保持身份与选中状态，窄窗底栏、适合的宽窗侧轨；更多空间用于内容，不拉宽导航图标 |
| AND-06 · 可访问的执行摘要与动态内容 | 官方 [Compose Semantics：headings/live regions/paneTitle/errors/progress/stateDescription][AND-06] | 官方指导：标题、面板、错误、状态与进度有语义属性；常用 polite live region，避免频繁更新造成连续打断 | 不能把每个流式 token、秒级计时器都做 live region；自定义 UI 需补语义，不以颜色/图标单独表达状态 | 摘要可读出动作/状态/数量；弹层有 paneTitle，图表有文字等价，错误可定位；重要状态变化适度通知，阅读焦点不被流式刷新抢走 |


## 不应写进 Claude Design 需求书的七种结论

1. “复制 WorkBuddy 的真实五 Tab 顺序和页面尺寸”：只有资源/标识，真实顺序与尺寸未证实
2. “使用 Claude/Muse APK 自带字体和图标还原风格”：资源只用于识别，不是获准再利用的设计资产
3. “四款 App 都保证 exactly-once、Stop 即撤回效果、离线仍后台继续”：静态材料不支持，Muyon 也必须区分请求、执行器和外部效果
4. “DIL 证明所有副作用必须先回模型”：字串不是完整控制流，而且 Muyon 已允许受控业务按钮直达 Rust 核验
5. “旧报告的四档组成、全部允许仅个人、强制逐站点审批是现行 Muyon 决定”：旧研究建议不能覆盖后续合同与用户最新的四档、默认 Auto 决定；Auto 与全部允许语义应区分
6. “关闭记忆就是临时/无痕，删聊天就自动删掉全部记忆”：四项控制与派生数据生命周期独立；临时会话、容量及相关未决项不得擅定
7. “来源数、步骤数、完成文案本身就是可信回执”：来源需可定位，计数需明确口径，成功需真实效果证据；无法得知总数不展示伪进度

## 设计交付的最小证据标注

每张关键图旁放四行即可：

- 图的性质：原创 Muyon 示意；合成数据；当前/历史/失败状态
- 借鉴来源：本矩阵 ID，例如 WB-04 + CL-06 + AND-06
- 交互事实：哪个按钮只展开，哪个修改草稿，哪个触发受控业务动作；成功由什么回执驱动
- 待验证项：大字/窄窗/IME/TalkBack/过期版本/未知结果，不把设计验收清单写成已通过测试

优先画六组：A01 对话与输入、T02 执行摘要详情、Research 进展与来源、产物预览、S06 记忆管理、S07 身份预览。它们覆盖用户要借鉴的四种产品长处，且能暴露授权、回执与错误恢复的实际边界。

## 来源与核验说明

- 四 app 与执行摘要材料均通过 GitHub 连接器直接读取指定当前提交；报告引用入口和证据片段都固定 SHA。部分原报告说“已决定”的内容与后续 v1.3 冲突，只把它们当历史研究意见
- 只读复用《AUTH-TRACE-02 只读复核与 v1.2 补证建议》和《Muyon 记忆生命周期与恢复协议增量评审》的反例；没有把旧报告里指向旧 SHA 的链接带入本文，也没有重新访问旧敏感正文
- Android 官方页在本轮重新读取。它们是滚动文档，链接不是历史快照；本文只采纳页面中明确可见的指导，不猜 Compose/Material 最新稳定依赖版本，不把文档示例当 Muyon 已实现代码
- 本矩阵不重新认证四 app 的签名、APK 完整性或商店归属；仓内摘录与原始包是否完全一致仍依赖研究作者提供的原始证据


[WB-R]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/workbuddy/2.6.1/report.md#L46-L96
[WB-L]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/workbuddy/2.6.1/report.md#L135-L164
[WB-F06]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/workbuddy/2.6.1/evidence/snippets/06-dart-widget-name-clues.txt
[WB-F08]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/workbuddy/2.6.1/evidence/snippets/08-icon-inventory.txt
[WB-F11]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/workbuddy/2.6.1/evidence/snippets/11-ui-string-clues.tsv
[WB-F14]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/workbuddy/2.6.1/evidence/snippets/14-textstyle-consts.tsv
[WB-F15]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/workbuddy/2.6.1/evidence/snippets/15-spacing-radius.txt
[WB-F17]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/workbuddy/2.6.1/evidence/snippets/17-enum-state-clues.txt
[MU-R]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/muse/11.0.0.8.164/report.md#L53-L127
[MU-F06]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/muse/11.0.0.8.164/evidence/snippets/06-workspace-files.txt
[MU-F07]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/muse/11.0.0.8.164/evidence/snippets/07-approval-permission-enums.txt
[MU-F08]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/muse/11.0.0.8.164/evidence/snippets/08-ui-strings.tsv
[MU-F09]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/muse/11.0.0.8.164/evidence/snippets/09-nav-routes.txt
[CL-R]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/claude/1.261009.20/report.md#L28-L67
[CL-F14]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/claude/1.261009.20/evidence/snippets/12-ui-framework-assets.txt
[CL-F11]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/claude/1.261009.20/evidence/snippets/07-strings-artifacts-viz.txt
[CL-F13]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/claude/1.261009.20/evidence/snippets/09-strings-research.txt
[CL-F06]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/claude/1.261009.20/evidence/snippets/06-strings-compaction.txt
[EX-R]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/claude/1.261009.20/exec-summary/report.md#L8-L57
[EX-I]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/claude/1.261009.20/exec-summary/report.md#L59-L88
[EX-01]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/claude/1.261009.20/exec-summary/evidence/01-strings-exec-summary.txt
[EX-02]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/claude/1.261009.20/exec-summary/evidence/02-serial-fields-core.txt
[EX-03]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/claude/1.261009.20/exec-summary/evidence/03-serial-fields-blocks-ui.txt
[GPT-R]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/chatgpt/1.2026.272/report.md#L6-L18
[GPT-L]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/chatgpt/1.2026.272/report.md#L37-L71
[GPT-F02]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/chatgpt/1.2026.272/evidence/snippets/02-tool-state-quads.txt
[GPT-F03]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/chatgpt/1.2026.272/evidence/snippets/03-dil-host-action-allowlist.txt
[GPT-F04]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/chatgpt/1.2026.272/evidence/snippets/04-dil-sandbox.txt
[GPT-F05]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/chatgpt/1.2026.272/evidence/snippets/05-dil-compiler-validate.txt
[GPT-F10]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/chatgpt/1.2026.272/evidence/snippets/10-unknown-outcome.txt
[AUTH-GPT-R]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/auth-trace-02/chatgpt.md
[AUTH-GPT-02]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/auth-trace-02/evidence/GPT-02-params-digest-reuse-check.txt
[AUTH-GPT-04]: https://github.com/mightyoung/Muyon/blob/190ddd88359a4f1a8f21f8d62d9186eb474137e9/docs/research/android-reference/auth-trace-02/evidence/GPT-04-dil-host-action-gate.txt
[AND-01]: https://developer.android.com/develop/ui/compose/accessibility/api-defaults
[AND-02]: https://developer.android.com/about/versions/14/features#non-linear-font-scaling
[AND-03]: https://developer.android.com/develop/ui/compose/system/insets
[AND-03b]: https://developer.android.com/develop/ui/compose/system/setup-e2e
[AND-04]: https://developer.android.com/develop/adaptive-apps/guides/use-window-size-classes
[AND-05]: https://developer.android.com/develop/ui/compose/layouts/adaptive/build-adaptive-navigation
[AND-06]: https://developer.android.com/develop/ui/compose/accessibility/semantics

