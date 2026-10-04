# MuSpace 首业务模块：Folio 迁入验收

日期：2026-10-04。当前交付是首个内置业务模块的代码迁入与本地回归；不是完整 V0.1、动态插件安装或跨设备发布验收。

## 用户覆盖与源码

用户在修订 4 执行请求后明确要求优先使用较成熟的 software-cost-calculator。宿主默认进入 Folio，科研入口保留；原科研计划和验收项未删除。

供应商迁入依据为 `origin/main@b35eccbe9ddf458a6538fa107baa9b456972a4f8`，不混用原仓库旧工作树、并发工作树或原用户数据。MIT 与第三方资产许可随代码保留。具体文件和依赖偏差见 `supplier-source-manifest.md`。

## 实现结果

- 单一 MuSpace MaterialApp 与入口，迁入 85 个原业务 UI 文件；原 main 未迁入，AppState/Shell 增加宿主适配。
- supplier_core、inquiry_module 分包。保留供应商、项目、报价、物料复核、采购询价、助手、备份交换和局域网相关业务代码。详细覆盖见 `supplier-feature-matrix.md`；保存代码不等于每项平台行为都已实测。
- 宿主独占业务数据库与任务数据库连接，串行写入、关闭排空、schema 校验；已有业务事务走同一连接，后台操作不另开同库连接。
- 宿主独立应用数据根、文件目录与凭据命名空间；不会自动读取原 Folio 私有目录或密钥。局域网和自动同步不在启动时自动开启。
- 备份导出只从副本移除宿主 schema 管理表，使原严格导入校验继续有效；恢复保留宿主自身迁移元数据。实际宿主导出、预览、恢复、重开已验证。
- 退出请求等待模块停机、活动任务与数据库写入排空；重复关闭返回同一 Future。研究工作区切换释放旧 session。
- Folio 当前通过专用宿主适配器加载，尚未实现通用 BusinessModule/ModuleRuntime 合约或动态安装。原 supplier 跨项目实体关系保持原语义，尚未映射到科研 WorkspaceBinding。

## 本地验证证据

环境：macOS；Flutter 3.47.5 / Dart 3.13.4。测试使用已锁定的当前 workspace 依赖，去掉影响 localhost WebSocket 的代理变量。

| 检查 | 最终结果 | 边界 |
|---|---|---|
| MuSpace 宿主测试 | 29 通过 | 含首入口、单 MaterialApp、持久化、恢复、scope、检索、HTTP 问答、取消与关闭排空；合成数据 |
| 公共 API 契约 | 7 通过 | 接口层自动测试 |
| supplier_core 全量 | 465 通过、3 跳过、0 失败 | 跳过真实模型凭据、supplier-hub 二进制、系统 CJK 字体条件 |
| inquiry_module 全量 | 309 通过、1 跳过、1 已知源 golden 失败 | 见下方原始基线对比；没有改写 golden |
| supplier 宿主/导出/fixture 回归 | 18 通过 | 最终导出元数据修复包含在核心全量中 |
| supplier 最终 LAN/生命周期回归 | 4 通过 | 验证关闭拒绝新任务并等待 LAN 转换；合成环境 |
| research_module 全量 | 95 通过 | 已对齐 archive 4.0.9 后重跑；科研验收缺口见包内 MIGRATION_STATUS.md |
| Dart analyze 全 workspace | 无问题 | 最终代码静态分析 |
| git diff --check | 通过 | 历史脏计划文件保留；未提交、未推送、无 CI 声明 |
| Android release APK | 构建通过，120.8 MB | Gradle 9.3.1 / AGP 8.11.1 / Kotlin 2.2.20 / JBR 25.0.3；使用开发签名，不代表实机安装/导出/密钥/联网验收 |

唯一 desktop settings golden 失败为 158 像素（约 0.02%）。同一 SDK 和宿主依赖下，未改的冻结源 AppState/Shell/settings 截图测试产生完全相同差异，迁入前后渲染图片 SHA256 都是 `3f51c7a531a4fc403840bfb0aa007f04f8cb93b462ad409b4c673590de638090`。因此本次没有证实该截图失败由迁移引入，测试本身仍然是失败状态。原 golden 未更新，详情见 `packages/inquiry_module/MIGRATION_VALIDATION.md`。

复现命令：各包目录下 `flutter test --no-pub --reporter expanded`；仓库根下 `dart analyze apps/muspace packages`；宿主目录下 `flutter build apk --release --no-pub`。

Android 产物：`apps/muspace/build/app/outputs/flutter-apk/app-release.apk`（构建目录已忽略，不提交二进制）。构建日志仍包含旧 AGP/Kotlin 未来支持警告及原插件 Java 8/弃用 API 警告，未通过绕开依赖校验来构建。macOS/Windows 与实机缺口如下。

APK SHA256：`02afc59daa156096ece03f9d3aa2608ebb7cc4a0b2d1073737440dd705f2aa5f`。`apksigner verify --print-certs` 通过，证书 DN 为 `C=US, O=Android, CN=Android Debug`，确认为开发签名。

## 尚未验收

1. 本机只有 CommandLineTools，无完整 Xcode；macOS 原生构建未通过验证。无 Windows 构建环境，无 Android 连接设备。不能声明三平台设备验收。
2. 真实模型请求、跨设备 LAN/文件交换、原用户真实数据迁移和恢复后的业务抽查尚未验证。
3. supplier-hub 运行时及工作流可用性、平台 WebView/G6/PDF/文件选择器、系统安全存储、Android 保存重开仍需目标平台验证。
4. 原 V0.1 的真实 PDF 检索质量、卡片 UI、研究完整包的宿主接线、跨设备与 V01–V09 验收仍待后续执行。已有科研代码和明确缺口保留，不将自动测试计作这些项目通过。

运行与数据位置说明见 `apps/muspace/README.md`。
