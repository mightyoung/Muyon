# P0-2 审查结论

审查对象：`task/p0-2-llm-baseline` @ `8b8eb9c` · 审查：leader（代码核实由 Sonnet 子代理执行）· 日期：2026-10-06

**结论：修复后合并。** 正确性没有阻断项。F1、F2、F5 三项应改，F3 因为关系到 P0-4 的取证质量，本轮一并修改，F4 顺手处理。

## 范围
相对 `develop`，三点 diff 只有 3 个文件：`selection_eval.dart`、新增的 `llm_selection_eval.dart`、新增的 `test/llm_selection_eval_test.dart`。没有修改已有测试和已有文档；`tool-selection-eval-2026-10-05.md` 中 LLM 一行仍是 not measured。✅

## 交付核对
交付 1～4 全部满足，交付 5 部分满足（问题见 F2）。重点核实结果：
- **离线数字不变**：子代理把 develop 上旧版 `selection_eval.dart` 与本分支版本并排运行，`SelectionScore` 完全相同：top-1 54/140，exact 28/28，chinese/mixed/paraphrase 各 0/28，弃权 26/26，误选写入 0，校准桶一致。
- **失败不算作正确的 none**：
  - 140 次请求全部返回 HTTP 500 时，top-1 为 0/140，弃权 0/26；
  - 全部返回未注册工具名时同样为 0/26；
  - 对 none 题返回写入工具时，误选写入/外发为 26。
- **门控**：普通 `flutter test` 跳过真实运行，不发出任何请求。只有设置 `MUYON_WRITE_EVAL_REPORT=1` 时才写报告，报告按 slug 命名（例如 `probe:model` 生成 `probe-model`）。
- **凭据处理**：端点含用户信息或查询参数时，在发出请求前就被拒绝；报告中的端点会去掉凭据。

## 核实结果（子代理在 Linux 上重跑）
- `flutter analyze`（apps/muyon）：No issues found。
- `flutter test test/selection_eval_test.dart test/llm_selection_eval_test.dart`：+15 ~1，全部通过；跳过的那一项是需要真实模型的测试。
- 宿主全量 `flutter test`：+409 ~2，全部通过；两项跳过都是需要真实模型的测试。

## 必须修复

### F1（应改，安全）密钥格式异常时会被原样打印
复现方法：`MUYON_EVAL_MODEL_KEY` 末尾带 `\r`，或含有全角字符。Dart 设置请求头时抛出的 `FormatException` 会包含完整的 `Bearer <密钥>`。这段文字经 `llm_selection_eval.dart:277-284` 进入 `LlmChoice.error`，再由测试的 `reason`（`llm_selection_eval_test.dart:692-696`）打印到终端或 CI 日志；只有部分请求失败时，还可能写进报告里的「错误」格。
**修复：**
1. 真实运行开始前校验密钥只包含可见 ASCII 字符（`^[\x21-\x7E]+$`）。不符合时抛出不含密钥值的 `ArgumentError`。
2. `catch` 中对错误文本做脱敏：把 `Bearer\s+\S+` 替换成 `Bearer <redacted>`。更稳妥的做法是只记录异常类型和不含请求头的消息。
3. 增加一个夹具测试：用格式异常的密钥运行，断言 `choice.error`、报告和测试输出中都不出现密钥。

### F2（应改，文档与取证）顶部注释说网关「无论哪种都直连」，这不对
dart:io 的 `HttpClient` 默认会使用 `https_proxy` 与 `HTTPS_PROXY`，子代理已用回环监听确认收到了 `CONNECT`。注释给出的命令会去掉所有代理变量，所以在必须走代理才能访问远程端点的机器上，真实运行连不上。这正是 P0-4 会遇到的情况。
**修复：**
1. 改正注释，写明这条命令会绕过代理。
2. 补充需要代理时的写法：保留 `HTTPS_PROXY`，同时设置 `NO_PROXY=localhost,127.0.0.1,::1`，让 Flutter 测试的本地 websocket 仍然直连。
3. 在你本机实际验证这种写法，可以用你手上的远程端点只发 1 题，或者让一个回环测试在保留代理变量的情况下通过。在提交说明里写清楚验证方法和结果，**不要贴出密钥和私有地址**。

### F3（本轮修复）超时时间固定为 45 秒，不能配置
推理模型或慢速本机模型容易超时，超时会计为错误，污染 P0-4 的基线。
**修复：** 测试读取可选的 `MUYON_EVAL_MODEL_TIMEOUT_SECONDS`，传给网关的 `timeout`；在顶部注释的命令说明里加上这个变量。

### F4（顺手处理）
- `test/llm_selection_eval_test.dart` 没有通过 `dart format`。只格式化这个文件。
- 可选：加一个连接被拒绝时的夹具测试。

### F5（应改，leader 在审查 P0-3 时追加）导出了环境变量就会静默调用真实模型
只要 shell 里导出了 `MUYON_EVAL_MODEL_ENDPOINT` 与 `MUYON_EVAL_MODEL_ID`，普通的 `flutter test` 或 `scripts/verify.sh` 就会对 140 题发出真实请求，产生费用。P0-3 也有同样的问题，两处统一处理。
**修复：** 只有同时设置 `MUYON_EVAL_REAL=1` 才进行真实运行。只设置了模型变量、没有这个开关时跳过，跳过原因写明需要这个开关。顶部注释中的命令同步加上这个开关。

## 修复方式
1. 执行者（senior）检出 `review/P0-2`，先合并最新的 `develop`（只有文档改动），再修复上面各项，提交并推送到该分支。
2. 修复后重跑 `flutter analyze` 与上面两个测试文件，贴出摘要行和数量。
3. leader 派子代理复核后合入 `develop`。

---

## 复核（2026-10-06，`653e5e4`，Sonnet 子代理）

**结论：通过，合入 `develop`。**

- **范围**：本轮只改了两个评测文件。文档改动与 `develop` 自身的变化逐字节一致，修复提交没有新写任何文档。`selection_eval_test.dart` 没有改动。
- **F1 已修复**：
  - 密钥含回车或全角字符时，在发出请求前就失败，提示 `value not shown`，探针服务器一次请求都没收到。
  - 绕过前置检查直接调用时，含 `bearer` 或 `authorization` 的错误文本整体不予显示，比审查建议的局部替换更严格。
  - 正常密钥 `sk-abc_DEF.123` 能完整跑完 140 题。
- **F2 已修复**：文档写明 dart:io 会使用 `HTTPS_PROXY` 和 `NO_PROXY`。按文档的「保留代理 + `NO_PROXY`」写法，在本环境实测：
  - 测试框架正常运行，回环请求不经过代理；
  - 去掉 `NO_PROXY` 后测试框架崩溃，说明这项设置是必需的；
  - 远程请求确实经过代理。

  提交说明里没有密钥，也没有私有地址。
- **F3 已修复**：`MUYON_EVAL_MODEL_TIMEOUT_SECONDS` 已经生效：
  - 超时的请求按错误计分，不会被算成 none；
  - 0、-1、abc、1.5 这类非法值，在发出请求前就被拒绝。
- **F5 已修复**：只导出模型变量、没有设置 `MUYON_EVAL_REAL=1` 时，测试会跳过并说明原因，探针收到 0 次请求。
- **F4 已完成**：`dart format` 检查通过，并新增了连接被拒绝的测试。
- **回归**：
  - analyze 无问题；
  - 两个评测文件 +19 ~1；
  - 宿主全量测试 +413 ~2；
  - 第一轮的各项探针结果不变：500 → 弃权 0/26；未注册名 → 0/26；写入误选 26。

### 留作记录
- **另开 P0-S1（安全修复）**：`model_gateway.dart` 请求失败时把 `'$error'` 写进出站账本；`personal_agent.dart` 也把错误文本写进任务记录并显示在界面上。密钥格式异常时，这两处文本都会含 `Bearer <密钥>`。这个问题不在本任务范围内，因为评测不使用账本。
- **原有问题**：设置 `MUYON_WRITE_EVAL_REPORT=1` 后跑全部测试，会覆盖 `tool-selection-eval-2026-10-05.md`。文档里的命令都限定了 `--plain-name`，按文档运行是安全的。
- **小问题**：「保留代理」那条命令里没有带 `MUYON_EVAL_MODEL_TIMEOUT_SECONDS`，这个变量在命令上方已有说明。
