# CF2 与 library2 契约独审（CR-CF2-LIB2，Haiku）

基线 develop `ab5506c3`；反例测试在 `task/cr-cf2-library2-review-20261012` @ `6780a8aa`（只写反例，不改生产代码）。

| 编号 | 级别 | 问题 | 位置 | 反例与失败首行 |
|---|---|---|---|---|
| C1 | Critical | GAP1：计算绑定 `verified` 证据但值为 null 仍被接受（`isUiScalar(null)` 为真，未比较 evidence state 与值） | `muyon_module_api/lib/src/ui/validation.dart:494-512`、`:59-63` | `a computed total claiming verified with a null value is rejected`：Expected false / Actual true（control：null + notDisclosed 仍接受，通过） |
| C2 | Critical | 旧值无「旧结果 / 上次计算」标注、无逐值 freshness；`UiSurfaceController.outdated` 无 UI 读取 | `muyon_ui/lib/src/dynamic/surface.dart:140` | `an outdated surface labels its previous values as an old result`：Found 0 widgets with text containing 旧结果 |
| I1 | Important | end-only 流（模型不出卡）被判 `invalid_plan` | `apps/muyon/lib/assistant/stream_ui_planning.dart:111-115` | PR #58 N1a / N1b：Expected 'model_no_card' / Actual 'invalid_plan' |
| I2 | Important | 用户在规划暂停时切「只用文字」被判 `host_state_changed` | `ui_planning.dart:387-396`（`:394` 的 `mode != selectedMode`） | N2a：Expected 'user_text_only' / Actual 'host_state_changed' |
| I3 | Important | complete 流在无呈现时显示「界面流未完成」；`revoke` 把完整视图改回 incomplete | `ui_stream_task_view.dart:288-295`、`stream_ui_planning.dart:21-24` | N3：Found 1 widget「界面流未完成，已使用只读事实展示。」 |
| I4 | Important | 方案 A 被挡：重算失败后 `_outdated` 使所有事件（含本地 editField）被拒；现测试 `ui_publication_coordinator_test.dart:494-502` 把此错误行为固化为断言 | `publication.dart:236`、`:56` | `cf2_lib2_review_publication_test.dart`：Expected true / Actual false |
| M1 | Minor | `FactState.notApplicable` 无生产者 | `snapshot.dart:9` | — |

通过项：原因码由宿主判定（N4 全部通过）；批量路径非法计划走 `invalid_plan`；整批重算失败 fail-closed（`surface.dart:158-200`）。待确认：库 1 路径 `ui_recompute_adapter.dart:215` 非 typed 分支保留旧 `computedEvidence`。

实施拆分：T1 证据与值一致性（C1）；T2 end-only 与完成状态（I1、I3）；T3 暂停期用户文字模式（I2）；T4 方案 A 恢复（I4，需同时改固化错误行为的旧断言——用户已批准方案 A）；T5 旧结果标注与 freshness（C2，依赖 T4）；T6 notApplicable 与库 1 证据路径（依赖 T5，先写反例）。
