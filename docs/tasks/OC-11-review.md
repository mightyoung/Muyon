# OC-11 审查（leader A，2026-10-11）

提交 `6192950` · 结论：**通过，可合入**（授权安全路径，修 CR-10 F4）。

- `readTask`：会话事实行存在但损坏（`_read` 为 null），或 `taintState` 为 unknown 时，原 clean 任务返回 unknown；tainted 优先（任务自身 tainted 显式保留）；会话事实不存在时行为不变。
- 复跑：facts 测试 25 例通过；执行者另报 `assistant_loaded_input_authority_test`、`assistant_grants_test` 共 43 例通过，analyze 无问题。
- 变异：执行者 `(historyRowExists && history == null)` → false 被检出；审查方 `history?['taintState'] == 'unknown'` → false 被检出（1 例失败）。改前测试 1、2 均失败，属有效 RED。
