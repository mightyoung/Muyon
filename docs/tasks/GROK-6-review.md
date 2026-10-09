# GROK-6 审查

审查分支 `review/GROK-6` @ `94d2973`（grokbot）· 审查：leader A 自审 · 2026-10-09

| 项 | 结论 |
|---|---|
| 交付 1～6 | 满足：10 个对象类型、约 68 个顶层字段；关系；写入方式（对照 GROK-2 补漏）；卡片建议；REG-3 要补的缺口与工具清单；「未能静态确认」9 项 |
| 抽查 | 4 处都与代码一致：`change_log.dart` 没有跟踪 `project`、`note`、`paper_binding`；`saveNote` 只插入（`store.dart:417`）；卡片作者的默认值是 `'local-user'` 和 `'import'`（`card_store.dart:300,343`）；`saveTask` 每次修订号加 1（`store.dart:437` 起） |
| 关键发现 | 科研没有询价那样统一的 `save/delete/restore` 和统一校验入口，多数对象也没有版本字段，所以 REG-3 不能直接套用 REG-4c 的通用写工具，要先补版本字段和校验，或者改用具名工具 |
| 待用户确认 | §6 第 9 项：科研内容字段的敏感度 |

**合入。** 作为 REG-3 与 AIUI-7、AIUI-9（科研部分）的规格依据。
