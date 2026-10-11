# OC-4 补测：动态界面没有探针时按外部内容处理（只加测试）

分支 `task/oc-4-external-probe-default` · 基线 `review/leader-a-batch-20261011` @ `37404cc`（含 SN-1）· 执行：opencode · 审查：leader A

## 背景
SN-1 让 `UiSurfaceController.externalContent` 失败即关闭：**没有传 `externalContentProbe` 时返回 `true`**（`packages/muyon_ui/lib/src/dynamic/surface.dart`，`externalContentProbe?.call() ?? true`）。审查变异发现：把 `?? true` 改成 `?? false`，现有测试全部还能通过，这个默认值没有被测住。

## 只做这些
在 `packages/muyon_ui/test/` 新建 `dynamic_external_content_default_test.dart`，写 2 个 `test`（不需要 widget）：
1. `surface_without_probe_treats_content_as_external`：构造 `UiSurfaceController(<一个已校验的计划>)`，**不传** `externalContentProbe`，断言 `controller.externalContent` 为 `true`。
2. `surface_with_clean_probe_is_not_external`：同样的计划，传 `externalContentProbe: () => false`，断言为 `false`。

已校验计划怎么造：照抄 `packages/muyon_ui/test/aiui5_live_publication_test.dart` 里 `mountedPlan()`（约 142 行附近被调用，先找到它的定义）或 `aiui5_library2_renderer_test.dart:126` 附近的写法。可以把需要的辅助函数**复制**进新文件，不要改原测试文件。测试结束调用 `controller.dispose()`。

## 自检（结果逐项写进回报）
1. `cd packages/muyon_ui && flutter test test/dynamic_external_content_default_test.dart`，2 例通过。跑测试时保留代理设置，只把 `localhost,127.0.0.1,::1` 加进 `NO_PROXY`。
2. **变异**：把 `surface.dart` 里 `externalContentProbe?.call() ?? true` 改成 `?? false`，测试 1 必须失败；立刻恢复，`git diff --stat packages/muyon_ui/lib` 必须为空。
3. `cd packages/muyon_ui && flutter analyze`，0 个问题。
4. `dart format` 只格式化新文件。

## 不做
不改 `lib/`、不改其他测试、不改 `analysis_options.yaml`；过不了就停下回报报错前 20 行；不用 `skip`。

## 提交与回报
提交说明 `test(ui): pin fail-closed external content default`，只含新测试文件，推到 `task/oc-4-external-probe-default`，`git ls-remote` 确认。
回报**必须逐项写**：提交哈希；2 个测试名与结果；变异时失败的测试名；`git diff --stat packages/muyon_ui/lib` 原样输出；analyze 结果。只给提交号不算完成。
