# SN-2 接手 Codex 的 PR42：修好 CI（生产流式接线首片）

分支 `task/aiui-6-conversation-card-wiring-20261010`（[PR42](https://github.com/mightyoung/Muyon/pull/42)，head `ac1b6ea`，基于 develop `6c821d6`）· 原作者 Codex（额度用完，本机没有 Flutter，提交前没跑过测试）· 接手：**Claude Sonnet 5.5** · 审查：leader A

SN-1（动态确认卡外部内容标记）**作废**：PR42 已在 `surface.dart` 里做了失败即关闭的外部内容标记，SN-1 不再执行。

## PR42 做了什么
先读 [AIUI-production-stream-wiring.md](AIUI-production-stream-wiring.md) 和 PR42 描述：生产规划改走宿主冻结的 stream/2 编译器与 library-2 目录；三档呈现偏好（自动 / 仅用户明确要求 / 只用文字，默认只用文字）持久保存；动态确认卡带宿主外部内容标记，未知或变化即拒绝。上位决定见 ADR-0001 末尾 10-10 几条（三档、少用策略 A、外部内容必须贯穿到确认卡）。

## CI 失败（run 38065416338）
- analyze：`lib/screens/ui_planning_preference_switch.dart:24` 缺花括号（info）；`test/aiui6_stream_approval_widget_test.dart:30` 未定义 `UiPlanningMode`（error，缺 import）。
- host 测试 6 例失败：
  - `aiui6_stream_approval_widget_test.dart` 编译失败（同上）；
  - `aiui8_presentation_widget_test.dart`「failed UI mode save rolls the selection back; retry commits the actual choice」；
  - **既有测试**：`assistant_production_policy_model_test.dart` 的 `actual host model policy / readonly-json`、`/ readonly-native`；`assistant_production_policy_order_test.dart` 加载失败；`assistant_subconversation_widget_test.dart` 的 `shell_child_back_restores_parent_draft_and_scroll`。

## 要求
1. 本机先复现：`apps/muyon` 下 `flutter analyze` 和上面 5 个测试文件。跑测试时保留代理设置，只把 `localhost,127.0.0.1,::1` 加进 `NO_PROXY`；不导出 `MUYON_EVAL_REAL`。
2. 逐个找根因再修。**既有测试是回归信号**：默认按「PR42 弄坏了既有行为」处理，修产品代码；只有当既有测试断言的正是本次决定有意改掉的旧行为（例如默认呈现从开改成只用文字），才可以改测试，并在提交说明里逐条写清：哪条决定、旧断言是什么、新断言为什么等价地守住同一条安全或行为要求。
3. 不放宽任何门槛：不删断言、不加 `skip`、不改 `analysis_options.yaml`、不降低超时来掩盖问题；外部内容标记保持失败即关闭；授权、确认、工具注册不改。
4. 只格式化改动过的文件。修完跑：`apps/muyon` 与 `packages/muyon_ui` 的 `flutter analyze`（info 也算失败）；`apps/muyon` 全量 `flutter test`；`packages/muyon_ui` 全量 `flutter test`。
5. 小步提交，推回同一分支；等 PR42 的 CI 跑完再回报。

## 回报
各提交哈希（`git ls-remote` 确认）；每个失败的根因与修法（一句话一条）；改了哪些既有测试及理由；analyze 与全量测试的通过/失败/跳过数；PR42 最新 CI 链接与结论；发现的范围外问题。
