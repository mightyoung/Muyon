import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// One chat row. Delivery, read and acceptance are separate fields.
/// The text never grants tool permission.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.peerFingerprint,
    required this.direction,
    required this.body,
    required this.createdAt,
    required this.sentAt,
    required this.receivedAt,
    required this.sendState,
    required this.acceptance,
    required this.readAt,
    required this.error,
    required this.packageItemId,
  });
  final String id, peerFingerprint, direction, body, acceptance;
  final DateTime createdAt;
  final DateTime? sentAt, receivedAt;
  final String? sendState, readAt, error, packageItemId;

  bool get grantsExecution => false;

  DateTime get orderedAt => receivedAt ?? sentAt ?? createdAt;
}

/// Latest row for one peer, plus whether that peer can be sent to now.
class ChatThread {
  const ChatThread({
    required this.peerFingerprint,
    required this.peerName,
    required this.last,
    required this.unread,
    required this.online,
    required this.paired,
  });
  final String peerFingerprint;
  final String? peerName;
  final ChatMessage last;
  final int unread;
  final bool online, paired;
}

/// Rows in `chat_messages`. Dedupe is the pair (peer fingerprint, message id).
class ChatLog {
  static const marker = 'muyon-chat-v1';
  static const maxBody = 16000;
  static final _uuid = RegExp(r'^[0-9a-fA-F-]{36}$');

  static Map<String, Object?>? decodeFile(String path) {
    try {
      final decoded = jsonDecode(File(path).readAsStringSync());
      if (decoded is! Map || decoded['muyon'] != marker) return null;
      final type = decoded['type'];
      final messageId = decoded['messageId'];
      if (type is! String ||
          messageId is! String ||
          !_uuid.hasMatch(messageId)) {
        return null;
      }
      if (type == 'text') {
        final body = decoded['body'];
        final createdAt = decoded['createdAt'];
        if (body is! String ||
            body.isEmpty ||
            body.length > maxBody ||
            createdAt is! String) {
          return null;
        }
      } else if (type != 'delivered') {
        return null;
      }
      return Map<String, Object?>.from(decoded);
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  static ChatMessage _row(Row row) => ChatMessage(
    id: row['message_id'] as String,
    peerFingerprint: row['peer_fingerprint'] as String,
    direction: row['direction'] as String,
    body: row['body'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
    sentAt: _time(row['sent_at'] as String?),
    receivedAt: _time(row['received_at'] as String?),
    sendState: row['send_state'] as String?,
    acceptance: row['acceptance'] as String,
    readAt: row['read_at'] as String?,
    error: row['error'] as String?,
    packageItemId: row['package_item_id'] as String?,
  );

  static DateTime? _time(String? value) =>
      value == null ? null : DateTime.parse(value);

  static List<ChatMessage> list(Database db, {String? peerFingerprint}) {
    final rows = peerFingerprint == null
        ? db.select('SELECT * FROM chat_messages')
        : db.select('SELECT * FROM chat_messages WHERE peer_fingerprint=?', [
            peerFingerprint,
          ]);
    final messages = [for (final row in rows) _row(row)];
    messages.sort((a, b) {
      final byTime = a.orderedAt.compareTo(b.orderedAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    return messages;
  }

  /// Inserts an inbound row. Returns false when that pair already exists.
  static bool insertInbound(
    Database db, {
    required String peerFingerprint,
    required String messageId,
    required String body,
    required DateTime createdAt,
    required DateTime receivedAt,
    String? packageItemId,
  }) {
    final existing = db.select(
      'SELECT 1 FROM chat_messages WHERE peer_fingerprint=? AND message_id=?',
      [peerFingerprint, messageId],
    );
    if (existing.isNotEmpty) return false;
    db.execute(
      '''
INSERT INTO chat_messages(
  peer_fingerprint, message_id, direction, body, created_at, received_at,
  acceptance, package_item_id
) VALUES(?,?,?,?,?,?,?,?)
''',
      [
        peerFingerprint,
        messageId,
        'in',
        body,
        createdAt.toUtc().toIso8601String(),
        receivedAt.toUtc().toIso8601String(),
        'none',
        packageItemId,
      ],
    );
    return true;
  }

  static void insertOutbound(
    Database db, {
    required String peerFingerprint,
    required String messageId,
    required String body,
    required DateTime createdAt,
  }) {
    db.execute(
      '''
INSERT INTO chat_messages(
  peer_fingerprint, message_id, direction, body, created_at, send_state, acceptance
) VALUES(?,?,?,?,?,?,?)
''',
      [
        peerFingerprint,
        messageId,
        'out',
        body,
        createdAt.toUtc().toIso8601String(),
        'queued',
        'none',
      ],
    );
  }
}
