# UI-1a 设计系统：v6 token、通用组件与自适应尺寸

分支 `task/ui-1a-design-system` · 依据：[设计稿 v6](../design/v6/README.md)（`tokens.md`、`components.md`、`round7-notes.md`）、[前端开发备忘录](../design/v6/frontend-memo.md)（稿内错误以备忘录为准，尤其是确认卡在外部内容下的按钮档位）、[UI 方案](../design/ui-redesign-brief-2026-10-06.md) §3、§4、§8、[UI-1](UI-1.md) 第 1、2、5 步 · 执行：Codex（排在 AUTH-1a 之后）· 审查：leader（交叉核实：junior 或 engineer 重跑测试，leader 抽查）· 阶段：第二阶段（ADR-0003 允许 UI-0～UI-5）

本任务是 UI-1 的前半：建套件，**不迁移询价部件、不改任何页面**。UI-1 的第 3、4 步（迁入询价通用部件、去硬编码颜色）拆到 UI-1b，等 FOLIO-BYPASS、REG-4 动完 `inquiry_module` 后再派。UI-0 的截图基线不是本任务的前提。

## 尺寸规则（用户 2026-10-07 决定，优先于设计稿里的像素值）
设计稿里的 `height: 48px` 等固定高度**只是视觉参考，不照抄**：
- 控件高度由内容和内边距决定；48 只作为**最小点击区**，用 `BoxConstraints(minHeight: 48, minWidth: 48)` 或 `MaterialTapTargetSize`/`kMinInteractiveDimension` 保证，不写死 `height`。
- 布局按比例分配：用 `Flexible`/`Expanded`、`LayoutBuilder` 断点和 `FractionallySizedBox` 之类，不按像素拼。
- 文字放大到 200% 时不得截断或溢出，容器随文字增高。
- 例外是确实需要定高的元素，例如表头、表行这类数据表格行高、开关、图标尺寸。要在 token 里命名，并注释原因。

## 只做这些
1. **文档** `docs/design/muyon-design-system.md`：
   - 信息架构摘要（底栏 / 图标轨 5 项）；
   - token 表，以 v6 `tokens.md` 为准，含 `warn` / `warnbg`，并写明颜色规则：红表示失败、危险、外传；`warn` 表示需注意；绿表示成功；琥珀只作深色主色；待确认与选中同色系；
   - 上面的尺寸规则；
   - 组件清单与用法；
   - 状态词表：枚举名对应中文业务词，单一来源；
   - 无障碍规则。

   另在 `docs/design/DESIGN.md` 顶部加一行注记，不改其余内容。
2. **token**（`packages/muyon_ui/lib/src/tokens.dart`）：按 v6 补齐浅色、深色两套，深色主色琥珀，新增 `warn` / `warnbg`、圆角、间距；`theme.dart` 生成对应的 `ThemeData`。现有 token 名保留，或者给出兼容别名，保证现有使用方编译不报错。
3. **组件**（`packages/muyon_ui/lib/src/…`，从 `muyon_ui.dart` 导出），全部按尺寸规则实现：
   - `PageScaffold`（loading / empty / filtered-empty / error 四态）、`MasterDetail`、`StatusBadge`（图标 + 中文，色调只用 success / danger / warn / neutral）、`ObjectChip`（含「已不存在」态）、`SegmentedPill`、`IconRail` / `BottomIconBar`（5 项，选中实心，`Semantics` + tooltip，不画文字）；
   - 确认类组件：`ConfirmCard`（字段为做什么 / 对谁 / 发送内容（可展开）/ 摘要散列 / 后果；状态与按钮档位按 v6 `Muyon Assistant Auth`）、`BatchConfirmCard`、`WarnBanner`（外部内容提示条）、`ScopeChip`。**本任务只做组件，不接入助手**，接入属于 UI-3、UI-4；
   - `MuyonDialog`、`MuyonToast`。
4. **组件目录页**：只在 debug 构建（`kDebugMode`）下注册入口，展示每个组件的全部状态。
5. **测试**：
   - 每个组件都有 widget 测试，断言最小点击区 ≥ 48、`Semantics` 标签齐全，以及 200% 文字下不溢出（用 `tester.takeException()` 检查）；
   - golden 只在 macOS 生成，按 `scripts/ci.sh` 的 golden 约定处理 Linux 上的跳过；
   - 状态词表测试：每个枚举值都有中文词；
   - 对比度测试：按 WCAG 公式断言正文类配对 ≥ 4.5（含 `warn/sf`、`warn/warnbg`）。

## 不做
- 不改任何页面、不迁移询价部件、不改询价的 `theme.dart`、不加新第三方依赖、不改包名；不接入助手，也不改确认语义；不碰 REG-2b 的文件（`app/module_host.dart`、`module_catalog.dart`、`module_registry.dart`、`platform/scope_resolver.dart` 等）。
- 已有测试不改断言（`responsive_shell_test`、`inquiry_*`、`north_star_inquiry_test` 等）。
- 原始验证日志不进仓库，摘要写在提交说明里。

## 验证
- `flutter analyze`（`packages/muyon_ui`、`apps/muyon`，info 也算失败）；`packages/muyon_ui` 全量测试；宿主全量 `flutter test`。
- 变异：(a) 把 `BottomIconBar` 某一项的点击区改成 40；(b) 去掉某个组件的 `Semantics` 标签；(c) 把 `warn` 的深色值改成与 `deep` 相同。对应测试都必须失败。

## 回报
分支与提交哈希、新增和修改的文件、token 名与 v6 的对照表、哪些地方用了定高及理由、验证摘要行、变异结果。
