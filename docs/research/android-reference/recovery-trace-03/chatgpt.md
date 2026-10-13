# RECOVERY-TRACE-03 · ChatGPT Android 1.2026.272

> **样本与工具**
> - 只做静态分析。base APK sha256 `47d8350a…f8831e40a`，证书 SHA-256 `b24f4bfb…db40473c`。
> - 以 apktool 2.7.0 smali 为主。jadx 1.5.3 跑到约 66% 时中止，因此部分类只有 smali。序列化字段名从 `$$serializer` / `o3o` smali 中读出。
>
> **标签与引用**
> - 标签只用四种：包内直接证据 / 官方说明 / 推断 / 未知。
> - 证据文件：`evidence/RC-GPT-*.txt`。
> - AUTH-TRACE-02 的 GPT-01…05 是参数摘要、审批身份相关的结论，本文引用，不再重复。

## 1. 事件模型

**包内直接证据**（RC-GPT-01/02）：
- `/f/conversation` 的 SSE 事件类型（weo/veo）包括：`resume_conversation_token`、`stream_handoff`、`message_stream_complete`、`main_stream_complete`、`conversation_async_status`、`input_message` 等。
- `resume_conversation_token` 对应 w3o，携带 conversationId 和 token；处理器（`stream/a.smali`）把它存进 lfo。
- `stream_handoff` 对应 pfo，携带 conversationId、turnExchangeId 和 options。当 option 是 `resume_sse_endpoint` 或 `subscribe_ws_topic` 时：
  - 处理器把 topic 写入 `lfo.c`；
  - 然后抛出 `StreamHandoffException("SSE stream requested handoff to resume endpoint")`，它是 IOException 的子类。
  - → 主动切流是靠异常路径实现的。

**位置游标**（包内直接证据，RC-GPT-03）：
- 每解析出一个 SSE 事件，`qqx` 就执行 `b220.f += 1`。
- 恢复请求 `q3o` / `o3o` 的字段是 `conversationId`、`model`、`offset`，其中 `offset = lfo.d.f`。
- → **offset 是客户端本地数到的事件条数，不是服务端下发的 event id。**
- **推断**：服务端必须按"同一 token 下的事件序号"来解释这个 offset。一旦客户端少数或多数一条，就会出现重复或缺口；服务端如何校验 → **未知**。

**WebSocket topic 通道**（包内直接证据，RC-GPT-04，smali `g0w0` WebSocketManager）：
- 订阅消息为 `subscribe{topicId, offset}`。
- 服务端回复 `{topicId, recovered, lastOffset, catchups}`。

**去重、乱序、缺口处理**：
- **未知**：offset 只被存储，没有看到比较或去重的代码。
- **推断**：交给服务端按 offset 补发。

## 2. 快照与本地库

**包内直接证据**：
- 本地有 SQLDelight 表：`DBConversation`、`DBMessage`、`DBMessageChunk(messageId, chunkIndex)`。
- 另有 `DBWebSocketTopicOffset(topicId, offset)`：
  - 写入：`INSERT OR REPLACE`，即 o1w0.e。
  - 删除：`DELETE FROM`，即 o1w0.d，一次全删。
  - 加载失败时全部删除，并记录日志 "Failed to delete WebSocket topic offsets after load failure."

**写入顺序**（包内直接证据，g0w0 ~6844→6877）：每条 WS 消息先调用 `h()` 持久化 offset，再 `emit`。
- **推断**：这是本地 at-most-once 语义。持久化之后、处理完成之前如果进程被杀，重订阅时会从新 offset 开始，这条消息就漏掉了。

**快照与游标是否同一版本**：
- **未知**：消息表与 offset 表分开写，没有看到它们在同一事务里提交。
- **推断**：两者不保证一致；UI 重进时以服务端重新拉取的会话为准。

## 3. 恢复与游标失效

**SSE 恢复**（包内直接证据，RC-GPT-03）：
- 端点：`/f/conversation/resume`，同一组里还有 `/f/conversation`、`/steer`、`/prepare`。
- 请求内容：`q3o(conversationId, model, offset)` 加上 `t3o(token)`。
- 恢复原因枚举：`INITIAL_STREAM_ERROR`、`RELOAD`、`RESUME_STREAM_ERROR`。
- 遥测字段：offset、num_successful_resumes、num_failed_resumes。另有 `is_resume_token_expired` 字段（nex0）。

**token 过期或无效**：
- **推断**：失败后计入 failed_resumes，然后转为重新加载会话（RELOAD）。
- 具体的分支没有完整追到 → **未知**。

**WS 未恢复**（包内直接证据，g0w0 ~3138–3202）：
- `recovered=true`：逐条发射 catchups，并记录 "Caught up N messages"。
- `recovered=false`：把该 topic 推到 refresh 流，并记录 "Refreshing topic after unrecovered subscription"。
- → 结果是**整体刷新，而不是从缺口处续传**。

**全量刷新的副作用**：
- 是否会重复累加计数器 → **未知**。
- 本地不执行工具，因此不存在重跑工具的问题（推断）。

## 4. Stop

**普通聊天**：
- **未知**：包内没有找到普通聊天的 stop 端点字符串。
- **推断**：Stop 可能只是关闭本地流，服务端是否取消不可见。

**Codex 远程**（包内直接证据，RC-GPT-06）：
- JSON-RPC 方法包括 `turn/interrupt`、`thread/stop`、`turn/steer`、`thread/resume`、`thread/queue/*`、`thread/items/list`。

**官方说明**（Codex app-server README，raw.githubusercontent.com/openai/codex/main/codex-rs/app-server/README.md，2026-10-13）：
- "Cancellation cannot roll back completed effects."
- revision 是 equality token，不是时钟，不能跨线程或跨主机比较。
- "Loading snapshots never acknowledges activity."
- item 锚点失效时返回 -32602。
- 列表出错 "not evidence that history is exhausted"。

**三种状态是否区分**：
- **推断**：协议层面有区分。interrupt 是请求，之后的 turn 完成通知才代表确认。
- 但"外部效果未知"只能通过上面那条"不能回滚"的官方说明来表达，客户端里没有看到专门的状态 → **未知**。

**retract 类事件**：没有看到 → **未知**。

## 5. 杀进程、登出、切换、权限

- 待审批的身份与参数摘要校验见 AUTH-TRACE-02 GPT-01/02。
- 杀进程：只会丢失本地流，WS offset 已经持久化（包内直接证据）。
- 登出后 offset 表是否清空：只看到全删语句，调用方没有追踪 → **未知**。
- 草稿 → **未知**。
- 执行边界：手机端执行设备动作的范围见 AUTH-TRACE-02 GPT-04/05（DIL、日历）；Codex 在远端主机或云端执行，手机只显示（推断）。

## 6. 后台与存活

**包内直接证据**（RC-GPT-05）：
- `ConversationStreamingService`：
  - 普通 Service，没有 FGS 类型，不导出。
  - `onStartCommand` 会挂一个 20 分钟（0x124f80 ms）的保险计时器，到点 `stopSelf`，日志为 "failsafe timeout → stopSelf()"。
  - 返回 START_NOT_STICKY。
- `WorkReasoningNotificationForegroundService`：
  - FGS 类型为 dataSync（0x1）。
  - action 有 START、STOP、UPDATE_PET；通知渠道为 `conversation_streaming_ongoing`；实现了 onTimeout。

**推断**：两者都是为了**显示远端推理进度、维持流**，不在本地执行任务。

## 7. 时间线（6 个场景）

1. **正常恢复**：
   - SSE 下发 resume token，客户端存入 lfo。
   - 断开后调用 /resume，带上 token 和 offset，offset 即本地事件计数。（包内直接证据）
2. **断线**：
   - IOException 会触发 RESUME_STREAM_ERROR 路径。（推断）
   - WS 通道按持久化的 offset 重新订阅。（包内直接证据）
3. **取消竞态**：
   - 普通聊天 → 未知。
   - Codex：interrupt 不能回滚已完成的效果。（官方说明）
4. **迟到结果**：
   - 本地没有 seq 比较，迟到事件是否被丢弃 → 未知。
   - catchups 会原样发射。（包内直接证据）
5. **进程重启**：
   - 服务返回 NOT_STICKY，20 分钟 failsafe。
   - offset 已持久化，重启后从该位置继续；先写 offset 再发射，所以存在漏消息的窗口。
   - （包内直接证据 + 推断）
6. **游标失效**：
   - WS `recovered=false` 时整体刷新 topic。（包内直接证据）
   - SSE token 过期 → is_resume_token_expired 遥测，随后 RELOAD。（推断）

## 覆盖缺口

- jadx 只完成约 66%，依赖 smali。
- 普通聊天的 stop 路径、offset 比较逻辑、登出清理调用方都没有看到。
- 没有做动态验证。
