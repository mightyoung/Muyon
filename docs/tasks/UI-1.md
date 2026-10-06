# UI-1 设计系统基线与统一前端套件

分支 `task/ui-1-design-system`（UI-0 合入后由 leader 从 `develop` 创建）· 执行 本地 senior engineer（Opus）· 审查 leader · 依赖 UI-0

设计依据：[ui-redesign-brief-2026-10-06.md](../design/ui-redesign-brief-2026-10-06.md) §3、§4.2、§4.4、§4.6、§4.7。**范围冻结**：本任务属于 UI 重构，须用户批准例外后才开工（见设计稿 §7）；批准前只允许做第 1 步（文档）。

## 目标
让 `packages/muyon_ui` 成为**所有业务插件共用的唯一前端套件**：主题、token、图标、通用组件。本任务**只建套件与迁移通用部件，不改任何页面的信息架构**（新壳在 UI-2）。

## 步骤

### 1. 设计系统文档（可在冻结期先做）
新建 `docs/design/muyon-design-system.md`：
- 信息架构摘要（底栏/图标轨 5 项）、沿用的 token（引用 `muyon_ui/lib/src/tokens.dart`）、新增 token（`radiusLarge=24`、`radiusPill=999`、手机壳层 canvas 候选值与对比度结果）；
- 组件清单与用法、状态词表（任务/传输/送达/接纳/索引/模型位置），**单一来源**，枚举名→中文业务词；
- 无障碍规则：底栏/图标轨无可见文字，但必须有 `Semantics` 标签与 tooltip；颜色之外必须有图标或文字；对比度 ≥4.5:1；
- 在 `docs/design/DESIGN.md` 顶部加一行注记：「信息架构以 muyon-design-system.md 为准」，**不改其余内容**。

### 2. 套件组件（`packages/muyon_ui/lib/src/…`）
实现并导出：`PageScaffold`（标题/说明/主操作/次操作/内容 + loading/empty/filtered-empty/error 四态）、`MasterDetail`（≥1000 并排，窄屏独立页）、`DataTable`（沿用询价 `data_grid` 规则：表头 42、行 52、表内横滚、金额右对齐、tabularFigures）、`StatusBadge(kind,label)`（图标+中文+色）、`ObjectChip`（含"已不存在"态）、`ConfirmSheet`（做什么/对谁/发送内容可展开/摘要散列/后果/按钮）、`ObjectDetail`（字段表+关联 chips+在业务页打开+针对此对象提问）、`SegmentedPill`（胶囊分段）、`IconRail`/`BottomIconBar`（5 项，选中实心，Semantics+tooltip，不画文字）、表单控件（输入、下拉、金额、日期、筛选条）、`MuyonDialog`、`MuyonToast`。
- 圆角大尺寸只给壳层组件使用；`DataTable`/表单保持 8px。
- 动效沿用 `muyon_ui/motion.dart`，尊重 `disableAnimations`。

### 3. 迁入询价的通用部件
把 `packages/inquiry_module/lib/src/{widgets,app}` 中**通用**部分迁入 `muyon_ui`：`data_grid`、`AppIcon`/`MaterialIcon` 与 102 枚图标目录（生成器与 `catalog.json` 的路径保持可用，`python3 …/generate_business_icons.py --check` 仍通过）、`motion`、`command_palette`。询价自己的 `theme.dart` 改为从 `muyon_ui` 取 token（暂留薄适配层，UI-9 再删）。**不改询价页面的行为与文案。**

### 4. 去硬编码颜色
- 研究、原型包内 `Color(0x…)`、`Colors.*` 改用 token；
- 加 lint/测试：`packages/*_module` 的 UI 代码出现硬编码颜色即失败（token 文件与 golden 除外）。询价包允许一个**带到期说明**的白名单，UI-9 清零。
- 原型 WebView 内部不管（内容以导入为准）；只处理其外围页面。

### 5. 组件目录页与 golden
- debug 构建下可进入的组件目录页（`kDebugMode` 才注册入口），展示每个组件的全部状态；
- 每个组件的 widget 测试 + golden：浅/深 × 宽 320/390/1280 × 文字 100%/200%；
- 状态词表有测试，保证每个枚举值都有中文词。

## 验收（leader 按 REVIEW.md「必做」+ 下列）
- `bash scripts/ci.sh` 全绿；`flutter analyze` 无新增；现有测试**不改断言**通过（`responsive_shell_test`、`inquiry_*_test`、`north_star_inquiry_test` 等）。
- 询价与科研页面外观**不应有可见变化**（除圆角/token 微调外），贴出前后截图各 2 张（与 UI-0 基线对照）。
- 无新第三方依赖；无硬编码颜色（lint 通过，白名单有清单）。
- 文档可读：新人只看 `muyon-design-system.md` 能用套件拼出一个页面。
- 报告写明：迁移了哪些文件（旧路径→新路径）、哪些仍留在询价包及理由。

## 不做
新壳与导航（UI-2）、收件箱（UI-3）、助手栏（UI-4）、各页面改版、重命名 Folio（UI-10）、改包名。
