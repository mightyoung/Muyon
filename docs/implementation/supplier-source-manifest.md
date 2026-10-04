# 首业务插件：Folio 询价与成本

用户在本轮开发中明确改为 software-cost-calculator 优先。成熟源码冻结为刷新后的 origin/main@b35eccbe9ddf458a6538fa107baa9b456972a4f8；本地旧 snapshot/revision-dag-wip@7d6cb78 不用于迁入。来源仓库 MIT，Copyright (c) 2026 mu yi。

迁入：packages/supplier_core 的领域源码与测试，apps/supplier_app 的完整业务页面与平台服务；不复制旧 main/MaterialApp、不读取旧安装资料或其他工作区。字体、品牌和图谱资源只从同一提交迁入，保留对应 OFL 与第三方声明。

目标：packages/supplier_core、packages/inquiry_module、apps/muspace/assets。宿主提供私有模块根、唯一数据库 owner 和插件入口；模块保留报价、项目成本、供应商/物料、导入导出/备份、公司资料与现有助手语义。原备份恢复和 AI 接纳不能因挂载壳而绕过确认。

初次挂载不会读取原 Folio settings 或自动启动 LAN/文件夹同步。模块数据单独位于 MuSpace 私有根；现有领域项目与共享供应商保持原关联，不强行套用科研 project/workspace 绑定模型。后续明确范围的跨模块上下文再使用公共 ObjectRef/ContextRef。

兼容性差异：科研源锁定 archive 4.3.0，供应商锁定 archive 3.6.1；同一 Dart 应用不能解析两个 major。pdf 3.12.0 又要求 archive <4.1.0；统一到科研原约束允许的 archive 4.0.9，仅适配 ZIP 低层 API，保留 central directory 与实际膨胀输出上限、防重复和 CRC 规则，完整供应商安全测试作为回归门槛。不以直接读取无界 content getter 替代旧安全 decoder。供应商 dev test 从1.32.0调整为1.31.1，匹配 Flutter3.47.5 固定 test_api0.7.12；pdf3.12.0/xml6.6.1 保留。

本文件记录实施输入，不宣称迁入完成或设备验收通过。

## Android 宿主构建适配

当前宿主保留 Flutter 模板的 Gradle 9.3.1（本机 Android Studio JBR 25.0.3），使用 AGP 8.11.1 和 Kotlin 2.2.20。AGP 9.1 对原依赖 flutter_inappwebview_android 1.1.3 的旧 ProGuard 配置拒绝构建；AGP 8.11.1 避开该依赖冲突，Kotlin 2.2.20 满足当前 Flutter 的最低检查。曾尝试 Gradle 8.13，但本机唯一 JBR 为 25，无法运行该组合。未改动全局 Flutter JDK 配置或旧项目配置。

[AGP 8.11 官方版本要求](https://developer.android.com/build/releases/agp-8-11-0-release-notes)与 [Flutter Android Kotlin/AGP 迁移说明](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin)用作适配参考；本项目最终可构建性以实际构建结果为准。Flutter 对旧 AGP 仍有未来支持警告，后续需随原 WebView 依赖升级解决，不能将这次适配作为长期兼容承诺。
