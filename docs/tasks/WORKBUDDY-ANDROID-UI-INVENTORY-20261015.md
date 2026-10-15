# WorkBuddy Android 高保真还原：证据与工程盘点

2026-10-15。仅文档，不修改 Android、Flutter、Rust、授权行为或共享 UI 代码。最新方向是 Android 以 WorkBuddy 安卓版为单一视觉参考，暂停旧设计中的多 App 自由混搭；保留 Muyon 名称与自有素材。

**结论：可以继续页面/组件映射；完整页面像素还原仍缺真实截图。**已逐张查看10张已入库 PNG，都是 APK 内置资源的渲染/拷贝，不能作为完整页面截图。没有将竞品 PNG、字体、原 APK、反编译源码或凭据加入本提交。

## 固定来源与真实性

- [PR69](https://github.com/mightyoung/Muyon/pull/69) 本轮 GitHub 只读查询：`closed`、`merged=false`；完整 head 为 `dca32eebd723e5a4e577cb63a39bea1f8588fd04`，base 为 `01e56cc2d729dab70e1b1def05c3aa93b28f421a`。
- 固定树 `docs/research/android-reference/workbuddy/2.6.1/` 含32文件：18条静态证据片段、10 PNG、report.md/.docx、manifest.json、findings-index.md。实际树已含图片，旧设计矩阵“visual未提交/配图缺失”的结论过时；PR旧描述也不能覆盖实际树。
- [样本 manifest](https://github.com/mightyoung/Muyon/blob/dca32eebd723e5a4e577cb63a39bea1f8588fd04/docs/research/android-reference/workbuddy/2.6.1/manifest.json)：`com.tencent.workbuddy.app`，2.6.1/build852，293687392字节，APK SHA-256 `5ce904337ba2821fb1cdb7965075445746d198bc82d40b12d6842d24f1da34e3`。这是既有记录复核；本轮未持有原 APK，不能声称重算该哈希。
- [原报告](https://github.com/mightyoung/Muyon/blob/dca32eebd723e5a4e577cb63a39bea1f8588fd04/docs/research/android-reference/workbuddy/2.6.1/report.md) 明确：没有安装运行、没有真机截图；blutter只恢复常量/枚举，拿不到完整Widget树、调用点和条件分支。资源名称与路由字符串不能证明页面布局及运行行为。

| PNG类别 | 个数/尺寸 | 像素核实结果 |
|---|---|---|
| icon-sheet.png | 1，540×272 RGB | 5列×4行图标拼图，无页面导航/输入区组合 |
| assistant-empty-illustration-light/dark、empty-state-illustration-light/dark、state_load_failed、state_load_failed_dark | 6，240×180 RGBA | 机器人/耳机问号等空态或失败插画 |
| empty-error-light-dark.png | 1，512×648，I;16 | 资源汇总拼图，无页面结构 |
| login_hero_light/dark_poster.png | 2，960×960 RGB | 3D机器人登录海报资源，无表单/按钮/协议区 |

32文件均从完整固定提交提取至独立临时报告目录，记录SHA-256与Git blob；10 PNG均完整解码并逐张查看。没有用重建图补造截图。已有RD-P08手机viewport图是Muyon合成供应商实验的Chromium网页，不是WorkBuddy或Android/Compose截图。

## 页面与组件线索

| 组件簇 | 静态直接证据/线索 | 仍未知 |
|---|---|---|
| 一级入口 | tasks/channel/discover/automation/mine的outline/filled资产名 | 真实排序、默认页、可见条件及是否同屏 |
| 任务目录/历史/搜索 | pin/unpin/rename/delete/batch/archive/search资产及文案 | 列表行、卡片尺寸、菜单触发形态 |
| ChatPage/消息流 | 类名、会话路径、processGroup/answer/attachmentGroup/artifactGroup等枚举 | 顶栏/正文宽度、消息排版、折叠与滚动触发策略 |
| 输入区 | 加号、附件、语音、模型、盾牌、发送/停止、最大化资产 | 同屏位置、尺寸、切换时序、键盘布局 |
| 短选择/执行位置 | ModelSheet、AttachmentSheet、HomeRunLocationSheet、LocalDeviceManageSheet等名字 | 实际Sheet高度、拖动柄、蒙层、转场与关闭后恢复 |
| 任务过程/产物 | 状态图标、工具类型、ArtifactFileSheet、preview各格式路径 | 同屏构图、手机全屏预览、宽屏分栏及保存控件 |
| 发现/频道/自动化 | connector/expert/skill/project/knowledge、团队路径、TaskFormSheet等 | 页面卡片/筛选/详情的实际布局 |
| 我的/设置/登录 | font-size/memory/privacy/storage/voice/my-shares/about等路径与LoginSheet | 页面分组、开关、表单、协议区；海报不证明登录布局 |

F06有46行组件名；F07混有API/路由，不能按路径数计算页面。F14/F15/F16是常量表，不是屏幕测量：间距存在2/6/10/14，圆角含0.5/1.5/5/7/9/15.5/27，行高也含小数；不能概括成全部4倍数、全部取整或直接映射到Android dp/sp。

## Flutter宿主与Compose实验的实际落点

产品源码位于 `apps/muyon/`，Android宿主不是独立Compose应用。初次历史只读盘点的 `/workspace/Muyon` 是 `work@cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`；后续活动integration会由其owner继续推进，不能把本报告当作冻结writer。

| 源码位置 | 当前职责/页面 | 边界 |
|---|---|---|
| apps/muyon/android/app/src/main/kotlin/com/mightyoung/muyon/MainActivity.kt | FlutterActivity、系统凭据MethodChannel/AndroidKeyStore适配 | 不是Kotlin页面；不因视觉参考改凭据行为 |
| apps/muyon/android/app/build.gradle.kts、AndroidManifest.xml | com.mightyoung.muyon、Flutter Gradle、Java/Kotlin17、adjustResize、Muyon名称 | 没有独立Compose app装配 |
| apps/muyon/lib/app/app_shell.dart、screens/platform_shell*.dart | 初次cc7c8d盘点为工作台/助手/资料/我的；3836149基线已为助手/任务/资料/设置，见追加分片 | Flutter页面历史版本须区分，不是WorkBuddy已还原页面 |
| screens/assistant_page.dart、execution_panel.dart、chat/ | 助手、执行卡片、对话入口/目录/线程/消息泡泡 | 绑定原有业务与真实授权状态 |
| screens/其它文件 | MemoryPage、DevicesPage、McpServersPage、DataStoragePage、DataFlowPage、KnowledgePreview、ExperienceSection、DreamSection | 源码存在不代表Android逐页已验 |
| packages/inquiry_module、research_module、prototype_module | 询价/报价/比较/规格/项目/目录/AI审阅/交换、阅读/关系/写作、原型页面等 | 保留业务合同，不因外观擅自改功能 |
| packages/muyon_ui/lib/src/{tokens,theme,motion}.dart | 明暗色、间距、圆角、主题、动效 | 未来视觉候选改动点，本轮未动共享包 |
| experiments/redesign/device-deferred/android-mock/ | RD-P04 SupplierScreen/Presenter，列表/详情/编辑/确认/冲突/未知等投影 | Compose源码排除于stdlib JVM测试；compile/render/Android NOT_RUN |
| experiments/redesign/device-deferred/operable-supplier-flow/android/ | RD-P08 SupplierPage/List/Detail/Editor/Status，SupplierScreenModel与投影检查 | SOURCE ONLY；没有Compose宿主/native transport/device验收 |
| experiments/redesign/device-deferred/core-port-lab/jvm-adapter/ | Port/Controller/Driver/Json/Presentation | 协议与投影实验，无完整页面 |
| experiments/redesign/spike01-native-lab/android-probe/Probe.kt | UniFFI/JNA探针 | JVM/native实验，不是Android Activity |

integration盘点含18个Kotlin文件（含宿主、测试和探针）。Muyon自有品牌素材在 `apps/muyon/assets/brand/`；现有字体及OFL文件在 `apps/muyon/assets/fonts/`。JVM测试、网页手机viewport和Linux native load均不能替代Android运行验收。

## 资源复用矩阵与工具缺口

本轮 `command -v` 未发现rea/jadx/jadx-cli/jadx-headless-mcp/apktool/aapt/aapt2/apksigner/blutter；仅unzip/fc-scan存在。对 `/workspace /tmp /opt /usr/local /home/agent` 按APK/XAPK/APKS及相关工具文件名查找无结果；可用工具目录也没有REA/decompiler能力。不能从历史报告路径推断原APK实存，未从未知镜像下载/安装。

| 资源 | 可用证据与参考 | 直接复用条件/当前结论 |
|---|---|---|
| 字体/字形 | F09的MaterialIcons、AlimamaShuHeiTi Bold、KaTeX族名/路径 | 没有原字体/NOTICE/LICENSE或适用授权，不能仅凭名字复用；优先既有Muyon字体/系统字体 |
| 图标 | 图标名称和一张拼图，可观察线形/视觉重量 | 没有完整SVG和明确许可；本地审查、自绘等价图标，不裁拼图入产品 |
| 插画/海报 | 10 PNG内明暗资源可直接查看 | 许可未明，不复制竞品机器人；沿用自有素材/自绘 |
| 明暗主题/颜色 | 静态颜色常量及light/dark资源 | 仅作候选视觉值，常量混第三方且无调用点；不能假定运行时token映射 |
| 字号/尺寸 | TextStyle/EdgeInsets/Radius表 | 无页面调用点/density/缩放，须真实原图核对后用自有代码实现 |
| Flutter assets/布局 | 资产、类名、枚举和路由 | 无完整Widget树/布局约束；不能直接复用完整布局，也不复制反编译业务源码 |

若继续要求原包核验/直接复用，需补充与预期APK哈希匹配的原包，以及覆盖具体文件/版本和预期用途的许可/授权证据。现有资源可读取与有hash不等于可移入产品。

## 最小原图需求与下一步

在恢复像素还原前，需要同一版本/设备设置的原始PNG，未经缩放裁剪，并注明App版本/build、屏幕px/density、系统显示/字体缩放、明暗主题、导航模式、页面/触发步骤。可提供已有脱敏截图；不因此授权登录真实账号/调用在线模型。若沿用“不做动态观察”，只用提供的已有原图。

首批：任务列表默认态及有内容行；对话空态/已有对话与完整输入区；键盘收起/弹起；同一对话生成/可停止与完成状态；模型/附件/运行位置三个弹层；产物卡与一种完整预览；搜索/历史；我的/设置。若覆盖发现、频道、自动化，各页也须原图。优先浅色主流程；暗色至少补同一列表、对话和一个弹层。没有图的状态保留Muyon真实合同表示并标注未视觉核对。

暂停的是“按真实页面像素复原/完全一致”的实现与验收声明。可继续只读映射、素材台账；不把推测、重建图或未入库渲染当真实截图。Rust内核、授权、防重复、回执、未知先核对和撤权语义均不随视觉参考改变。

## 本轮交付与验证

完整临时审查报告：`/tmp/rd-workbuddy-android-ui-20261015/inventory.md`；同目录含reference-manifest.json、SHA256SUMS、pr69-identity.json、source-inventory.json及固定证据副本。原始图像/manifest仅临时目录审查，不随此文档提交。

完成固定提交tree/show、SHA-256副本校验32/32、10 PNG完整解码与逐张查看、源路径/类/Compose函数清单核查。本文档提交仅新增本文件；无产品代码变动，不声称Android已编译/运行或像素已对齐。剩余阻塞是真实页面原图；原包/工具/明确许可仅在继续资源核验或直接复用时需要。

## 追加：Drive候选已实际尝试，停止在安全警告

用户授权文件夹 `https://drive.google.com/drive/folders/1ifCHLvXiRAThyWUyCb6FbP8CfvKjnrVi`。主线程列出的 `base (2).apk` 候选293687392字节与既有manifest同大小，ID为 `12u0R5_dyUPamFlX2VSQUX8Wg6G8-cQWh`；大小一致不等于身份验证。连接器413对应268435456字节单文件上限，不是访问权限拒绝。

本轮已对候选正常公开view页、`drive.usercontent.google.com/download?id=12u0R5_dyUPamFlX2VSQUX8Wg6G8-cQWh&export=download`执行未经认证的正常GET，无cookie/凭据/确认token。两者HTTP200，但都是HTML；下载入口返回2552字节，实际可见安全警告“**This file is too large for Google to scan for viruses.**”，并要求Download anyway确认。

依照明确的“遇安全警告不绕过”要求，本轮没有提交该表单、构造confirm-token请求或尝试绕过入口。**APK尚未下载，SHA-256/包名/版本未从原包核验，资源ZIP/字体许可未检查。**这不是自动审批拒绝，也不能再笼统归因“Drive没权限”。进一步原包检查需用户先处理正常Drive安全确认并提供已批准的可读文件/交付方式；不因此暂停现有页面清单。

实际请求与可见提示证据在独立临时报告的 `drive-review/public-download-attempts.json`、`security-warning.json`；无凭据原值或隐藏表单字段。原先只读结论仍成立：已有10张资源PNG不是完整页面截图；REA未提供且未使用；许可未明资源不直接复制。

## 追加：页面/组件/状态实施分片（仅文档）


2026-10-15追加。范围仅UI线文档与只读映射；不扩大APK/REA线，不等待core/plugin研究才产出UI清单。没有再次请求Drive下载、提交安全确认或安装工具；产品代码未修改。

## 证据标记与使用规则

- `directpixel`：仅指已逐张查看的10张资源PNG的像素；可判断资源形状、资源尺寸和配色。**没有任何页面获此标签。**机器人海报、图标拼图不能提升为完整页面/状态截图。
- `静态线索`：固定WorkBuddy提交 `dca32eebd723e5a4e577cb63a39bea1f8588fd04` 中的资源名、类名、路由、文案、常量/枚举。只证明字符串/资产存在，不证明调用点与页面组合。
- `未知`：页面位置、顺序、尺寸、真实交互、主题映射、字体分配或适用许可未证实，等待原图/明确证据。
- `Muyon源码`：已有实现事实，来源于现有只读文件；不能宣称为WorkBuddy事实。下文组件名均为既有符号或明确写作“候选组件”，没有新建产品接口/状态。

## 主流程分片清单

以下路径相对仓库根。分片是后续实施边界，**本轮已完成的是证据/映射文档，不是这些产品分片的实现**。Flutter路径是现有产品接触点，Compose路径是未来原生实验接触点，二者不暗示本轮改变技术路线。各片完成视觉实现前均需对应真实原图。

本追加以主线程指定产品基线 `3836149416020a0ac58f9e7ca788c20e66688e0e` 的源码为准：壳内页面为助手/任务/资料/设置，`taskHub()`承接任务入口；初次盘点 `/workspace/Muyon@cc7c8d14...` 的工作台/助手/资料/我的四入口仅属旧版本记录。不能混用两版方法名或把旧版当当前布局。

| 分片 / 页面 | 组件与状态清单 | WorkBuddy证据标签 | 现有Muyon/Android落点 | 现在可独立完成 / 真实像素阻塞 |
|---|---|---|---|---|
| UI-00 参考台账 | 10资源、32证据文件、图像类别/许可/原图缺口；原图与截图版本关联 | `directpixel`仅资源；完整页面`未知` | 独立/tmp报告；本docs文件 | 已完成哈希/像素/类型核验；可接收原图后绑定页ID，不能以拼图补页 |
| UI-01 基础视觉候选 | 明/暗画布、层级文字、强调/警告、字号/行高、边距/圆角；默认/暗色/字体放大 | `directpixel`图标与资源明暗；F14/15/16`静态线索`；组件token映射`未知` | `packages/muyon_ui/lib/src/{tokens,theme,motion}.dart`；`apps/muyon/assets/brand/`；Android `res/values{,-night}/styles.xml` | 可列候选与现有token差异、保留自有资产；精确配色分配/字体/尺寸待同页明暗原图。不得先改共享UI包影响其他writer |
| UI-02 任务入口与目录 | 顶栏、导航、任务行、搜索入口、更多菜单、空态；有内容/空/选中/加载/失败 | F08 tabs/drawer/search资产、F11文案为`静态线索`；顺序/卡片/顶底栏`未知` | `screens/platform_shell.dart` 的`ConversationDestination`；`platform_shell_home.dart` 的`taskHub()`/`tasks()`；`chat/chat_list_page.dart` | 可清点稳定任务/会话ID与已有导航回调；默认页、5入口组合、任务行构图待首页/列表/菜单原图。不根据5个图标强加频道/自动化功能 |
| UI-03 对话与过程 | 顶栏、用户/助手内容、过程组、步骤卡、任务状态、引用、附件/产物组、操作行；空/准备/运行/待确认/完成/失败/暂停/取消中/中断 | ChatPage、F17块/滚动枚举、F11文案为`静态线索`；块间距、气泡、折叠/跟随阈值`未知` | `screens/assistant_page.dart` 的`AssistantPage`；`execution_panel.dart` 的`ExecutionPanel`/`_TaskCard`；`chat/chat_thread_page.dart` 的`_Bubble` | 可按现有状态列展示字段/动作表；保持`ObjectRef`回访和任务ID。原图决定排版/过程折叠/滚动提示；不把资源名当流式行为已复刻 |
| UI-04 输入区 | 原始输入、模型、附件/本地工具、语音入口、权限标记、发送/停止候选、最大化候选；空文本/输入中/准备中/组字/键盘起落/忙/不可用 | F08 input-*图标`静态线索`；拼图的形状`directpixel`；排列/共用按钮时序/高度`未知` | `assistant_page.dart` 的`_input`/`_profileId`/`_busy`/`_send()`/`_tool()`；`screens/platform_shell_personal.dart`模型选择 | 可记录已有回调与disabled来源，区分发送准备与真实执行。键盘、IME、输入区尺寸/控件位置待原图；不凭图标增加未支持语音/附件能力 |
| UI-05 选择弹层 | 模型、附件来源、执行位置、范围候选：标题、选项、选中、取消、空/不可用/加载 | F06各Sheet名为`静态线索`；实际Sheet样式/高度/拖动柄`未知` | 现`assistant_page.dart`及`platform_shell_personal.dart`使用Dialog/选择器；`devices_page.dart`仅现有设备能力 | 可列模型profile与真实执行位置数据来源；不默认所有Dialog改BottomSheet。待3个完整弹层原图；电脑/云端资产不授予跨设备执行 |
| UI-06 授权与结果 | 权限范围摘要、确认正文、允许/拒绝/取消、撤权后显示、历史/当前回执、结果未知核对 | shield图形`directpixel`；standard/fullAccess/confirmThenApply名为`静态线索`；权限语义/绑定`未知` | `assistant_page.dart`的`_confirm()`与agent回调；`screens/data_flow_page.dart`；现有Rust/宿主授权边界只读 | 可列哪些文字消费宿主事实、哪些动作必须走原回调；UI不新造grant/receipt。盾牌和确认卡样式待原图；绝不把“完全访问”外观映射为Muyon授权变化 |
| UI-07 产物与预览 | 产物行/卡、类型图标、标题/版本、加载/错误/可打开/历史、预览顶栏/返回/分享候选 | F07 preview路径、F06 ArtifactFileSheet、F08文件图标为`静态线索`；完整预览布局`未知` | `screens/knowledge_preview.dart`的`KnowledgePreview`；`platform_shell.dart`打开记录/资料与`ObjectRef`回调；`packages/prototype_module/lib/src/prototype_screens.dart` | 可列现支持PDF/图片/有界文本及错误/等待展示；WorkBuddy代码/diff/视频路径不等于Muyon已支持。待产物卡+预览页原图，不自动加导出/分享副作用 |
| UI-08 我的/设置 | 入口行、分组标题、模型配置、个人资料、记忆、存储、主题/减少动效；正常/空/编辑/确认/失败 | F07 settings、mine、memory路由为`静态线索`；分组/开关/列表布局`未知` | `platform_shell.dart`的`mine()`；`platform_shell_personal.dart`的`personal()`/`settings()`；`memory_page.dart`、`data_storage_page.dart` | 可列现有设置绑定和授权来源；会员/积分/运营能力不因视觉引用加入。待我的/设置/记忆原图，保存行为保留原实现 |
| UI-09 搜索/历史/回访 | 搜索输入、结果行、空/失败、原对象定位、历史标记、归档候选 | F07 search路径、F08 drawer/search/archive、F11空文案为`静态线索`；实际搜索页`未知` | `platform_shell_knowledge.dart`的`knowledge()`及查找业务对象；`platform_shell_home.dart`会话回访；`chat_list_page.dart` | 可列各入口返回的稳定引用与回退路径；不能假定业务对象搜索等于全局任务搜索。待任务历史/搜索页原图，跨域查询范围不扩大 |
| UI-10 自有业务页适配 | 供应商列表/详情/编辑、当前值/原草稿/预览/历史回执、取消确认；partial/unavailable/editing/prepared/saving/conflict/unknown/rejected/saved | WorkBuddy无供应商页面，属于`未知`，不能宣称复刻对应页 | RD-P08 `operable-supplier-flow/android/{SupplierPage,SupplierScreenModel}.kt`的LIST/DETAIL/EDITOR；产品`packages/inquiry_module/lib/src/features/` | 可按原状态列同一基础视觉的组件映射；不碰Rust合同/原始UTF-16/回执绑定。Compose仅源码未编译运行；字体放大/IME/TalkBack仍需后续真实验收 |
| UI-11 发现/频道/自动化/登录 | 各入口、能力卡/团队行/任务表单/登录表单候选 | 资产/路由/Sheet名`静态线索`；登录海报`directpixel`仅插画；全页`未知` | 未发现等价完整WorkBuddy功能页；现有`McpServersPage`/设备/科研工具也不能自动等同竞品页面 | 可记录功能适用差距与原图需求；没有原图和业务授权时不建假入口、假账号页或复制品牌海报 |

## 状态与动作绑定：不得按竞品名称强行对齐

| 状态来源 | 已有事实 | 后续UI允许表示 | 禁止的推定 |
|---|---|---|---|
| `FoundationRepository.PersonalTaskState` | queued/waitingConfirmation/running/succeeded/failed/cancelled/paused/interrupted | 直接消费原任务状态、stage、waitingFor、error、summary、executionDeviceId、references | 枚举没有unknown；不能从枚举推断外部执行结果；现有ExecutionPanel已显示interrupted未知警示，必须保留，不靠视觉增加枚举 |
| `AssistantPage._busy` | 发送准备过程的页面本地标志 | 禁重复触发准备、显示已有“准备中”；在状态表明确区别执行状态 | `_busy=false`不能证明任务完成/外部动作停止 |
| `ExecutionPanel._TaskCard` | 取消/暂停/恢复由任务状态及platform owner决定；stage=cancelling另判 | 沿用onCancel/onPause/onResume/onOpenObject回调和原guard | 不为显示停止图标绕过guard；请求取消不等于已取消 |
| RD-P08 `SupplierScreenModel` | `canSave`要求prepared+preview+同步草稿且无未决；`canLookup`核对原操作；saved要求真实receipt | 展示当前读值和原历史回执，unknown保留原草稿/会话；只核对原操作 | 不把prepared当已保存；不自动重发；不将旧回执当当前版本 |
| WorkBuddy F17 | 存在dispatchAmbiguous、reconcilePending、streamingFollow等枚举名 | 仅作为待观察的视觉/流程问题清单 | 不据此证明其服务端幂等、滚动实现或Muyon已有同名能力 |

候选组件如导航项、任务行、状态徽标、过程组、输入工具条、选择行、预览顶栏、设置组，后续应先绑定已批准的单页原图和现有回调再实现。组件样式不能代替权限判定；缺状态时先报合同缺口，不由UI writer改核心。

## 可实施与阻塞边界

**当前可独立交付：**UI-00台账、UI-01候选token差异表、UI-02至UI-10的页面/状态/回调映射、本页分片清单、原图接收模板。已完成的文档本身不依赖APK或core/plugin新增结果；也不因此获得修改产品代码的授权。

**获得对应原图后可提请具体实施：**以UI-02任务列表、UI-03/04对话输入、UI-05三个弹层、UI-07产物预览、UI-08设置为顺序，一片一次交付可查看结果。每片评审包须包含原图版本/设备、目标组件、未覆盖状态、实际渲染图和对比结论；原图参考尺寸与Muyon无障碍适配分开记录。没有实测渲染就不标“像素一致”。

**仍阻塞：**真实完整页面像素；资源许可；若继续原包解析，Drive大文件安全确认与工具缺失。三路并行不是批准Download anyway或REA安装，本轮未触及它们。独立UI owner只改本docs和/tmp审查材料，不接管/挪动core writer，品牌与自有素材不变。

## 追加：UI首片规格与实施准备计划（不改产品）

本追加延续UI owner，固定基线3836149，运行测试保持NOT_RUN；完整JSON台账位于独立/tmp。

# UI首片规格：当前导航、任务状态与自有素材验收基线

2026-10-15。UI独立owner续接；源码基线 `3836149416020a0ac58f9e7ca788c20e66688e0e`，先前UI准备提交 `68211a2af35a605decae5fdd5b92875d30742c26`。本规格对应UI-00/UI-02的实施准备，引用UI-01自有素材和UI-03状态边界；不等待core/plugin研究，也不接管其目录。

## 目标与交付边界

首片先固定后续视觉改造必须保持的真实行为和验收入口，使工程师不依赖WorkBuddy原图也能准备回归与素材台账。**当前交付为spec/plan/静态清单；没有更改或运行产品。**不新建视觉风格、不复制竞品资源、不改变四入口顺序/业务权限，不运行Android、安装REA、重试APK下载或提交Drive安全确认。

首片行为验收与后续像素验收分别记录：widget回归可以在离线合成夹具中执行，WorkBuddy像素验收仍需要同版本完整原图；前者通过不意味着后者通过。

## 固定行为（Muyon源码事实，不是WorkBuddy页面推断）

| ID | 精确规格 | 现有符号/文件 |
|---|---|---|
| B01 | 默认入口索引0；顺序严格为助手、任务、资料、设置；不加第五项或运营入口 | `screens/platform_shell.dart`：`ConversationDestination`、`section=0` |
| B02 | 宽度以`MediaQuery.sizeOf(context).width`判断：<900用NavigationBar，≥900用NavigationRail；不把内部LayoutBuilder宽度误当全窗宽 | 同文件`desktop`、`showSection(int value)` |
| B03 | 四页由同一IndexedStack承载；非当前页ExcludeFocus、TickerMode disabled；助手实例、未发送草稿、选中模型、滚动位置在切页/390↔1280变化后保留；切页不派发任务/工具 | 同文件`KeyedSubtree(ValueKey(ConversationDestination.values[i]))`；`AssistantPage`已有控制器/草稿持久化 |
| B04 | 返回关闭当前工作区，再回原助手；不重复挂载workspace或丢原焦点；导航项selected语义正确，触摸目标≥48×48逻辑像素 | `ConversationWorkspaceHost`、`conversation_shell_accessibility_test.dart`的既有断言 |
| B05 | 任务入口是`taskHub()`；快捷入口为执行面板、消息中心、数据交换；任务点击使用原`conversationId`打开任务对话；不根据名称复制/合并对象 | `platform_shell_home.dart`：`taskHub()`、`tasks()`；`platform_shell.dart`：`assistant(...)` |
| B06 | `ExecutionPanel`只显示宿主提供的prompt/state/stage/device/wait/error/summary/ObjectRef；事件仍走传入回调 | `ExecutionPanel({tasks,onCancel,onPause,onResume,onOpenObject})`，回调类型分别`Future<void> Function(PersonalTask)`和`void Function(ObjectRef)` |
| B07 | 明/暗与减少动效读取现有设置；Noto Sans SC及自有品牌引用保持；没有竞品字体/图像进入资源表 | `MuyonApp`、`packages/muyon_ui/lib/src/theme.dart`、pubspec；theme/reduce-motion既有用例 |

不把布局相似当行为授权。现有`showSection`返回原焦点、`action`忙态防重入、`AssistantPage._send`草稿检查都保留，不由视觉组件替代宿主事实。

## 任务状态与动作基线

表格针对`ExecutionPanel._TaskCard`，不概括其它任务表。`PersonalTask.terminal`在该基线含succeeded/failed/cancelled/paused/interrupted；不能把paused当正在运行。

| 状态 | 当前文案 | 可见动作（非platform owner、非cancelling） |
|---|---|---|
| queued | 排队中 | 取消 |
| waitingConfirmation | 等待你确认 | 取消、暂停 |
| running | 执行中 | 取消 |
| succeeded | 已完成 | 无 |
| failed | 失败 | 恢复（再次确认） |
| cancelled | 已取消 | 无 |
| paused | 已暂停 | 恢复（再次确认） |
| interrupted | 已中断（结果未知）；另显示“结果未知，重试前请先核实。” | 恢复（再次确认），不自动重试 |

补充优先级：`owner=platform`不提供逐项取消/暂停/恢复；`stage=cancelling`且未terminal显示“取消中…”并移除第二次取消；回调必须收到原任务对象/ID，ObjectRef回调保持原引用。

**状态表精度修正：**枚举没有名为unknown的值，但当前`ExecutionPanel`已明确把interrupted显示为“结果未知”警示，且有既有测试固定。上一轮“不能把interrupted等同未知”仅应理解为不能凭枚举新增独立unknown/推断外部执行事实；**不能据此删改当前未知警示或恢复再确认流程。**

**现有两处guard不同：**`taskHub.tasks()`更多菜单对所有非terminal任务列暂停/取消；`ExecutionPanel`仅waitingConfirmation列暂停，且额外处理cancelling。此处只是记录两处事实；首片不统一规则、不扩大按钮权限，若视觉提取跨两处共享组件，需先提出具体行为合同差异，禁止顺手改core。

## 自有素材与当前引用

| 资源 | 实测像素/字节 | SHA-256与引用边界 |
|---|---|---|
| assets/brand/header-mark-v3.png | 256×256 RGBA，43470B | `a1c6224ed91e221153b16eb56538a4f4533a96f06fd014f27e3987fa2a7b1f93`；pubspec assets已声明 |
| assets/brand/launcher-master-v3.png | 1254×1254 RGBA，1246085B | `0ccadcf7e661a95eb7a8e548670a89270b03ec89b8c351ea2ed27df291cb72bc`；源素材存在，不能称当前widget已引用 |
| assets/brand/mark-v3.png | 1254×1254 RGBA，416500B | `809de63a91dc2bc85378df97a4f2a1ae2cc6c120c86a9775700577da3f78caa5`；源素材存在，不能称当前widget已引用 |
| assets/fonts/NotoSansSC-VF.ttf | 17773132B | `d68bafcb48a2707749396aa12bbbd833cb70401f3a9a689fd2902c7e0d295964`；pubspec的Noto Sans SC字体族与theme已引用 |
| assets/fonts/OFL.txt | 4301B | `6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2`；仓库既有许可文本，非竞品字体许可证明 |

这五项只做现有文件身份与引用核验；本轮不改素材、颜色或字体。WorkBuddy10资源的`directpixel`标签仅是参考证据，不进入此自有资产清单。

## 独立可测试范围与现成用例

下列**仅核对源码中的用例存在和断言，未在本轮执行Flutter/widget测试**。夹具只应使用隔离临时数据；已有NavigationFixture会创建本地合成SQLite/注册页，不是纯mock，也不代表Android真机。不要使用用户业务目录或真实模型端点。

| 验收 | 可复用文件/精确用例 | 本片补充或限制 |
|---|---|---|
| 默认/四入口与字体放大 | `responsive_shell_test.dart`：`assistant_is_default_and_four_destinations_are_exact`；参数化`four_destinations_320_390_430_900_1250_1280_at_200_percent` | 已覆盖6种宽度与2倍文字；尚未单独锁899边缘，后续仅在改断点/壳结构时补899/900断言 |
| 草稿/模型/滚动/实例保留 | `conversation_shell_navigation_test.dart`：`switching_destinations_keeps_unsent_parent_draft_and_scroll` | 已断言任务/工具/消息计数不增加；不点发送/暂停/恢复 |
| 返回与引用回访 | 同文件`root_back_closes_workspace_before_exit`、`data_and_answer_open_same_registered_business_page` | 只验证原导航与原注册页，不调用外部模型 |
| 触摸/焦点/选中语义 | `conversation_shell_accessibility_test.dart`：`navigation_workspace_and_back_have_48_targets_and_selected_semantics`、`keyboard_focus_returns_to_source_node` | widget语义测试不是TalkBack/IME实机；不在本轮扩为设备验收 |
| 状态/取消中/平台owner/原对象回调 | `execution_panel_test.dart`：`actions follow the actual task state`、`a cancel request in flight shows 取消中… and no second cancel`、`interrupted states say the outcome is unknown`、`platform-owned tasks offer no per-item actions`、`buttons call back with the exact task` | 当前动作表未单列running，但canceling用例使用running；若改卡片再补running普通态、platform+cancelling组合，当前不为文档添加镜像实现测试 |
| 主题/动效 | `theme_persistence_test.dart`三个用例；`reduce_motion_readback_test.dart`两用例 | 只表示设置持久化/读回，不能证明WorkBuddy主题映射或实际逐像素外观 |

已有命令模板在应用目录：`flutter test --no-pub test/responsive_shell_test.dart test/conversation_shell_navigation_test.dart test/conversation_shell_accessibility_test.dart test/execution_panel_test.dart test/theme_persistence_test.dart test/reduce_motion_readback_test.dart`。仅在已有可信Flutter SDK/解析配置/离线依赖均可用、所有写入定位到批准的/tmp后执行；**本轮没有启动此命令**。当前PATH没有flutter/dart，`/workspace/flutter-sdk`目录存在不等于可无写入调用；不能为跑准备文档测试自动升级/安装依赖。

独立验收的预期为命令退出0、所有选定用例通过、无widget异常、无任务/工具额外派发；测试进程如缺缓存/配置应记录阻塞，不将未执行改成通过。真实Android键盘/TalkBack/旋转、完整WorkBuddy像素、未见状态视觉、资源许可不在此命令证明范围。

## 进入产品视觉首片前的具体输入

只需要UI-02目标页的原图：同一目标版本、完整顶/底栏、默认/有内容任务列表，以及设备px/density/字体缩放/主题。先交单页组件布局方案，写明映射现有导航/任务回调，新增外观只来自该原图；保留上述B01–B07及状态guard。无原图时此规格已可独立审查，产品视觉更改仍不开始。

# UI首片验收基线 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execution remains with the existing UI owner; no subagents are authorized by this plan.

**Goal:** 在修改视觉之前固定当前导航、状态动作、自有素材与离线回归入口，给单页高保真实施一个可检查的起点。

**Architecture:** 沿用现有Flutter宿主与组件接口；本阶段只补文档和/tmp台账，复用已有widget测试。WorkBuddy资源证据、Muyon行为基线、后续真实页面像素分别登记，不引入产品适配层或状态协议。

**Tech Stack:** 既有Flutter/Dart源码与flutter_test；本轮静态核验用Python标准库/Pillow和git只读命令，不新增依赖，不运行Android。

**Spec:** `/tmp/rd-workbuddy-android-ui-20261015/first-slice-spec.md`，同时纳入`docs/tasks/WORKBUDDY-ANDROID-UI-INVENTORY-20261015.md`的追加首片章节。

## Global Constraints

- 源码基线`3836149416020a0ac58f9e7ca788c20e66688e0e`；承接UI准备提交`68211a2af35a605decae5fdd5b92875d30742c26`。
- 仅原UI owner/clone/branch；root sole pusher；不改core/plugin目录或其它writer。
- 当前授权为独立实现准备；本阶段不改产品代码、共享token/字体/图片，不开始视觉实现。
- 默认助手；顺序助手/任务/资料/设置；断点900逻辑像素；保留B01–B07与既有状态guard。
- 不重试Drive确认、不安装REA、不运行Android；不复制竞品APK/字体/插画/源码。

## Review Focus

1. 899/900边缘：现有参数化用例覆盖900但未覆盖899；未来改壳时应同时断言bar/rail切换且实例/草稿不丢，归Task2。
2. 小屏320且2倍文字：沿用现有responsive用例，不凭正常390截图判定可用，归Task2。
3. interrupted有未知警示：枚举无unknown不意味着可删现有警示，复用execution_panel精确用例，归Task2。
4. platform owner与取消中组合：当前单独用例已存在，未来改卡片时再补组合，归Task2；未执行前不声称覆盖。
5. 资产存在与实际引用：header/font已声明，另外两张品牌源素材未声明；清单必须分别记录，归Task1。

### Task 1: 固定当前入口/接口/自有资源台账（本轮准备）

**Files:** 只读`apps/muyon/lib/screens/{platform_shell,platform_shell_home,execution_panel}.dart`、`apps/muyon/lib/platform/foundation_repository.dart`、`apps/muyon/pubspec.yaml`与既有brand/font；创建`/tmp/rd-workbuddy-android-ui-20261015/first-slice-baseline.json`。

**Interfaces:** Consumes固定git blob和现有组件签名；Produces JSON包含source_base、source_files(path/sha256)、destinations、breakpoint_logical_width、assets(path/sha256/size/declared)、runtime_tests_status。

- [x] 逐文件核对与固定基线字节相同，记录SHA-256；不是只读当前活动branch名。
- [x] 记录4入口、断点900、taskHub及ExecutionPanel回调签名；不创建新组件。
- [x] 完整解码3张自有PNG，记录5项资源身份与pubspec声明区别。
- [x] 用JSON结构和固定源码断言校验台账；任何不符停止提交并修正文档，不改产品来迎合台账。

### Task 2: 固定可复用回归入口与未覆盖项（本轮准备；运行留后续）

**Files:** 只读spec所列6个`apps/muyon/test/*.dart`和support夹具；更新同一/tmp JSON的existing_tests与not_run。

**Interfaces:** Consumes原测试源码/夹具；Produces测试文件、精确用例、覆盖目的、当前执行状态；没有新的测试API。

- [x] 核验spec列的用例名和关键断言真实存在，记录文件hash；不能从文件名推断测试覆盖。
- [x] 写明6套widget测试的离线命令与/tmp写入前置条件；本轮状态设`NOT_RUN`。
- [x] 标注899/900普通边缘、running普通态及platform+cancelling组合仅在后续相应产品改动时补；复用现有320/2倍文字/interrupted/owner/回调用例，避免为文档写镜像测试。
- [ ] 后续执行者若只跑已有回归：先核现有SDK/配置/离线缓存，不安装/联网取包；在独立/tmp环境运行spec命令并保存完整退出码/测试汇总。没有环境则报告阻塞，不改`NOT_RUN`为通过。

### Task 3: 单页实施交接与文档验证（本轮准备）

**Files:** 修改仅`docs/tasks/WORKBUDDY-ANDROID-UI-INVENTORY-20261015.md`；本地spec/plan/JSON留/tmp。保留先前32参考文件与10资源证据。

**Interfaces:** Consumes Task1/2台账及spec B01–B07；Produces docs-only提交和完整SHA给root，不push。

- [x] 自审精确状态：当前ExecutionPanel的interrupted未知警示保留；两处暂停guard差异不在视觉片中统一。
- [x] 将首片spec与plan纳入既有来源文档，保持先前68211a2内容与证据来源历史可追溯；只补明确的状态表解释。
- [ ] 验证`git diff --check`、base→HEAD仅一个docs文件，JSON/source/asset/test引用逐项通过；不以此冒称widget/Android运行通过。
- [ ] docs提交后给root完整SHA、报告和NOT_RUN清单；root负责推送/草稿。没有原图的视觉实现继续保留输入门槛，本计划不触发额外用户确认或安装。

## 自审与后续视觉片范围

Task1覆盖B01/B02/B05/B06/B07，Task2覆盖B03/B04及状态/主题/无派发回归入口，Task3核可评审交付与授权边界。原图像素、未见页面状态、TalkBack/IME设备测试和竞品素材许可明确不在本首片通过范围。后续视觉片先只做UI-02任务列表，组件结构/尺寸来自完整原图，行为接口仍取本spec；原图前不引入猜测布局。
