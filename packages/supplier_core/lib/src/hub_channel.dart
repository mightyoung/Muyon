import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:sqlite3/sqlite3.dart';

import 'ai_runtime.dart';
import 'hub.dart';
import 'store.dart';

Object? _freeze(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return Map<String, Object?>.unmodifiable({
      for (final key in keys) key: _freeze(value[key]),
    });
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  return value;
}

/// Canonical JSON preserves every business field and array order. Only object
/// key order is insignificant. Server envelope fields are projected explicitly.
String hubCanonical(Object? value) => jsonEncode(_freeze(value));
Future<String> hubDigest(Object? value) async =>
    (await Sha256().hash(utf8.encode(hubCanonical(value)))).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

class HubRequest {
  HubRequest(this.method, this.destination, Object? body)
    : body = _freeze(body),
      encodedBody = body == null ? null : hubCanonical(body);
  final String method;
  final Uri destination;
  final Object? body;
  final String? encodedBody;

  /// Host audit observes body bytes at the native transport boundary.
  void Function(int)? onBodySent;
  bool get publishes =>
      method == 'POST' && destination.path.endsWith('/v1/publications');
}

class HubApprovalPreview {
  const HubApprovalPreview(
    this.request,
    this.invocationId,
    this.parameterDigest,
    this.payloadDigest,
  );
  final HubRequest request;
  final String invocationId, parameterDigest, payloadDigest;
}

typedef HubReview = Future<bool> Function(HubApprovalPreview, AiCancellation);

abstract interface class HubAuthority {
  Future<T> run<T>({
    required HubRequest request,
    required HubReview? review,
    required AiCancellation cancellation,
    required void Function() validateSession,
    required Future<T> Function(void Function()) operation,
  });
}

typedef HubJournalWrite = Future<T> Function<T>(T Function(Database) action);

/// The host owns this connection and supplies its serialized write queue.
/// Payload digests, never credentials or business/contact bodies, are persisted.
class HubPublicationJournal {
  HubPublicationJournal(this.db, {required this.write});
  final Database db;
  final HubJournalWrite write;
  static void initializeSchema(Database db) => db.execute('''
CREATE TABLE hub_attempts (
 endpoint TEXT NOT NULL, publication_id TEXT NOT NULL,
 attempt_id TEXT NOT NULL UNIQUE, origin TEXT NOT NULL,
 revision INTEGER NOT NULL, payload_digest TEXT NOT NULL,
 state TEXT NOT NULL, PRIMARY KEY(endpoint, publication_id));
''');

  Map<String, Object?>? read(String endpoint, String id) {
    final rows = db.select(
      'SELECT * FROM hub_attempts WHERE endpoint=? AND publication_id=?',
      [endpoint, id],
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
  }

  Map<String, Object?>? unresolved(String id) {
    final rows = db.select(
      "SELECT * FROM hub_attempts WHERE publication_id=? AND state!='applied' LIMIT 1",
      [id],
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
  }

  Future<String> reserve(
    String endpoint,
    String origin,
    Map<String, Object?> draft,
    String digest,
  ) => write((db) {
    final id = draft['publication_id']! as String;
    final prior = read(endpoint, id);
    if (unresolved(id) != null) {
      throw HubException('上次发布结果尚未确认；请核验中心状态。停止本地操作不代表远端撤回。');
    }
    if (prior != null &&
        (draft['revision']! as int) <= (prior['revision']! as int)) {
      throw HubException('此版本已发布，请重新核对资料后再发布');
    }
    final attempt = newUuid();
    db.execute('INSERT OR REPLACE INTO hub_attempts VALUES(?,?,?,?,?,?,?)', [
      endpoint,
      id,
      attempt,
      origin,
      draft['revision'],
      digest,
      'pending',
    ]);
    return attempt;
  });

  Future<void> applied(String attempt) => write((db) {
    db.execute("UPDATE hub_attempts SET state='applied' WHERE attempt_id=?", [
      attempt,
    ]);
  });
  Future<void> noSend(String attempt) => write((db) {
    db.execute(
      "DELETE FROM hub_attempts WHERE attempt_id=? AND state='pending'",
      [attempt],
    );
  });
  Future<void> conflict(String attempt) => write((db) {
    db.execute(
      "UPDATE hub_attempts SET state='conflict' WHERE attempt_id=? AND state!='applied'",
      [attempt],
    );
  });
}
