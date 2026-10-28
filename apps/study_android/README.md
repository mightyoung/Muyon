# 木易学习 Android

个人学习、工作待办、DIY 项目和资源管理。基于 Muyon `develop` 的 Rust/SQLite 能力，新建 Kotlin/Compose 应用，不改变现有应用的发布入口。

图标由 GPT Image 逐个生成，包含桌面、五个导航、新增、语音、导入及到期通知图标；原图和提示词在源码中保留。

## 安装与首次使用

Android 8.0 及以上，支持 ARM64 手机和 x86_64 模拟器。交付的 APK 是可安装的调试签名版本，尚未完成用户真机和个人云端账号验收。

1. 安装后进入“我的”，设置固定学习时段、每日时间上限、通知权限。
2. 在“学习”创建考试/课程目标，考试必须填写固定截止日期；其他目标允许建议延期。
3. 导入课程和任务，或在“今日”录入待办。在任务详情关联资料、例程文件和视频链接。
4. 在排程页面检查时间安排、容量不足、延期建议和远期阶段，确认后生效。输入、日历和空闲时间变化会重新产生建议，不自动覆盖已确认安排。
5. “收件箱”接收文字和语音碎片；可调用 DeepSeek 转成任务建议，检查后确认。
6. 定期导出 ZIP 备份，包含上传文件、计划、项目及作答；API 密钥不导出。

## 离线中文语音

APK 内含 `vosk-model-small-cn-0.22` 的实际权重，首次使用在本机解压，不需要另外下载。点击语音、允许麦克风、说话，再检查并保存识别文字。音频不上传。识别结果先进入收件箱，计划调整另经确认。第一次加载需要等待；识别准确率取决于设备和环境，需真机验证。

## Google Calendar / Drive

需要手机具备 Google Play 服务，并能访问 Google。先在 Google Cloud 项目启用 Calendar API、Drive API，配置 OAuth 同意屏幕和测试用户，创建 Android OAuth 客户端：包名 `com.mightyoung.muyon.study`，登记实际安装 APK 的签名证书 SHA-1。无需在 APK 中放客户端密钥。修改签名后需重新登记 SHA-1。

“连接／刷新全部日历”读取所有可访问日历的事件；目前同步最近一天至未来 120 天，远期排程应留意尚未同步的外部占用。授权后按系统后台作业条件约每小时刷新，系统省电策略可能延迟；可手动刷新或关闭后台刷新。

发布另需写入授权和应用内确认，只写应用专用日历。清理的范围为本应用创建且未被手动改动的旧时间块；被手动修改的事件保留并报告冲突。撤销本地排程不会撤销已发布的外部变更，需要再次检查并发布。

Drive 使用 `drive.file` 权限，仅列出本应用获授权文件。其他文件可通过 Android 文件选择器的 Google Drive 入口选择。上传资料保存本机副本；视频仅保存链接。支持上传/恢复完整 ZIP 备份，不进行无确认的双向文件覆盖。

## 墨墨与 DeepSeek

“我的”中填写墨墨开放 API token，可手动或后台读取学习进度。该进度受官方接口更新频率限制，不等于实时抓取整个墨墨应用数据。

填写 DeepSeek API key，可设置模型名（默认 `deepseek-chat`）。调用时会把输入及必要任务上下文发送给 DeepSeek；语音识别本身在本机完成。AI 任务更改先预览；不伪造已完成记录。主观题点评是参考，不是标准评分。

凭据由 Android Keystore 保护，仅存当前设备。卸载前先备份学习数据；恢复后需重新填写凭据。

## 导入格式

- Markdown：一行一个任务，支持复选项与明确的日期/分钟字段。
- Word：`.docx` 文本段落/表格。
- Excel：`.xlsx`，建议首行 `title, minutes, due, notes`；日期使用 `YYYY-MM-DD`，时长使用分钟。
- `.doc` / `.xls` 请先另存为新格式；复杂版式、图片和公式不会自动变成可靠学习步骤。所有导入先预览。
- 题包：支持 MEM `papers.json` 数组，保留题目 ID。公开源码不包含用户的私人题库。可使用“导入题包”选择自己的文件；个人构建可设置 `MUYON_MEM_PAPERS=/absolute/path/papers.json` 后运行 `prepare-inputs.py`，仅复制到 git 忽略的本机资源。交付给用户的私人 APK 包含其提供的题包。未提供答案的题目显示无法判定，不编造正确率。
- 单个上传资料最多 64 MB；计划/题包最多 24 MB；完整备份资源合计最多 256 MB。资料和视频关联可填写页码、片段等备注。

## 源码构建

依赖 JDK 17、Android SDK 36、Build Tools 35、NDK 28.2.13676358、Gradle 8.13、Rust 1.93.1。SDK 路径使用 `ANDROID_HOME`。安装 Rust 的 `aarch64-linux-android` 和 `x86_64-linux-android` 目标。

```sh
python apps/study_android/prepare-inputs.py
sh apps/study_android/build-native.sh
python apps/study_android/native_identity.py
gradle -p apps/study_android :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
```

输出 `apps/study_android/app/build/outputs/apk/debug/app-debug.apk`。模型和本机编译的 JNI 文件未提交 git；脚本固定模型 SHA-256 校验，缺少权重会拒绝构建。第三方许可见 `THIRD_PARTY_NOTICES.md`。

## 验收边界

自动测试覆盖持久化、排程约束、确认版本、考试截止、恢复、题包和导入等。Google、墨墨、DeepSeek 真实账号、真机麦克风、厂商后台省电和到期通知必须使用个人设备/凭据验收。当前应用不提供自动控制墨墨、后台常驻录音或全盘 Drive 抓取。
