# OC-6 主题设置值损坏时不让应用启动崩溃（一行修复 + 1 个测试）

分支 `task/oc-6-theme-bad-value` · 基线 develop · 执行：opencode · 审查：leader A

## 问题
`apps/muyon/lib/app/app_shell.dart` 约 82～84 行：
```dart
mode = ThemeMode.values.byName(
  value.workspaces.setting('theme') as String? ?? 'system',
);
```
`byName` 遇到不认识的名字会抛异常；如果数据库里的 `theme` 值被改坏（例如 `'purple'`，或者不是字符串），应用一打开就崩。

## 只改这一处
改成（保持原来的缩进风格，用 `dart format` 排版）：
```dart
final stored = value.workspaces.setting('theme');
mode = (stored is String ? ThemeMode.values.asNameMap()[stored] : null) ??
    ThemeMode.system;
```
不改别的任何代码。

## 加 1 个测试
在你 OC-5 写的 `apps/muyon/test/theme_persistence_test.dart` 末尾加：
`unknown_stored_theme_falls_back_to_system`：`pumpWidget` 之前存 `setSetting('theme', 'purple')`，打开应用不抛异常，断言 `MaterialApp.themeMode == ThemeMode.system`，`tester.takeException()` 为 `null`。

## 自检
1. 先**不改** `app_shell.dart`，只加测试，跑一次：新测试必须失败（证明它测到了问题）。记下失败信息第一行。
2. 再改 `app_shell.dart`，跑 `flutter test test/theme_persistence_test.dart`：3 例全过。保留代理设置，`NO_PROXY` 加 `localhost,127.0.0.1,::1`。
3. `cd apps/muyon && flutter analyze`：0 个问题。
4. `dart format` 只格式化这两个文件。

## 提交与回报
一个提交：`fix(app): fall back to system theme when stored value is invalid`，只含这两个文件。推到 `task/oc-6-theme-bad-value`，`git ls-remote` 确认。

**回报必须是下面 5 行，每行都要有内容，否则视为未完成：**
1. 提交哈希：
2. 修改前新测试的失败信息第一行：
3. 修改后 3 个测试的结果：
4. `git diff --stat origin/develop` 的输出：
5. analyze 最后一行：
