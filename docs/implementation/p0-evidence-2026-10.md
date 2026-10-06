# P0-4 真机与真实模型取证（2026-10-06）

分支 `task/p0-4-evidence` · 基于 `develop` @ `6d21831`（`MUYON_EVAL_COMMIT=6d21831`）· 执行 engineer（本机）· 只跑、只记录，没有改任何代码。验收账本不在本次修改范围，由 leader 审查后更新。

真实模型：`deepseek-chat`，端点 `https://api.deepseek.com`（远程，OpenAI 兼容）。密钥来自本机未入库的 `.env`，只在命令里读取；本报告与证据文件已用 grep 检查，没有密钥。

## 汇总表

| 项目 | 平台 / 设备 | 模型 | 命令 | 结果 | 证据文件 | 类别 |
|---|---|---|---|---|---|---|
| doctor（未配模型） | macOS 主机 | — | `bash scripts/doctor.sh` | 3 ok, 2 warn, 0 fail, 3 skip（xcode、proxy 两条 WARN） | 见下 | — |
| doctor（已配模型） | macOS 主机 | deepseek-chat（远程） | 同上，设置了 `MUYON_EVAL_MODEL_*` | 6 ok, 2 warn, 0 fail, 0 skip；`model-reach` GET models 返回 200 | 见下 | — |
| verify（含 golden） | macOS 主机 | — | `bash scripts/verify.sh`（去掉模型变量） | **退出码 0**；analyze 7/7 ok；测试全部通过 | 见下 | T |
| ci.sh | — | — | — | **未执行**：P0-1 还没合入 `develop`，`scripts/ci.sh` 不在本分支 | — | — |
| 工具选择基线 | macOS 主机（无头 flutter_test） | deepseek-chat（远程） | 见 `llm_selection_eval.dart` 顶部命令，`MUYON_EVAL_REAL=1`、`MUYON_WRITE_EVAL_REPORT=1`，取消代理 | top-1 66/140，误选写入/外发 0，弃权 26/26，请求失败 0 | `docs/implementation/tool-selection-llm-baseline-deepseek-chat.md` | M |
| North Star 链路 第 1 次 | macOS 主机（无头 flutter_test） | deepseek-chat（远程） | `flutter test test/north_star_inquiry_test.dart`，`MUYON_EVAL_REAL=1` | **失败** `passed:false`：比价题成功；预算题任务 `failed` | `docs/evidence/2026-10-p0/north-star-macos-headless-deepseek-chat.json` | 不计为 M 证据（见下） |
| North Star 链路 第 2 次 | 同上 | 同上 | 同上 | **失败** `passed:false`：比价题成功；预算题任务 `failed` | `docs/evidence/2026-10-p0/north-star-macos-headless-deepseek-chat-run2.json` | 不计为 M 证据（见下） |
| North Star 链路（macOS 设备集成测试） | macOS 桌面应用 | — | `flutter test integration_test/north_star_inquiry_test.dart -d macos` | **未验证**：本机没有 Xcode（`xcodebuild` 不可用），构建 macOS 应用不了 | — | — |
| North Star 链路（Android 真机） | vivo V2324A，Android 16 | deepseek-chat（远程） | `flutter test integration_test/north_star_inquiry_test.dart -d <设备 id> --dart-define=…` | **未执行**：真机在运行时断开连接（`adb devices` 为空，重启 adb 无效） | — | — |
| North Star 链路（Windows） | — | — | — | **未验证**：没有 Windows 设备 | — | — |
| 手动界面走查 | — | — | — | **未执行**：我不能操作应用界面，交给用户 | — | — |

## doctor 输出

未配置模型时：

```
OK	flutter	Flutter 3.47.5 与 verify.yml 一致
OK	devices	V2324A(android-arm64), macOS(darwin), Chrome(web-javascript)
OK	android	adb 与 java 均可用
WARN	xcode	xcodebuild 不可用或失败
WARN	proxy	检测到代理变量: HTTP_PROXY HTTPS_PROXY；运行 flutter test 前请按 scripts/verify.sh 去掉代理
SKIP	model-env	未配置真实模型，只能跑夹具
SKIP	model-key	未配置真实模型
SKIP	model-reach	前置检查未通过
summary: 3 ok, 2 warn, 0 fail, 3 skip
```

配置了模型之后（只显示「已设置」，没有密钥）：

```
OK	flutter	Flutter 3.47.5 与 verify.yml 一致
OK	devices	macOS(darwin), Chrome(web-javascript)
OK	android	adb 与 java 均可用
WARN	xcode	xcodebuild 不可用或失败
WARN	proxy	检测到代理变量: HTTP_PROXY HTTPS_PROXY；运行 flutter test 前请按 scripts/verify.sh 去掉代理
OK	model-env	远程端点（HTTPS）已配置
OK	model-key	远程端点，密钥已设置
OK	model-reach	GET models 返回 200
summary: 6 ok, 2 warn, 0 fail, 0 skip
```

第二次 doctor 时 Android 真机已经断开，所以 `devices` 一行不再列出它。deepseek 在不走代理的情况下可以直连（直连与走环境代理的 GET models 都返回 200），所以后面的真实运行都取消了代理变量。

## verify 摘要（含 golden，macOS）

```
analyze  packages/muyon_module_api: ok
analyze  packages/muyon_ui: ok
analyze  packages/prototype_module: ok
analyze  packages/research_module: ok
analyze  packages/supplier_core: ok
analyze  packages/inquiry_module: ok
analyze  apps/muyon: ok
test     module_api: ok  +17: All tests passed!
test     muyon_ui: ok  +6: All tests passed!
test     prototype: ok  +24: All tests passed!
test     research: ok  +199: All tests passed!
test     supplier_core: ok  +482 ~3: All tests passed!
test     host: ok  +414 ~2: All tests passed!
test     inquiry: ok  +322 ~1: All tests passed!
exit=0
```

## 工具选择基线（deepseek-chat，一次运行，没有挑选）

| 项 | 值 |
|---|---|
| top-1 | 66/140 |
| 误选写入/外发 | 0 |
| 弃权质量 | 26/26 |
| 平均 / p50 / p95 延迟 | 1222.4 / 1224.8 / 1973.8 ms |
| 用量 | 213840 in / 15651 out tokens |
| 请求失败 / 未注册工具名 | 0 / 0 |
| 一次返回多个工具调用 | 1（只取第一个） |

分类 top-1：exact 10/28，chinese 8/28，mixed 12/28，paraphrase 8/28，ambiguous 8/8，misleading 10/10，adversarial 10/10。完整逐题表在 `tool-selection-llm-baseline-deepseek-chat.md`。

## North Star：真实模型运行里两道只读题各自的 `tasks[].tools`

两次运行都是 macOS 主机无头运行，`binding` 为 `flutter_test (headless)`，不是 R 证据。

| 运行 | 比价题 `tools` | 比价题结果 | 预算题 `tools` | 预算题结果 |
|---|---|---|---|---|
| 第 1 次 | `["inquiry.compare_quotes"]` | `succeeded`，2 轮，有 `inquiry.compare_quotes` 的只读回执，回答引用 2 个对象 | `["inquiry.project_budget"]` | **`failed`**，1 轮 |
| 第 2 次 | `["inquiry.compare_quotes"]` | `succeeded`，2 轮，有 `inquiry.compare_quotes` 的只读回执，回答引用 2 个对象 | `[]`（空） | **`failed`**，0 轮 |

按任务说明：比价题必须包含 `inquiry.compare_quotes`（两次都满足），预算题必须包含 `inquiry.project_budget`（第 1 次包含，第 2 次不包含）。两次运行整体都 `passed:false`，所以**都不计为 2.3 的 M 证据**；如实记录，由 leader 人工核对。

## 发现的缺陷（只记录，没有修复）

**D1：deepseek-chat 在预算题上两次都没有给出助手协议要求的 JSON，任务因 `FormatException` 失败。**

- 平台：macOS 主机无头；模型 `deepseek-chat`，远程；代码 `6d21831`。
- 第 1 次：模型提议了 `inquiry.project_budget`，工具执行成功后，下一轮的最终回答是**纯文本**（“项目「北极星验收项目」的成本预算：成本合计 2080 元，销售合计 2080 元，毛利 0 元……”），不是协议 JSON。错误原文：`执行失败（FormatException: Unexpected character (at character 1) 项目「北极星验收项目」的成本预算：…）`。
- 第 2 次：第一轮回复就是 DeepSeek 原生工具调用标记，错误原文：`执行失败（FormatException: Unexpected character (at character 1) <｜｜DSML｜｜ calls>）`，没有工具被提议。
- 复现：`MUYON_EVAL_REAL=1`，端点 `https://api.deepseek.com`，模型 `deepseek-chat`，运行 `flutter test test/north_star_inquiry_test.dart`（`apps/muyon`）。比价题同一轮成功，失败只出现在预算题。
- 影响：真实模型对第二道只读题的表现不稳定；任务结果为 `failed`，错误文本里含模型的回答原文。P0-3c 只涉及「每道题都必须经由对应工具作答」的判定收尾，与这里的协议格式问题不是一回事；根因（模型输出格式、助手协议解析）由 leader 判断。

## 未验证的平台和原因

- **macOS 设备集成测试**：本机没有 Xcode，`xcodebuild` 不可用。
- **Android 真机**：运行时设备断开（`adb devices` 为空，重启 adb 后仍然没有），所以没有 Android 证据；等设备重新连上后补。
- **Windows**：没有设备。
- **手动界面走查**：我不能操作应用界面，写「未执行」，交给用户。
- **`ci.sh`**：P0-1 尚未合入 `develop`。

## 其他说明

- 建议仍然在 Android 上跑一次时注意：设备运行要用 `--dart-define` 传密钥，**密钥会被编进这次构建的测试包**。运行后要卸载测试包，不要分发构建产物。
- 机器上同时跑着别的任务（负载很高），不影响这几项的结论，但门禁耗时不具参考价值。
