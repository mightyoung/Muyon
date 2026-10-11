# WC-A 写卡契约骨架（`muyon_module_api`）

分支 `task/wc-a-write-card-contract` · 基线 develop（含 ADR-0004 §4.5 2026-10-11 修订）· 执行：待指派 · 审查：leader A

## 依据
[GB-5 写卡契约设计](../reviews/2026-10-11-write-card-contract.md) 第 1 节与第 5 节「片 A」；用户已采纳 W1～W6（ADR-0001 末尾、ADR-0004 §4.5 修订）。

## 范围（只做片 A）
- 在 `packages/muyon_module_api` 按 GB-5 §1.1 指定位置新增：`WriteFormCapable`、写表单声明类型（类型 × 操作、可写字段、创建可用、关系写入约束）、`WriteValidationResult`（规范化候选、错误码 + 字段路径、表单级错误、草稿修订）、结构化冲突数据类型、`BusinessReceiptLookup` 与对应 `ModuleFeature`。
- 从 `muyon_module_api.dart` 导出；全部是可选能力，不实现的模块行为不变。
- 合规检查：声明了 `writeForms` 却不实现 `validateDraft` → 合规套件报错（找现有合规测试的位置，照现有检查项的写法加）。
- **不做**：询价实现（片 B）、冲突与回执的执行路径（片 C、D）、任何 UI 与宿主接线（片 E）。

## 测试
- 新类型的值语义与不可变性（构造、相等、拒绝非法组合，如字段路径为空）。
- 合规检查的正反两例。
- 不变性：现有模块（询价、科研、原型）不实现新能力时，现有合规与宿主测试全部照旧通过。

## 验证
`packages/muyon_module_api` 与 `apps/muyon` 的 analyze（info 也算失败）与全量测试；保留代理设置，`NO_PROXY` 加 localhost；不导出 `MUYON_EVAL_REAL`；只格式化改动文件。

## 回报
提交哈希；新增公开类型清单与文件位置；测试与 analyze 数字；与 GB-5 草案不一致的地方及理由。
