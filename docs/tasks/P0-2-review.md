# P0-2 审查结论

审查对象：`task/p0-2-llm-baseline` @ `8b8eb9c` · 审查：leader（代码核实由 Sonnet 子代理执行）· 日期：2026-10-06

**结论：修复后合并。** 正确性没有阻断项。F1、F2 两项应改，F3 因为关系到 P0-4 的取证质量，本轮一并修改，F4 顺手处理。

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

## 修复方式
1. 执行者（senior）检出 `review/P0-2`，先合并最新的 `develop`（只有文档改动），再修复上面各项，提交并推送到该分支。
2. 修复后重跑 `flutter analyze` 与上面两个测试文件，贴出摘要行和数量。
3. leader 派子代理复核后合入 `develop`。
