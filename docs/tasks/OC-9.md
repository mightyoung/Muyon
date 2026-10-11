# OC-9 选择题「其他（自己填写）」回传测试（只加测试）

分支 `task/oc-9-choice-custom-entry` · 基线 develop · 执行：opencode · 审查：leader A

## 背景
GROK-8 追溯第 5 节：`packages/muyon_ui/lib/src/ui_components/inputs.dart` 的 `Choice` 在 `allowCustom: true` 且不是 ID 模式时，有一个「其他（自己填写）」输入框（key `choice-custom`）和「添加」按钮（key `choice-custom-add`）；`addCustom`（约第 83～93 行）会去掉首尾空格、空串忽略、把新值加进选项并选中，然后通过 `onChanged` 回传。目前没有测试证明自填值真的被回传。

## 只做这些
新建 `packages/muyon_ui/test/choice_custom_entry_test.dart`。照抄 `packages/muyon_ui/test/aiui5_controlled_inputs_test.dart` 开头的写法（`import 'support/widget_harness.dart';`、`show` 函数、`addTearDown(() => tester.binding.setSurfaceSize(null))`）。

写 3 个测试，都用 `Choice(label: '选项', options: const ['甲'], allowCustom: true, multiple: true, selected: const {}, onChanged: changes.add)`，其中 `changes` 是 `<Set<String>>[]`：
1. `custom_entry_is_reported_through_onChanged`：在 `choice-custom` 里输入 `  乙  `（前后带空格），点 `choice-custom-add`，`pump`。断言 `changes.last` 等于 `{'乙'}`（已去空格），输入框被清空。
2. `blank_custom_entry_is_ignored`：输入三个空格，点添加。断言 `changes` 仍为空。
3. `id_mode_has_no_custom_entry`：已有同名测试在 `aiui5_controlled_inputs_test.dart` 里覆盖了，**不要重复**；改写成：`allowCustom: false` 时找不到 `choice-custom`。
如果你发现 `selected`/`onChanged` 的实际参数名或类型和上面不一样，以源码为准照改，并在回报里写明。

## 自检
1. `cd packages/muyon_ui && flutter test test/choice_custom_entry_test.dart`，3 例通过。保留代理设置，`NO_PROXY` 加 `localhost,127.0.0.1,::1`。
2. **变异**：把 `inputs.dart` 里 `final text = custom.text.trim();` 改成 `final text = custom.text;`，测试 1 必须失败；恢复。再把 `if (text.isEmpty) return;` 删掉，测试 2 必须失败；恢复。之后 `git diff --stat packages/muyon_ui/lib` 必须为空。
3. `cd packages/muyon_ui && flutter analyze`：0 个问题。
4. `dart format` 只格式化新文件。

## 提交与回报
提交说明 `test(ui): cover Choice custom entry reporting`，只含新测试文件，推到 `task/oc-9-choice-custom-entry`，`git ls-remote` 确认。

**回报必须是下面 5 行：**
1. 提交哈希：
2. 3 个测试名与结果：
3. 两次变异各自失败的测试名：
4. `git diff --stat packages/muyon_ui/lib` 的输出（应为空）：
5. analyze 最后一行：
