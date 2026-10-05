# 询价 North Star 链路：运行手册

任务 P0-3。驱动代码在 `apps/muyon/integration_test/support/north_star_*.dart`。两个入口共用同一份驱动：

| 入口 | 用途 |
|---|---|
| `apps/muyon/test/north_star_inquiry_test.dart` | 无头运行，随普通 `flutter test` 跑 |
| `apps/muyon/integration_test/north_star_inquiry_test.dart` | 在设备或桌面应用里跑 |

## 链路做了什么

1. `MuyonHost.open(新数据目录)`，激活询价模块。
2. 用询价模块自己的 `Store` 函数准备数据：
   - 一个项目，两条预算行：电缆 100 米、单价 11.80；桥架 20、单价 45.00。
   - 两家供应商。
   - 一张询价单和 4 条报价：电缆 甲 12.50 / 乙 11.80，桥架 甲 45.00 / 乙 47.20。
3. 在主对话里问两个只读问题：比较报价、项目预算。
   - 每一轮模型调用都和界面一样：读取 `requestDigest` 后再 `confirm`。
   - 断言**逐题**进行：每道只读题都必须提出至少一个工具，并且这道题至少有一条成功的只读工具回执。任何一题由模型直接作答、没有经过工具，整次运行就失败，失败原因写进证据。
   - 没有产生写入审批；询价单数量不变。
   - 工具返回的数值和种子数据一致：最低价、两条预算行、预算成本 2080。无论夹具还是真实模型，这两项核对都必须实际执行（步骤 `read.results`），缺了哪项会写进 `failure`。只读任务本身失败时（例如 HTTP 错误、坏响应、被拒绝的工具），`failure` 记录的是任务自己的状态和错误。
4. 在选中 5 个对象的专题对话里，请助手用 `inquiry.create_inquiry` 新建一张询价单。
5. 审批前确认三件事：没有任何回执，没有任何审批，用错误的摘要确认会被拒绝且什么都不写。然后用正确的摘要 `confirm`。
   审批后，再用**同一个摘要**确认一次：必须被拒绝，并且没有新增询价单、审批或回执（证据字段 `repeatConfirmRefused`）。
6. 审批后检查：
   - 审批记录只有一条，状态 `consumed`；
   - 回执 `succeeded`，摘要一致；
   - 询价库里能查到新询价单；
   - 任务的结果引用了这张询价单。夹具模式下还要求助手回答的引用里包含它。
7. 检查不变量：
   - 提供给模型的、模型提议的、实际执行的工具都在注册表里；
   - 只有一次写入；
   - 出站账本每次确认的模型发送各有一行，都是成功状态，HTTP 200，调用方是 `assistant`；
   - 夹具模式下，账本记录的载荷摘要和夹具收到的请求体逐字节一致。

   然后 `host.close()`，重开同一目录。对话、消息、任务、工具回执、审批、`outbound_requests` 和重开前逐项一致，新询价单的数据也一致。

不在链路里的：外发类写入（询价网页请求、供应商中心发布）、取消和中断、双设备。

## 三种运行方式

所有命令都在 `apps/muyon` 下执行。先按 `scripts/verify.sh` 的做法处理代理：

```bash
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy; export NO_PROXY=localhost,127.0.0.1,::1
```

### 1. 无头加夹具模型（本机，不需要密钥）

```bash
flutter test test/north_star_inquiry_test.dart
```

要写出证据文件时，加上 `MUYON_EVIDENCE_OUT`：

```bash
MUYON_EVIDENCE_OUT=/tmp/north-star-fixture.json flutter test test/north_star_inquiry_test.dart
```

夹具是一个只监听 `127.0.0.1` 的 OpenAI 兼容端点，按脚本返回助手协议 JSON。只有在主机确实把某个工具提供给了模型时，它才会提议这个工具。

### 2. 桌面加真实模型（无头，用环境变量）

真实模型必须同时设置 `MUYON_EVAL_REAL=1`。只设置了 `MUYON_EVAL_MODEL_*`、没有这个开关时，仍按夹具运行，并在输出里提示一次。这样 shell 里导出了模型变量，也不会让普通的 `flutter test` 或 `scripts/verify.sh` 发出真实请求。

```bash
MUYON_EVAL_REAL=1 MUYON_EVAL_MODEL_ENDPOINT=https://<提供方>/v1 MUYON_EVAL_MODEL_ID=<模型 id> MUYON_EVAL_MODEL_KEY=<密钥> MUYON_EVIDENCE_OUT=/tmp/north-star-real.json MUYON_EVAL_COMMIT=$(git rev-parse --short HEAD) flutter test test/north_star_inquiry_test.dart
```

- `MUYON_EVAL_MODEL_KEY` 可以不设，例如本机模型不需要密钥。
- `MUYON_EVAL_MODEL_LOCATION`（`local` / `ownDevice` / `remote`）可以不设：端点是回环地址时记为 `local`，否则记为 `remote`。
- `MUYON_EVAL_DEVICE_LABEL` 可以写一个设备说明。
- 设置了 `MUYON_EVAL_REAL=1` 时，端点和模型 id 都必须设置。缺任何一个（包括变量名拼错），运行都会直接失败，证据里写明缺少模型变量，不会悄悄改用夹具。没有这个开关时，模型变量一律不生效。
- 端点必须是完整的 URL，不能带用户信息、查询参数或片段。配置有误时运行失败，但仍会写出完整的证据（`passed: false` 和原因），错误信息不会引用你配置的值。
- 密钥只在这次运行里经过测试用的密钥通道，不会写进本次运行的数据库、证据和日志。证据里只写 `"credential": "env (not stored)"`。这个通道在测试里是模拟的，所以这次运行**不能**证明应用平时使用的系统钥匙串是安全的。

### 3. Android / macOS 设备加真实模型（集成测试）

设备上的应用读不到主机的环境变量，所以改用 `--dart-define`：

```bash
flutter test integration_test/north_star_inquiry_test.dart -d <设备 id> --dart-define=MUYON_EVAL_REAL=1 --dart-define=MUYON_EVAL_MODEL_ENDPOINT=https://<提供方>/v1 --dart-define=MUYON_EVAL_MODEL_ID=<模型 id> --dart-define=MUYON_EVAL_MODEL_KEY=<密钥> --dart-define=MUYON_EVIDENCE_OUT=north-star-evidence.json --dart-define=MUYON_EVAL_DEVICE_LABEL=<设备说明> --dart-define=MUYON_EVAL_COMMIT=<提交>
```

- **密钥会被编进这次构建的测试包。** 请使用临时的或额度受限的密钥，跑完后卸载测试包，不要分发这次的构建产物。
- 不加 `MUYON_EVAL_REAL=1` 时，设备上也用夹具模型。这样的运行是 R 证据，但不是 M 证据。
- 证据文件 `MUYON_EVIDENCE_OUT` 用相对路径时：
  - Android 写到应用的外部文件目录，取回方式：

    ```bash
    adb pull /sdcard/Android/data/com.mightyoung.muyon/files/north-star-evidence.json
    ```

  - macOS 写到应用的文稿目录。
- 证据同时会按 `MUYON_NORTH_STAR_EVIDENCE[i/n]` 分段打印到测试输出里。它也会写进 `binding.reportData['northStar']`，但只有用 `flutter drive` 运行时才会回传到主机，用 `flutter test` 运行时不会。
- 注意事项：
  - Android 上运行会覆盖安装同一个 `com.mightyoung.muyon`，不要和其他人的真机取证同时进行。
  - macOS 需要本机装好 Xcode。
  - Windows 的凭据走 FFI，测试用的密钥通道覆盖不到，Windows 设备上只能用不需要密钥的端点。

## 证据格式

JSON，`kind` 为 `muyon-north-star-inquiry`，`schema` 为 1。主要字段：

| 字段 | 内容 |
|---|---|
| `evidenceClass` / `realModelEvidence` | `fixture` / `false`，或 `real-model` / `true` |
| `note` | 这次运行能证明什么。夹具运行明确写着"NOT real-model (M) evidence" |
| `model` | 端点（只保留协议、主机、端口和路径，不含查询参数和用户信息）、模型 id、位置、凭据方式；夹具运行还带 `fixture: true` |
| `device` | 平台、系统版本、Dart 版本、处理器数、`label`，以及运行入口 `binding` |
| `commit` | `MUYON_EVAL_COMMIT` |
| `steps` | 每一步的名称、是否成功、耗时（毫秒） |
| `tasks` | 每个任务的阶段、状态、模型和工具确认次数、轮数、使用的工具、回答前 200 字、引用数；只读题还有成功的只读回执 `readReceipts` |
| `write` | 审批前后的询价单数量、错误摘要被拒、重复确认被拒、从审批到出结果的耗时、询价单 id、回答是否引用它 |
| `ledger` / `receipts` | 账本行数和状态分布、发送字节数；回执行数和按工具的分布 |
| `beforeReopen` / `afterReopen` / `reopenIdentical` | 重开前后的计数，以及是否逐项一致 |
| `passed` / `failure` | 失败时记录错误和前 8 行调用栈 |

## 回填验收账本

| 账本行 | 夹具、无头 | 真实模型、桌面 | 设备（夹具或真实模型） |
|---|---|---|---|
| 2.3 询价完整业务和受控工具 | T：只读工具返回模块自己的结果；审批后的写入能在库里查到 | 再加 M：真实模型对**每一道**只读题都经已注册的只读工具作答（运行逐题强制），而且 `readResultsChecked` 同时包含 `compare_quotes` 和 `project_budget`，即两道题都用了能核对种子数据的询价只读工具（运行强制）；还要能选对写入工具 | 再加 R |
| 7 统一调用路径和审批 | T：先给出摘要再执行；错误摘要被拒；审批只能用一次；回执、账本和重开后一致 | 同左，并加上真实网络的出站账本 | 再加 R |
| 9a 模型端点显式、凭据安全 | 只有 T，而且只能证明端点显式记账 | M：端点是显式配置的，账本 HTTP 200，本次运行没有写出密钥。不能证明系统钥匙串的安全性，因为测试里的密钥通道是模拟的 | 再加 R（同样不涉及钥匙串）；Windows 除外 |

回填时写上：
- 证据文件的位置（不要提交到仓库，可以放进 PR 或审查分支的附件）；
- `commit`、`evidenceClass`、设备和 `binding`；
- `steps` 里关键步骤的耗时。

只有 `passed: true` 的证据才能回填。真实模型运行失败也要记录，包括失败在哪一步、`failure` 里的内容。

## 夹具运行能证明什么、不能证明什么

**能证明**，宿主侧的连接都是对的：
- 模型的每一轮都要确认，确认要带摘要；
- 只读问题经注册表里的只读工具回答，不会写入；
- 写入只在用户审批之后执行，错误的摘要会被拒绝，审批只能用一次；
- 回执、审批、出站账本、对话和任务在重开后都还在，而且一致；
- 账本记录的正是端点实际收到的字节。

**不能证明**：
- 真实模型会不会选对工具、填对参数、引用对的对象。夹具的回答是脚本写好的，带"[夹具回答，不是真实模型]"前缀。
- 真实网络和提供方的行为：鉴权、超时、限流、非 200 响应。
- 在 `binding` 为 `flutter_test (headless)` 时，任何真机行为。它是在主机上跑的，不是 R 证据。

真实模型运行时只断言不变量：每道只读题都经过只读工具、工具只来自注册表、写入只在审批之后且审批只能用一次、重开后记录还在、出站账本有记录。不断言回答措辞，也不要求回答里一定有引用（夹具模式才要求），但要求写入结果引用新询价单。

## 已验证的运行（截至交付时）

- **无头加夹具**（macOS 主机，`flutter_test (headless)`）：通过。链路本身约 2–3.5 秒，加上编译，整个 `flutter test` 进程约 17–18 秒。
- **macOS 设备集成测试**：**未运行**。本机没装 Xcode，构建 macOS 应用时报 "Xcode not installed"。
- **Android 设备集成测试**：**未运行**。唯一一台 Android 真机正在被别的任务用于 2.4 真机取证，在上面运行会覆盖安装同一个应用。
- **只读题不经工具时运行失败**（F1 演示）：用回环假模型走真实模型路径（`MUYON_EVAL_REAL=1`，端点指向本机假模型）。假模型对比价题调用 `inquiry.compare_quotes`，对预算题直接回答、不调用工具。结果：比价那一步通过，`assistant.read.project_budget` 那一步失败，`passed: false`，失败原因为 "answered without a registered read tool"。
- **真实模型**：**未运行**。需要用户提供 `MUYON_EVAL_MODEL_*`。
