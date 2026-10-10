# OC-2 审查（leader A，2026-10-10）

提交 `3012d54`（测试）、`3d7d1c6`（删包装）· 结论：**通过，可合入**。

- 范围：新增 `apps/muyon/test/reduce_motion_readback_test.dart`（50 行）；`business_tools.dart` 只删 `registerBusinessTools` 及其注释 6 行。`registerInquiryTools` 仍由 `inquiry_module.dart:65` 和测试使用，未动。删除后代码里已无 `registerBusinessTools` 引用（ADR-0004 第 32、353 行的旧描述是历史文字，留待文档整理）。
- 复跑（`git archive` 副本，保留代理、`NO_PROXY` 含 localhost，无 `MUYON_EVAL_REAL`）：`flutter analyze` 无问题；新测试 2 例加 `widget_test.dart` 共 3 例通过。
- 变异：`app_shell.dart` 里 `setting('reduceMotion') == true` 改为 `false` → `reduce_motion_stored_true_disables_animations_on_open` 失败，被检出。
- 意见（不阻断）：回报仍只给了提交号，测试、变异、analyze 结果由审查方补跑。
