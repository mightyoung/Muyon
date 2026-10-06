import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supplier_core/lan.dart';

import '../../services/transfer/chat_log.dart' as log;
import '../../services/transfer/transfer_service.dart';
import 'chat_models.dart';

/// Adapts [TransferService]'s chat API (docs/implementation/chat-backend.md)
/// to the screens' [ChatBackend]. Own it from a State and call [dispose].
class TransferChatBackend extends ChangeNotifier implements ChatBackend {
  TransferChatBackend(this.service) {
    _changes = service.chatChanges.listen((_) => notifyListeners());
    // Who is online changes without any chat row changing.
    _poll = Timer.periodic(
      const Duration(seconds: 2),
      (_) => notifyListeners(),
    );
  }

  final TransferService service;
  late final StreamSubscription<void> _changes;
  late final Timer _poll;

  @override
  void dispose() {
    _poll.cancel();
    _changes.cancel();
    super.dispose();
  }

  @override
  Duration get sentRetryAfter => service.chatSentRetryAfter;

  @override
  bool get listening => service.listening;

  static String shortName(String fingerprint) =>
      '设备 ${fingerprint.length > 8 ? fingerprint.substring(0, 8) : fingerprint}';

  @override
  List<ChatThread> threads() {
    final fromLog = [
      for (final t in service.threads())
        ChatThread(
          peerFingerprint: t.peerFingerprint,
          peerName: t.peerName ?? shortName(t.peerFingerprint),
          online: t.online,
          paired: t.paired,
          last: _message(t.last),
          unread: t.unread,
        ),
    ];
    final known = {for (final t in fromLog) t.peerFingerprint};
    return [
      ...fromLog,
      // Paired devices that can be messaged now but have no history yet.
      for (final peer in service.pairedOnline())
        if (!known.contains(peer.fingerprint))
          ChatThread(
            peerFingerprint: peer.fingerprint,
            peerName: peer.name,
            online: true,
            paired: true,
          ),
    ];
  }

  @override
  ChatThread? thread(String peerFingerprint) {
    for (final t in threads()) {
      if (t.peerFingerprint == peerFingerprint) return t;
    }
    return null;
  }

  @override
  List<ChatMessage> messages(String peerFingerprint) => [
    for (final m in service.messages(peerFingerprint)) _message(m),
  ];

  LanPeer? _peer(String fingerprint) {
    for (final peer in service.peers) {
      if (peer.fingerprint == fingerprint) return peer;
    }
    return null;
  }

  @override
  String? destination(String peerFingerprint) {
    final peer = _peer(peerFingerprint);
    return peer == null ? null : '${peer.address}:${peer.port}';
  }

  @override
  Future<void> sendText(String peerFingerprint, String body) async {
    final peer = _peer(peerFingerprint);
    if (peer == null) throw StateError('对方不在线，没有中继');
    await service.sendText(peer, body);
  }

  @override
  Future<void> markRead(String peerFingerprint) =>
      service.markChatRead(peerFingerprint);

  // Chat rows are keyed by (peer, message id); a shared id never crosses peers.
  @override
  Future<void> accept(String peerFingerprint, String messageId) =>
      service.acceptChat(peerFingerprint, messageId);
  @override
  Future<void> reject(String peerFingerprint, String messageId) =>
      service.rejectChat(peerFingerprint, messageId);
  @override
  Future<void> retry(String peerFingerprint, String messageId) async {
    await service.retryText(peerFingerprint, messageId);
  }

  @override
  Future<void> delete(String peerFingerprint, String messageId) =>
      service.deleteChat(peerFingerprint, messageId);
  @override
  Future<void> deleteThread(String peerFingerprint) =>
      service.deleteChatThread(peerFingerprint);

  static ChatMessage _message(log.ChatMessage m) => ChatMessage(
    id: m.id,
    peerFingerprint: m.peerFingerprint,
    direction: m.direction == 'in'
        ? ChatDirection.incoming
        : ChatDirection.outgoing,
    body: m.body,
    createdAt: m.orderedAt,
    sentAt: m.sentAt,
    sendState: m.direction == 'in'
        ? null
        : switch (m.sendState) {
            'sent' => SendState.sent,
            'delivered' => SendState.delivered,
            'failed' => SendState.failed,
            _ => SendState.queued,
          },
    acceptance: switch (m.acceptance) {
      'accepted' => Acceptance.accepted,
      'rejected' => Acceptance.rejected,
      _ => Acceptance.none,
    },
    readAt: m.readAt == null ? null : DateTime.tryParse(m.readAt!),
    error: m.error,
  );
}
