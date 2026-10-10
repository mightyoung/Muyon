# OC-1 设置页三个控件补行为测试（只加测试）

分支 `task/oc-1-settings-tests` · 基线 develop `a68ba43` · 执行：opencode · 审查：leader A

## 背景
GROK-8 追溯发现设置页三个控件有生产入口但没有测试：「接口与工具」入口、「减少动态效果」开关、「主对话模型」下拉。代码都在 `apps/muyon/lib/screens/platform_shell_personal.dart` 的 `settings()`（约 216～280 行）。

## 只做这些
新建**一个**测试文件 `apps/muyon/test/settings_controls_test.dart`。照抄 `apps/muyon/test/aiui4c_settings_entry_test.dart` 的写法：`NavigationFixture.open`、`mountShell`、`select(tester, '设置')`、同样的 `addTearDown` 清理、视口宽度 1280。

写 3 个测试：
1. **接口与工具**：进设置 → 点「接口与工具」→ 断言出现标题为「接口与工具」的页面；`tester.pageBack()` 后回到设置页（能再找到「接口与工具」这行）。断言前后 `f.host.tools.history().length` 不变。
2. **减少动态效果**：进设置 → 先断言 `f.host.workspaces.setting('reduceMotion') != true` → 点「减少动态效果」的开关 → 断言 `f.host.workspaces.setting('reduceMotion') == true` → 再点一次 → 断言变回 `false`。
3. **主对话模型**：用 fixture 里已有的方式准备至少一个 `ModelPurpose.chat` 的模型配置（先在 `apps/muyon/test/` 里搜 `ModelPurpose.chat` 找现成写法照抄；找不到就停下回报，**不要改 lib**）→ 进设置 → 在「主对话模型（Folio 共用）」下拉里选这个配置 → 断言 `f.host.workspaces.setting('activeModelProfileId')` 等于它的 id → 再选「未指定 · 离线工具可用」→ 断言变成 `''`。

## 自检（必须做，结果写进回报）
1. 跑：`cd apps/muyon && flutter test test/settings_controls_test.dart`，3 个都通过。跑测试时保留代理设置，只把 `localhost,127.0.0.1,::1` 加进 `NO_PROXY`；不要导出 `MUYON_EVAL_REAL`。
2. **变异检查**，每次只改一处，跑完立刻恢复：
   - 把 `platform_shell_personal.dart` 里 `setSetting('reduceMotion', value)` 改成 `setSetting('reduceMotion', false)` → 测试 2 必须失败；
   - 把 `setSetting('activeModelProfileId', value!)` 改成 `setSetting('activeModelProfileId', '')` → 测试 3 必须失败。
   - 两次都恢复后执行 `git diff --stat apps/muyon/lib`，输出必须为空。
3. `cd apps/muyon && flutter analyze`，必须 0 个问题（info 也算）。
4. `dart format test/settings_controls_test.dart`，只格式化这一个文件。

## 不做
- 不改 `lib/` 下任何文件，不改其他测试文件，不改 `analysis_options.yaml`、`pubspec`。
- 测试过不了时，不要去改产品代码让它过；写清哪一步失败、报错原文的前 20 行，然后停下回报。
- 不要用 `skip`。

## 提交与回报
只提交 `apps/muyon/test/settings_controls_test.dart` 一个文件，提交说明 `test(settings): cover tools entry, reduce motion and chat model controls`，推到 `task/oc-1-settings-tests`，再用 `git ls-remote origin refs/heads/task/oc-1-settings-tests` 确认远端哈希与本地 `git rev-parse HEAD` 一致。
回报：提交哈希；3 个测试名与结果；两次变异各自失败的测试名；`git diff --stat apps/muyon/lib` 的输出（应为空）；analyze 结果。
