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

## 独立失败清理补修（2026-10-11 UTC）

作者源 `c83951abd284364ddf23b4170cae385522decd38` 保留；唯一执行入口在独立 `task/sn6-cleanup-repair-20261011` 修复，不改原作者分支。Parent 已明确授权测试/夹具补修；仍须 Parent 非作者独审、最新 develop/PR52/SN6 新组合 CI 及 CR18 统一复审，未合 AIUI。

- 独立 RED 已保留：只让 internal child 确认 no-op，原 automatic:true 合跑90.021s保护终止；分开诊断 automatic:true/few:true 均经过300 tick到原 terminal=false 断言，在 finally `runAsync(agent.close)` 挂住，30.013/30.015s外部保护终止。旧固定8次flush仅在更晚的storage.close，不能证明失败清理退出。外部终止不算合格变异结果。
- 测试专用修复：`drainLoopCleanup` 在real zone启动并观察真正完成，逐轮排空real/fake event callbacks；widget场景以2000轮上限给明确未完成诊断，按完成状态提前结束。同步/异步错误保存原对象与栈再抛出；不用吞异常换绿。plain非widget上下文保留正常await。审批finally改用此驱动，HTTP override另用finally保证恢复；storage.close改用同一实际完成条件，移除固定8次假定。未改产品、授权、原测试300 tick、请求数、零写、skip或模式。
- 原6例正常通过：6/0/0、exit0、28.730s。child-only no-op automatic:true/few:true合跑：0/2/0、exit1、18.040s，原第183行 Expected true / Actual false，两例testDone及runner done均到达、进程自然退出；无外部保护触发。生产回调临时逆变异已逐字节恢复。
- 新夹具4例：跨fake gate及32个real event完成、同步错误不吞、异步错误不吞、永不完成时有界失败诊断，4/0/0。把驱动退回8轮的额外逆变异：3/1/0、exit1、6.104s，跨时钟完成原正例失败；恢复helper逐字节一致。
- 恢复后的原6例+夹具4例：10/0/0、exit0、27.438s；再含stream生产、resume与budget，71/0/0、exit0、20.030s，均未触发外部进程保护。AST核对原11条expect/matcher表达式、testWidgets注册名称/skip表达式逐项一致，运行原六个完整名称不变。strict host analyze --no-pub --fatal-infos：No issues found，exit0。
- Flutter 3.47.5 / Dart 3.13.4；仅loopback fixture，无真实模型/MUYON_EVAL_REAL/Android。原始JSON、RED/变异diff、恢复散列与命令/耗时保存在工作树外 `/workspace/reports/AIUI-chain-independent-evidence-20261011/`，未入Git。最终完整补修SHA及源CI状态由任务分支回读报告；这里不冒称尚未运行的全量host或组合CI通过。
