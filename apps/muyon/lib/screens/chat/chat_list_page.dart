import 'package:flutter/material.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'chat_models.dart';
import 'chat_thread_page.dart';

/// 设备聊天: one row per paired device.
class ChatListPage extends StatelessWidget {
  const ChatListPage({super.key, required this.backend});
  final ChatBackend backend;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: backend,
    builder: (context, _) {
      final threads = backend.threads();
      final theme = Theme.of(context);
      return ListView(
        padding: const EdgeInsets.all(MuyonTokens.space4),
        children: [
          Text('设备聊天', style: theme.textTheme.titleLarge),
          const SizedBox(height: MuyonTokens.space2),
          Text(
            '只在本人已配对、同时在线的设备之间发送文字，没有中继。'
            '聊天内容不会授予任何操作权限，也不会自动进入助手上下文。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: MuyonTokens.space3),
          if (threads.isEmpty)
            Text(
              '还没有对话。先在“设备”里配对另一台设备，两台都在线时才能发送。',
              style: theme.textTheme.bodyMedium,
            ),
          for (final thread in threads)
            Card(
              child: ListTile(
                title: Text(thread.peerName),
                subtitle: Text(
                  '${_status(thread)}'
                  '${thread.last == null ? '' : '\n${_preview(thread.last!)}'}',
                ),
                isThreeLine: thread.last != null,
                trailing: thread.unread > 0
                    ? Semantics(
                        label: '${thread.unread} 条未读',
                        child: Badge(label: Text('${thread.unread}')),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ChatThreadPage(
                      backend: backend,
                      peerFingerprint: thread.peerFingerprint,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  static String _status(ChatThread t) => !t.paired
      ? '未配对（历史可读，不能发送）'
      : t.online
      ? '在线'
      : '离线（没有中继，对方上线后才能发送）';

  static String _preview(ChatMessage m) {
    final body = m.body.replaceAll('\n', ' ');
    final text = body.length > 60 ? '${body.substring(0, 60)}…' : body;
    return m.direction == ChatDirection.outgoing ? '我：$text' : text;
  }
}
