# PACKAGING-CHECK 报告（2026-10-12）

执行：grokbot 路线 2。分支 `task/packaging-android-windows-20261012`。
Windows 打包基线：`d83008ef`（`windows-experience-package.yml` + 说明文档）。
交付提交：`32ac6f68df8e91a8b8b10d44bb06b3c608ab5af3`（基于工作区 `6de6e3af539d83b4dea62fb80c22e1906ab05e3c`）。
时间：2026-10-12 20:13:26 CST。

## 环境

- 宿主：Linux box（`Linux grok-bot-vm-416298673 6.12.94+ #1 SMP PREEMPT_DYNAMIC Mon Oct  5 16:05:05 UTC 2026 x86_64 GNU/Linux`）
- Flutter：Flutter 3.47.5 • channel stable • https://github.com/flutter/flutter.git @ `/home/box/flutter`
- `ANDROID_HOME`：未设置；`~/Android/Sdk` 不存在
- Java：未安装
- 已连接用户机器：MacBookAir（macOS，connected）；yhhWorkPC（disconnected，未确认 OS）
- 本机无 Windows 工具链；按任务约束未 apt/sudo 安装，未自动下载 SDK/NDK

## Windows

### 静态审查（`d83008ef` / 当前分支工作流）

见 `windows-static-review.txt`。要点：

- 仅 `workflow_dispatch`；`permissions: contents: read`；`runs-on: windows-2022`；60 分钟
- 输入：完整小写 40 位 `target_sha` + 必须勾选 `artifact_storage_approved`
- actions 均固定 40 位 SHA（checkout / flutter-action / upload-artifact）
- 构建：`flutter build windows --release --no-pub`，无 `dart-define`
- 复用 `scripts/package_artifacts/package.py`：要求完整 Release 树、拒绝 symlink/reparse、要求 Authenticode `NotSigned`、ZIP+manifest SHA256、保留 1 天
- 现有 `package_artifacts` 离线测试 **26/26 通过**（见 `package-artifacts-tests.log`）
- **main 上未登记**该工作流（main 仅有 `verify.yml`）；`workflow_dispatch` 无法从 Actions UI 对未登记工作流触发

### 不改 main 的原生构建路线与所需授权

| 路线 | 做法 | 所需授权（均未代为开启） | 本轮状态 |
|---|---|---|---|
| W1. 任务分支 push/PR 触发 | 在本分支把 `windows-experience-package.yml` 增加 `push` 和/或 `pull_request` 触发（GitHub 对 push/PR 使用触发提交上的工作流，不必先登记 main） | ① 批准修改工作流触发器并推送 ② 批准首次运行产生的 1 日公开仓库 artifact 下载范围与存储占用 ③ 确认 Actions 已启用 | 未开启 |
| W2. 本机/用户 Windows 机器本地构建 | 在已授权 Windows 环境安装 Flutter 3.47.5 + VS C++，`flutter build windows --release` 后跑 `package.py` 或等价打包 | ① 用户提供已连接的 Windows 机器本地执行许可 ② 可安装已有免费工具链（非付费 runner） | 本 Linux box 无法执行；yhhWorkPC 未连接 |
| W3. 默认分支登记后再 dispatch | 另开**只含工作流/脚本**的 main 登记 PR，登记后再 `workflow_dispatch` | ① 用户明确批准改 main 登记 ② 存储/公开下载范围确认 ③ 勾选 `artifact_storage_approved` 并填写最终候选 SHA | **本任务禁止改 main**；仅作对照列出 |
| W4. 付费/larger/self-hosted runner | — | — | **排除**（不付费） |

### 四项结果

| 脚本测试 | 原生构建 | 启动 | 交互 |
|---|---|---|---|
| 通过（复用 `package_artifacts` 26/26；工作流静态审查通过） | **未实跑**（Linux 宿主无 Windows；未改工作流触发器；未 dispatch） | **未实跑** | **未实跑** |

无密钥核查（静态）：工作流与 `package.py` 均不注入 `dart-define`/secret；要求 unsigned；路径黑名单拒绝 keys/keystore/env/logs。真实 ZIP 内容核验待首次获授权构建。

## Android

### 交付

重写本地无密钥打包（测试先行）：

- `scripts/package_android/package_android.py`
- `scripts/package_android/test_package_android.py`（11 项）
- `scripts/package_android/README.md`

行为：`flutter build apk --release --no-pub`；禁止全部 `dart-define`；产物名 `muyon-android-<build_sha>-internal.apk`；旁路 `.sha256` + `manifest.json`；缺 SDK/NDK/Java 时失败且不自动拉取；apksigner 要求 debug 证书。

### 脚本测试

```
python3 -m unittest discover -s scripts/package_android -p 'test_*.py' -v
```

**11/11 通过**，退出码 0（见 `android-script-tests.log`）。

### 原生构建阻断

```
python3 scripts/package_android/package_android.py \
  --repo ... --output /tmp/muyon-android-out --flutter /home/box/flutter/bin/flutter
```

退出码 **1**：`Android SDK not found. Set ANDROID_HOME to an already-cached SDK; will not auto-fetch.`
（见 `android-blocker.log`）。另缺 Java。按约束未下载 SDK/NDK、未 apt 安装。

工程侧确认：`apps/muyon/android/app/build.gradle.kts` release 使用 debug `signingConfig`；无 `key.properties` / 上传 keystore。

### 四项结果

| 脚本测试 | 原生构建 | 启动 | 交互 |
|---|---|---|---|
| 通过（11/11） | **未实跑**（无缓存 SDK/NDK、无 Java；不自动下载） | **未实跑** | **未实跑** |

产物：无（未构建）。无密钥核查（脚本层）：拒绝 dart-define；manifest 记录 `dart_defines: []`、`keyless: true`、`signing.method=android-debug-key`；APK 路径黑名单。

## 未做

- 未改 main、未 merge、未付费、未新增凭证
- 未开启 Windows 工作流触发器、未 dispatch Actions
- 未在用户机器上执行本地工具（Windows 机未连接）
- 未做 Android 真机安装/启动/交互

## 建议下一步（需授权）

1. Windows：选 W1 或 W2；若 W1，批准触发器补丁与首次 artifact 存储范围后再跑。
2. Android：在已缓存 SDK+NDK+Java17 的环境跑 `scripts/package_android/package_android.py`，交 APK/SHA256/manifest。

## PACKAGING-BUILD 结果（W1 / A1，2026-10-12）

工作流提交 / build SHA：`a66819630e9b8072deb3c6a8f41ea98bf3adfd58`（分支 `task/packaging-android-windows-20261012`）。
用户已批准 Windows W1、Android A1；仅本任务分支 `push` 触发；未改 main；无 secrets；标准托管 runner。

### 工作流 run

| 平台 | Run | 结论 |
|---|---|---|
| Windows | https://github.com/mightyoung/Muyon/actions/runs/38261835192 | success（9m10s） |
| Android | https://github.com/mightyoung/Muyon/actions/runs/38261835161 | success（6m56s） |

### 产物

| 平台 | 文件名 | 大小 | SHA256 | build SHA |
|---|---|---|---|---|
| Windows | `muyon-windows-a66819630e9b8072deb3c6a8f41ea98bf3adfd58-Release.zip` | 41296801 | `7ff7eaf286117182aef86035a8d08942b66e106fb81d329d22a5f6e46582c83c` | `a66819630e9b8072deb3c6a8f41ea98bf3adfd58` |
| Android | `muyon-android-a66819630e9b8072deb3c6a8f41ea98bf3adfd58-internal.apk` | 191782958 | `b6105555f20102a24a9ef59c81b4a03b084c729c4e3b31007301862c4cec1437` | `a66819630e9b8072deb3c6a8f41ea98bf3adfd58` |

manifest 副本：`manifests-a668196/`。完整 ZIP/APK 保留在 Actions artifact（1 日）与本机 `artifacts-*/from-a668196/`（不入库）。

### 四项结果

| 平台 | 脚本测试 | 原生构建 | 启动 | 交互 |
|---|---|---|---|---|
| Windows | 通过（package_artifacts 26/26；工作流静态检查） | **通过**（windows-2022 @ a668196） | **未实跑** | **未实跑** |
| Android | 通过（package_android 11/11） | **通过**（ubuntu-24.04 @ a668196） | **未实跑** | **未实跑** |

### 无密钥核查

方法：① 工作流 no-key 步骤拒绝 `--dart-define` 注入与私钥装甲；② 下载产物后扫 ZIP/APK 成员路径黑名单；③ 非二进制成员扫 `--dart-define=` / `api_key=` / 私钥装甲 / `sk-` 长串；④ 读 manifest：Windows `signing.method=unsigned`，Android `keyless=true`、`dart_defines=[]`、`signing.method=android-debug-key` 且含「仅供体验，非发布签名」。

结果：见 `nokey-verification-a668196.txt` — **两端 NO_KEY_OK**。

### 构建过程备注

- Windows：`package.py` 曾误期待 `data/icu.dat`，已改为 Flutter 实际安装的 `data/icudtl.dat`。
- Android：发布构建去掉 `--no-pub`（避免 `integration_test` 残留进 GeneratedPluginRegistrant）；apksigner digest 兼容带冒号格式。
- Android 使用 runner 预装 SDK（`/usr/local/lib/android/sdk`）；本打包脚本未调用 sdkmanager。AGP/Flutter 构建过程可能按工程声明的 ndkVersion 协调 NDK（与 Windows 侧 ONNX 依赖下载同类，非本脚本拉取）。
- 首次 push 工作流文件时 box OAuth 缺 `workflow` scope，经用户 Mac 上带 `workflow` 权限的 `gh` 用 Git Data API 推送；后续同法。

