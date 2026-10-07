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
| North Star 链路（macOS 设备集成测试） | macOS 27 桌面应用（`integration_test`，Xcode 27 + CocoaPods 1.17.0） | deepseek-chat（远程） | `flutter test integration_test/north_star_inquiry_test.dart -d macos --dart-define=…`（先 `flutter pub get` 生成 Podfile） | **失败** `passed:false`：应用能构建并运行；比价题成功；预算题任务 `failed`（同 D1） | `docs/evidence/2026-10-p0/north-star-macos-deepseek-chat.json` | R（设备）+ 真实模型，但未通过，不计为 M 证据 |
| North Star 链路（Android 真机） | vivo V2324A，Android 16（`integration_test`） | deepseek-chat（远程） | `flutter test integration_test/north_star_inquiry_test.dart -d <设备 id> --dart-define=MUYON_EVAL_REAL=1 --dart-define=…` | **失败** `passed:false`：比价题成功；预算题任务 `failed`（同 D1） | `docs/evidence/2026-10-p0/north-star-android-deepseek-chat.json` | R（设备）+ 真实模型，但未通过，不计为 M 证据 |
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

前两次是 macOS 主机无头运行，`binding` 为 `flutter_test (headless)`，不是 R 证据；第三行是 Android 真机运行，`binding` 为 `integration_test`，`device.platform` 为 `android`。

| 运行 | 比价题 `tools` | 比价题结果 | 预算题 `tools` | 预算题结果 |
|---|---|---|---|---|
| 第 1 次 | `["inquiry.compare_quotes"]` | `succeeded`，2 轮，有 `inquiry.compare_quotes` 的只读回执，回答引用 2 个对象 | `["inquiry.project_budget"]` | **`failed`**，1 轮 |
| 第 2 次 | `["inquiry.compare_quotes"]` | `succeeded`，2 轮，有 `inquiry.compare_quotes` 的只读回执，回答引用 2 个对象 | `[]`（空） | **`failed`**，0 轮 |
| Android 真机（第 1 次，`integration_test`，`flutter test`） | `["inquiry.compare_quotes"]`，成功，2 轮，有只读回执 | `[]`（空），**失败**，0 轮 |
| macOS 设备（第 1 次，`integration_test`，`flutter test`） | `["inquiry.compare_quotes"]`，成功，2 轮，有只读回执 | `[]`（空），**失败**，0 轮 |

按任务说明：比价题必须包含 `inquiry.compare_quotes`（四次都满足），预算题必须包含 `inquiry.project_budget`（只有 macOS 无头第 1 次包含，其余三次都不包含）。四次运行整体都 `passed:false`，所以**都不计为 2.3 的 M 证据**；如实记录，由 leader 人工核对。

## 第 3 批：P0-3d 合入之后（`review/P0-4` 合并 `origin/develop` @ `4a4fb2f`，合并提交 `d635a1e`）

文件名带 `-p03d` 以区别于合入前同平台的失败证据，两批都保留，不覆盖。

| 项目 | 平台 / 设备 | 模型 | 命令 | 结果 | 证据文件 | 类别 |
|---|---|---|---|---|---|---|
| North Star 链路（macOS 设备集成测试） | macOS 27 桌面应用 | deepseek-chat（远程） | `flutter test integration_test/north_star_inquiry_test.dart -d macos --dart-define=MUYON_EVAL_REAL=1 …`（先 `flutter pub get`） | **`passed: true`**：13 个步骤全部成功，重开后逐项一致（`reopenIdentical: true`）；账本 6 行全部 `succeeded`，发送 139699 字节；写入：审批前 1 张询价单、审批后 2 张，错误摘要被拒、重复确认被拒，回答引用了新询价单 | `docs/evidence/2026-10-p0/north-star-macos-deepseek-chat-p03d.json` | R（设备）+ M |
| North Star 链路（Android 真机） | vivo V2324A | deepseek-chat（远程） | 同上，`-d <设备 id>` | **未执行**：手机没有出现在 `adb devices`（输出为空），见下 | — | — |
| `bash scripts/ci.sh` | macOS 27 主机 | — | `bash scripts/ci.sh`（去掉模型变量） | **`CI SUMMARY: FAILED (test:host test:inquiry)`**，见下 | — | T |

### macOS 设备运行（P0-3d 之后）两道只读题的 `tasks[].tools`

| 题 | `tools` | 状态 | 轮数 | 只读回执 | 回答引用数 |
|---|---|---|---|---|---|
| 比价 | `["inquiry.compare_quotes"]` | `succeeded` | 2 | `["inquiry.compare_quotes"]` | 2 |
| 预算 | `["inquiry.project_budget"]` | `succeeded` | 2 | `["inquiry.project_budget"]` | 3 |

两题都满足任务说明的要求（比价含 `inquiry.compare_quotes`，预算含 `inquiry.project_budget`）。写入任务的 `tools` 为 `["inquiry.create_inquiry"]`，`succeeded`。D1 在这次运行中**没有复现**：合入 P0-3d 之前同一设备同一模型的预算题失败，合入之后通过。这是一次运行的结果，没有挑选，也没有重复运行。

`commit` 字段是 `d635a1e`。运行时的 `git status`：Flutter 与 CocoaPods 的构建副产物改了 `apps/muyon/macos` 下 4 个已跟踪文件并生成 `Podfile`、`Podfile.lock`、两处 `xcshareddata/swiftpm/`（与前一次 macOS 设备运行相同，没有 Dart 代码改动）；运行后已 `git checkout` 还原、删除，没有提交。

### `scripts/ci.sh`（本机 macOS 27）

```
analyze  7/7: ok
test     module_api: ok  +17: All tests passed!
test     muyon_ui: ok  +6: All tests passed!
test     prototype: ok  +40: All tests passed!
test     research: ok  +211: All tests passed!
test     supplier_core: ok  +482 ~3: All other tests passed!
test     host: FAILED (exit 1)  +441 ~2 -3: Some tests failed.
test     inquiry: FAILED (exit 1)  +276 ~1 -46: Some tests failed.
CI SUMMARY: FAILED (test:host test:inquiry)
```

- **inquiry 的 46 个失败**：全部是 `screenshot_test.dart`（82 处输出）和 `ontology_screenshot_test.dart` 的 golden 像素对比，例如 `ontology-light.png` 差 0.15%、2383 px，`ontology-dark.png` 差 0.14%、2165 px。这是 macOS 27 渲染与基准图（旧版 macOS 生成）的漂移，如预期；`develop` 上的 `ci.sh` 不再排除这些测试（Linux 上它们靠 `skip: !hasFont` 自行跳过），所以本机会失败。失败输出里只出现这两个文件。
- **host 的 3 个失败（真实缺陷，只记录，没有修复）**：`apps/muyon/test/research_object_open_test.dart` 里的 `an object without a binding falls back to the JSON page` 这个测试**挂起**，整个 `flutter test` 报 `TimeoutException after 0:10:00.000000: Test timed out after 10 minutes`，随后的测试因为框架状态被破坏连带失败（`Failed assertion: '!inTest' is not true`、`Reentrant call to runAsync() denied`）。
  - 单独复现：`flutter test --no-pub --reporter compact test/research_object_open_test.dart --plain-name 'an object without a binding falls back'` 运行超过 120 秒不结束（我手动终止）。同一文件的前三个 `openObject …` 用例单独运行在 120 秒内结束。
  - 这个文件来自 E11/E11b（已合入 `develop`）。我没有在其它平台复现，所以不能判断是否与 macOS 27 有关。
  - `--timeout 120s` 没有生效：失败信息仍是 10 分钟超时，因此这个挂起会让 `ci.sh` 的 host 套件多花约 10 分钟。

## 发现的缺陷（只记录，没有修复）

**D1：deepseek-chat 在预算题上四次都没有给出助手协议要求的 JSON，任务因 `FormatException` 失败（macOS 无头两次，Android 真机一次，macOS 设备一次）。**

- 平台：macOS 主机无头；模型 `deepseek-chat`，远程；代码 `6d21831`。
- 第 1 次：模型提议了 `inquiry.project_budget`，工具执行成功后，下一轮的最终回答是**纯文本**（“项目「北极星验收项目」的成本预算：成本合计 2080 元，销售合计 2080 元，毛利 0 元……”），不是协议 JSON。错误原文：`执行失败（FormatException: Unexpected character (at character 1) 项目「北极星验收项目」的成本预算：…）`。
- 第 2 次：第一轮回复就是 DeepSeek 原生工具调用标记，错误原文：`执行失败（FormatException: Unexpected character (at character 1) <｜｜DSML｜｜ calls>）`，没有工具被提议。
- Android 真机（vivo V2324A，Android 16，`integration_test`）：第一轮就是 `<｜｜DSML｜｜ calls>`，错误原文同第 2 次，预算题 0 轮、无工具。比价题同一次运行成功（`inquiry.compare_quotes`，2 轮，耗时 2665 ms）。
- macOS 设备（`integration_test`）：第一轮同样是 `<｜｜DSML｜｜ calls>`，预算题 0 轮、无工具；比价题成功，耗时 2217 ms。代码是 `369ecca`，**不含 P0-3d**（`ebc9bf6`），所以这里的 D1 失败是预期的，不是 P0-3d 的回归。链路在预算题读取失败后就终止了，没有走到写入，所以 JSON 里没有 `readResultsChecked` 和 `write.repeatConfirmRefused`。
- 以上四次运行的代码都早于 P0-3d。P0-3d 合入之后，macOS 设备运行了一次，预算题通过（见「第 3 批」）。这次运行中 D1 没有复现，但只跑了一次，不能据此说 D1 已经修复。
- 复现：`MUYON_EVAL_REAL=1`，端点 `https://api.deepseek.com`，模型 `deepseek-chat`，运行 `flutter test test/north_star_inquiry_test.dart`（`apps/muyon`）。比价题同一轮成功，失败只出现在预算题。
- 影响：真实模型对第二道只读题的表现不稳定；任务结果为 `failed`，错误文本里含模型的回答原文。P0-3c 只涉及「每道题都必须经由对应工具作答」的判定收尾，与这里的协议格式问题不是一回事；根因（模型输出格式、助手协议解析）由 leader 判断。

## 未验证的平台和原因

- **macOS 设备集成测试**：已运行一次（见上）。过程中遇到的环境问题，都不是代码问题：`xcodebuild -runFirstLaunch` 要先执行（用户已执行）；`flutter_inappwebview_macos` 不支持 Swift Package Manager，需要 CocoaPods（用户已 `brew install cocoapods`），并且要先 `flutter pub get` 才会生成 Podfile；首次运行时沙盒容器里缺 `Library/Caches/com.mightyoung.muyon` 目录，测试创建临时目录失败，我手动创建了这个空目录后重跑成功（第一次尝试写出的证据是空的 `{}`，已丢弃，没有入库）。
- **Android 真机**：已运行一次（见上）；测试包没有留在手机上（`flutter test` 结束后已卸载，`pm list packages` 复查无 muyon）。
- **Windows**：没有设备。
- **手动界面走查**：我不能操作应用界面，写「未执行」，交给用户。
- **`ci.sh`**：P0-1 尚未合入 `develop`。

## 其他说明

- **macOS 设备运行时的 `git status`**：工作区是 `review/P0-4` @ `369ecca`（`commit` 字段即它）。构建过程由 Flutter 和 CocoaPods 改动了 `apps/muyon/macos/Flutter/Flutter-Debug.xcconfig`、`Flutter-Release.xcconfig`、`Runner.xcodeproj/project.pbxproj`、`Runner.xcworkspace/contents.xcworkspacedata`（共 104 行增、3 行删），并生成了未跟踪的 `Podfile`、`Podfile.lock` 和两处 `xcshareddata/swiftpm/`；这些是 CocoaPods 集成的构建副产物，**没有任何 Dart 代码或其它目录的改动**。运行后我已用 `git checkout` 还原、删除了它们，没有提交。也就是说被测的 Dart 代码就是 `369ecca` 的内容，但 macOS 工程文件在运行时被构建流程改过。

- **运行时的工作区与 `git status`**：三次链路运行的 `commit` 字段是手工传入的（`MUYON_EVAL_COMMIT`）。两次 macOS 无头运行时，工作区是 `6d21831` 上的干净检出：运行前 `git status --short` 没有任何输出，运行产生的只有本批的未跟踪证据文件，没有已跟踪文件改动。Android 真机运行时工作区是 `f535db4`（`task/p0-4-evidence`，与 `origin` 一致，`git status` 干净）；`f535db4` 比 `6d21831` 只多证据与报告文档，没有代码改动，所以被测代码与 `6d21831` 相同。Android 运行之后我又尝试过一次 macOS 构建，它会让 Flutter 改动 `apps/muyon/macos` 下的 `xcconfig` 并生成 `Podfile`，那是构建副产物，已还原删除，没有提交，也不属于这三次运行。

- 证据 JSON 里调用栈中的本机绝对路径（含用户名）已替换成 `<repo>`，其余内容未改。

- 建议仍然在 Android 上跑一次时注意：设备运行要用 `--dart-define` 传密钥，**密钥会被编进这次构建的测试包**。运行后要卸载测试包，不要分发构建产物。
- 机器上同时跑着别的任务（负载很高），不影响这几项的结论，但门禁耗时不具参考价值。
