# PACKAGING-BUILD：按 W1 / A1 原生构建无密钥体验包

执行：grokbot（路线 2，**先做本任务，再做 E02**）。派发：leader A，2026-10-12。基线：本分支 `task/packaging-android-windows-20261012` @ `7e668b15`（PR #67）。用户已批准（ADR-0001 2026-10-12）：Windows W1、Android A1。

## 要做
1. **Windows（W1）**：只在本任务分支的工作流里加 `push` 触发（限定本分支路径或分支名，不影响其他分支），保持 `contents:read`、固定 action SHA、`windows-2022`、无 `dart-define`、unsigned ZIP + manifest SHA256、artifact 保留 1 天。推送后取得该 run 的 artifact。
2. **Android（A1）**：新增同样限定本分支的 push 工作流，`ubuntu-latest` 标准 runner，使用 runner 预装的 Android SDK 与 Java 17（`setup-java` 用固定 SHA 可以；**不得**由脚本下载 SDK / NDK），运行 `scripts/package_android/package_android.py`，上传 APK + `.sha256` + `manifest.json`，保留 1 天，`contents:read`。release 暂用 debug 签名，manifest 写明「仅供体验，非发布签名」。
3. 两个 run 都绑定精确源 SHA（`github.sha`），manifest 记录 build SHA、Flutter 版本、工具链版本。
4. 无密钥核查：工作流、构建日志与产物中不得出现任何 key / token / dart-define；核查方法写进报告。
5. 不改 main、不开 `workflow_dispatch`、不新增 secrets、不付费 runner。

## 回报
每平台：工作流提交 SHA、run 链接与结论、产物文件名 / 大小 / SHA256 / build SHA、无密钥核查结果；启动与交互一律写「未实跑」（真机 / Windows 机器验收另行安排，由用户确认）。报告追加到 `docs/evidence/2026-10-12-packaging-check/REPORT.md`。
