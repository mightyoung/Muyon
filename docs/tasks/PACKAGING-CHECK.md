# PACKAGING-CHECK：Android 与 Windows 无密钥体验包准备核查

执行：grokbot（路线 2）。派发：leader A，2026-10-12。基线：`task/windows-manual-experience-package-20261012` @ `d83008ef`（Windows 打包代码）；分支 `task/packaging-android-windows-20261012`。

## 背景
- Android 打包脚本 `cfd7f7b9` 只在已停的云端工作区，用户决定**当作丢失、重做**。
- Windows 打包代码 `d83008ef` 远端存在；原报告 26 测试与静态校验通过，**从未原生构建**。工作流说明：windows-2022、contents:read、固定 action SHA、无 key、ZIP + manifest SHA256、保留 1 天。
- 约束：不付费、不新增凭证或权限、不改 main（`workflow_dispatch` 需默认分支注册 → 涉及 main，禁止）、不擅自安装手机、包内不得含任何 key / token；旧含 dart-define 密钥的冒烟方案不能当日用包。

## 要做
1. Windows：静态审查 `d83008ef` 的打包代码与工作流；找出不改 main 也能原生构建的可行路线（例如 `pull_request` / `push` 触发的任务分支工作流、或你环境内的 Windows 构建），**列出每条路线需要的授权**，不擅自开启。若在获准环境能构建，交付真实 ZIP、SHA256、build SHA、构建日志。
2. Android：重写无密钥打包脚本（release 构建、不嵌 dart-define 密钥、产物文件名带 build SHA、输出 SHA256 与 manifest）；脚本测试先行；核查 SDK / NDK 是否已缓存，**不得联网自动下载工具链**。能构建则交付真实 APK 与证据；不能则写清阻断。
3. 两平台分别报告：脚本测试 / 原生构建 / 启动 / 交互，未实跑写「未实跑」。

## 回报
每平台：代码提交哈希、构建路线与所需授权、产物（文件名、大小、SHA256、build SHA）或阻断原因、启动 / 交互状态、无密钥核查结果。
