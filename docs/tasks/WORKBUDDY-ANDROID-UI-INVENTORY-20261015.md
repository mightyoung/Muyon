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

当前产品源码位于 `apps/muyon/`，Android宿主不是独立Compose应用。只读盘点的 `/workspace/Muyon` 是 `work@cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`；后续活动integration会由其owner继续推进，不能把本报告当作冻结writer。

| 源码位置 | 当前职责/页面 | 边界 |
|---|---|---|
| apps/muyon/android/app/src/main/kotlin/com/mightyoung/muyon/MainActivity.kt | FlutterActivity、系统凭据MethodChannel/AndroidKeyStore适配 | 不是Kotlin页面；不因视觉参考改凭据行为 |
| apps/muyon/android/app/build.gradle.kts、AndroidManifest.xml | com.mightyoung.muyon、Flutter Gradle、Java/Kotlin17、adjustResize、Muyon名称 | 没有独立Compose app装配 |
| apps/muyon/lib/app/app_shell.dart、screens/platform_shell*.dart | 工作台/助手/资料/我的；窄屏底栏、宽屏侧栏和可选侧面板 | 现有Flutter页面，不是WorkBuddy已还原页面 |
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
