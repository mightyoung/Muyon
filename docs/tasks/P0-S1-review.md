# P0-S1 审查结论

审查对象：`task/p0-s1-credential-redaction` @ `31f775a` · 审查：leader（代码核实由 Opus 子代理执行）· 日期：2026-10-06

**结论：小修后合并。** 没有阻断项。F1、F2、N2 本轮修复；F3 由 leader 认可；F4 另开 [P0-S2](P0-S2.md)。

## 范围
共 11 个文件（+422/−20），都与说明相关。`platform_shell.dart` 增加的 1 行只是 import：`platform_shell_personal.dart` 是它的 `part`，必须从这里引入。✅

## 核实结果
- **R1 共享脱敏函数：满足。** 规则与评测原来的实现一致：匹配 `bearer|authorization`，不区分大小写，命中时整条不显示、只保留类型。评测已经改为引用这个共享函数，旧副本已删除。
- **R2 网关提前校验：满足。** 用 11 种异常密钥做了探针：CR、LF、全角数字、全角空格、NUL、制表符、空格、前导空格、DEL、é、零宽空格。全部抛出 `credential_invalid`，`beforeSend` 调用 0 次，请求数为 0，账本行数为 0。包含全部可见 ASCII 标点的正常密钥能端到端跑通。
- **R3 账本脱敏：满足。** 读回实际的 SQLite 行，两种带 `Bearer` 的异常写入的都是 `details withheld`；超时和取消写入的是固定文本；网关出口也做了脱敏。
- **R4 调用方：满足。** 逐一核对结果：
  - `personal_agent`、`qa_service`、`dream_service` 已处理；
  - `embedding_service` 不涉及，错误文本经工具注册表记为固定文本；
  - `inquiry_plugin` 的保存有校验，传输经过网关；
  - 询价页面由网关出口兜底。

  全仓检索约 96 处错误文本流向，没有别的地方会把网关错误原样写出。
- **R5 设置界面：部分满足。** 平台设置和询价的保存入口都做到了：拒绝保存，提示文字一致，不写入钥匙串，界面上也不显示密钥。漏了科研工具页的入口，见 F2。
- **验证：**
  - analyze 无问题，格式化没有改动；
  - 4 个指定测试文件：+42 ~1；
  - 宿主全量：+420 ~2，即 P0-2 合入后的 +413 加上本次新增的 7 个。
- **变异测试：**
  - 去掉网关的提前校验：被测试抓到；
  - 去掉设置界面的校验：被测试抓到；
  - 去掉助手的脱敏：**没有被抓到**；
  - 去掉评测的脱敏：**没有被抓到**。

## 本轮修复

**F1（应改）两处调用方的脱敏没有测试守护**
助手的测试只走到 `credential_invalid` 这一步，这段文本本来就不含密钥。所以去掉 `personal_agent.dart:378` 或 `llm_selection_eval.dart:306` 的脱敏，测试仍然全部通过。子代理用一个跳过脱敏的网关子类复现了：密钥会进入 `task.error` 和通知正文。
**修复**：用一个跳过网关脱敏的子类（覆写 `chat` 或 `request`，抛出 dart:io 原样的 `FormatException`，消息里带 `Bearer <密钥>`），分别为助手（检查 task error、通知、会话消息）和评测的 `chooseWithModel`（检查 `choice.error`）补测试，断言其中都没有密钥。同时改正 `llm_selection_eval_test.dart` 第 645-646 行和第 675-677 行的注释。

**F2（应改）科研工具页的密钥保存没有校验**
`app/research_tools_page.dart:270-348` 的「配置模型端点」对话框在第 347 行写入密钥，但没有调用 `isSendableCredential`。入口路径：工作台 → 科研工作台 → 检索与资料问答。这里不会泄漏密钥（网关后面会拒绝），但格式异常的密钥会被静默保存，之后所有请求都失败。
**修复**：加上同样的校验和提示，并补一个 widget 测试。

**N2（应改，来自 [P0-3 第 2 轮复核](P0-3-review.md)）错误文本中出现密钥本身时不会被清除**
如果端点在 200 响应体里回显密钥，`FormatException` 的消息会带上这段响应体。它不包含 `bearer` 或 `authorization` 这类关键词，所以脱敏规则不会命中。密钥随后会进入证据、`tasks[].error` 和测试输出。
**修复**：网关在出口和写账本时，除了按关键词整条隐藏，还要把**本次请求实际使用的凭据值**在文本中替换为 `<redacted>`，凭据非空时执行。补测试：模拟端点返回 200，响应体为 `invalid key <密钥>`，断言网关抛出的错误和账本行里都不含密钥。

## leader 认可
- **F3**：已有测试 `llm_selection_eval_test.dart:675-678` 的断言从 `details withheld` 改成了 `credential_invalid`。原因是 R2 让格式异常的密钥在设置请求头之前就被拒绝，原来的断言不可能再成立。保密相关的断言都还在：不含 `SECRET`、报告不含 `SECRET`、`requests == 0`，提交说明中也已披露。**认可这处改动**。它导致评测自身的脱敏失去测试，由 F1 补上。

## 另开任务
- **F4 → [P0-S2](P0-S2.md)**：MCP 令牌有同类泄漏，位置在 `platform/mcp_adapter.dart:208`，显示在 `mcp_servers_page.dart:213`。

## 只记录
- **F5**：脱敏只匹配关键词，`api_key=`、`x-api-key:`、`Basic <令牌>` 都不在规则内。目前网关只把密钥放在 `Bearer` 之后，所以现在不构成缺口。N2 修复后，回显密钥值的情况也能覆盖。以后接入用查询参数或 `x-api-key` 传密钥的服务时，需要重新检查这一点。
- **F6**：询价设置会先修剪掉密钥首尾的空白再保存（`ai_settings.dart:70`，模块原有的行为）。被拒绝时，提示前缀「无法写入系统安全存储」有误导性。
- **F7**：单行输入框本身会去掉 `\n`，所以粘贴 `key\n` 会保存为 `key`。这无害。
- **F8**：`addProfile` 在对话框的退出动画期间就释放了输入框的 controller，导致「used after being disposed」。这是 `develop` 上已有的缺陷，执行者已披露。

## 修复方式
1. 执行者（senior）检出 `review/P0-S1`，按上文修复，提交并推送。
2. 回报中附：analyze 结果、新增测试的名称、宿主全量测试的数量。
3. leader 派子代理定向复核，重跑 M2、M4 变异和 N2 探针。

## 复核（2026-10-06，接任 leader；核实子代理 Opus）

修复提交 `31f775a`、`ee9843d`。**结论：暂不合并，发现 1 阻断。**

| 项 | 结论 | 依据 |
|---|---|---|
| F1 调用方脱敏有测试守护 | 满足 | `credential_redaction_callers_test.dart:70-124`；去掉 `personal_agent.dart:378` 或 `llm_selection_eval.dart:306` 的脱敏，对应测试失败 |
| F2 科研工具页密钥校验 | 满足（测试有弱点，见 R3） | `research_tools_page.dart:334-339`；widget 测试 `:164-232` 断言是实的 |
| N2 回显密钥被清除 | **部分满足** | 短密钥有效；常见长度的密钥无效，见 R1 |

- 重跑：`flutter analyze`（apps/muyon）`No issues found!`；宿主全量 `+424 ~2: All tests passed!`，与执行者自述一致。
- 变异：助手脱敏、评测脱敏、N2 `replaceAll(secret)`、F2 校验，四处改坏后对应测试都失败；其中 F2 是 10 分钟超时才失败。
- 探针：含正则特殊字符的密钥按字面替换，没有异常；短密钥 `sk-SECRET-7` 各处都是 `<redacted>`。

### 本轮修复（senior，在 `review/P0-S1` 上）

**R1（阻断）N2 对常见长度的密钥无效。**
`model_gateway.dart:291` 用 `jsonDecode` 解析 200 响应体；失败时 `FormatException.toString()` 把超过 78 字符的源行截断为约 75 字符。164 字符的真实格式密钥只露出一部分，`replaceAll(完整密钥)` 匹配不到，密钥前 63 个字符进入网关抛出的错误、账本 `outbound_requests.error`、`task.error` 和通知正文。
**修复**：网关解析响应失败时，抛出不带源文本的固定错误（例如 `FormatException('model_response_not_json')`），不依赖事后替换。测试改用 80 字符以上的密钥，并断言错误和账本行中不出现密钥的任意 12 字符片段。

**R2（应改）模型正文回显密钥时，会经助手进入任务错误。**
`personal_agent.dart:425` 对模型文本 `jsonDecode` 失败时，异常带着模型原文，`:378` 的脱敏不知道密钥。这是原有路径，但正属于本任务的范围。
**修复**：协议解析失败时只记固定原因（例如 `model_reply_not_json`），不引用模型原文。补测试：模型正文为含长密钥的非 JSON 文本，断言 `task.error`、通知和会话消息中都不含密钥片段。
注意：同一处还有 D1（模型不按协议回答，见 [P0-4 审查](P0-4-review.md)），会另开 P0-3d 在本任务合入后处理，**本轮不要改协议的容错行为**，只改错误文本。

**R3（应改，轻）F2 测试要靠 10 分钟超时才能发现变异。**
`credential_redaction_callers_test.dart:211-212`：点击保存后改用有限次 `pump`，在任何 IO 之前先断言提示文字和对话框仍在。

**可选（建议顺手做）**
- **R4** 极短密钥（如 1 个字符）会让错误文本被大面积打码，并把错误类型改成 StateError。只在 `secret.length >= 8` 时做值替换（`credential_redaction.dart:26`）。
- **R5** `llm_selection_eval_test.dart:648` 注释指向的文件名有误；`credential_redaction_callers_test.dart:129` 设置的 `HttpOverrides.global = null` 没有在 tearDown 中恢复；`credential_redaction_test.dart` 没有 `secret:` 参数的单元测试。

### 合并时注意
`git merge-tree` 显示与 `develop` 在 `apps/muyon/lib/screens/platform_shell.dart` 的 import 处冲突（E11 加了 `object_pages.dart`）。两行都保留，按字母序排列。可以由执行者在本分支先合并 `origin/develop` 解决，也可以由 leader 合入时解决。

### 修复方式
1. 执行者（senior）检出 `review/P0-S1`，先 `git merge origin/develop` 解决上述冲突，再修 R1～R3（R4、R5 建议顺手），提交并推送。
2. 回报中附：analyze 结果、新增测试名称、宿主全量测试数量。
3. leader 派子代理定向复核 R1～R3（长密钥探针重跑）。
4. P0-S2 基于本分支，需要在 P0-S1 合入后再合并一次 `develop`，然后核实。
