import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supplier_core/lan.dart';
import 'package:uuid/uuid.dart';

import '../services/models/credential_redaction.dart';
import 'grants/host_tool_authorization.dart';
import 'mcp_adapter.dart' show maskedEndpoint, redactEndpoint;

/// Body bytes handed to the transport, excluding protocol headers and TLS.
/// Standalone managed connections also install the table in the same write
/// transaction as pending; a failed transaction always prevents sending.
class OutboundToolLedger implements LanOutboundLedger {
  OutboundToolLedger(this.database);
  final ManagedDatabase database;

  static void createTable(Database db) => db.execute('''
CREATE TABLE IF NOT EXISTS outbound_tool_requests(
 id TEXT PRIMARY KEY, task_id TEXT, tool_id TEXT NOT NULL,
 channel TEXT NOT NULL CHECK(channel IN ('mcp','inquiry_web','inquiry_hub','transfer')),
 destination TEXT NOT NULL, payload_digest TEXT NOT NULL,
 bytes_sent INTEGER NOT NULL DEFAULT 0 CHECK(bytes_sent >= 0),
 state TEXT NOT NULL CHECK(state IN ('pending','succeeded','failed','cancelled')),
 error TEXT, created_at TEXT NOT NULL, finished_at TEXT
)''');

  static String _now() => DateTime.now().toUtc().toIso8601String();
  Future<String> begin({
    required String toolId,
    required String channel,
    required Uri destination,
    required String payloadDigest,
    String? taskId,
    HostAuthorizationLink? authorization,
  }) => database.write((db) {
    authorization?.reserve(database, toolId, destination, payloadDigest);
    if (authorization != null &&
        taskId != null &&
        taskId != authorization.taskId) {
      throw StateError('Host task identity mismatch');
    }
    createTable(db);
    final id = const Uuid().v4();
    final safe = Uri(
      scheme: destination.scheme,
      host: destination.host,
      port: destination.hasPort ? destination.port : null,
      path: destination.path,
    );
    db.execute(
      'INSERT INTO outbound_tool_requests(id,task_id,tool_id,channel,destination,'
      'payload_digest,state,created_at'
      "${authorization == null ? '' : ',grant_id,authorization_source,review_decision_id'}) VALUES(?,?,?,?,?,?,?,?"
      "${authorization == null ? '' : ',?,?,?'})",
      [
        id,
        authorization?.taskId ?? taskId,
        toolId,
        channel,
        maskedEndpoint(safe),
        payloadDigest,
        'pending',
        _now(),
        if (authorization != null) ...[
          authorization.grantId,
          authorization.authorizationSource,
          authorization.reviewDecisionId,
        ],
      ],
    );
    return id;
  });

  Future<void> finish(
    String id,
    String state,
    int bytesSent, {
    String? error,
  }) => database.write(
    (db) => db.execute(
      "UPDATE outbound_tool_requests SET state=?,bytes_sent=?,error=?,finished_at=? WHERE id=? AND state='pending'",
      [
        state,
        bytesSent,
        error == null ? null : redactCredentials(error),
        _now(),
        id,
      ],
    ),
  );

  Future<T> run<T>({
    required String toolId,
    required String channel,
    required Uri destination,
    required List<int> payload,
    required Future<T> Function(void Function(int)) operation,
    String? taskId,
    String? secret,
    String? errorCode,
    bool Function(T)? failedResult,
    bool Function()? isCancelled,
    HostAuthorizationLink? authorization,
  }) => runDigest(
    toolId: toolId,
    channel: channel,
    destination: destination,
    payloadDigest: sha256.convert(payload).toString(),
    operation: operation,
    taskId: taskId,
    secret: secret,
    errorCode: errorCode,
    failedResult: failedResult,
    isCancelled: isCancelled,
    authorization: authorization,
  );

  Future<T> runDigest<T>({
    required String toolId,
    required String channel,
    required Uri destination,
    required String payloadDigest,
    required Future<T> Function(void Function(int)) operation,
    String? taskId,
    String? secret,
    String? errorCode,
    bool Function(T)? failedResult,
    bool Function()? isCancelled,
    HostAuthorizationLink? authorization,
  }) async {
    authorization?.check(database, toolId, destination, payloadDigest);
    final id = await begin(
      toolId: toolId,
      channel: channel,
      destination: destination,
      payloadDigest: payloadDigest,
      taskId: taskId,
      authorization: authorization,
    );
    var sent = 0;
    try {
      authorization?.check(database, toolId, destination, payloadDigest);
      final result = await operation((count) => sent += count);
      final failed = failedResult?.call(result) ?? false;
      await finish(
        id,
        failed ? 'failed' : 'succeeded',
        sent,
        error: failed ? 'remote_protocol_failure' : null,
      );
      return result;
    } catch (error) {
      final safe =
          errorCode ??
          redactCredentials(
            redactEndpoint('$error', destination),
            secret: secret,
          );
      await finish(
        id,
        error is ToolCancelled || (isCancelled?.call() ?? false)
            ? 'cancelled'
            : 'failed',
        sent,
        error: safe,
      );
      rethrow;
    }
  }

  @override
  Future<T> send<T>({
    required String toolId,
    required Uri destination,
    required String payloadDigest,
    required Future<T> Function(void Function(int)) operation,
  }) => runDigest(
    toolId: toolId,
    channel: 'transfer',
    errorCode: 'transfer_request_failed',
    destination: destination,
    payloadDigest: payloadDigest,
    operation: operation,
  );
}
