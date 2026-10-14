# RECOVERY-TRACE-03 · Muse (com.facebook.aura) 11.0.0.8.164

> **样本与工具**
> - 仅做静态分析。base APK（可单独安装），sha256 `c7e788b5…994fcefa`；证书 SHA-256 `a16bbe02…89667e99`（Meta）。
> - jadx 1.5.3 反编译失败 138 个。审批 reducer 的提前 return 被 jadx 丢掉了，因此对 `HatchAgentPermissionsRepository` 单独用 baksmali 2.5.2 定向反编译。
> - 标签仅用以下四种：包内直接证据 / 官方说明 / 推断 / 未知。
> - 证据文件：`evidence/RC-MU-*.txt`。审批决策链见 AUTH-TRACE-02 MU-01。

## 1. 事件模型

**包内直接证据**（RC-MU-01）：
- WebSocket（Jarvis/Hatch gateway）事件带三个序号字段：`seq`、`message_seq`、`chat_event_seq`。
- 每个会话的游标是 `SessionCursors{afterStreamSeq, afterChatEventSeq}`：
  - 存在内存 ConcurrentHashMap 里，**不落盘**；
  - 更新函数 `bumpChatEventSeqIfNewer` 只取最大值，只增不减。
- `getReplayCursor` 只在两个游标都存在时返回非空。
- `sendSubscribe` 的行为：
  - 发送 `chat.subscribe`，参数为 `after_stream_seq`、`after_chat_event_seq`；有游标时附加 `replay_limit=500`；
  - 传输层拒绝时记录 "send rejected by transport"，并清除 pending 订阅。
- `HatchGatewayEventsHandler` 的相关行为：
  - 记录 "Deferring chat.subscribe for unconfirmed thread session"；
  - 还处理 agentStatusSequence 准入下限，以及 `reset`。

**推断**：去重靠"seq ≤ 游标即忽略"，因为游标只取最大值。逐条事件的处理函数没有完整追踪。

## 2. 快照：待审批

**包内直接证据**（RC-MU-02，smali 已核对）。`replaceServerPendingApprovals(list, recent, snapshotMs, source, capturedWsVersion)` 依次判断：
- 来源是 `HTTP_RECOVERY`，且捕获的 ws 版本为 null 或不等于当前的 `websocketSnapshotVersion` → **丢弃**。原因是 HTTP 请求在途时 WS 已经推来了更新的快照。
- 来源是 `HTTP_RECOVERY`，`snapshotMs ≤ 0`，且 `lastApplied > 0` → 丢弃。
- `snapshotMs > 0`、`lastApplied > 0`，且 `snapshotMs ≤ lastApplied` → 丢弃（防止旧快照覆盖）。
- 来源是 `WEBSOCKET` → 版本号加 1。
- 之后执行：
  - `lastApplied = max`；
  - `resolvedServerApprovalIds.retainAll(current)`；
  - **过滤掉本地已经决策过的 id**，避免已批准或已拒绝的项重新出现。
- `SnapshotSource` 有三个值：WEBSOCKET、HTTP_RECOVERY、DECISION_RESPONSE。
- `recoverPendingApprovals` 用 SingleFlight 合并并发恢复请求。

**结论**：先连 WS 还是先用 HTTP 都可以。HTTP 快照通过"版本令牌 + 时间戳"与 WS 对齐，**快照与流用同一套版本判定**（包内直接证据）。

## 3. 重连与游标失效

**包内直接证据**：
- 重连后，用内存游标调用 `chat.subscribe(after_*, replay_limit=500)`。
- 进程重启后游标丢失，于是发送不带 after 的订阅，即全量或最新状态（`getReplayCursor` 返回 null）。
- VmFetchSource 有以下取值：gateway_connect、preconnect_prefetch、gateway_recovery、gateway_subscribe_status、internal_status、startup_job、vm_reconnect。

**未知**：
- 服务端游标失效、或超过 500 条时如何回应、客户端怎么处理。
- 全量重拉是否会重复计数。

**推断**：审批不会重复弹出，因为有已解决集合加时间戳过滤。

## 4. Stop

**包内直接证据**（RC-MU-03），`cancelGeneration` 的流程：
1. 先执行 `NodeCommandService.cancelAll`，取消本机正在执行的设备命令。
2. 如果 streamingState 为 Done、agent 空闲且不是强制取消 → 记为 `PRE_STREAM`，不发送 chat.cancel。
3. 否则发送 `chat.cancel`，按返回结果处理：
   - 返回 null，即超时或传输失败 → `TRANSPORT_FAILURE`，**本地照常清理**；
   - `cancelled=true` → `USER_STOP`；
   - `cancelled=false` 且状态已经是 Done → `CANCEL_RACE`，即服务端已经先结束了；
   - 其他情况 → 等待 ChatAborted，5000 ms 内没收到就记为 `FALLBACK_TIMEOUT` 并强制清理。

`CleanupReason` 的完整取值还包括 CHAT_ABORTED、STATIC_OVERRIDE_INVALID、STREAM_IDLE_TIMEOUT。

→ **三种状态部分区分**（包内直接证据）：
- "请求已发出"对应 chat.cancel；
- "服务端确认"对应 cancelled=true 或 ChatAborted；
- "无法确认"对应 TRANSPORT_FAILURE / FALLBACK_TIMEOUT。

但界面上是否把"外部效果未知"单独显示出来 → **未知**。

**浏览器任务停止**（包内直接证据，RC-MU-04，`stopWithRetry`）：
- 返回 OK、200 或 409 都算成功。
- 返回 503 且错误码为 `browser_stop_outcome_unconfirmed`、`browser_stop_owner_settling` 或 `browser_stop_cleanup_pending` 时，最多重试 3 次，每次间隔 1000 ms，仍失败则返回 false。
- → 服务端会**显式表达"停止结果未确认"**。另有 `BrowserControlLease(taskId, controlOwner, controlExpiresAtMs, takeoverId)` 控制租约；ComputerEvent 带 seq。

**取消后的迟到事件**：
- **推断**：清理后会重置 streaming 状态，迟到的 delta 由 statusAccumulator 的 reset 和序号准入下限拦截。
- 没有逐行核实 → 部分**未知**。

## 5. 杀进程、登出、切换会话

| 事件 | 结果 | 标签 |
|---|---|---|
| 登出 `clearUserData` | 本地待审批全部以 **DENY** 完成后清空；服务端 pending、lastAppliedSnapshotMs、websocketSnapshotVersion 归零；resolved ids 清空；`recoverySingleFlight.clearAndCancelAll()` | 包内直接证据 RC-MU-02 |
| 杀进程（设备命令执行中） | 见 §6：重启后清除，**不重跑** | 包内直接证据 RC-MU-05 |
| 杀进程（会话游标） | 内存游标丢失，订阅时不再带 after | 包内直接证据 |
| 切换会话或模式 | 未追踪 | 未知 |

**执行边界**：
- 手机端会**真正执行**服务端下发的设备命令（定位、通讯录同步等），由 NodeCommandService 负责。
- 浏览器和电脑操作任务在云端 VM 上执行，手机只负责控制租约、停止和显示。
- 云端执行器的内部状态 → **未知**。

## 6. 后台与存活

**包内直接证据**（RC-MU-05）：
- `NodeCommandService` 是 FGS，类型 specialUse，子类型说明为 "Execute server-initiated device commands such as location queries and contact sync"。其 `onStartCommand` 的处理顺序：
  1. 用 `attemptedRequestIds.add(requestId)` 记录请求；如果该 id 已存在，记录 "Dropping redelivered command" 并返回 2；
  2. 否则在任务启动**之前**，先把命令写入 `PendingCommandStore`（SharedPreferences `aura_pending_commands`，内容为 command、params_json、createdAt）；
  3. 返回 **3（START_REDELIVER_INTENT）**。
- `onCreate` 时调用 `clearStaleCommands`：把上一次会话遗留的命令标记为已尝试并删除，日志为 "Clearing N stale command(s) from previous session"。→ **崩溃后不重新执行**。
- `cancelAllCommands`：取消所有 job 并清空存储。
- `NodeCommandFallbackWorker` 也会写入同一个存储。
- 其他前台服务：
  - `HatchForegroundService`（specialUse，"Keep the app running … long-running assistant tasks"）；
  - `NotificationReplyService`（"Reconnect WebSocket and send user reply from notification"）；
  - 音频服务（0x2）、通话服务（0x80）。

**推断**：同一进程内，系统重投递的 Intent 会被 `attemptedRequestIds` 拦截。新进程 `onCreate` 会 `clearStaleCommands`，表现为"崩溃后不重跑已落盘命令"。

**未知（崩溃窗）**：`PendingCommandStore.save` 使用 SharedPreferences `edit().apply()`（异步落盘，见 RC-MU-05）。若进程在命令 job 已启动、但 `apply()` 尚未持久化完成时被杀，重投递的 Intent 可能找不到已持久化的 requestId，从而再次执行带副作用的设备命令。在未演示"claim 先于 execute 且同步落盘"之前，**不能**把整条链路标成 at-most-once；该崩溃窗应视为未知。

**未知**：服务端是否会收到"命令被放弃"的回执。

## 7. 时间线（6 个场景）

1. **正常恢复**：带内存游标调用 chat.subscribe（after_*，limit 500）；同时 HTTP 恢复待审批，结果交给版本令牌门控。（包内直接证据）
2. **断线**：游标保留在内存中；重连后补发；HTTP 快照如果比 WS 旧则被丢弃。（包内直接证据）
3. **取消竞态**：cancelled=false 且已 Done 时记为 CANCEL_RACE；ChatAborted 5 s 内未到时记为 FALLBACK_TIMEOUT。（包内直接证据）
4. **迟到结果**：snapshotMs ≤ lastApplied 时丢弃；本地已决策的审批 id 被过滤。（包内直接证据）迟到的聊天 delta → 部分未知。
5. **进程重启**：已落盘的待执行命令会被 clearStaleCommands 清除且不重跑；游标丢失后全量订阅。（包内直接证据；未落盘崩溃窗见上节未知）
6. **游标失效**：服务端行为未知；客户端在游标缺失时退化为无游标订阅。（包内直接证据 + 未知）

## 覆盖缺口

- 没有追踪 chat delta 的逐条处理器。
- 没有追踪 replay 超过 500 条时的行为。
- 没有追踪切换会话时的取消逻辑。
- 只分析了 base APK。
- 没有做动态验证。
