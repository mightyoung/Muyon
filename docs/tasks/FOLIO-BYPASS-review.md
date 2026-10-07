# FOLIO-BYPASS 审查

审查分支 `review/FOLIO-BYPASS` @ `3a615f2`（junior）· 核实：`reviewer-sonnet-high` · 2026-10-07

## 范围
`app_state.dart`、`ask_page.dart`、`ai_settings.dart`，新增 `assistant_permission_hosted_test.dart`，另改了已有测试 `inquiry_web_authority_test.dart`（4 行）。没有碰 `supplier_core`，也没有隐藏助手。

## 核实结果
| 项 | 结论 |
|---|---|
| getter | 满足：宿主模式下，存储的 `bypass` 读作 `confirmWrites`；setter 原样保存存储值；非宿主模式行为不变 |
| 宿主模式下没有别的路径让 `bypass` 生效 | 满足：存储值只在 `app_state.dart:452` 读取一次，其余使用方（`ask_page` 的 `autoApprove`、`createAssistantWebTools`、`supplier_core` 的 `skipApproval`）都取自 getter。探针用例确认：经 AskPage 驱动写入，仍先弹出确认，确认前库里没有改动 |
| 选择器 | 满足：两个选择器在宿主模式下都不列出 `bypass`；存储值为 `bypass` 时，下拉框显示 `confirmWrites`，不会崩溃 |
| 改动的已有测试 | **可接受且必要**：用原写法跑新代码，`inquiry_web_authority_test` 会失败。因为宿主模式下 `bypass` 读出来仍是 `confirmWrites`，「权限发生变化」的条件不再成立。改成 `readOnly`（收窄权限）保留了「审阅期间权限变化就中止」的原意，这个失败本身也恰好证明修复生效了 |
| 变异 | 三个都被抓住：去掉 getter 的宿主分支（4 例失败）；任一选择器在宿主模式下列出 `bypass` |
| 运行 | 两个包的 analyze 都没有问题；`assistant_permissions_test` 原样通过；CI run 37629301317 success。本机全量测试有 5 例因机器负载失败，用 `--concurrency=1` 重跑全部通过；inquiry 的 46 例是已知的 golden 漂移 |

## 可选（REG-4c 一并处理）
- `ask_page.dart:433` 附近菜单的 `onChanged` 仍可以把 `bypass` 写进存储。现在只是因为菜单不列出这一项才到不了，属于纵深防御。
- `inquiry_web_task_stop_test.dart:146,245` 仍把权限设为 `bypass`。在宿主模式下它实际跑的是 `confirmWrites`，用例名容易误导。

## 结论
**合入。**
