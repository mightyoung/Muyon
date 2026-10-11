# OC-5「外观」主题的保存与重启读回测试（只加测试）

分支 `task/oc-5-theme-persistence` · 基线 develop `cf75546` · 执行：opencode · 审查：leader A

## 背景
设置页「外观」下拉选主题后，`apps/muyon/lib/app/app_shell.dart` 约 263～266 行把选择存成 `workspaces.setSetting('theme', value.name)`；应用打开时约 82～84 行读回 `ThemeMode.values.byName(setting('theme') ?? 'system')`。这两处都没有测试。

## 只做这些
新建 `apps/muyon/test/theme_persistence_test.dart`。写法照抄你在 OC-2 写的 `apps/muyon/test/reduce_motion_readback_test.dart`（临时目录、`MuyonHost.open`、`MuyonApp(host: host)`、`try/finally` 关闭 host）。切到设置页的写法照抄 `apps/muyon/test/widget_test.dart` 里点 `NavigationBar` 中「设置」的那几行。

写 2 个测试：
1. `stored_dark_theme_is_applied_on_open`：`pumpWidget` 之前用 `tester.runAsync(() => host.workspaces.setSetting('theme', 'dark'))` 存好；打开应用后断言 `tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode == ThemeMode.dark`。
2. `choosing_light_theme_is_saved_and_applied`：打开应用 → 切到「设置」→ 点「外观」下拉 → 选 `light` → `pumpAndSettle` → 断言 `host.workspaces.setting('theme') == 'light'`，且 `MaterialApp` 的 `themeMode == ThemeMode.light`。如果保存是异步的，照抄 OC-1 `settings_controls_test.dart` 里 `_settingReaches` 的等待写法。

## 自检（结果逐项写进回报）
1. `cd apps/muyon && flutter test test/theme_persistence_test.dart`，2 例通过。跑测试时保留代理设置，只把 `localhost,127.0.0.1,::1` 加进 `NO_PROXY`；不导出 `MUYON_EVAL_REAL`。
2. **变异**（每次一处，跑完立刻恢复）：
   - `setSetting('theme', value.name)` 改成 `setSetting('theme', 'system')` → 测试 2 必须失败；
   - 读回处 `setting('theme') as String? ?? 'system'` 改成 `'system'`（直接写死）→ 测试 1 必须失败。
   - 恢复后 `git diff --stat apps/muyon/lib` 必须为空。
3. `cd apps/muyon && flutter analyze`，0 个问题。
4. `dart format` 只格式化新文件。

## 不做
不改 `lib/`、不改其他测试、不改 `analysis_options.yaml`；过不了就停下回报报错前 20 行；不用 `skip`。

## 提交与回报
提交说明 `test(app): cover theme save and readback`，只含新测试文件，推到 `task/oc-5-theme-persistence`，`git ls-remote` 确认。
回报**必须逐项写下面 5 项**，缺一项就算没完成：
1. 提交哈希；
2. 2 个测试名与结果（通过/失败）；
3. 两次变异各自失败的测试名；
4. `git diff --stat apps/muyon/lib` 的原样输出；
5. analyze 结果原文最后一行。
