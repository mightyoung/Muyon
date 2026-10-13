# RECOVERY-TRACE-03 · Muyon 最小恢复契约（草案，供设计评审）

> 本文**不是**产品代码，也不改动设计书。
> 竞品的调用链只用来作对照参考，不能拿来证明我们的设计正确。
> 下文条目中括号里写的是对应的竞品证据。

## 0. 分层

恢复工作拆成三个互相独立的层面，彼此不能互相替代：

- **显示恢复**：客户端投影，可以随时丢弃并重建。
- **模型请求恢复**：服务端的 turn 或生成任务。
- **工具执行恢复**：带副作用的事实。

几条基本原则：

- **Rust core 是执行事实的唯一来源。** 两个客户端（Android 与桌面/Web）都只消费投影。
- 旧快照只能说明"截至某个版本时看到了什么"，**不能**说明工作还在运行。是否在运行，只看 Rust 当前给出的 `run_state`。

## 1. 标识与顺序

| 字段 | 生成方 | 语义 |
|---|---|---|
| `session_id / turn_id / tool_call_id / block_id` | Rust | 稳定 ID，客户端不得自己生成执行类 ID |
| `event_seq` | Rust，**按 session 单调** | 用于去重和检测缺口；**不是跨设备、跨 session 的全局顺序**（参照 Claude 的 `sequence_num`、Muse 的 `chat_event_seq`；Codex 官方说明 revision 不可跨主机比较） |
| `generation` | Rust，turn 每次重开或重试时 +1 | 迟到事件如果 generation 小于当前值，一律丢弃（参照 Claude e5l 的代际计数） |
| `snapshot_version` | 等于该快照覆盖到的 `event_seq` | 快照与游标**必须是同一个版本号**（参照 Muse 的 ws 版本令牌门控；反例是 Claude 快照，它不带游标） |

## 2. 客户端规则

- **R1 去重**：`seq ≤ applied_seq` 的事件直接丢弃，`seq == applied_seq + 1` 的事件应用。`seq > applied_seq + 1` 说明有**缺口**，此时不要硬拼接，应进入"缺口修复"。
- **R2 缺口修复**：调用 `GET events?after_seq=applied_seq`。
  - 如果服务端返回 `cursor_expired`，就拉取快照（快照自带 `snapshot_version`）来**整体替换**投影，然后从 `snapshot_version` 继续订阅。
  - 如果修复失败，界面上**显式显示"历史有缺口"**，不要静默地当作连续（参照 Claude 的 `twu(true, false)` "unfetchable transcript gap"）。
- **R3 快照单调**：版本号更旧的快照不能覆盖更新的投影（参照 Muse 的 `snapshotMs ≤ lastApplied` 丢弃，以及 Claude 的 complete_blocks 只增不减）。持久化顺序是先写数据、最后写头指针（参照 Claude eka.x → eka.w）。
- **R4 恢复顺序**：
  1. 先渲染本地快照，并标注为"缓存"；
  2. 再订阅 `after=snapshot_version`；
  3. 运行中、等待审批之类的状态，只有拿到 Rust 返回的新鲜事实后才显示为活动态。
- **R5 撤回**：`block_retract` 只删除**显示片段**，从不删除执行事实（参照 Claude 的 retract 只作用于 reducer 内存）。要删除执行事实，必须走单独的 `tool_call.state` 变更。

## 3. 执行与副作用

- **E1 先认领再执行**：执行器先持久化 `claim(tool_call_id, generation)`，然后才执行。重启后，凡是"已认领但没有结果"的记录，一律标为 `outcome_unknown`，**不自动重跑**（参照 Muse NodeCommand 的 `clearStaleCommands`、Claude 的 executed_client_tools）。
- **E2 幂等键**：所有对外调用都带 `idempotency_key = tool_call_id`。下游不支持幂等的，就把它标为 `non_idempotent`，这类调用在恢复后只能由人工确认重试。
- **E3 断线不重发**：重连只重新订阅事件，绝不重新提交 turn。"重新发送用户消息"需要用 `client_msg_id` 去重（参照 Claude l9o 的 `serverMayHaveReceivedMessage`）。

## 4. Stop 的三种状态

`cancel_requested` → `executor_stopped`（执行器确认已停）或 `stop_unconfirmed`（超时或传输失败）。此外还有一个独立的字段 `external_effect: none | done | unknown`。

- Stop 之后才到达的结果，**照样记录为事实**，因为副作用已经发生了，但界面上要标为"停止后到达"。显示层可以收起，事实层不能丢。
- Stop 请求传输失败时，本地照常清理显示，但 `run_state` 保持 `stop_unconfirmed`，直到 Rust 确认（参照 Muse 的 TRANSPORT_FAILURE / FALLBACK_TIMEOUT，以及浏览器停止返回的 503 unconfirmed）。

## 5. 生命周期事件

| 事件 | 待审批 | 工具认领 | 草稿 |
|---|---|---|---|
| 断网 | 保留，带 TTL（服务端设定截止时间；参照 Claude 的 240 s） | 不变 | 只存本地 |
| 杀进程 | 重启后从 Rust 重新拉取，不信任本地缓存 | 按 E1 处理 | 本地持久化 |
| 登出 | 本地视为**拒绝**并清空，同时通知 Rust 撤销该设备的审批能力（参照 Muse 的 clearUserData） | 清空本地；服务端事实保留 | 按账户清除 |
| 切换会话 | 不取消，只取消订阅 | 不变 | 每个会话各自保存 |
| 模式或权限变更 | 已签发的审批按新策略重新校验，旧审批**不能**当作授权使用（参照 Codex 官方说明："Notifications remain snapshots") | — | — |

## 6. 不能保证的事项（请明确写进文档）

- **没有 exactly-once。** 对外副作用最多做到"至多一次加上结果未知"，或者"至少一次加上幂等键"。
- 本地 `seq` 和 `event_seq` 不构成跨设备、跨 session 的全局顺序。
- 取消不能回滚已经完成的副作用（参照 Codex 官方说明）。
- 本地快照不能证明工作仍在运行，也不能当作授权使用。
- 服务端游标被截断之后，历史可能永久存在缺口，只能如实显示出来。

## 7. 故障注入验收用例

| # | 注入 | 期望 |
|---|---|---|
| F1 | 流在 block 中途断开 | 重连后 `after_seq` 补齐，没有重复文本，计数器不重复累加 |
| F2 | 服务端重放重复事件，或调换相邻事件的顺序 | R1 丢弃重复事件；遇到乱序进入缺口修复，不错位 |
| F3 | `cursor_expired` | 用快照整体替换后继续，界面不出现"新输入被旧快照覆盖" |
| F4 | 缺口无法拉取 | 显示缺口提示，`run_state` 不显示成"完成" |
| F5 | 工具执行中杀进程 | 重启后状态为 `outcome_unknown`，不自动重跑；非幂等工具需要人工确认 |
| F6 | 客户端 claim 写入后、执行前崩溃 | 不执行，标记为 unknown |
| F7 | Stop 与 turn 完成同时发生（竞态） | 最终状态确定为 `executor_stopped` 或 `completed` 之一，且 `external_effect` 被正确标注 |
| F8 | Stop 请求丢包 | 状态为 `stop_unconfirmed`，之后由 Rust 的事实收敛 |
| F9 | Stop 之后迟到的 tool_result | 记入事实，并标为"停止后到达"；generation 较旧的显示片段被丢弃 |
| F10 | 停止后迟到的 retract | 只影响显示，事实表不变 |
| F11 | 登出时有待审批 | 本地全部拒绝；重新登录后不复活 |
| F12 | 两台设备同时在线 | 不把 seq 当作跨设备的顺序来用；以 Rust 的事实为准，两端投影最终一致 |
| F13 | 发送消息时网络超时，随后重试 | 依靠 `client_msg_id` 去重，不产生两条 human 消息 |
| F14 | HTTP 快照返回得比 WS 慢 | 旧版本快照被丢弃 |
