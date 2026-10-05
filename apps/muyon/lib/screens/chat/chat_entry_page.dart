import 'package:flutter/material.dart';
import 'package:muyon_ui/muyon_ui.dart';

import '../../app/bootstrap.dart';
import 'chat_list_page.dart';
import 'transfer_chat_backend.dart';

/// Owns the backend adapter for the chat screens and explains when device
/// communication is switched off.
class ChatEntryPage extends StatefulWidget {
  const ChatEntryPage({super.key, required this.host});
  final MuyonHost host;
  @override
  State<ChatEntryPage> createState() => _ChatEntryPageState();
}

class _ChatEntryPageState extends State<ChatEntryPage> {
  late final backend = TransferChatBackend(widget.host.services.transfer);

  @override
  void dispose() {
    backend.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: backend,
    builder: (context, _) => Column(
      children: [
        if (!backend.listening)
          Material(
            color: MuyonTokens.of(context).amberBg,
            child: Padding(
              padding: const EdgeInsets.all(MuyonTokens.space3),
              child: Text(
                '设备通信未开启：历史记录可读，要发送或接收请先在“设备”页开启并配对。',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: MuyonTokens.of(context).amber),
              ),
            ),
          ),
        Expanded(child: ChatListPage(backend: backend)),
      ],
    ),
  );
}
