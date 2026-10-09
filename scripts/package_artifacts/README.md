# Muyon 手动内部打包

本轮仅供草稿 PR 审查，不 dispatch、不发布、不合并。基础设施独立于 AIUI-1/2。
基线：develop `01404ae472451f55af5baa6ce76c95af72b0cbfc`。仓库及 `/workspace`
未找到 AGENTS.md；已读 HANDOVER-LEADER A–D、REVIEW 及现有 ci/verify/ui-preview。

## 启用前提与用法

用户确认 Actions 存储预算后，另行授权首次构建。GitHub 手动 workflow_dispatch
还要求该工作流已存在于默认分支（目前 main）；本 PR 只面向 develop，默认分支的
登记/更新须另行安排，本任务不会改 main。

建议登记方案（仅提案，待 leader/user 决定）：本 PR 在 develop 审查完成后，另开面向
main 的独立草稿 PR，只引入最终审查版本的四个基础设施文件：
`.github/workflows/package-artifacts.yml`、`scripts/package_artifacts/package.py`、
`test_package.py`、`README.md`（后三者位于 scripts/package_artifacts）。不把 develop
产品/AIUI 改动整体合入 main，不添加 push 触发器。由 leader 核对文件与最终审查版
一致并取得用户对默认分支登记的决定后，另行处理该 PR。登记完成仍不自动构建；
首次 dispatch 须在用户知悉下述下载范围、确认存储预算并授权之后执行。

之后选择经过审查的 workflow 分支/提交，
填写完整、小写 40 位 `target_sha` 并选一个 `platform`（android/macos/windows）。
无 all 选项、无矩阵、无 push/PR 触发器；UI 首选项只会选 Android，不会默认三端全跑。

源码与打包工具分别 checkout 指定源码 SHA、`github.workflow_sha`，各自核验 HEAD。
打包脚本来自工作流版本，因此可打包尚无该脚本的历史源码。仅对可信、已审查且有
对应原生工程的源码构建：源码里的 Gradle、Xcode、CMake、依赖构建钩子会执行代码。
缺少原生工程、依赖锁失配、工具链/插件不兼容或产物不完整均失败，不生成替代成功包。
Flutter 固定 3.47.5，与现有 CI 一致；workspace 使用 enforce-lockfile。
标准 GitHub 托管 ubuntu-24.04 / macos-15 / windows-2022，60 分钟上限，无 SDK/pub
缓存，无 larger/self-hosted runner，无新增 secret，仅 contents:read。

## 下载范围与数据约束

mightyoung/Muyon 当前是 public 仓库。GitHub Actions artifacts 不是私有分发：
登录 GitHub 且有仓库读取权限的用户可以下载；对 public 仓库，这个范围包括其他
GitHub 登录用户。“内部验证”只描述用途、签名和验收状态，不代表产物私密。
首次真实构建前，leader 必须让用户知悉此下载范围，再取得首次构建授权。

任何待打包源码、资源及最终产物都不得嵌入 secret 或真实用户数据。此工作流不读取
环境凭据、不注入密钥；路径过滤只防止常见敏感文件/目录被打包，不能证明文件内容
无秘密或真实用户数据。首次实际构建前仍须核对指定源码/资源符合该约束；本轮只做
静态检查，不声称已完成真实产物内容核验。3 天保留并不提供私密访问控制，也不是存储账单硬上限；
多次构建的产物会重叠保留并占用存储。public 仓库标准 runner 的免费计算分钟数
不能证明 artifacts 存储预算已核准，首次执行前须另行确认预算。

## 产物及签名

- Android：`flutter build apk --release` 的完整 APK（不拆 ABI）。当前
  `android/app/build.gradle.kts` Release 配置使用 debug key。只用于内部验证，脚本用
  apksigner 验证并记录 debug 证书 SHA-256；云 runner 的 debug key 不保证跨次相同，
  不能承诺覆盖安装。不上传 keystore，不是正式分发签名。
- macOS：完整 Release `.app` 经 ditto 压缩，保留 bundle、权限、symlink。现有 Xcode
  工程使用 ad-hoc identity，脚本 verify 并要求实际 Signature=adhoc；无 Developer ID、
  签名证书、notarization 或 Gatekeeper 分发保证。macos-15 标准 runner 当前为 arm64，
  manifest 记录实际架构；不承诺 Intel 包。
- Windows：完整 `build/windows/x64/runner/Release` 压缩为带 Release 根目录的 zip，
  包括 exe、DLL、data、Flutter assets 和所有递归文件；验证 exe 未签名及必需运行文件。
  Windows Release 拒绝所有 symlink/reparse point（含 junction、内部链接），并要求各
  路径 resolve 后仍在 Release 内，避免读取/打包目录外内容。此链接策略仅适用 Windows，
  macOS 正常 bundle symlink 仍由 ditto 保真，不一刀切拒绝。
  无 Authenticode。运行仍可能需要宿主 Visual C++ runtime，首次构建/启动尚未实测。

源码包含三端工程，flutter_onnxruntime 1.8.5 的 pubspec 声明支持三端，Windows
CMake 已固定 ONNX Runtime 1.23.0；没有为打包修改原生工程或产品代码。OCR 模型通过
现有应用按固定摘要下载安装，安装包不另加模型下载步骤。完整构建包不代表真机、
真实模型、Golden 测试通过；现有 macOS 截图门禁失败结论仍保留。

每次仅上传 package 和 manifest.json，保留 3 天，传输压缩级别 0（包已压缩）。manifest
记录源码 SHA、工作流 SHA/ref、run ID/attempt、OS/架构、Flutter/Dart/Python 及平台
工具版本、实际签名方式、包大小和 SHA-256。仅收集明确版本/签名字段，不上传
rawlogs、源码、用户数据、环境文件、keys、依赖缓存；打包前逐段拒绝常见凭据/日志路径，统一正反斜杠并忽略点/空段，
拒绝目录穿越、绝对/UNC/盘符路径、冒号和控制字符；不依赖 ZIP 显式目录条目。
不传 dart-define、不开真实模型取证、不读取 .env；路径检查不是任意历史源码的秘密
扫描，操作者必须选择可信源码。预算仍待确认，3 天保留不代表已核准存储费用。

## 本轮静态验证

```
actionlint -shellcheck= .github/workflows/package-artifacts.yml
python3 -m unittest discover -s scripts/package_artifacts -p 'test_*.py' -v
git diff --check
```

actionlint 1.7.7 通过；26 个离线测试通过，涵盖三端打包/provenance、SHA 不匹配、缺
Windows DLL、错误 Android 签名、APK 内凭据和日志路径拒绝（含无目录条目的 keys/token.json 与 rawlogs/session.txt）、
ZIP 路径穿越/绝对路径拒绝及正常无敏感路径正例、两类 SHA 格式及 HEAD 不一致、
缺/多 .app、三端签名和命令失败、Windows 内外文件/目录链接拒绝、reparse point 元数据替身及 resolve 越界拒绝。Windows zip 对
全部成员集合及每项字节做对照。原生工具输出以夹具
模拟，Windows zip 使用真实 Python zipfile 校验内容；不是三端真实构建/安装证据；
macOS 正常 symlink 正例仅证明脚本允许该结构，不证明真实 ditto 压缩包权限/
symlink 保真或 codesign 已成功，这些都待首次获授权的原生构建核验。
本轮未安装 Flutter/Android/Xcode/Windows 工具链，未执行 Actions 构建。
所有直接使用的 actions 固定完整 commit SHA，并由上游 Git tag 核对版本。
提交含 `[skip ci]`，避免此基础设施草稿的 push/PR 自动启动现有 ci 工作流。
