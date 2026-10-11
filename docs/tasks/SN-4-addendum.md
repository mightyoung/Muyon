# SN-4 补充范围（CR-12 后，leader A，2026-10-11）

SN-4 原任务见分支 `task/sn-4-real-source-cancel-fallback` 的 `docs/tasks/SN-4.md`。CR-12（`docs/reviews/2026-10-11-aiui-handover-review.md`）后扩为 I1+I2+I3，都在取消 / 退路这条线上：

- **I2（原范围加深）**：要贯通 source、Harness、renderer 三处——`inquiry_ui_planning_source.dart:19-41`、`ui_planning.dart:191-210`（先查取消终态再处理 source-null）、`ui_stream_task_view.dart:85-112`。区分「执行资格撤销」与「事实不能合法读取」；真撤权仍拒绝读取，不能删权限检查。
- **I1**：`PersonalAgent.cancel()` 里 UI 辅助清理失败不能短路原任务取消。同步撤 UI 能力 → 原任务取消独立完成 → 最后报告辅助清理错误。负例：只让 `ui_stream_diagnostics` 写入失败，原任务仍进入正确取消流程；活动工具仍按「发取消信号、真实回执决定终态」。
- **I3**：事实仍可读、仅允许动作收窄时，保留受约束的只读展示身份和最后预览，只撤执行能力（`ui_planning.dart:279-287`、`420-427`，`ui_stream_task_view.dart:163-184`）。屏障测试：第三次 source 检查只收窄动作集合 → 视图仍显示只读退路、零执行能力。

每项先 RED 后修，每项至少一处变异被抓到。回报仍按 SN-4 的 6 行格式，第 1、4 行按 I1/I2/I3 分别写。
