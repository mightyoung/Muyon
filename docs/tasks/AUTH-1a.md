# AUTH-1a 分级授权：授权库、解析器与外传内容审查接口（不接线）

分支 `task/auth-1a-grants` · 依据：[ADR-0002](../adr/0002-graded-assistant-authorization.md) §1～§4（已采纳）、[ADR-0004](../adr/0004-module-contract-v2.md) §5.4、§12.1 Q11 · 执行：Codex（本机）· 审查：leader（`reviewer-sonnet-high`）· 阶段：第二阶段

本任务只做 AUTH-1 的**库层**：表、解析、撤销、审计和审查接口，都是纯 Dart，可以独立测试。**不接入** `ToolRegistry`、`PersonalAgent`，也不改界面。接线属于 AUTH-1b，等 REG-2b 合入后再派，因为 REG-2b 正在改 `tool_registry.dart`、范围解析和模块注册。

## 只做这些
1. **迁移 11**（REG-2a 用 9，REG-2b 用 10；后合入的一方负责重新编号）：
   - `assistant_grants`：`grant_id, category, tool_id, scope_digest, destination, duration_kind, task_id, conversation_id, expires_at, max_uses, uses, created_at, revoked_at`。`category` 取值 `model | write | outbound`；`duration_kind` 取值 `once | task | conversation | timed | always`。
   - `assistant_grant_audit`：创建、使用、撤销各记一行，至少含 `grant_id`、`action`、`at`、`task_id`、`detail`。
2. `apps/muyon/lib/platform/grants/`（新目录）：
   - `GrantStore`：创建、撤销（立即生效）、列出、记一次使用（`uses + 1`，并写审计）。
   - `GrantResolver.resolve(request)`：输入为 `category`、`toolId`、`scopeDigest`、`destination`、`taskId`、`conversationId`、`now`、`taskTainted`，返回命中的授权或 null。规则：
     - 工具、范围、目的地三项**必须全部相同**，任何一项变化都不命中（ADR-0002 §3.2）。
     - 已撤销、已过期、次数用完都不命中；`task` 只在同一 `taskId` 内命中，`conversation` 只在同一 `conversationId` 内命中。
     - `outbound` 类：`always` 一律不命中，创建时就拒绝（外传最长到本次对话，§5 Q2）；`destination` 为空也不命中。
     - **`taskTainted == true` 时，`write` 和 `outbound` 都不命中**（Q11 外部内容污染）。
     - 只读类不走授权，传入 `read` 时直接报错。
   - 创建入口只接受「来自宿主界面」的调用：用一个只有宿主 UI 层能构造的令牌类型做参数（例如 `HostUiGrantToken`）。在注释里写明，模型、资料、规则、SOUL 的任何路径都拿不到这个令牌（§3.1）；再加一个测试，断言 `assistant/` 目录下没有代码构造它（用文件扫描实现）。
3. `OutboundContentReviewer`（§4）：
   - 输入为工具、端点、发送内容、范围、来源对象引用；输出 `allow`、`confirm(reason)`、`block(reason)`。
   - `NoopReviewer` 一律 `allow`，并标记「未审查」。
   - 组合器 `ReviewerChain`：多个审查器取最严的结果；任一审查器抛异常或超时，按 `confirm` 处理，超时时长作为参数传入。审查器只能收紧，不能放宽。
4. 测试 `apps/muyon/test/assistant_grants_test.dart`，必须覆盖：过期、撤销、范围变化、目的地变化、次数用尽、`task` 与 `conversation` 的边界、外传不能设为 `always`、外部内容污染、只读报错、审计三种动作，以及审查器的 `allow`、`confirm`、`block`、异常、超时、多个审查器取最严。

## 不做
- 不改 `tool_registry.dart`、`personal_agent*.dart`、`model_gateway.dart`、`outbound_ledger.dart`、`mcp_adapter.dart`、模块注册与范围解析（属于 REG-2a、REG-2b、AUTH-1b）；不改界面。
- 不改已有测试；原始验证日志不进仓库，摘要写在提交说明里。

## 验证
- 变异：
  - (a) 去掉范围比对；
  - (b) 去掉「外部内容污染」判断；
  - (c) 允许外传设为 `always`；
  - (d) 审查器异常时改成 `allow`。

  对应测试都必须失败。
- `flutter analyze`（`apps/muyon`，info 也算失败）；新测试；宿主全量 `flutter test`。

## 回报
分支与提交哈希、改动文件、迁移号、解析规则与 ADR 条款的对照表、验证摘要行、变异结果。
