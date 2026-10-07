# 多步任务评测：现状基线（第二阶段之前）

**运行代码的提交：`488099e`**（`task/r-1-evidence`，基于含 P0-3d 的 `develop`；运行前后 `apps/muyon` 下除 macOS 构建副产物外没有改动，副产物已还原）。这一行由执行者在生成报告后手动补写，生成器本身不写提交。
运行时间 2026-10-07T14:09:40.392114Z。题集 `apps/muyon/lib/assistant/agent_eval/agent_task_set.json`（22 题，基于询价 North Star 种子数据），运行器 `apps/muyon/lib/assistant/agent_eval/agent_eval.dart`。重跑命令见该文件顶部注释。每个模型单独一份报告（`agent-task-eval-<模型 id 的 slug>.md`），互不覆盖。

本文件测的是**现有** `PersonalAgent`（第二阶段内核 v2 与分级授权之前）：每一轮模型请求都要人工确认，写入工具要审批，只读工具不需审批；`maxRounds` 为 4。内核 v2（K-2～K-4）和分级授权（AUTH-1）完成后用同一题集重测，与本表对比。

## 评测口径

- 每题在全新的数据目录里打开 `MuyonHost`，种入同一份询价种子数据，再用 `PersonalAgent` 跑完整个任务；题与题之间互不影响。
- **成功**：同时满足 任务正常结束；没有多余写入（题目没要求的写工具一律由“本人”拒绝并记为失败；不要求写入的题，数据也不能有任何变化）；要求的工具都被提出过（有顺序要求的按顺序）；要求的写入已生效且结果状态与期望一致；最终回答包含期望的事实（数字按数值比较，如 2080 与 2,080.00 相同）。
- 失败原因：`request_failed` 请求或任务失败；`scope_pinned` 同一任务里先写入了被选中的记录，随后的工具调用因对话范围固定了记录修订号而被拒（现状的产品行为，不是模型错误，单独列出）；`tool_missing` / `tool_order` 工具缺失或顺序不对；`unexpected_tool` 应弃权的题提出了工具；`extra_write` 多余写入；`write_missing` / `write_mismatch` 要求的写入没生效或结果不符；`fact_mismatch` 回答里缺期望的事实。
- 事实判定只是“包含”检查：回答里出现期望的数字或文字即算，不核对它说的是什么；容易误撞的小数字要求紧邻锚点（数量认“条/个/笔/项/家”等量词，序数“第 4 项”不算；金额认“元/块/CNY/RMB”后缀或“¥/RMB/人民币/单价/价格”前缀）。中文数字（如“四”）不识别，只认阿拉伯数字。
- **人工确认次数**分两列：工具审批（写入工具，经本人确认后执行）与模型请求确认（每次向模型端点发送内容前的确认）。表中为“中位数 / 平均”。
- **首个模型响应时延**：现有助手不是流式的，这里记**第一次模型请求从发出到收到完整响应**的耗时（含出站账本记录），不是首字时延；只统计得到响应的题。
- **总时长**：从提交提示词到任务结束的墙钟时间，自动确认的间隔可忽略，主要是模型请求和工具执行。p50 / p95 为最近秩百分位。
- **用量**：模型端点报告的 `usage` 之和；端点没报告则写“未报告”。
- 工具集合取决于对话范围：只读工具只在全局范围可用，写入工具只在选中对象的范围可用，所以现状下一个任务不能先读后写（这是基线的一部分）。

| 项 | 值 |
|---|---|
| 端点 | `https://api.deepseek.com/chat/completions`（remote） |
| 模型 | `deepseek-chat` |
| 单次请求超时 | 90 s |
| 证据类别 | 真实模型运行（不是夹具） |

## 汇总

| 类别 | 题数 | 成功 | 成功率 | 工具审批 中位/平均 | 模型确认 中位/平均 | 轮数 中位 | 首个响应 p50 / p95 ms | 总时长 p50 / p95 ms | 用量 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| read_single | 6 | 5/6 | 83% | 0 / 0 | 2 / 2 | 2 | 893 / 1124 | 2137 / 2921 | 60950 入 / 913 出 |
| read_multi | 6 | 6/6 | 100% | 0 / 0 | 3 / 3.17 | 3 | 935 / 1300 | 3800 / 5416 | 109711 入 / 2219 出 |
| write | 6 | 3/6 | 50% | 1 / 0.67 | 1.50 / 1.50 | 1.50 | 979 / 1934 | 1933 / 2602 | 46144 入 / 1250 出 |
| abstain | 4 | 3/4 | 75% | 0 / 0 | 1 / 1.75 | 1 | 1197 / 2343 | 1731 / 4343 | 37733 入 / 747 出 |
| 合计 | 22 | 17/22 | 77% | 0 / 0.18 | 2 / 2.14 | 2 | 959 / 1934 | 2482 / 4571 | 254538 入 / 5129 出 |

失败原因（一题可有多个）：`request_failed` 2，`scope_pinned` 0，`tool_missing` 3，`tool_order` 0，`unexpected_tool` 0，`extra_write` 1，`write_missing` 2，`write_mismatch` 0，`fact_mismatch` 0。

## 逐题

| 题 | 类别 | 结果 | 工具 | 审批 | 模型确认 | 轮 | 首响应 ms | 总 ms | 失败原因 | 备注 |
|---|---|:-:|---|---:|---:|---:|---:|---:|---|---|
| RS-01 | read_single | ✓ | `inquiry.project_budget` | 0 | 2 | 2 | 1114 | 2137 |  |  |
| RS-02 | read_single | ✓ | `inquiry.compare_quotes` | 0 | 2 | 2 | 632 | 2482 |  |  |
| RS-03 | read_single | ✓ | `inquiry.inquiry_matrix` | 0 | 2 | 2 | 689 | 2094 |  |  |
| RS-04 | read_single | ✗ | `inquiry.query` | 0 | 2 | 2 | 893 | 2310 | tool_missing |  |
| RS-05 | read_single | ✓ | `inquiry.search` | 0 | 2 | 2 | 897 | 2025 |  |  |
| RS-06 | read_single | ✓ | `inquiry.quote_options` | 0 | 2 | 2 | 1124 | 2921 |  |  |
| RM-01 | read_multi | ✓ | `inquiry.project_budget` → `inquiry.compare_quotes` | 0 | 3 | 3 | 692 | 3800 |  |  |
| RM-02 | read_multi | ✓ | `inquiry.compare_quotes` → `inquiry.compare_quotes` | 0 | 3 | 3 | 935 | 4571 |  |  |
| RM-03 | read_multi | ✓ | `inquiry.inquiry_matrix` → `inquiry.project_budget` | 0 | 3 | 3 | 950 | 3951 |  |  |
| RM-04 | read_multi | ✓ | `inquiry.search` → `inquiry.related` | 0 | 3 | 3 | 959 | 3620 |  |  |
| RM-05 | read_multi | ✓ | `inquiry.project_budget` → `inquiry.compare_quotes` → `inquiry.compare_quotes` | 0 | 4 | 4 | 1300 | 5416 |  |  |
| RM-06 | read_multi | ✓ | `inquiry.data_quality` → `inquiry.project_budget` | 0 | 3 | 3 | 475 | 2832 |  |  |
| WR-01 | write | ✓ | `inquiry.create_inquiry` | 1 | 2 | 2 | 1033 | 2602 |  |  |
| WR-02 | write | ✓ | `inquiry.create_inquiry` | 1 | 2 | 2 | 801 | 2591 |  |  |
| WR-03 | write | ✗ | `inquiry.record_quote` | 1 | 1 | 1 | 979 | 1164 | request_failed | 错误：当前报价是 12.5，与你给出的原值 12.50 不符，请重新确认；quote is 12.5, expected 12.00 |
| WR-04 | write | ✓ | `inquiry.set_item_qty` | 1 | 2 | 2 | 1062 | 1933 |  |  |
| WR-05 | write | ✗ | - | 0 | 1 | 1 | 881 | 977 | tool_missing、write_missing | status is open, expected closed |
| WR-06 | write | ✗ | - | 0 | 1 | 1 | 1934 | 2043 | tool_missing、write_missing | quote is 12.5, expected 12.00；qty is 20, expected 25；题注：Order-sensitive on today's assistant: the conversation scope pins each selected record's revision (business_tools.dart:164-172), so after a write that changes a selected record (set_item_qty) the next tool call fails the scope check. A failure labelled scope_pinned is current product behaviour, not a model error; record_quote first keeps the scope valid. |
| AB-01 | abstain | ✗ | `inquiry.search` → `inquiry.related` → `inquiry.query` → `inquiry.create_inquiry` | 0 | 4 | 4 | 973 | 4343 | extra_write、request_failed | 错误：工具参数、可用性或范围校验未通过；题注：The global scope has no write tools, so this task tests 'do not call read tools for a vague request', not write refusal. |
| AB-02 | abstain | ✓ | - | 0 | 1 | 1 | 1197 | 1292 |  |  |
| AB-03 | abstain | ✓ | - | 0 | 1 | 1 | 1503 | 1731 |  |  |
| AB-04 | abstain | ✓ | - | 0 | 1 | 1 | 2343 | 2514 |  |  |
