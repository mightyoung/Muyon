# SN6 独立动态复验：no-op 失败清理仍挂住

固定作者源：`c83951abd284364ddf23b4170cae385522decd38`，父 `f21719c1bc486d9a4482627ba03c030230cd8a9f`；只读核对远端与源一致。任务依据 `docs/tasks/SN-6.md` 第4项要求审批回调 no-op 时明确失败、不能挂住。本复验只修改隔离 worktree 中的临时逆变异/诊断打印，恢复后无产品或原测试差异；作者分支、develop/main 未写。

## 作者证据边界

仓库固定源只包含两个测试/夹具文件修改，`docs/tasks/SN-6.md` 为原任务说明，未见作者实际六行回报、RED 原始日志或 no-op 变异报告。提交说明解释了 timer/viewport/storage.close 根因，但不是已执行变异证据。提交评论及当前开放 PR 查询也未找到该回报；不能断言作者在其他会话从未运行，只能明确本次未取得。源 CI `38160295957` 为 success；Parent 另核实际 checkout 精确源 SHA。源绿及静态断言保留不替代本任务 no-op 的有界失败要求。

## 独立正例

Flutter 3.47.5 / Dart 3.13.4；`apps/muyon` cwd，取消代理，仅 loopback fixture，不调用真实模型：

```sh
flutter test --no-pub --reporter json test/aiui6_stream_approval_widget_test.dart
```

原六例 automatic/few/textOnly × approve true/false：6 passed、0 failed、0 skipped、exit0，34.304s。逆变异及诊断全部恢复后同命令再次 6/0/0、exit0，12.662s。

## I1：原失败断言被 finally 中的 agent.close 等待挡住

临时仅将 `apps/muyon/lib/screens/assistant_page.dart:293` 的真实确认回调改为：

```dart
if (task.payload['uiPlanningInternal'] != true) {
  await widget.agent.confirm(task.id, requestDigest: digest);
}
```

父任务确认不变，真实生产对话框与按钮仍点过，只对内部 child 确认执行 no-op。原测试/等待/300 tick/请求数/零写断言不修改。运行原文件，`--name 'mandatory planning approval remains reachable in (automatic|few): true'`：automatic:true 开始后没有 testDone；90.021s 外部进程保护终止，包装退出124，0个完成用例/0个已报告失败。**这不是合格的变异 FAIL，也不是编译失败。** few:true 未在此合跑开始，不能冒称两例均由该合跑验证。

进一步逐例只加诊断 print（无新断言、不改任何原断言或等待），各用原文件 `--plain-name 'mandatory planning approval remains reachable in automatic: true'` / `few: true`：

| 原例 | 300 tick 后 terminal | 进入 finally | 最后进度 | 外部保护终止 |
|---|---|---|---|---|
| automatic:true | 9.624s `false` | 9.626s | 9.650s pumpWidget 完成、进入 runAsync(agent.close)，未见返回 | 30.013s，exit124，无 testDone |
| few:true | 9.397s `false` | 9.400s | 9.419s pumpWidget 完成、进入 runAsync(agent.close)，未见返回 | 30.015s，exit124，无 testDone |

对应原源码 `apps/muyon/test/aiui6_stream_approval_widget_test.dart:183` 的 `expect(...terminal, isTrue)` 已到达且实际false，但 `finally` 第200行等待 `tester.runAsync(agent.close)`，使失败不能报告、进程不能正常结束。进程保护只限诊断运行安全，不修改 Flutter 测试超时、不算原测试明确失败。

`support/agent_loop_fixture.dart:166-183` 固定8次跨时钟 flush 只在 storage.close 的 addTearDown；上述停点更早在测试自己的 finally。六个成功/取消路径绿不能证明这一失败清理可退出。本次已复现此具体窗口；未证明所有8次 flush 都不够，也未指控生产授权被绕过。

## 恢复、后续门槛与组合状态

回调和诊断打印逐字节恢复，源 worktree 恢复干净，再跑原六例全绿；只停止自己外部超时遗留的独立测试引擎，未停其他 writer。原始 JSON、临时 diff、SHA256 恢复证据、命令/耗时结果均在工作树外 `/tmp/aiui-chain-evidence/`，不入仓库。

结论：C0 / **I1** / M0，**需修改 SN6 失败路径测试清理再复验**。必须保留原 terminal/精确请求数/零写/模式断言，让 automatic:true 与 few:true 的 child-only no-op 在有界等待后报 Expected true / Actual false，并正常完成 finally 和 test process（exit1、无外部终止），然后恢复全六例通过；不以删断言、skip、改产品授权或缩短原等待掩盖。

最新 develop `ffc1f9d1d56956ec699c8b5c6f939a4fefc491ef` + SN5/PR52 `11225c4f2823ab45cb1e9421aeda0eb03969be95`（祖先含 PR42/SN2–4/PR51）+ SN6 已在独立组合 worktree 正常合成 `62fe69e7a987f99a6951e0e8879421b45fb27ca5`；唯一冲突为 ADR-0001 两段新增记录，保留双方，产品/测试无冲突。组合未推、未运行组合 CI、未合 develop；发现此验收阻断后先回报，不把未来组合正例 CI 绿冒称 no-op 验收完成。最新 SN6 修复到达后仍由唯一执行入口组合，再交 Parent/CR18 独立统一复审。
