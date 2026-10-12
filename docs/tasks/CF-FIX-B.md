# CF-FIX-B：CF2 原因码与完成状态（T2、T3）

执行：Sonnet（senior engineer）。派发：leader A，2026-10-12。集成：leader A。基线：develop `9de4235a`；分支 `task/cf-fix-b-20261012`。依据：`docs/reviews/2026-10-12-cf2-library2-review.md`（在 `task/docs-20261012a`）I1、I2、I3；PR #58 反例 `65b85d89`（`apps/muyon/test` 下 N1–N4）。

## 要做
1. 把 PR #58 的反例测试文件原样带进本分支，确认 N1a、N1b、N2a、N3 RED、N4 全过。
2. **T2（I1 + I3）**：`apps/muyon/lib/assistant/stream_ui_planning.dart:111-115` end-only 流（模型没出卡）归 `model_no_card`，非法节点 / 宿主校验失败仍归 `invalid_plan`；`stream_ui_planning.dart:21-24` 的 `revoke` 不得把已完整（phase complete）的视图改回 incomplete；`ui_stream_task_view.dart:288-295` 按真实完成状态选文案，complete 且无失败码时不得显示「界面流未完成」。
3. **T3（I2）**：`ui_planning.dart:387-396` 把「用户切换到只用文字」与宿主漂移分开，前者归 `user_text_only`，宿主真实变化仍归 `host_state_changed`。
4. 原因码仍由宿主判定，模型 `reasonCode` 不得透传（N4 保持全过）。

## 变异（必须做）
end-only 归回 invalid_plan；revoke 把 complete 改回 incomplete；用户模式变化并回宿主漂移。都必须被测试抓到。

## 约束
不删、不放宽 PR #58 断言；不碰 Haiku 的 CF-FIX-A 文件（`muyon_module_api` 的 validation / publication）；strict analyze 零 info；`apps/muyon` 全量；不提交平台文件；不合 develop。

## 回报（固定 6 行）
1. RED（N1a/N1b/N2a/N3 失败首行）　2. 修复提交（远端与本地一致）　3. 改动文件与行数　4. 变异结果　5. analyze 与全量（pass/skip/fail 及分类）　6. 未做或有疑问
