# OC-7 评测报告里「没有样本」不再显示成 0 ms（小改 + 1 个测试）

分支 `task/oc-7-eval-empty-latency` · 基线 develop · 执行：opencode · 审查：leader A

## 问题
`apps/muyon/lib/assistant/agent_eval/agent_eval_report.dart` 第 91～92 行把首响应和总耗时的 p50 / p95 写进报告表格：`_ms(percentile(s.firstResponseMs, 0.5))` 等。`percentile` 在列表为空时返回 0，所以某类任务一个耗时样本都没有时，报告里会写「0 / 0」，看起来像「0 毫秒」。（CR-5 延迟调研指出的问题。）

## 只改这些
1. 在同一文件 `_ms` 函数（第 73 行）下面加一个函数：
```dart
String _latency(List<num> values, double p) =>
    values.isEmpty ? '未观察到' : _ms(percentile(values, p));
```
2. 把第 91～92 行里的四处 `_ms(percentile(X, P))` 换成 `_latency(X, P)`。
3. **不要改** `percentile`、`median`、`mean` 本身（已有测试 `agent_eval_test.dart:608` 依赖空列表返回 0）。

## 加 1 个测试
在 `apps/muyon/test/agent_eval_test.dart` 里找到生成报告表格行的现有测试（搜 `_row` 的调用方或报告文字 `| `），照它的写法加一个测试 `empty_latency_samples_render_as_not_observed`：构造一个 `firstResponseMs` 和 `totalMs` 都为空的 `CategorySummary`，生成报告，断言那一行包含 `未观察到`，且不包含 `| 0 / 0 |`。如果找不到能从测试里调到这一行的公开入口，**停下回报**，不要把私有函数改成公开。

## 自检
1. 先只加测试、不改 lib，跑一次：新测试必须失败。记下失败信息第一行。
2. 改 lib 后跑 `cd apps/muyon && flutter test test/agent_eval_test.dart`，全部通过。保留代理设置，`NO_PROXY` 加 `localhost,127.0.0.1,::1`；**不导出 `MUYON_EVAL_REAL`**。
3. `cd apps/muyon && flutter analyze`：0 个问题。
4. `dart format` 只格式化改动的两个文件。

## 提交与回报
一个提交：`fix(eval): show missing latency samples as not observed`，只含这两个文件，推到 `task/oc-7-eval-empty-latency`，`git ls-remote` 确认。

**回报必须是下面 5 行，每行都要有内容，否则视为未完成：**
1. 提交哈希：
2. 修改前新测试的失败信息第一行：
3. 修改后 `agent_eval_test.dart` 的通过 / 失败 / 跳过数：
4. `git diff --stat origin/develop` 的输出：
5. analyze 最后一行：
