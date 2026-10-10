# OC-2「减少动态效果」重启后生效的测试 + 删除一个无调用的包装函数

分支 `task/oc-2-reduce-motion-readback` · 基线 develop `a68ba43` · 执行：opencode · 审查：leader A

## 背景
OC-1 测了设置页能把 `reduceMotion` 存下来；但存下来以后，应用启动时会不会真的关掉动画，还没有测试。读回的代码在 `apps/muyon/lib/app/app_shell.dart` 约 213～219 行：`MaterialApp.builder` 里把 `host.workspaces.setting('reduceMotion') == true` 并进 `MediaQuery.disableAnimations`。
另外 GROK-8 发现 `apps/muyon/lib/platform/business_tools.dart` 第 46 行的 `registerBusinessTools` 没有任何调用者（它只是调用另外两个函数的 3 行包装）。

## 第一部分：加测试
新建 `apps/muyon/test/reduce_motion_readback_test.dart`。照抄 `apps/muyon/test/widget_test.dart` 开头的写法：临时目录、`tester.runAsync(() => MuyonHost.open(root.path))`、`tester.pumpWidget(MuyonApp(host: host))`、`pumpAndSettle`、`try/finally` 关闭 host（看原文件怎么关就怎么关）。

写 2 个测试：
1. `reduce_motion_unset_keeps_animations`：不设置，打开应用后，取 `find.byType(AssistantPage)` 的 context，断言 `MediaQuery.of(context).disableAnimations` 为 `false`。
2. `reduce_motion_stored_true_disables_animations_on_open`：在 `pumpWidget` **之前**用 `tester.runAsync(() => host.workspaces.setSetting('reduceMotion', true))` 存好，再打开应用，断言同一个值为 `true`。

## 第二部分：删包装函数
1. 先跑 `git grep -n registerBusinessTools -- apps packages`，确认只有定义那一行（文档里的提及不算）。如果还有别的代码调用它，**停下回报，不要删**。
2. 只删 `business_tools.dart` 里 `void registerBusinessTools(MuyonHost host) { ... }` 这 4 行（函数和它的空行）。`registerInquiryTools`、`registerNonInquiryBusinessTools` **不要动**。

## 自检（必须做，结果逐项写进回报）
1. `cd apps/muyon && flutter test test/reduce_motion_readback_test.dart test/widget_test.dart test/settings_controls_test.dart`（最后这个文件在 OC-1 分支上，如果当前分支没有就跳过并说明）。跑测试时保留代理设置，只把 `localhost,127.0.0.1,::1` 加进 `NO_PROXY`；不要导出 `MUYON_EVAL_REAL`。
2. **变异检查**：把 `app_shell.dart` 里 `host.workspaces.setting('reduceMotion') == true` 临时改成 `false`，跑新测试文件，测试 2 必须失败；然后恢复，`git diff --stat apps/muyon/lib/app` 必须为空。
3. `cd apps/muyon && flutter analyze`，0 个问题（info 也算）。
4. `dart format` 只格式化你新建的测试文件和 `business_tools.dart`。

## 不做
- 除上面说的两个文件外，不改任何文件；不改 `analysis_options.yaml`、`pubspec`。
- 测试过不了就停下，回报报错原文前 20 行，不要为了让测试通过去改 `app_shell.dart`。
- 不用 `skip`。

## 提交与回报
两个提交：先 `test(app): cover reduce motion readback on app open`（只含新测试文件），再 `refactor(tools): drop unused registerBusinessTools wrapper`（只含 `business_tools.dart`）。推到 `task/oc-2-reduce-motion-readback`，`git ls-remote` 确认远端哈希与本地一致。
回报（**每项都要写**）：两个提交哈希；每个测试名与结果；变异时失败的测试名；`git grep` 的输出；`git diff --stat apps/muyon/lib/app` 的输出；analyze 结果。
