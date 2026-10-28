# 木易学习 1.0.0 验证记录

日期：2026-10-28。分支：`codex/personal-study-app-20261028`，基于 `develop` 的 `50eb6092`。

## 已完成的验证

- Rust 工作区 `cargo test --locked --workspace --all-targets`：52 组，共 801 项通过，0 失败。包含个人学习域 15 项、FFI 错误处理 1 项及原有工作区回归。
- Android JVM 单元测试：18 项通过，0 失败，覆盖导入、路径、语音会话、流式大小限制、日历事件身份及 AI 更新白名单等。
- Android `lintDebug`：0 个错误、15 个警告；警告主要为依赖升级提示、KTX 写法和应用级上下文引用。未设置忽略错误或基线隐藏兼容性问题。
- `assembleDebug` 和 `assembleDebugAndroidTest` 构建成功。
- `apksigner verify`：APK v2 签名有效，为 Android Debug 证书。
- APK 两个 ABI 的 Rust 库内容与当前源码身份清单相符；源码身份 `8c87945dff8e40c64c0daca1c53467ae9b904b05c0de65cdb53ac734351e69db`。
- APK 中的模型 ZIP 为 43,898,754 字节，SHA-256 为 `3af8b0e7e0f835ae9d414ce5df580237a3cfb08d586c9fbbb0f7ff29ad5b14ba`。包含实际 Vosk 中文声学权重，并非下载占位符。
- 两个 ABI 所有打包 `.so` 的 ELF LOAD 段对齐均为 16,384 字节。
- APK：90,791,470 字节，SHA-256 `af518c017b5411e862962681eb26e08f78cbd8266c0964a215d9c8216a95172c`。

## 审查后修复

恢复备份后的生成 ID 冲突；日历应用事件反向占用和重复发布；无效 AI 输出在 UI 线程抛异常；备份大小限制不一致和大文件多重缓冲；考试缺失固定日期；作答位置恢复；AI 修改范围与预览；旋转后的输入状态；软目标延期及撤销；远期阶段和零容量日期缺口。新增相应自动化回归覆盖核心路径。

生成的 UniFFI 桥接改用其 Android/JNA 清理配置，避免 Android 8–12 引用 API 33 的 `java.lang.ref.Cleaner`。后台同步只读远端数据、生成待确认建议，不自动发布日历或调用付费 AI。

## 尚未完成的设备与账号验收

- 容器无 KVM，模拟器使用软件 CPU 仿真，冷启动慢；设备测试结果另记，不以“测试 APK 构建成功”代替设备测试通过。
- Google OAuth 需由用户在 Google Cloud 登记当前 APK 包名和签名；真实账号读日历、Drive 和日历发布尚未验收。
- 墨墨与 DeepSeek 需用户凭据；真实账户的权限、配额、网络结果尚未验收。
- 真机麦克风识别准确率、厂商省电策略、重启后通知和精确到期提醒尚未验收。

因此本次交付为首个可安装、可离线使用的版本，不代表已完成个人设备及所有第三方账号的最终验收。

## 1.0.1 图标更新

10 个应用自有图标均由 GPT Image 工具生成并使用原始 PNG 接入，提示词和资源校验清单位于 `docs/design/study-icon-*`。新增主题着色及窄屏按钮换行。重新执行 Android 18 项单元测试、lint 和两种测试/应用 APK 构建，构建成功。

APK 字节数：90739683；SHA-256：`0169d63ef224ff63383f8b44f7aabc91bda22ac0bb8170a731c2aaa74339daab`。仍为同一调试签名，可覆盖 1.0.0 安装。

## 私人资源与发布范围

GitHub 仅发布程序源码和 GPT 生成图标；用户提供的 MEM 题库不进入公开提交。个人 APK 保留题库，源码构建可通过 `MUYON_MEM_PAPERS` 本机配置。模拟器全局 System UI 出现 ANR，设备界面验收未通过；不将构建成功视作设备验收。

## 1.0.2 与 Android 运行时检查

统一导航、对话框与深色模式的暖色容器；18 项 JVM 测试通过，lint 0 错误、16 警告，应用 APK 构建成功。1.0.2 APK 为 90,998,809 字节，SHA-256 `264995352d7acecf04189ad6f46eb4d1676bf8d1d44e0a99dd7f07286e0d37e9`，沿用原签名。

Android 8.0 软件模拟器已识别并启动 1.0.1，人工截图确认五个 GPT 导航图标、新增和语音图标实际显示，Rust 状态加载成功。相同原生库及模型的独立 NativeSmokeTest 3/3 通过，耗时 72.989 秒：真实 Vosk SDK 成功加载完整中文模型、7 个 MEM 题包经 Android JNI 导入并保留作答、模型声学权重确实存在。

Compose 界面自动化未通过：先出现 Compose-Espresso idling 超时，随后在同一测试类下一用例出现 `updateRootConstraints called while measuring`。原先两个非 UI 用例也使用 Activity 规则，拆分后原生测试独立通过；这不表示界面问题已解决。模拟器无 KVM 且发生全局 System UI ANR，尚不能确认界面超时的最终根因。真机 UI 流程、麦克风识别准确率、通知、省电策略及个人账号同步仍需验收。

## 最终黑盒设备验收

Android 8.0 模拟器已成功覆盖安装 1.0.2。将 UI 用例改为系统 Accessibility 驱动，不依赖 Compose/Espresso 帧时钟；实际点击新增待办、在字段中录入内容、点击保存、核对 SQLite 中记录、重建 Activity 后再核对持久化及界面可用。

最终一次完整设备测试为 **4/4 通过**，耗时 131.383 秒：3 项原生/题包/模型检查，以及 1 项实际待办录入与 Activity 重建检查。无跳过项。历史 Compose/Espresso 测试的超时与测量异常仍保留在上文，不将驱动方式改变描述成对其内部问题的修复。

应用二进制未因测试驱动修改而改变，1.0.2 校验值保持不变。真实手机的麦克风准确率、提醒、省电策略及个人账号授权/同步仍待验收。
