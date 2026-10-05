# P0-3 审查结论

审查对象：`task/p0-3-north-star` @ `92483af` · 审查：leader（代码核实由 Opus 子代理执行）· 日期：2026-10-06

**结论：修复后合并。** 没有阻断项。F1～F4 和 F8 应改，必须在任何真实模型证据入账之前完成；F6、F7 顺手改。

## 范围
相对 `develop` 共 10 个新增文件：`apps/muyon/integration_test/` 下 8 个、`apps/muyon/test/north_star_inquiry_test.dart`、`docs/implementation/north-star-inquiry-runbook.md`。没有修改生产代码、已有测试和已有文档。✅ 最大的文件是 `north_star_chain.dart`，473 行（拆分前 951 行），满足 800 行上限。✅

## 链路与交付核对
- 链路第 1、2、4、5、6、7 步都已执行并有断言。
  - 数据通过模块自己的领域函数写入。
  - 审批前没有回执也没有批准记录；摘要不对时被拒绝，且没有发生写入。
  - 关闭后重开，对话、消息、任务、回执、批准记录、`outbound_requests` 逐字节一致，询价单记录相同。
- 第 3 步（只读回答）：夹具模式下会核对种子数据，但这项核对可能被静默跳过（F2）；真实模型下判定偏弱（F1）。
- 共享驱动、无头夹具、设备入口（analyze 能编译，本环境没有设备，未运行）、`--dart-define` 支持、证据 JSON 字段与夹具标注，都已满足。

## 核实结果（子代理在 Linux 上重跑）
- `flutter analyze`（apps/muyon）：No issues found，覆盖 `integration_test/`。
- 无头链路：通过。首次运行含编译 40.7 秒，链路本身约 2 秒；另外连续跑 5 次，没有出现不稳定。
- 证据 JSON：`evidenceClass: fixture`，`realModelEvidence: false`，端点只保留到路径，前后账本计数一致。
- 宿主全量 `flutter test`：+397 ~1，全部通过；跳过的 1 项是 OCR 真实模型测试。
- 用回环假模型走真实模型路径做对抗探针，以下情况都如实失败：
  - 返回未注册的工具；
  - 只读阶段提出写入；
  - 写入阶段换成别的写入工具；
  - 声称写入但实际没有写；
  - 第二次 `create_inquiry`；
  - 返回非 JSON、HTTP 500。

  端点里带凭据时，在发出请求前就被拒绝，证据和输出里都不会出现密钥。

## 必须修复

### F1（应改）真实模型可以不调用工具就回答只读题，运行仍判为通过（`north_star_chain.dart:222-227`）
现在「只读题通过注册工具作答」是把两道题合起来判定的。探针中，预算题完全没有调用工具，证据却是 `passed: true`、`realModelEvidence: true`，该任务的 `tools: []`。按运行手册第 118、127 行，这样的运行会被当作 2.3 的 M 证据回填。
**修复：** 在 `_drive` 中逐题判定：每道只读题至少提出一个工具，并且该任务至少有一条成功的只读回执。不满足时整次运行失败，证据里记录失败原因。

### F2（应改）夹具模式下，只读结果的核对可能被静默跳过（`north_star_checks.dart:42-55`、`north_star_chain.dart:234`）
`checkReadResults` 只记录核对了哪几项，核对不上时并不断言；`total != 2` 时直接跳过预算核对。变异测试：让 `compare_quotes` 少返回一条报价，测试仍然全部通过，`readResultsChecked` 只剩 `project_budget`。
**修复：** 夹具模式下断言两项核对都执行了，并且直接断言 `total == 2`，不要在不等时跳过。

### F3（应改）运行手册中有链路并没有证明的说法
- 「审批只能用一次」（第 119、134 行）：链路只读取了 `state == 'consumed'`，从来没有尝试第二次确认。**修复**二选一：在链路中用同一个摘要再调用一次 `confirm`，断言被拒绝且没有生成新的询价单；或者删掉这个说法。leader 倾向补上这项断言。
- 9a「凭据不落盘」（第 120 行）：密钥通道在测试里是模拟的（`north_star_settings.dart:94-102`），没有在任何平台上实际测过系统钥匙串。**修复：** 改写为本次运行只能证明「端点显式、本次运行没有写出密钥」。
- 2.3 的 M 证据说法：F1 修复后，说明逐题必须经过工具。
- 第 90 行（原 F7）：`binding.reportData` 只有在 `flutter drive` 下才会回传，`flutter test` 下不会。改正说明。

### F4（应改）配置错误时，证据文件是空对象 `{}`，畸形 URL 还会被完整打印（`north_star_chain.dart:72`）
`NorthStarModelSettings.fromEnvironment()` 在 `try` 之外执行。只设一个变量或端点格式错误时，证据只有 `{}`，没有 `evidenceClass`、`passed`、失败原因，与运行手册第 127 行不符；带凭据的畸形 URL 会出现在测试输出里。
**修复：** 把这个调用移进 `try`。失败时照常写出带 `passed: false` 和脱敏原因的证据，异常信息里不包含原始 URL。

### F8（应改，leader 从可选提级）导出了环境变量就会静默调用真实模型
只要 shell 里导出了 `MUYON_EVAL_MODEL_*`，普通的 `flutter test` 或 `scripts/verify.sh` 就会用真实模型运行这条链路，产生网络请求和费用。P0-2 的真实评测也有同样的问题，已在 `review/P0-2` 上提出相同要求。
**修复：** 只有同时设置 `MUYON_EVAL_REAL=1` 才走真实模型。只设置了模型变量、没有这个开关时，按夹具运行，并在输出里提示一次「检测到模型变量但未设置 MUYON_EVAL_REAL=1，按夹具运行」。设备运行通过 `--dart-define=MUYON_EVAL_REAL=1` 传入。运行手册中的命令同步更新。

## 顺手修改
- **F6**：夹具中比较报价的回答引用的类型是 `product`，但 `compare_quotes` 返回的是 quotation 的引用，所以实际什么都没引用上（`answerReferences: 0`）。改为引用 `quotation`，并断言引用数大于 0。
- **F5（可选）**：`seed.suppliers`、`seed.budgetLines` 写死为 2，改为从 store 中统计。

## 修复方式
1. 执行者（senior）检出 `review/P0-3`，先合并最新的 `develop`（只有文档改动），再按上文修复，提交并推送到该分支。
2. 修复后重跑 `flutter analyze` 与无头链路，各贴出摘要；再用一个假模型演示 F1，即只读题不调用工具时运行失败，在提交说明中写清楚演示方法。
3. leader 派子代理复核后合入 `develop`。

---

## 复核（2026-10-06，`7ff3630`，Opus 子代理）

**结论：再小修一轮后合并。** 上一轮要求的 F1～F8 全部已修复，并用探针实测确认：
- **F1**：只读题不调用工具、或调用的工具失败，都会失败。
- **F2**：三种变异都能被抓到。
- **F3**：同一摘要重复确认会被拒绝，并且已写进证据；运行手册的说法已修正。
- **F4**：6 种错误配置都会写出 `passed:false` 和脱敏后的原因，证据和输出中没有密钥。
- **F8**：没有 `MUYON_EVAL_REAL=1` 时一律按夹具运行，并提示一次；`--dart-define` 也一样。
- **F5、F6、F7**：已完成。

**回归：**
- analyze 无问题，`dart format` 无改动；
- 无头链路连跑 3 次都通过，每次约 1.5 秒；
- 宿主全量测试 +397 ~1；
- 所有文件不超过 800 行；
- 第一轮的对抗探针仍然全部如实失败。

### 本轮必须修复

**R2-A（应改）失败原因被记错（`north_star_chain.dart:435` 先于 `:230-232` 执行）**
只读任务本身已经失败时，`_requireReadTool` 会先抛错。结果 HTTP 500、坏 JSON、未注册工具、只读阶段提出写入、工具执行失败，都被记成同一个原因：「answered without a registered read tool」。真实原因只留在 `tasks[].error` 里。运行手册要求记录 `failure`，所以第一次真实运行如果遇到 401 或 404，会被记成错误的原因。
**修复：** 在只读阶段，如果任务状态不是 succeeded，先抛出包含 `task.state.name` 和 `task.error`（已脱敏）的错误，再调用 `_requireReadTool`。

**R2-B（应改，leader 从可选提级）用无关的只读工具回答也能通过**
探针中，预算题通过 `knowledge.search` 作答，结果是 `passed:true`、`realModelEvidence:true`，但 `readResultsChecked` 只有 `compare_quotes`。这样的运行仍可能被记为 2.3 的 M 证据，而 2.3 要证明的是「能选对只读工具」。
**修复：** 真实模型模式下，同样要求两项核对都执行（与夹具模式的 `requireAll` 一致）。也就是说，每道题都必须经由能核对种子数据的询价只读工具作答，否则判定失败，并在 `failure` 中写明缺少哪一项。运行手册第 132 行同步写明：2.3 的 M 证据要求 `readResultsChecked` 同时包含两项。

### 顺手修复
- **R2-C**：只设置了 `MUYON_EVAL_REAL=1`、没有设置模型变量（或变量名拼错）时，现在会静默跑夹具，改为直接失败，证据写明「设置了 MUYON_EVAL_REAL=1 但缺少模型变量」。用户明确要求了真实模型，不能悄悄换成夹具。
- **R2-D**：夹具模式下只读核对失败时，没有写入 `readResultsChecked`，相应步骤也没有标为 `ok:false`。把核对放进 `_step` 中执行。
- **措辞**：运行手册第 73 行「只设一个会直接报错」只在设置了 `MUYON_EVAL_REAL=1` 时成立，改正这句话。

### 复核方式
修完推送后，leader 派子代理定向复跑 `http500`、`bad_json`、`unrelated_read_tool`、`skip_tool_budget` 探针，加上 R2-C 的配置、无头链路和 analyze，不再做全量审查。
