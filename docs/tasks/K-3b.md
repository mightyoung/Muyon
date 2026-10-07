# K-3b 拆分 `personal_agent.dart`（纯重构）

分支 `task/k-3b-agent-split` · 来源：[K-3 审查](K-3-review.md) S-5 · 执行：Sonnet 5.5 子代理（leader 派发）· 审查 leader · 阶段：第二阶段 · 性质：**纯重构，行为零变化**

## 背景
`apps/muyon/lib/assistant/personal_agent.dart` 在 K-3 后约 2,400 行，单个类约 2,300 行。K-4（事件表）、K-2b（流式草稿）、AUTH-1、S-1 都要继续改它，须先按职责拆开。

## 交付
按审查建议拆成协作类（用共享的 `AgentContext` 持有 repository、gateway、取消令牌、`_closing`、`_operations` 等；**不用 `part` 文件**）：

| 新文件（`lib/assistant/`） | 职责 |
|---|---|
| `agent_dispatch.dart` | `_dispatch`、`_stage`、`_openCard`、`_runReads`、`_executeCard`、`_complete`、`_record`、`toggleSelection` |
| `agent_compaction_flow.dart` | `_compactIfNeeded`、`_settleCompaction`、`_askSummary`、`_runCompaction`、`_summaryFailed`、`compactNow`、`declineCompaction` |
| `agent_model_turn.dart` | `_runModel`、`_runNative`、`_collect`、`_drain`、`_streamCompat`、`_bill`、`_outputCap`、协议解析与纠正 |
| `agent_task_factory.dart` | `start` / `startTool` 的任务构造、提示词、候选工具规格 |

`PersonalAgent` 保留全部公共 API（构造参数、`maxRounds` getter、`start`、`startTool`、`confirm`、`toggleSelection`、`compactNow`、`declineCompaction`、`cancel`、`pause`、`resume`、`close` 等）和状态表，作为门面。

## 约束
- **行为零变化**：不改任何测试（全部测试文件 0 行 diff），不改载荷键、文案、摘要、预览字节、事件顺序。
- 公共符号与 import 路径不变（`package:muyon/assistant/personal_agent.dart` 仍导出原有类型）。
- 拆分后单文件建议不超过约 700 行；不顺手修 bug，发现问题写进回报。

## 验证
- `flutter analyze` 无问题；宿主全量通过，数量与拆分前一致（`+657 ~3`）；E-1 夹具 22/22。
- `git diff develop -- apps/muyon/test apps/muyon/integration_test` 为 0 行。
- 拆分前后各跑一次 `flutter test --reporter expanded` 并比较通过的测试名集合，必须完全相同。

## 回报
提交、各文件行数、公共 API 对照表、测试名集合比较结果、发现但未修的问题。
