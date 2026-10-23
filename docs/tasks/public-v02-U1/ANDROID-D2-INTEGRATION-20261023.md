# U1 + D2 Android 编译候选

2026-10-23。隔离分支 `task/android-u1-d2-host-compat-20261023`，基线 `d2c56a626736fa85a95cbf8f52d5dba85fc04be3`。唯一 develop 集成负责人为父任务；本分支只交候选。

## 精确组合与改动

复用联合编译输入 `a6f4255ac76e4971ef46b1eb4ef8723a00b358a8` 相对 develop 的 13 个文件，包含 U1 `4d032fa9d293512bae6bdb4d6d8874fdd96a5e1f`、Kotlin D2 `29609361569dd30bc5f81c56595357f7bfd3f888` 既有实现和报告。共享 fixture 始终从固定对象 `c95bc6a881bf721a982f907f1bd0bd37031dec40` 只读提取并核摘要；不修改 Rust、共享 fixture、公共登记、生产页面或 PR108。

- `HostDraftStoreChecks.kt`：12 处 Java 11 `Files.readString/writeString` 改为 Kotlin `File.readText/writeText`，显式 UTF-8。所有既有断言、进程竞争、故障、损坏、revision 与恢复场景保留。
- 两份新离线 runner：Linux 优先 `sha256sum`，macOS 使用已有 `shasum -a 256`，仍按固定摘要校验原字节，不下载或重建 fixture。
- `.github/workflows/android-compile-only.yml`：仅更新候选分支触发。原 `tools/ci/android_compile_only.py` 保持与联合入口完全相同，分别 dry-run、在线编译、同缓存离线重编译 main / androidTest / unitTest；无 APK、模型、native 包装或 runtime 任务。

公共综合候选旧的两份 Kotlin 测试/runner 由本线 142 组版本替代，已协调公共能力 owner 不在另一个 PR 再交旧版。

## 本机实际验证

现有 Android Studio Kotlin 2.3.10 / JBR 25.0.3，`-Werror -jvm-target 17`。固定 Maven `org.json:20250517` 测试 jar 下载至任务拥有的 `/private/tmp/muyon-u1-d2-json-20250517.jar`，82,710 字节，SHA256 `3ea61b2a06e31edf1c91134fe9106b0ebb16628be169f3db75bc7a2b06b45796`。未改项目依赖、SDK、系统配置。

| 实际入口 | 结果 |
| --- | --- |
| `product/services/documents/run-offline.sh` | 142 组通过、0 失败；D typed79 / outsideInt2，C typed26 / outsideInt2，W25 |
| `product/ui/publicservices/run-offline.sh` | 38 组通过、0 失败 |
| `product/ui/cards/run-offline.sh` | 45 项通过 |
| `product/chat/persistence/run-offline.sh` | 既有真实 JVM 子进程 CAS、重启、错误 owner、磁盘故障、Unknown 原回执、损坏/结构/边界检查通过 |
| 两份 runner `bash -n`、compile driver AST、`git diff --check` | 通过 |
| 本机 Gradle 三类编译 | 未进入编译；任务拥有 GRADLE_USER_HOME 后被 FileLockContentionHandler 的 socket 权限阻断 |

本机原 native library 失败根因是默认 `~/.gradle/native/.../libnative-platform.dylib.lock` 禁止写入。使用 `/private/tmp/muyon-u1-d2-gradle-home` 后 `gradle --version` 成功，但实际构建仍返回 `java.net.SocketException: Operation not permitted`。未关闭任何限制或启用 native-access 参数。JBR25 启动不是 Gradle8.13/AGP 正式兼容验收；原 CI 使用 Java17。

日志 `/private/tmp/muyon-u1-d2-offline.log` SHA256 `226e54fb7070a03921a1861693a5f7a14ff20243a040794739787f6bf6c40501`；Gradle 日志 `/private/tmp/muyon-u1-d2-gradle.log` SHA256 `58c3b5d93cb5519266bc8cfed1dc3f855bad2b81948bf43fbd7e366859aa1d68`。原始日志不入库。

## CI、独审及未完成项

首个组合源码提交 `388f0a8f806b81db4898a9e623530f3de4d5e475` 已触发同一编译入口 [39919728577](https://github.com/mightyoung/Muyon/actions/runs/39919728577)。交付时须另核最终提交对应的 CI，不能把前一个源码的通过转记给后续提交。独立审查由父任务安排；历史 U1/D2 独审只适用于报告所列旧源码，不能替代本次集成独审。

Android 设备 / instrumentation 实际执行仍未运行，不称 Android 全通过。默认 src/test 的 main 检查由离线 runner 实际执行，不拿编译 task 完成冒充 38/142 组运行。纯值形状检查不代表可信来源解析、已授权、Reader/FD 解除阻断、真实模型或索引检索；D2 域外 UTF16 诊断一致性 minor 保留，未来 codec 错误投影仍未冻结。
