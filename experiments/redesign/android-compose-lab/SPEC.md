# Android Compose 首片：离线导航与展示骨架

基线`31b9b6fc1f7f8b27952533ca141e901676ba90e8`；UI原owner独立实现，唯一写入目录`experiments/redesign/android-compose-lab/`。承接已批准12切片与首片行为规格，后续Android为Kotlin/Compose、桌面Electron；不新增Dart或改Rust/plugin owner文件。

## 本片决定

1. 独立实验app，不替换旧Flutter宿主。首入口助手，固定助手/任务/资料/设置；<900dp底栏，≥900dp侧栏。骨架仅功能占位，非WorkBuddy页面像素复刻。
2. 纯Kotlin不可变`ShellState`持有四页的raw draft、首可见item/offset、最后输入焦点标记；切页/断点切换不清空。Compose滚动对象和FocusRequester由壳统一持有。只承诺内存生命周期，进程死亡/配置持久化未实现。
3. `RustUiPort`只暴露未连接能力，默认`DisconnectedRustUiPort`。本片没有发送、取消、授权、模型、凭据、网络、native加载或真实任务数据；不设计产品DTO或冻结M03。任务/资料页真实显示“执行服务未连接”，没有合成业务结果冒充实证。
4. 纯展示安全文案保留8态含interrupted未知警示；cancelling不显示成功；platform owner提示回设备页。合成状态只在单元检查中使用，不写生产数据、不调用动作。
5. 用现有Java21 runtime+官方Kotlin2.2.20（仅/tmp安装，官方SHA核验）实际编译运行完整状态检查。Compose Android Gradle工程和可运行CI命令同时提供；缺Gradle/SDK时明确编译/渲染/Android运行NOT_RUN，不用JVM测试冒充。

## 验收

- 四入口顺序/默认、899/900边界、无效宽度拒绝、raw UTF-16草稿不trim/normalize、切页后焦点/滚动记忆、不可变状态互不污染、断开port、unknown/cancelling/platform提示均有JVM检查。
- 当前只有本片标准库状态检查需要在本环境通过；Gradle app编译、Compose行为/触摸语义/IME/TalkBack/旋转和像素核对分别记录。
- 不带WorkBuddy APK/字体/图标/插画；Muyon名称保留，默认离线占位使用中性Material组件，不主张与竞品外观一致。

## 实施顺序

测试先写并观察语义RED → 最小状态/port实现 → 全部JVM GREEN → Compose壳与独立Gradle配置 → 静态/编译能力检查 → README记录边界/CI命令 → 只提交本目录，不push。
