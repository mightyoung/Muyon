# REG-2a 审查

任务分支 `task/reg-2a-outbound-tool-ledger` · 审查分支 `review/REG-2a` · 交付代码 `224403b`（清理日志后 HEAD 见下）· 依据：[REG-2a.md](REG-2a.md)、[ADR-0004](../adr/0004-module-contract-v2.md) §2.3-6 / §9.1 / §12.1 Q4、[ADR-0002](../adr/0002-graded-assistant-authorization.md) §3.4

## 工程师2号定向复核（2026-10-07，待 leader 确认）

复核对象：`review/REG-2a` @ `4e55e70`（代码主体 `224403b feat: ledger outbound tool channels before sending`；其后仅文档/日志清理）· 复核：工程师2号（静态核对代码与测试意图；本机未装 Flutter，未重跑 `flutter test` / analyze / 变异）· 日期：2026-10-07（上海时间）

对照文档：`docs/tasks/REG-2a.md`、`docs/tasks/REVIEW.md`、`docs/tasks/README.md`、`docs/tasks/HANDOVER-LEADER.md`、`docs/adr/0004-module-contract-v2.md`（Q4）、`docs/adr/0002-graded-assistant-authorization.md` §3.4；执行者提交说明（`224403b`、`4e55e70`）。无既有 `REG-2a-review.md`，本文件新建。

相对 `origin/develop`（merge-base `8283638`）业务 diff：11 个文件，+1051/−115（含新账本与新测）；未改 `outbound_requests` / 模型网关 / UI / `module_api` / `ModuleRegistry`。

**建议结论：任务「只做这些」与四条通道「先写账再发送」从代码与测试结构上看已落实；合入前须处理宿主全量因 schema 钉死导致的 −1，并由有 Flutter 的环境重跑新测与变异。非正式合入批准。**

| 项 | 结论 | 依据 |
|---|---|---|
| 交付 1：表 `outbound_tool_requests` + 主库迁移 **9**；不改 `outbound_requests` | **通过（静态）** | `outbound_tool_ledger.dart:17-25` 列含 id / task_id / tool_id / channel（mcp\|inquiry_web\|inquiry_hub\|transfer）/ destination / payload_digest / bytes_sent / state（pending\|succeeded\|failed\|cancelled）/ error / created_at / finished_at。`workspace_repository.dart:22-23,144-149` `version: 9`、`id: 'outbound-tool-requests'`。`outbound_ledger.dart` / 模型网关无本分支改动。 |
| 交付 2：发送前写 `pending`，写失败不发送并抛错；完成后更新状态 | **通过（静态）** | `begin` 在 `database.write` 内 INSERT pending（`:28-58`）；`runDigest` 先 `await begin` 再 `operation`（`:113-123`）；`finish` 仅更新 `state='pending'` 行并 `redactCredentials(error)`（`:60-76`）。关闭库用例断言 effects=0（`outbound_tool_ledger_test.dart:318-334`）；各通道 blocked 用例用 INSERT 触发器 + 回环断言请求数 0（`:198-210` 与 transfer `:466-485`）。 |
| 交付 3a：MCP（initialize / tools/list / tools/call / 通知） | **通过（静态）** | `_post` 整段包在 `ledger.run`（`mcp_adapter.dart:344-405`）；成功路径断言 methods 含 `initialize`、`notifications/initialized`、`tools/list`、`tools/call`（测试 `:234-240`）。 |
| 交付 3b：询价网页 | **通过（静态）** | `inquiry_web_authority.dart:120-127`；GET 无 body，`payload: const []`，与「bytes_sent == bodies[i].length」一致。 |
| 交付 3c：询价资料中心 | **通过（静态）** | `inquiry_hub_authority.dart:120-137`；`onBodySent` 经 `hub.dart` / `hub_channel.dart` 在真正 `request.add` 时计数；另有 native `HubClient.preview` 用例（测试 `:253-271`）。 |
| 交付 3d：`transfer.*` 外发入账；listen/stop/export/import 说明 | **通过（静态，口径已写明）** | 宿主把主库账本注入 `TransferService`（`public_services.dart:76-79`；`transfer_service.dart:62-67,662`）。传输层 `_audit`（`lan.dart:212-236`）覆盖 UDP discovery（`:250-266`）、probe、`/push` 发送（`:964+`）、listen 身份回复与空拒绝（`:582-586,619-624`）。执行者说明：`listen` 会广播/应答故入账；`export`/`import` 纯本机；`stop` 只关闭。与任务「无外发则写理由」一致。 |
| 交付 4：每通道 blocked / 成功 / 失败测试；destination 无查询串与令牌；error 无令牌 | **通过（静态意图）** | 新文件 `apps/muyon/test/outbound_tool_ledger_test.dart`（约 20 例）。destination 在 `begin` 先剥成 scheme/host/port/path 再 `maskedEndpoint`（`outbound_tool_ledger.dart:37-51`）；成功断言无 query（测试 `:227-232`）。失败路径 `isNot(contains(marker))`（`:247-248` 等）。另有 cancelled / MCP timeout / 关闭库 / UDP 阻断。 |
| 不做：无 `grant_id`；不动 REG-2b 范围；不改既有测试文件 | **通过（静态）** | 表无 grant_id。diff 中测试侧仅新增 `outbound_tool_ledger_test.dart`。AUTH-1a 在 develop 上独立库 version 11，注释已预留 9/10 给 REG-2a/2b。 |
| destination 遮盖（P0-S2） | **通过（更严）** | 先丢弃 query/fragment/userInfo，再调用 `maskedEndpoint`；测试用带 `?token=` 的 URL，落账无查询串。 |
| 验证：analyze / 新测 / 宿主全量 / 变异 | **未在本轮复现** | 采信 `224403b`：analyze 无问题；相关套件 +117；新通道测曾报 +20；变异四通道去掉 begin/finish 后失败。`4e55e70` 称末次还原新测曾 `+18 -1`（原始日志已按用户决定删除），**哪一例失败无法静态还原**。宿主全量执行者报 `+777 ~3 -1`，唯一未解失败见下。 |

### 阻断 / 合入前须裁定

| 级别 | 项 | 说明 | 建议 |
|---|---|---|---|
| **阻断（门禁）** | `task_events_test.dart:99` 钉死 `WorkspaceRepository.schema.version == 8` | 本任务将 schema 升至 9 且任务写明「不改已有测试」，故执行者未改该断言；宿主全量必然 −1。与「验证：宿主全量 flutter test」冲突。 | leader 在审查分支做一行应改：改为 `9` 或 `WorkspaceRepository.schema.version` 自身比对；或开跟进小任务。属 REVIEW「小而确定的修复」口径。 |
| **应改（合入前）** | 未 rebase 最新 `develop` | develop 已合入 FOLIO-BYPASS、AUTH-1a；与本 diff 文件交集静态看为空，但合入前应 `--ff`/`rebase` 再跑全量。 | leader 或执行者合并 develop 后重跑。 |
| **存疑** | 末次新测 `+18 -1` | 日志已删；静态无法确认是否偶发。 | 有 Flutter 3.47.5 的环境重跑 `outbound_tool_ledger_test.dart` 与四通道变异。 |

### 可选（不阻塞）

1. transfer 失败行使用固定 `errorCode: 'transfer_request_failed'`（`outbound_tool_ledger.dart:160`），失败用例的「error 不含 marker」对脱敏的证明力弱于 web/hub（抛错串含 marker 再脱敏）。
2. `supplier_core` 既有测试仍未 `await helloTo`（现改为 `Future<void>`）；无 ledger 时行为大体可接受；宿主路径经 `_tick`/`_audit` 已 await。
3. 询价网页回执 `data.destination` 仍可能是完整 `destination.toString()`（含 query）——**改前既有**，非本任务引入；账本列已安全。
4. `begin` 每次 `CREATE TABLE IF NOT EXISTS`（防御性）；与迁移 9 并存可接受。
5. `finish` 在已发送后失败时可能留下 pending 或二次 failed——与模型 `OutboundLedger` 同类残余，非本任务扩大。

### 给 leader 的确认清单

1. 有 Flutter 的环境检出本分支：`flutter analyze`（apps/muyon，info 也失败）、`outbound_tool_ledger_test.dart`、任务点名的四个原套件、宿主全量；记录摘要行。
2. 逐通道去掉「先写账再发送」做变异，确认对应 blocked/成功测失败后还原。
3. 裁定 `task_events_test.dart:99` 一行修复是否本轮提交。
4. 与 REG-2b（迁移 10）/ AUTH-1a（独立 v11）编号无冲突；合入顺序按 HANDOVER：后合入方负责重编号（若有）。

本段为工程师2号预审记录，**非正式合入批准**。

## leader A 补验与结论（2026-10-08）
REG-2a 是随 REG-2b 一起合入的（`b95d6f9`），合入时只有上面这份静态预审，没有独立的变异验证。leader A 在合入后的 `develop`（`c1dbe2d`）上补验：
- 基线：`outbound_tool_ledger_test` `+20: All tests passed!`。
- 变异：在 `OutboundToolLedger.runDigest` 里让 `begin` 写失败时吞掉错误、继续发送。结果有 9 例失败，覆盖全部四条通道：MCP、询价网页、资料中心各自的 `blocked ledger sends zero requests`、`closed ledger sends nothing`、设备传输的发送、监听、发现。四条通道都经过 `runDigest`（设备传输经 `HostTransferLedger`，LAN 节点默认也装了账本，见 `transfer_service.dart:666`）。
- 预审里「存疑」的 `-1`，就是当时 `task_events_test` 钉死 schema 版本为 8 的那一例，已在 `7c59b57` 解决。

**结论：「记不进账就不发送」成立，正式确认合入。**

