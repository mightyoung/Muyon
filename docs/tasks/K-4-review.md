# K-4 审查

任务分支 `task/k-4-task-events` · 交付 `f20702c`、`ef16f4c`、`fe8b729`，修订 `c0f6398`、`576a849` · 核实：Sonnet 5.5 子代理（非作者，高强度），三轮 · 2026-10-07

## 范围
`apps/muyon/lib`：新增 `platform/task_records.dart`、`assistant/agent_resume.dart`；改 `foundation_repository.dart`（同事务写事件、`task_objects`、按工作区反查）、`workspace_repository.dart`（v8 `task-events`，只追加）、`agent_event_sink.dart`、`execution_store.dart`、`agent_context.dart`（`commit`）、`agent_dispatch.dart`、`agent_model_turn.dart`、`agent_compaction_flow.dart`、`personal_agent.dart`。新测试 `task_events_test`、`agent_resume_test`；非守护测试 `foundation_integration_test`、`agent_event_sink_test`、`context_compaction_test` 按新表调整读取。ADR-0005 §8.4 守护测试与 `north_star_chain.dart` 0 行 diff；载荷键名称与含义不变（新增 `stepFolded`）。ADR-0005 §6.5 增 K-4 注记。

## 第一轮（`fe8b729`）
| 项 | 结论 |
|---|---|
| 同事务 | 触发器使三张表任一写失败，`updateTask` / `createTask` 整体回滚；暂存事件不进载荷 |
| 事务外事件 | `tool_proposed`、逐调用 `approval`、`model_*`、`compaction*`：崩溃后最多留下无后果的“已批准无结果”，严重度低 |
| `seq` | 300 次并发追加（含 `updateTask` 交错）连续无重复 |
| 恢复安全 | 已成功回执不重放；结果未知停在 `resume`；确认核实后 0 次执行、0 个新审批；未能构造绕过确认的写入 |
| 密钥 | 164 字符密钥经工具异常，四张表 0 命中 |
| 迁移 | 5,000 任务 / 30 万事件 1.7 s，线性 |

应改：`tasksForObject` 无工作区过滤（会返回其他工作区任务的提问与摘要）。可选：恢复时预算重置、坏 JSON 行阻断迁移、取用回执未核对 `toolId`、追加时整份解析载荷、事务外 `approval` 时间线注记。

## 第二轮（`c0f6398`）
工作区过滤（全局任务需 `includeGlobal: true`）、预算结转、迁移 `json_valid`、`toolId` 核对、SQL 计算旧 `seq`、ADR 注记全部核实；新发现 SQL 对畸形旧 `events`（非数组、非对象元素、非整数 `seq`）抛错，可致迁移失败。

## 第三轮（`576a849`）
两处 SQL 仅处理数组、对象元素与整数 `seq`；`_legacy` 容错非列表。9 种畸形形状经追加与迁移均不抛错，合法 `seq` 续接正确；并发探针仍连续。`flutter analyze` 无问题；宿主全量 `+688 ~3`。

## 结论
**合入。** 合入 K-2b 后重跑 `task_events_test`、`agent_resume_test`、`agent_drafts_test`。
