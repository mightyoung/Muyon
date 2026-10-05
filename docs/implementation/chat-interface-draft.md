# 一对一文字聊天：后端接口草案（B → A → D）

目的：让 B 能做聊天界面。现状事实（`feat/d-transfer@54f8b99`）：`TransferService` 只保存收到的文件包和五种状态（`transfer_items`）；包里的 `message` 在核验导入时被丢弃，发出的文字也没有任何记录，所以界面没有历史可读、没有送达状态可显示。

## 原则
- 文字走已有的配对 TLS 通道，不新增通道；只发给已配对且在线的设备（沿用 `send` 的检查）。
- 收到的文字先“待核验”，人工接纳后才进入对话；接纳不等于执行，文字永远不授予工具权限（沿用 `grantsExecution == false`）。
- 状态互相独立，不合并：发出、对方已收到、失败，与接纳、已读分开记。

## 数据（主库新表，由 A/D 定迁移）
`chat_messages`
| 列 | 说明 |
|---|---|
| `message_id` | 全局唯一，发送方生成，接收方按它去重 |
| `peer_fingerprint` | 对方设备指纹，对话按它分组 |
| `direction` | `out` / `in` |
| `body` | 文字，≤ 16000 字符（与 `exportFiles` 的 message 上限一致） |
| `created_at` | 发送方时间，仅展示；排序用本机 `received_at` / `sent_at` |
| `send_state`（仅 out） | `queued` → `sent`（字节已发出）→ `delivered`（对方确认已持久保存）；或 `failed` + `error` |
| `acceptance`（仅 in） | `pending` / `accepted` / `rejected` |
| `read_at` | 本机已读时间，可空 |

## API（`TransferService` 上，签名为建议）
```dart
Future<ChatMessage> sendText(LanPeer peer, String body); // 校验长度与配对，返回 queued 记录
List<ChatThread> threads();                              // 每个对方一条：最后一条、未读数、待核验数
List<ChatMessage> messages(String peerFingerprint);      // 仅含 out 与 accepted 的 in
List<ChatMessage> pendingInbound({String? peerFingerprint}); // acceptance == pending
Future<void> accept(String messageId);                   // 幂等；不触发任何导入
Future<void> reject(String messageId);                   // 保留记录，不进入对话
Future<void> markRead(String peerFingerprint);
Future<void> retry(String messageId);                    // 仅 failed；见下
Stream<void> get chatChanged;                            // 或沿用 ChangeNotifier
```
`ChatMessage`：`id, peerFingerprint, direction, body, createdAt, sendState?, acceptance?, readAt?, error?`。`ChatThread`：`peerFingerprint, peerName?, last, unread, pending, online, paired`。

## 语义要点（请 D 确认）
1. `delivered` 只在对方回执“已持久保存”后置位；`sent` 之后超时或连接中断，状态保持 `sent`（结果未知），**不得自动重发或当作失败**。`retry` 前界面会提示“对方可能已收到，重发可能重复”，接收方靠 `message_id` 去重，所以重发是安全的。
2. 撤销配对后：历史保留可读，`sendText` 拒绝，界面显示“未配对”。
3. 对方离线：`sendText` 直接失败并说明“没有中继”，不排队（与现有 `send` 一致）；若 D 想做离线排队，需单独决定，界面再配合。
4. 删除：本机删除只删本机记录，不影响对方；界面会明说。需要 `delete(messageId)` 与 `deleteThread(peer)`。
5. 与现有包传输的关系：`message` 字段继续随文件包发送，但收到时也要写入 `chat_messages`（`acceptance` 与包的接纳联动或独立，由 D 定，请在回复里写明）。
6. 通知：收到待核验文字时沿用 `onPendingReceived` 的通知路径。

## B 的界面（接口确定后）
会话列表 → 单个对话（气泡、每条的状态文字加图标，不只靠颜色）、待核验区（接纳/拒绝）、发送确认（目的地与指纹，沿用设备页的确认对话框）、空状态、离线/未配对/失败状态；320/390/430/1280 宽度与 200% 字号测试。

## 请 A 转交 D 的最小清单
- 迁移 `chat_messages`；`sendText`、`threads`、`messages`、`pendingInbound`、`accept`、`reject`、`markRead`、`retry`、`delete*`；变化通知。
- 回执协议：接收方持久保存后回 `delivered`，按 `message_id` 去重。
- 测试：环回发送 → 待核验 → 接纳 → 出现在对话；重复投递只留一条；撤销配对后拒绝发送；`sent` 超时不自动重发。
