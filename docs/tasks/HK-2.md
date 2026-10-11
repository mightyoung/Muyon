# HK-2 不变量 2 的拒绝路径测试：没有业务映射时点确认绝不显示成功（只加测试）

分支 `task/hk-2-confirm-without-business-port` · 基线 develop `37404cc` · 执行：Claude Haiku 5.5 · 审查：leader A

## 背景
GB-1 审计（`review/gb-1-invariant-audit` 上的 `docs/reviews/2026-10-11-invariant-audit.md` 不变量 2）指出：助手页打开交互页时不传 `businessActions`（`apps/muyon/lib/screens/assistant_page.dart` 约 742 行，`dynamic_workspace.dart:31` 默认空 map），路由器缺映射时抛 `business_port_unavailable`（`apps/muyon/lib/assistant/ui_planning_events.dart` 约 48～51 行）。目前没有测试证明：这种情况下点确认卡**不会**显示成功、**不会**产生写工具回执。

## 只做这些
新建 `apps/muyon/test/hk2_confirm_without_business_port_test.dart`。先读并照抄现有夹具，不要自己从零搭：
- `apps/muyon/test/sn1_dynamic_confirm_external_test.dart`：怎么造一个含 `ConfirmCard` / `BatchConfirmCard` 的已校验计划、怎么用 `DynamicWorkspace` 打开它；
- 同一文件里设置任务污染状态的辅助函数，这里把任务设为 `clean`，排除外部内容的干扰。

写 2 个测试：
1. `confirm_without_business_port_never_shows_success`：用 `DynamicWorkspace` 打开含业务确认卡的计划，**不传 `businessActions`**；点确认按钮，`pumpAndSettle`。断言：卡片状态不是成功（不出现成功文案或 `BusinessStatus.success`）；页面上出现失败或不可用的提示（以你读代码后确认的实际文案为准，写明出处行号）；`host.tools.history()` 里没有新增任何 `ToolEffect.write` 工具的调用记录。
2. `confirm_card_without_receipt_stays_pending`：同一计划，点确认后不提供任何回执（不调用 `acceptReceipt`）。断言卡片仍在等待状态，不会自己变成成功。

## 自检（结果逐项写进回报）
1. `cd apps/muyon && flutter test test/hk2_confirm_without_business_port_test.dart`，2 例通过。跑测试时保留代理设置，只把 `localhost,127.0.0.1,::1` 加进 `NO_PROXY`；不导出 `MUYON_EVAL_REAL`。
2. **变异**：把 `packages/muyon_ui/lib/src/dynamic/surface.dart` 里决定成功状态的条件（`receipt?.status == UiReceiptStatus.succeeded ? BusinessStatus.success`）改成恒为 `BusinessStatus.success`，至少一个新测试必须失败；立刻恢复，`git diff --stat -- apps/muyon/lib packages/muyon_ui/lib` 必须为空。
3. `cd apps/muyon && flutter analyze`，0 个问题。
4. `dart format` 只格式化新文件。

## 不做
不改 `lib/`、不改其他测试；过不了就停下回报报错前 20 行；不用 `skip`。如果读代码后发现第 1 条的前提不成立（例如点确认根本不会到路由器），停下回报你看到的实际流程，不要硬写断言。

## 提交与回报
提交说明 `test(aiui): confirm without business port never reports success`，只含新测试文件，推到 `task/hk-2-confirm-without-business-port`，`git ls-remote` 确认。
回报逐项写：提交哈希；2 个测试名与结果；变异时失败的测试名；`git diff --stat` 输出；analyze 最后一行。
