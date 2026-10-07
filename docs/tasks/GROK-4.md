# GROK-4 UI-1b 盘点：硬编码颜色与询价通用部件

分支 `task/grok-4-ui-inventory` · 执行：grokbot（只做静态核对）· 审查：leader 抽查 · 给谁用：UI-1b（把询价的通用部件迁入 `muyon_ui`、去掉硬编码颜色）

## 只做这些
产出 `docs/reviews/2026-10-07-ui-1b-inventory.md`：
1. **硬编码颜色**：在 `packages/research_module/lib`、`packages/prototype_module/lib`、`packages/inquiry_module/lib`、`apps/muyon/lib` 中，找出 `Color(0x…)`、`Colors.*`、`Color.fromARGB/fromRGBO` 的每一处使用，附 `文件:行`。按包分组计数，并给出建议对应的 v6 token（以 `docs/design/v6/tokens.md` 为准），对不上的标「无对应 token」。排除 token 定义文件本身（`muyon_ui/lib/src/tokens.dart`、询价的 `theme.dart`）和测试文件，但要单独统计这两类的数量。
2. **写死尺寸**：同样范围内的 `height: <数字>`、`SizedBox(height: …)` 用在交互控件上的地方，只统计数量并给出前 20 处示例。依据 [UI 方案](../design/ui-redesign-brief-2026-10-06.md) §8 第 19 条的尺寸自适应规则。
3. **询价通用部件**：盘点 `packages/inquiry_module/lib/src/{widgets,app}` 里的 `data_grid`、`AppIcon` / `MaterialIcon` 与图标目录（生成器脚本与 `catalog.json` 的路径）、`motion`、`command_palette`，逐个列出：
   - 文件、公开类、被哪些文件引用（列出引用方）；
   - 是否依赖询价专属的类型（依赖了就不能直接迁）；
   - 建议迁移后的路径。
4. 风险：迁移后可能破坏的测试（按文件名列出）。

## 不做
不改代码；不运行 Flutter；不确定就写「未能静态确认」。

## 回报
分支与提交哈希；文档路径；各包的硬编码颜色数；可直接迁移和需要改造的部件清单。
