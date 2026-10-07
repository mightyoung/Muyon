# REG-2a 外传工具入账：`outbound_tool_requests` 与四条通道

分支 `task/reg-2a-outbound-tool-ledger` · 依据：[ADR-0004](../adr/0004-module-contract-v2.md) §2.3-6、§9.1、§10.1 REG-2、§12.1 Q4；[ADR-0002](../adr/0002-graded-assistant-authorization.md) §3.4（出站必入账）· 执行：Codex（本机）· 审查：leader（`reviewer-sonnet-high`）· 阶段：第二阶段 · 与 REG-2b 并行（文件不交叉，见「冲突约定」）

## 背景
`outbound_requests` 绑定模型 profile，只有模型网关写它。MCP 调用、询价网页取证、询价资料中心、`transfer.*` 这四条外传通道目前只留 `tool_invocation_receipts` 回执，不入出站账本。ADR-0002 §3.4 的底线是「记不进账就不发送」，本任务补上这个缺口。

## 只做这些
1. 新表 `outbound_tool_requests`，主库迁移 **9**（当前最新是 8，`platform/task_records.dart`）。列至少包括：`id`、`task_id`（可空）、`tool_id`、`channel`（`mcp` / `inquiry_web` / `inquiry_hub` / `transfer`）、`destination`（只到 host + path，不含查询串和凭据，用 P0-S2 的遮盖函数）、`payload_digest`、`bytes_sent`、`state`（`pending` / `succeeded` / `failed` / `cancelled`）、`error`（经 `redactCredentials` 脱敏）、`created_at`、`finished_at`。不改 `outbound_requests`。
2. 账本写入放在 `apps/muyon/lib/platform/outbound_ledger.dart`（或同目录的新文件），接口形态与模型网关一致：**发送前先写 `pending`，写失败就不发送并抛错**；完成后更新状态。
3. 四条通道全部接入：
   - MCP：`platform/mcp_adapter.dart` 中 `HttpClient` 发请求处（约 318 行），包括 `initialize`、`tools/list`、`tools/call` 和通知；
   - 询价网页：`app/inquiry_web_authority.dart`；
   - 询价资料中心：`app/inquiry_hub_authority.dart`；
   - `transfer.*`：`services/knowledge/public_tools.dart` 中的 `transfer.export/import/listen/stop/send`，凡是向外发数据的路径都要入账；只在本机起监听、不发数据的 `listen`/`stop` 如果确实没有外发，在说明里写清楚理由。
4. 测试（新增，`apps/muyon/test/outbound_tool_ledger_test.dart` 等）：
   - 每条通道一条「账本写不进去（例如用只读或已关闭的库）则什么都不发送」，用回环服务器断言请求数为 0；
   - 每条通道一条成功路径：账本行从 `pending` 变 `succeeded`，`destination` 不含查询串与令牌，`bytes_sent` 与实际一致；
   - 失败路径：`state = failed`，`error` 不含令牌。

## 不做
- 不加 `grant_id`（AUTH-1 再加）；不改 `outbound_requests` 和模型网关；不改界面；不动 `module_api`、`ModuleRegistry`、模块激活（属于 REG-2b）。
- 不改已有测试；`outbound_ledger_test`、`mcp_token_redaction_test`、`inquiry_web_authority_test`、`inquiry_hub_authority_test` 必须原样通过。

## 冲突约定
REG-2b 的迁移号是 **10**。后合入 `develop` 的一方，如果迁移号冲突，按 develop 重新编号，并在回报里说明。

## 验证
- 变异：逐条通道去掉「先写账再发送」，对应测试必须失败；恢复后通过。结果写进提交说明。
- `flutter analyze`（`apps/muyon`，info 也算失败）；新测试；宿主全量 `flutter test`。

## 回报
分支与提交哈希、改动文件、迁移号、每条通道的入账位置（文件:行）、验证摘要行、变异结果、没做或不确定的地方。
