import 'dart:async';

import 'package:flutter/material.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'chat_models.dart';

/// One conversation. History stays readable when the peer is offline or the
/// pairing was revoked; only sending is refused.
class ChatThreadPage extends StatefulWidget {
  const ChatThreadPage({
    super.key,
    required this.backend,
    required this.peerFingerprint,
  });
  final ChatBackend backend;
  final String peerFingerprint;

  @override
  State<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends State<ChatThreadPage> {
  final input = TextEditingController();
  String? error;
  bool sending = false;
  Timer? _tick;

  ChatBackend get backend => widget.backend;

  @override
  void initState() {
    super.initState();
    backend.addListener(_changed);
    // The retry offer for an unconfirmed message depends on elapsed time.
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
    _markRead();
  }

  @override
  void dispose() {
    _tick?.cancel();
    backend.removeListener(_changed);
    input.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _markRead();
  }

  void _markRead() {
    if (backend.messages(widget.peerFingerprint).any((m) => m.unread)) {
      backend.markRead(widget.peerFingerprint);
    }
  }

  Future<void> _guard(Future<void> Function() job) async {
    try {
      await job();
      if (mounted) setState(() => error = null);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _send() async {
    final body = input.text.trim();
    if (body.isEmpty || sending) return;
    final thread = backend.thread(widget.peerFingerprint);
    final where = backend.destination(widget.peerFingerprint);
    if (thread == null || where == null) {
      setState(() => error = '对方不在线，没有中继');
      return;
    }
    final ok = await _confirm(
      '发送给 ${thread.peerName}',
      '目的地：$where\n核对指纹：${thread.peerFingerprint}\n文字：$body\n'
          '仅发给已配对设备。“已发出”不等于对方已收到，收到也不会被当作命令执行。',
      '发送这一次',
    );
    if (!ok || !mounted) return;
    setState(() => sending = true);
    await _guard(() async {
      await backend.sendText(widget.peerFingerprint, body);
      input.clear();
    });
    if (mounted) setState(() => sending = false);
  }

  Future<bool> _confirm(String title, String text, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _retry(ChatMessage m) async {
    if (m.sendState == SendState.sent) {
      final ok = await _confirm(
        '重发这条消息？',
        '上次发出后没有收到对方的确认，对方可能已经收到。'
            '重发时对方会按消息编号去重，不会出现两条。',
        '重发',
      );
      if (!ok) return;
    }
    await _guard(() => backend.retry(m.peerFingerprint, m.id));
  }

  Future<void> _deleteMessage(ChatMessage m) async {
    final ok = await _confirm('删除这条消息？', '只删除本机上的记录，对方设备上的不受影响。', '删除');
    if (ok) await _guard(() => backend.delete(m.peerFingerprint, m.id));
  }

  Future<void> _deleteThread() async {
    final ok = await _confirm(
      '删除整个对话？',
      '只删除本机上的全部记录，对方设备上的不受影响。此操作不能撤销。',
      '删除',
    );
    if (!ok) return;
    await _guard(() => backend.deleteThread(widget.peerFingerprint));
    if (mounted && error == null) Navigator.of(context).pop();
  }

  String? _blockReason(ChatThread? thread) {
    if (thread == null) return '对话不存在';
    if (!thread.paired) return '已撤销配对，历史可读，不能再发送。';
    if (!thread.online) return '对方离线。没有中继，也不会排队，对方上线后再发送。';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final thread = backend.thread(widget.peerFingerprint);
    final messages = backend.messages(widget.peerFingerprint);
    final theme = Theme.of(context);
    final tokens = MuyonTokens.of(context);
    final blocked = _blockReason(thread);
    final over = input.text.length > ChatBackend.maxBodyLength;
    return Scaffold(
      appBar: AppBar(
        title: Text(thread?.peerName ?? '对话'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (_) => _deleteThread(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('删除对话（仅本机）')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (thread != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MuyonTokens.space4,
                MuyonTokens.space2,
                MuyonTokens.space4,
                0,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  '${!thread.paired
                      ? '未配对'
                      : thread.online
                      ? '在线'
                      : '离线'}'
                  ' · 指纹 ${thread.peerFingerprint}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(MuyonTokens.space4),
                      child: Text('还没有消息。', style: theme.textTheme.bodyMedium),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(MuyonTokens.space4),
                    itemCount: messages.length,
                    itemBuilder: (context, i) => _Bubble(
                      message: messages[i],
                      retryAfter: backend.sentRetryAfter,
                      onRetry: () => _retry(messages[i]),
                      onDelete: () => _deleteMessage(messages[i]),
                      onAccept: () => _guard(
                        () => backend.accept(
                          widget.peerFingerprint,
                          messages[i].id,
                        ),
                      ),
                      onReject: () => _guard(
                        () => backend.reject(
                          widget.peerFingerprint,
                          messages[i].id,
                        ),
                      ),
                    ),
                  ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MuyonTokens.space4,
              ),
              child: SelectableText(
                error!,
                style: TextStyle(color: tokens.red),
              ),
            ),
          if (blocked != null)
            Padding(
              padding: const EdgeInsets.all(MuyonTokens.space3),
              child: Text(
                blocked,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.amber,
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(MuyonTokens.space3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      enabled: blocked == null,
                      minLines: 1,
                      maxLines: 5,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: '发给 ${thread?.peerName ?? ''}',
                        helperText: '仅发给本人已配对的在线设备；不授予任何操作权限',
                        helperMaxLines: 2,
                        errorText: over
                            ? '超过 ${ChatBackend.maxBodyLength} 字'
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: MuyonTokens.space2),
                  IconButton.filled(
                    tooltip: '发送',
                    onPressed:
                        blocked != null ||
                            sending ||
                            over ||
                            input.text.trim().isEmpty
                        ? null
                        : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.retryAfter,
    required this.onRetry,
    required this.onDelete,
    required this.onAccept,
    required this.onReject,
  });
  final ChatMessage message;
  final Duration retryAfter;
  final VoidCallback onRetry, onDelete, onAccept, onReject;

  (IconData, String, bool) _delivery(SendState state) => switch (state) {
    SendState.queued => (Icons.schedule, '等待发送', false),
    SendState.sent => (Icons.help_outline, '已发出，对方是否收到未知', false),
    SendState.delivered => (Icons.done_all, '对方已收到', false),
    SendState.failed => (
      Icons.error_outline,
      '发送失败${message.error == null ? '' : '：${message.error}'}',
      true,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = MuyonTokens.of(context);
    final mine = message.direction == ChatDirection.outgoing;
    final state = message.sendState;
    final delivery = mine && state != null ? _delivery(state) : null;
    final waited = message.sentAt == null
        ? Duration.zero
        : DateTime.now().toUtc().difference(message.sentAt!.toUtc());
    final sentRetryable = state == SendState.sent && waited >= retryAfter;
    final sentTooNew = state == SendState.sent && !sentRetryable;
    final canRetry = state == SendState.failed || sentRetryable;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        child: Card(
          color: mine ? tokens.accentTint : tokens.surface,
          margin: const EdgeInsets.only(bottom: MuyonTokens.space2),
          child: Padding(
            padding: const EdgeInsets.all(MuyonTokens.space3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(message.body),
                const SizedBox(height: MuyonTokens.space1),
                Wrap(
                  spacing: MuyonTokens.space2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      message.createdAt.toLocal().toString().substring(0, 16),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (message.unread)
                      Text(
                        '未读',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: tokens.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (delivery != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            delivery.$1,
                            size: 16,
                            color: delivery.$3 ? tokens.red : tokens.ink2,
                          ),
                          const SizedBox(width: MuyonTokens.space1),
                          Flexible(
                            child: Text(
                              delivery.$2,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: delivery.$3 ? tokens.red : tokens.ink2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (message.acceptance != Acceptance.none)
                      Text(
                        message.acceptance == Acceptance.accepted
                            ? '已标记接纳（不会导入或执行任何内容）'
                            : '已标记拒绝',
                        style: theme.textTheme.labelMedium,
                      ),
                  ],
                ),
                Wrap(
                  spacing: MuyonTokens.space1,
                  children: [
                    if (canRetry)
                      TextButton(onPressed: onRetry, child: const Text('重发')),
                    if (sentTooNew)
                      Text(
                        '约 ${(retryAfter - waited).inMinutes + 1} 分钟后可重发',
                        style: theme.textTheme.bodySmall,
                      ),
                    if (!mine && message.acceptance == Acceptance.none) ...[
                      TextButton(
                        onPressed: onAccept,
                        child: const Text('标记为已接纳'),
                      ),
                      TextButton(onPressed: onReject, child: const Text('拒绝')),
                    ],
                    TextButton(
                      onPressed: onDelete,
                      child: const Text('删除（仅本机）'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
