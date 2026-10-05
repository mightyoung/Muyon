import 'package:flutter/foundation.dart';

/// UI-side view of the one-to-one chat backend (D-R9, docs/implementation/
/// chat-interface-draft.md). The transfer service's real types are adapted to
/// these once its final API is published; the screens depend only on this.
enum ChatDirection { incoming, outgoing }

/// Outgoing delivery. `sent` means bytes were written and the outcome is
/// unknown until the peer confirms durable storage.
enum SendState { queued, sent, delivered, failed }

/// Optional, independent of read: only used when a message is turned into
/// business data. Never imports or executes anything.
enum Acceptance { none, accepted, rejected }

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.peerFingerprint,
    required this.direction,
    required this.body,
    required this.createdAt,
    this.sendState,
    this.acceptance = Acceptance.none,
    this.readAt,
    this.error,
  });
  final String id, peerFingerprint, body;
  final ChatDirection direction;
  final DateTime createdAt;
  final SendState? sendState;
  final Acceptance acceptance;
  final DateTime? readAt;
  final String? error;
  bool get unread => direction == ChatDirection.incoming && readAt == null;
}

@immutable
class ChatThread {
  const ChatThread({
    required this.peerFingerprint,
    required this.peerName,
    required this.online,
    required this.paired,
    this.last,
    this.unread = 0,
  });
  final String peerFingerprint, peerName;
  final bool online, paired;
  final ChatMessage? last;
  final int unread;
}

abstract interface class ChatBackend implements Listenable {
  static const maxBodyLength = 16000;

  List<ChatThread> threads();
  List<ChatMessage> messages(String peerFingerprint);
  ChatThread? thread(String peerFingerprint);

  /// Fails immediately for an offline or unpaired peer (no relay, no queue).
  Future<void> sendText(String peerFingerprint, String body);

  /// Local only; no read receipt reaches the peer.
  Future<void> markRead(String peerFingerprint);
  Future<void> accept(String messageId);
  Future<void> reject(String messageId);

  /// Explicit. Allowed for `failed`, and for `sent` after the backend's
  /// timeout; the receiver de-duplicates.
  Future<void> retry(String messageId);

  /// Local records only; the peer is unaffected.
  Future<void> delete(String messageId);
  Future<void> deleteThread(String peerFingerprint);
}
