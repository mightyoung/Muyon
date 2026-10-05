# 一对一文字聊天后端

给 B 接界面。绑定规格是 `docs/superpowers/plans/2026-10-04-w1-agent-prompts.md` 里的 D-R9。存储在传输库 `KnowledgeService.schema` 版本 4 的 `chat_messages`，不在宿主主库。

文字走已有的配对 TLS 通道。`ChatMessage.grantsExecution` 恒为 false。聊天记录不会进入工具注册表，也不会写入记忆或经验。

## 方法

都在 `TransferService` 上。已有的 `markRead(itemId)` 和 `acceptItem(itemId)` 仍只作用于文件包，所以聊天用下面这些名字。

| 方法 | 行为 |
|---|---|
| `sendText(LanPeer peer, String body)` | 空文字或超过 16000 字抛 `ArgumentError`。未配对或已撤销抛 `StateError('未配对或已撤销')`。对方不在当前在线列表里抛 `StateError('对方不在线，没有中继')`，并且不写行。成功时先落 `queued`，字节写出后改为 `sent`，返回这条记录 |
| `threads()` | 每个对方一条：`peerFingerprint`、`peerName`（当前能看到才有）、`last`、`unread`（收到且 `readAt == null`）、`online`、`paired` |
| `messages(peerFingerprint)` | 这个对方的全部本机记录，按本机 `receivedAt` / `sentAt` / `createdAt` 排序。收到的文字立即在内，不看 `acceptance` |
| `markChatRead(peerFingerprint)` | 只写本机 `read_at`。不向对方发送已读 |
| `acceptChat(peerFingerprint, messageId)` / `rejectChat(peerFingerprint, messageId)` | 只改这一对收到的文字的 `acceptance`（`none` / `accepted` / `rejected`）。不导入、不执行。同一状态再调用一次没有变化。这一对不存在时抛 `StateError('消息不存在')` |
| `retryText(peerFingerprint, messageId)` | 只重发这一对发出的文字，沿用原来的 `messageId`。`failed` 和 `queued` 可以立即重发。`sent` 要早于 `chatSentRetryAfter`（默认 2 分钟），否则 `StateError('发出结果未知，尚未到可重发时间')`。已是 `delivered` 则 `StateError('对方已确认保存，不能重发')`。没有定时器，不会自动重发，也不会把 `sent` 改成 `failed` |
| `deleteChat(peerFingerprint, messageId)` / `deleteChatThread(peerFingerprint)` | `deleteChat` 只删这一对的本机行。`deleteChatThread` 删这个对方的全部本机行 |
| `chatChanges` | `Stream<void>`。行发生变化时发一次 |

`chatSentRetryAfter` 可以在测试里改短。生产不要关 `acknowledgeChatDelivery`。

## 状态

发出：`queued` → `sent`（本机 `push` 已返回）→ `delivered`（对方在已认证连接上确认本机那一行已经写入）。`push` 抛错才是 `failed`，并带 `error`。`sent` 之后连接断开保持 `sent`。

收到：立刻可读，`readAt` 为空就是未读。`acceptance` 默认 `none`，只表示用户后来要不要把它当成业务数据。

去重键是 `(peer_fingerprint, message_id)`，不是单独的 `message_id`。接纳、拒绝、重发、删除也按这一对定位：两个对方用了同一个 `messageId` 时，各自的操作只碰到自己那一行。重复投递保留第一行，仍会再回一次 `delivered`，所以重发是安全的。

成功路径上的 `sent` 不会把已经写上的 `delivered` 盖回去。

## 文件包里的 message

对方推过来的 `muyon-transfer-v1` 包如果带非空 `message`，会另写一条收到的聊天记录。`messageId` 用包的 `packageId`，`packageItemId` 指向 `transfer_items.item_id`。包清单没有发送方时钟，所以 `createdAt` 用本机收到的时间。写这行不修改包的 `imported` 或 `acceptance`。

## 错误

| 情况 | 错误 |
|---|---|
| 空文字 | `ArgumentError('文字不能为空')` |
| 超过 16000 字 | `ArgumentError('文字超过 16000 字')` |
| 还没开始监听 | `StateError('Device communication is disabled')` |
| 未配对或已撤销 | `StateError('未配对或已撤销')`，已有记录仍可读 |
| 对方不在线 | `StateError('对方不在线，没有中继')` |
| 这一对不存在 | `StateError('消息不存在')` |
| `sent` 还太新 | `StateError('发出结果未知，尚未到可重发时间')` |
| 已经 `delivered` | `StateError('对方已确认保存，不能重发')` |

界面上把 `sent` 显示为「已发出，对方是否收到未知」。只有这时提供重发，并说明对方可能已经收到、重发可能重复。
