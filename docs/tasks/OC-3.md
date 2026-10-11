# OC-3 放宽公式变异测试在负载下的超时（只改一个测试文件）

分支 `task/oc-3-formula-mutation-timeout` · 基线 develop `6c821d6` · 执行：opencode · 审查：leader A

## 背景
GROK-8 和多文件并发跑测试时，`apps/muyon/test/ui_formula_registry_mutation_test.dart` 的 `source mutation is killed: sum_decimal_exact_and_unit_checked` 超时失败；单独跑能通过（整个文件约 2 分钟）。原因：每个用例要启动两次 `dart` 子进程（基线和变异），子进程等待上限 45 秒，整例上限 120 秒，负载高时不够。

## 只改这两处（都在这个测试文件里）
1. 第 57 行左右：`process.exitCode.timeout(const Duration(seconds: 45))` 改成 `Duration(seconds: 150)`。
2. 第 78 行左右：`timeout: const Timeout(Duration(seconds: 120))` 改成 `Duration(seconds: 360)`。

除此之外一个字都不改。不要改断言、不要加 `skip`、不要改 `lib/`。

## 自检（结果逐项写进回报）
1. `cd apps/muyon && flutter test test/ui_formula_registry_mutation_test.dart`，全部通过，记下通过数和总耗时。跑测试时保留代理设置，只把 `localhost,127.0.0.1,::1` 加进 `NO_PROXY`；不导出 `MUYON_EVAL_REAL`。
2. `git diff --stat` 只显示这一个测试文件，且只有 2 行改动（`2 insertions(+), 2 deletions(-)`）。
3. `cd apps/muyon && flutter analyze`，0 个问题。

## 提交与回报
提交说明 `test(aiui): widen formula mutation timeouts for loaded runners`，推到 `task/oc-3-formula-mutation-timeout`，`git ls-remote` 确认远端哈希与本地一致。
回报**必须逐项写**：提交哈希；测试通过数与耗时；`git diff --stat` 原样输出；analyze 结果。只给提交号的回报不算完成。
