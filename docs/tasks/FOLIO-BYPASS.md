# FOLIO-BYPASS 宿主模式下 Folio 的 `bypass` 按「写入要确认」读取

分支 `task/folio-bypass` · 依据：[ADR-0004](../adr/0004-module-contract-v2.md) §12.1 Q12、§10.1 · 执行：junior（opencode）· 审查：leader（`reviewer-sonnet-high`）· 阶段：第二阶段，安全修复，优先

## 背景
宿主模式下，Folio 自带助手的 `assistant_permission = bypass` 档会让写入免确认（`ask_page.dart:220` 的 `autoApprove`、`assistant_actions.dart:321`）。导入的供应商文本经提示注入，就能驱动对 7 类询价记录的增改删。这些写入能从回收站恢复，但不留宿主回执。REG-4c 会彻底禁用这一档并隐藏助手，在那之前先用本任务堵住。

## 只做这些
1. `packages/inquiry_module/lib/src/app/app_state.dart` 的 `assistantPermission` getter（约 451 行）：`_isHosted` 为真时，存储值 `bypass` 读作 `confirmWrites`；`readOnly` 和 `confirmWrites` 不变；非宿主模式行为完全不变。setter 不改，存储值原样保留。
2. 宿主模式下，两个权限选择器不再列出 `bypass`：`features/settings/ai_settings.dart`（约 215 行）和 `features/ai/ask_page.dart`（约 433 行的菜单）。这样用户选了之后不会看到它被悄悄改回。`ai_settings.dart:228` 的 `bypass` 提示在宿主模式下自然不再出现。非宿主模式下两个选择器不变。
3. 新增测试 `packages/inquiry_module/test/assistant_permission_hosted_test.dart`：
   - 宿主模式：存储 `bypass` 后，`assistantPermission == confirmWrites`；写入类动作仍先询问（在 `ask_page` 或 `assistant_actions` 层面断言没有自动批准）；两个选择器都不含 `bypass`；
   - 非宿主模式：存储 `bypass` 后读作 `bypass`，选择器包含 `bypass`。

## 不做
- 不隐藏 Folio 助手（属于 REG-4c）；不改 `supplier_core`；不改已有测试，`assistant_permissions_test.dart` 必须原样通过。

## 验证
- 变异：去掉 getter 里的宿主分支，新测试的宿主用例必须失败；恢复后通过。结果写进提交说明。
- `flutter analyze`（`packages/inquiry_module`、`apps/muyon`，info 也算失败）；`packages/inquiry_module` 全量测试；宿主全量 `flutter test`。

## 回报
分支与提交哈希、改动文件、验证摘要行、变异结果。
