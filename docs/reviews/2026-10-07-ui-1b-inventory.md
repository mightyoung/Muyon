# UI-1b 盘点：硬编码颜色、写死尺寸、询价通用部件（GROK-4）

日期：2026-10-07 · 任务：[GROK-4](../tasks/GROK-4.md) · 执行：工程师2号（grokbot）· 分支：`task/grok-4-ui-inventory` · 方法：只读 `rg`/文件阅读，**未**改代码、**未**运行 Flutter · 对照设计：[v6 tokens](../design/v6/tokens.md)、[UI 方案 §8 第 19 条](../design/ui-redesign-brief-2026-10-06.md)

不确定处标「未能静态确认」。

---

## 1. 硬编码颜色

检索模式：`Color(0x…)`、`Colors.*`、`Color.fromARGB`、`Color.fromRGBO`。  
范围：`packages/research_module/lib`、`packages/prototype_module/lib`、`packages/inquiry_module/lib`、`apps/muyon/lib`。  
**主清单排除**：`packages/muyon_ui/lib/src/tokens.dart`、询价 `packages/inquiry_module/lib/src/app/theme.dart`、以及测试文件（这两类单独计数）。  
本范围**无** `Color.fromARGB` / `Color.fromRGBO` 命中。

### 1.1 按包计数（主清单）

| 包 | 命中次数 | 涉及文件数 |
|---|---:|---:|
| `research_module` | 1 | 1 |
| `prototype_module` | 0 | 0 |
| `inquiry_module`（已排除 `theme.dart`） | 8 | 6 |
| `apps/muyon` | 0 | 0 |
| **合计** | **9** | **7** |

### 1.2 逐处清单与建议 v6 token

| 文件:行 | 用法 | 建议 token |
|---|---|---|
| `packages/research_module/lib/src/relations/relations_page.dart:298` | `Colors.transparent` | **无对应 token**（透明占位；可保留或日后封装 `clear`） |
| `packages/inquiry_module/lib/src/app/shell.dart:212` | `Colors.transparent`（非选中态） | **无对应 token** |
| `packages/inquiry_module/lib/src/features/projects/project_detail.dart:353` | `Colors.transparent`（非选中 tab 底） | **无对应 token** |
| `packages/inquiry_module/lib/src/features/ai/source_input.dart:147` | `Colors.transparent` | **无对应 token** |
| `packages/inquiry_module/lib/src/features/ai/ask_page.dart:693` | `Colors.transparent` | **无对应 token** |
| `packages/inquiry_module/lib/src/features/ai/ask_page.dart:748` | `Colors.transparent` | **无对应 token** |
| `packages/inquiry_module/lib/src/features/ai/ask_page.dart:817` | `Colors.transparent` | **无对应 token** |
| `packages/inquiry_module/lib/src/features/home/command_palette.dart:39` | `barrierColor: Colors.black26` | **无对应 token**（v6 未定义 scrim/遮罩） |
| `packages/inquiry_module/lib/src/features/exchange/import_flow.dart:231` | `barrierColor: Colors.black54` | **无对应 token**（同上） |

说明：主清单几乎全是 `Colors.transparent` 与对话框遮罩；业务色多数已走询价 `Tokens.*`（定义在被排除的 `theme.dart`）。

### 1.3 单独统计：token 定义文件

| 文件 | 命中次数 | 备注 |
|---|---:|---|
| `packages/muyon_ui/lib/src/tokens.dart` | 44 | v6 色板本体，排除出主清单 |
| `packages/inquiry_module/lib/src/app/theme.dart` | 4 | 见下表；另有 `_pick(int,int) => Color(...)` 用整型字面量，**不**匹配 `Color(0x` 模式，未计入 4 |

`theme.dart` 4 处：

| 文件:行 | 用法 | 建议 v6 token |
|---|---|---|
| `:68` | `Color(0xFF0B1221)` / `Colors.white`（`onPrimary`） | 深色侧接近 **bg** `#0A0A0A`（非精确）；浅色 **onacc** / 白 |
| `:74` | `Colors.white`（`onSecondary`） | **onacc**（浅色） |
| `:76` | `Colors.white`（`onError`） | **onacc**（浅色） |
| `:216` | `Color(0xFF1B47C2)` | **deep**（浅色 `#1B47C2`，精确） |

### 1.4 单独统计：测试文件

| 范围 | 命中次数 |
|---|---:|
| `packages/inquiry_module` 测试 | 9（`generated_icon_sources_test.dart`、`app_icon_test.dart`） |
| `research_module` / `prototype_module` / `apps/muyon` 测试 | 0 |

---

## 2. 写死尺寸（交互控件）

依据：[UI 方案 §8 第 19 条](../design/ui-redesign-brief-2026-10-06.md)——设计稿固定像素高度只作视觉参考；实现应由**内容 + 内边距**决定高度，48 仅为最小点击区；文字放大到 200% 时容器随之增高。v6 参考：表头 42、表行 52、底栏 76、图标轨 72、命令面板宽 560 等（见 tokens「间距与尺寸」）。

### 2.1 统计口径

- **计入**：控件/容器自身的 `height: <数字>`（排除 `TextStyle` 行高 `height: 1.x`）、`rowHeight` / `minimumSize`/`fixedSize` 的高度分量、带 `width`+`height` 的 `SizedBox`（命中区）。
- **不计入**：纯间距 `SizedBox(height: N)`（无 `width`、无 `child` 包裹控件）、`Divider(height:)`、OCR 图像预处理里的 `height:`（非 UI 控件）。
- 同范围内另有大量间距用 `SizedBox(height: …)`（约数百处）；按 §8.19 / v6 间距档 4·8·12·16·20·24 治理，但不算「交互控件写死高度」。

### 2.2 数量

**交互/控件维度写死高度：16 处**（4 包合计；已去掉 `paddle_ocr_service` 图像高 48）。

按包：`inquiry_module` 11 · `research_module` 3 · `apps/muyon` 2 · `prototype_module` 0。

### 2.3 前 20 处示例（不足 20 则列全）

| # | 文件:行 | 值 | 语境 |
|---|---|---:|---|
| 1 | `research_module/.../relations_page.dart:415` | 340 | 图区容器高 |
| 2 | `research_module/.../relations_page.dart:422` | 340 | 同上 |
| 3 | `research_module/.../relations_page.dart:439` | 56 | 节点卡片 `Positioned` 高（内含 `InkWell`） |
| 4 | `inquiry_module/.../widgets/data_grid.dart:50` | 52 | 默认 `rowHeight = 52` |
| 5 | `inquiry_module/.../widgets/data_grid.dart:136` | 42 | 表头 `Container(height: 42)` |
| 6 | `inquiry_module/.../app/shell.dart:337` | 72 | `NavigationBar(height: 72)` |
| 7 | `inquiry_module/.../features/home/command_palette.dart:163` | 420 | 面板 `SizedBox(width: 560, height: 420)` |
| 8 | `inquiry_module/.../app/title_bar.dart:21` | 600 | 窗口 `minimumSize: Size(960, 600)`（窗口最小高，非控件） |
| 9 | `inquiry_module/.../features/ai/ask_page.dart:509` | 14 | 进度/指示条高度 |
| 10 | `inquiry_module/.../features/ai/source_input.dart:143` | 20 | 步骤圆点容器高 |
| 11 | `inquiry_module/.../features/quotes/compare_view.dart:136` | 34 | 行/条高度 |
| 12 | `inquiry_module/.../features/quotes/compare_view.dart:413` | 96 | `PriceTrend(..., height: 96)` |
| 13 | `inquiry_module/.../features/data_center/relation_graph.dart:415` | 38 | 图节点/条高度 |
| 14 | `inquiry_module/.../app/motion.dart:135` | 6 | 减少动态时 `TaskProgress` 静态圆点 |
| 15 | `apps/muyon/.../model_profile_tile.dart:372` | 16 | 磁贴内固定高 |
| 16 | `apps/muyon/.../draft_view.dart:54` | 12 | 视图内固定高 |

（未列入：`apps/muyon/lib/services/ocr/paddle_ocr_service.dart:348` `height: 48`——ONNX 输入缩放，非 UI。）

**与 §8.19 的差距**：`NavigationBar` 72、表头 42、行 52、命令面板 420 等均为写死像素；迁移/UI-1b 时应改为最小高度约束 + 内容撑开，命令面板高度宜随内容/视口比例，而非固定 420。

---

## 3. 询价通用部件盘点

范围按任务：`packages/inquiry_module/lib/src/{widgets,app}`，并含任务点名的 `command_palette`（实际在 `features/home/`）。

### 3.1 `data_grid`

| 项 | 内容 |
|---|---|
| 文件 | `packages/inquiry_module/lib/src/widgets/data_grid.dart` |
| 公开 API | `GridColumn<T>`、`GridSort`（typedef）、`DataGrid<T>` |
| 引用方（生产） | `features/catalog/catalog_page.dart`、`features/quotes/quotes_page.dart`、`features/hub/hub_page.dart` |
| 询价专属依赖 | **是**：`package:supplier_core` 的 `Num`（排序/导出）；`../app/theme.dart` 的 `Tokens.*`；同包 `app_icon.dart` |
| 建议迁移路径 | `packages/muyon_ui/lib/src/widgets/data_grid.dart`；迁移前把 `Tokens` 换成 `muyon_ui` token，`Num` 改为抽象比较或可选依赖，避免 `supplier_core` 进入 UI 包 |
| 判定 | **需改造后迁移** |

### 3.2 `AppIcon` / `MaterialIcon` / 图标目录

| 项 | 内容 |
|---|---|
| 文件 | `widgets/app_icon.dart`、`widgets/material_icon.dart`、生成物 `widgets/icon_paths.g.dart` |
| 公开 API | `AppIcon`；`materialIconFor(...)`、`MaterialIcon`；生成表 `businessIconPaths` / `businessIconNames` / `businessIconFills` |
| `AppIcon` 引用方 | 询价内约 **47** 个生产文件（壳层、目录、报价、项目、AI、交换、规格等）；`data_grid` / `material_icon` / `ledger` 亦引用 |
| `MaterialIcon` 引用方 | 仅 `features/catalog/catalog_page.dart`（静态所见） |
| 询价专属依赖 | **否**（仅 Flutter + 生成路径表）。`MaterialIcon` 内建中文/英文物料关键词映射，语义偏采购，但代码自洽、无 `AppState` |
| 图标目录路径 | 见下 |
| 建议迁移路径 | `muyon_ui/lib/src/widgets/app_icon.dart`、`material_icon.dart`、`icon_paths.g.dart`；生成器输出目标同步改到 `muyon_ui` |
| 判定 | **可直接迁移**（生成器路径需一并搬迁/改写） |

#### 图标目录与生成器（静态核对）

| 角色 | 文档/注释中的路径 | 本分支是否存在 |
|---|---|---|
| 源目录 | `docs/design/icons/catalog.json`（`icon_paths.g.dart` 头注释；[DESIGN.md](../design/DESIGN.md)） | **缺失** |
| 生成器 | 头注释：`tool/generate_business_icons.py`；DESIGN.md：`apps/supplier_app/tool/generate_business_icons.py --check` | **均缺失**（仓库无 `apps/supplier_app/`、无根级该脚本） |
| 测试夹具副本 | `packages/inquiry_module/test/fixtures/icons/catalog.json` | **存在**（102 条） |
| 已提交生成物 | `packages/inquiry_module/lib/src/widgets/icon_paths.g.dart` | **存在** |

**未能静态确认**：生成器脚本与设计源 `catalog.json` 的现行权威位置（可能未迁入本 monorepo，或仅留在历史路径）。UI-1b 迁移时需先找回生成器，否则 `--check` 无法在本树运行。

### 3.3 `motion`

| 项 | 内容 |
|---|---|
| 文件 | `packages/inquiry_module/lib/src/app/motion.dart` |
| 公开 API | `AppMotion`、`AccessiblePageTransitions`、`PageArrival`、`showAppDialog`、`TaskProgress` |
| 引用方（生产，节选） | `app/shell.dart`、`app/theme.dart`、`platform/files.dart`、`widgets/deletion.dart`、`features/home/command_palette.dart`，以及大量 `showAppDialog` 调用方（询价/规格/交换/项目/目录/AI 等，约 30+ 文件） |
| 询价专属依赖 | **否**（仅 Flutter） |
| 与 `muyon_ui` 关系 | `packages/muyon_ui/lib/src/motion.dart` **已有** `AppMotion` + `AccessiblePageTransitions`（与询价前半一致）；询价多出 `PageArrival` / `showAppDialog` / `TaskProgress` |
| 建议迁移路径 | 并入已有 `packages/muyon_ui/lib/src/motion.dart`；询价改为 `export`/`import` muyon_ui，删除重复前半 |
| 判定 | **可直接迁移**（合并进现有文件，注意符号重复） |

### 3.4 `command_palette`

| 项 | 内容 |
|---|---|
| 文件 | `packages/inquiry_module/lib/src/features/home/command_palette.dart`（不在 `widgets/`/`app/`，但任务点名） |
| 公开 API | `showCommandPalette`、`showShortcutHelp`（其余 `_Entry` / `_Palette` 私有） |
| 引用方 | `app/shell.dart`（快捷键）、`features/home/home_page.dart`（入口按钮）；`showShortcutHelp` 亦被面板内条目调用 |
| 询价专属依赖 | **是**：`AppState`、`Section`、`shell`/`toast`、以及询价特性页（`showQuoteForm`、`showMaterialImport`、`showProjectForm`、`openRecord`、`showSpecMatch`、`CatalogPage` 等） |
| 建议迁移路径 | 通用壳（搜索框 + 列表 + 键盘导航）→ `muyon_ui/lib/src/widgets/command_palette.dart`；动作注册表留在询价（传入 `List<PaletteAction>`）。**整文件原样迁不可行** |
| 判定 | **需改造后迁移**（抽离 UI 壳） |

### 3.5 迁移判定汇总

| 部件 | 判定 |
|---|---|
| `AppIcon` + `icon_paths.g.dart` | 可直接迁移 |
| `MaterialIcon` | 可直接迁移（语义偏采购，可接受放在 `muyon_ui` 或随后再拆） |
| `motion`（含 PageArrival / showAppDialog / TaskProgress） | 可直接迁移（合并入已有 `muyon_ui` motion） |
| `data_grid` | 需改造（去 `supplier_core` / 询价 `Tokens`） |
| `command_palette` | 需改造（去 `AppState` 与特性页耦合） |
| 图标生成器 + 设计源 catalog | **阻塞**：本树缺失，路径未能静态确认 |

---

## 4. 风险：迁移后可能破坏的测试

按**文件名**列出（静态：直接测这些符号，或强依赖其渲染/路径）：

| 测试文件 | 关联部件 |
|---|---|
| `packages/inquiry_module/test/app_icon_test.dart` | AppIcon / icon_paths |
| `packages/inquiry_module/test/material_icon_test.dart` | MaterialIcon |
| `packages/inquiry_module/test/generated_icon_sources_test.dart` | catalog 夹具、icon_paths、AppIcon |
| `packages/inquiry_module/test/motion_test.dart` | PageArrival / TaskProgress / showAppDialog |
| `packages/inquiry_module/test/theme_integration_test.dart` | 主题 / AccessiblePageTransitions（若改 import） |
| `packages/inquiry_module/test/catalog_responsive_test.dart` | DataGrid 布局 |
| `packages/inquiry_module/test/ui_workspace_test.dart` | 工作区含表格/图标 |
| `packages/inquiry_module/test/workspace_design_audit_test.dart` | 设计审计 |
| `packages/inquiry_module/test/screenshot_test.dart` | 截图（图标/壳层） |
| `packages/inquiry_module/test/hub_test.dart` | Hub 页 DataGrid |
| `packages/inquiry_module/test/catalog_test.dart` | 目录页 / MaterialIcon |
| `packages/inquiry_module/test/ui_conformance_test.dart` | UI 一致性 |
| `packages/inquiry_module/test/business_design_audit_test.dart` | 业务页审计 |

命令面板：未见独立 `*command*palette*_test.dart`；破坏面主要在依赖 `Shell` / 快捷键的集成与截图类测试（**未能静态确认**每一份是否断言 Ctrl+K）。

图标生成器缺失时，任何依赖 `python3 …/generate_business_icons.py --check` 的 CI/本地步骤也会失败（路径见 §3.2）。

---

## 5. 回报摘要（给 UI-1b）

- 主清单硬编码颜色：**9**（research 1 + inquiry 8）；prototype / muyon app **0**。定义文件另计 tokens **44**、询价 theme **4**；测试 **9**。
- 交互控件写死高度：**16**（示例见 §2.3）；另有大量间距 `SizedBox` 未计入。
- 可直接迁移：`AppIcon`/`icon_paths`/`MaterialIcon`、`motion` 增量合并。
- 需改造：`DataGrid`、`command_palette`。
- 阻塞：设计源 `catalog.json` 与 `generate_business_icons.py` 不在本分支树内。
