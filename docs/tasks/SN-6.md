# SN-6：aiui6_stream_approval_widget_test 停在 waitingConfirmation 的根因与修复

执行：grok-build。派发：leader A，2026-10-11。集成：Leader B。基线：`task/sn4-stale-read-guard-20261011` @ `d5cd97a1`（PR #51 = SN-4 `6d47da8` + Leader B 渲染器补修）；分支 `task/sn-6-approval-widget-hang`。

## 背景
grok-build 的 SN-4 回报：`apps/muyon/test/aiui6_stream_approval_widget_test.dart` 在 SN-4 head 与此前交接点上都会挂住（停在 `waitingConfirmation`），全量测试只能排除该文件跑。CR-12 记录交接点把六个必需审批控件的动作挪到了待确认卡开头（测试相对原 PR42 只改了 import）。若 CI 也挂住，AIUI 组合永远拿不到终态 GREEN。

## 要做
1. 先定位：单独跑该文件，找出第一个挂住的用例与卡住的等待点（哪个 `pumpUntil` / tap 没生效、对话框是否出现、按钮是否在视口外或被遮挡、是否 fake/real async zone 混用）。回报写清根因证据。
2. 判断根因属于哪一类，按类处理：
   - **生产代码问题**（审批按钮不可点、点了没进入批准流程）→ 先写/保留会失败的断言，修生产代码；
   - **测试夹具问题**（时钟区、视口、pump 方式）→ 只做最小夹具修正，**不删减、不放宽任何断言**（批准/取消、精确请求数、零写工具、视口尺寸都保留）。
3. 修后该文件全部通过，并在 `apps/muyon` 全量测试里**不再排除**它。
4. 至少一处变异：让审批按钮回调变成 no-op，测试必须失败（不是挂住——如挂住说明测试缺超时保护，要补成有界等待后明确失败）。

## 约束
不碰 SN-5 范围（`muyon_ui` 的 workspace/surface 草稿操作、`agent_resume._carry`、`dynamic_workspace` 自定义 sink）；不改取消/撤权语义；strict analyze 零 info；不提交 pub get 改的平台文件；不合 develop。

## 回报（固定 6 行）
1. 根因（一句）与证据（挂住的用例名、卡住的行）
2. 提交哈希（远端与本地一致）
3. 改动文件与行数；属生产修复还是夹具修正
4. 变异结果
5. analyze 与 apps/muyon 全量（不排除任何文件）pass/skip/fail 与用时
6. 未做或有疑问
