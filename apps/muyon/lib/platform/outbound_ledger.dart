import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../services/models/model_gateway.dart';

/// Where data actually went: one row per model/network request, written
/// before any byte is sent. Holds digests and sizes, not payload content.
class OutboundLedger {
  OutboundLedger(this.database);
  final ManagedDatabase database;

  static void createTable(Database db) => db.execute('''
CREATE TABLE outbound_requests(
  id TEXT PRIMARY KEY,
  caller TEXT NOT NULL,
  profile_id TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  endpoint_identity TEXT NOT NULL,
  location TEXT NOT NULL,
  cloud_proxy INTEGER NOT NULL,
  model_id TEXT NOT NULL,
  payload_sha256 TEXT NOT NULL,
  payload_bytes INTEGER NOT NULL,
  item_count INTEGER NOT NULL,
  started_at TEXT NOT NULL,
  finished_at TEXT,
  status TEXT NOT NULL CHECK(status IN ('sending','succeeded','failed','cancelled','timeout','interrupted')),
  http_status INTEGER,
  error TEXT
)''');

  static String _now() => DateTime.now().toUtc().toIso8601String();

  /// Throws if the record cannot be written; callers must then not send.
  Future<String> begin({
    required String caller,
    required ModelProfile profile,
    required String payload,
    required int itemCount,
  }) {
    final id = const Uuid().v4();
    final bytes = utf8.encode(payload);
    return database.write((db) {
      db.execute(
        'INSERT INTO outbound_requests(id,caller,profile_id,endpoint,'
        'endpoint_identity,location,cloud_proxy,model_id,payload_sha256,'
        "payload_bytes,item_count,started_at,status) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,'sending')",
        [
          id,
          caller,
          profile.id,
          profile.endpoint.toString(),
          profile.endpointIdentity,
          profile.location.name,
          profile.cloudProxy ? 1 : 0,
          profile.modelId,
          sha256.convert(bytes).toString(),
          bytes.length,
          itemCount,
          _now(),
        ],
      );
      return id;
    });
  }

  Future<void> finish(
    String id,
    String status, {
    int? httpStatus,
    String? error,
  }) => database.write(
    (db) => db.execute(
      "UPDATE outbound_requests SET status=?,http_status=?,error=?,finished_at=? WHERE id=? AND status='sending'",
      [status, httpStatus, error, _now(), id],
    ),
  );

  /// Requests still `sending` from a previous run: the process stopped while
  /// waiting, so whether the endpoint processed them is unknown.
  Future<int> recoverInterrupted() => database.write((db) {
    db.execute(
      "UPDATE outbound_requests SET status='interrupted',finished_at=?,"
      "error='Process stopped while waiting; outcome unknown' WHERE status='sending'",
      [_now()],
    );
    return db.updatedRows;
  });

  /// Newest first.
  List<Map<String, Object?>> recent({int limit = 100}) => [
    for (final row in database.raw.select(
      'SELECT * FROM outbound_requests ORDER BY started_at DESC, rowid DESC LIMIT ?',
      [limit],
    ))
      Map<String, Object?>.from(row),
  ];
}
