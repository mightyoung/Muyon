import 'dart:convert';

import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../../app/host_ui_grant_authority.dart' show HostUiGrantToken;
import 'grant.dart';

/// Pure library storage. Migration 11 is deliberately not appended to the v8
/// host schema: migrations 9/10 belong to REG-2a/2b and must arrive first.
/// Integration must install this migration through the existing main DB owner.
final class GrantStore {
  GrantStore(this.database);
  final ManagedDatabase database;
  final _revoking = <String>{};

  static final migration = ModuleMigration(
    version: 11,
    id: 'assistant-grants',
    definitionDigest: 'foundation-v11',
    migrate: createTables,
  );

  static void createTables(Database db) => db.execute('''
CREATE TABLE assistant_grants(
 grant_id TEXT PRIMARY KEY,
 category TEXT NOT NULL CHECK(category IN ('model','write','outbound')),
 tool_id TEXT NOT NULL CHECK(length(tool_id)>0),
 scope_digest TEXT NOT NULL CHECK(length(scope_digest)>0),
 destination TEXT,
 duration_kind TEXT NOT NULL CHECK(duration_kind IN ('once','task','conversation','timed','always')),
 task_id TEXT, conversation_id TEXT, expires_at TEXT,
 max_uses INTEGER CHECK(max_uses IS NULL OR max_uses>0),
 uses INTEGER NOT NULL DEFAULT 0 CHECK(uses>=0),
 created_at TEXT NOT NULL, revoked_at TEXT,
 CHECK(duration_kind!='once' OR (max_uses IS NOT NULL AND max_uses=1)),
 CHECK(duration_kind!='task' OR (task_id IS NOT NULL AND length(task_id)>0)),
 CHECK(duration_kind!='conversation' OR (conversation_id IS NOT NULL AND length(conversation_id)>0)),
 CHECK(duration_kind!='timed' OR expires_at IS NOT NULL),
 CHECK(category!='outbound' OR duration_kind!='always'),
 CHECK(category!='outbound' OR (destination IS NOT NULL AND length(trim(destination))>0)),
 CHECK(category!='outbound' OR duration_kind='once' OR (conversation_id IS NOT NULL AND length(conversation_id)>0))
);
CREATE TABLE assistant_grant_audit(
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 grant_id TEXT NOT NULL REFERENCES assistant_grants(grant_id),
 action TEXT NOT NULL CHECK(action IN ('created','used','revoked')),
 at TEXT NOT NULL, task_id TEXT, detail TEXT NOT NULL
);
CREATE INDEX assistant_grant_audit_grant ON assistant_grant_audit(grant_id,id);
''');

  Future<AssistantGrant> create({
    required HostUiGrantToken token,
    required GrantDraft draft,
    required DateTime now,
  }) {
    token.checkActive();
    _validate(draft, now);
    return database.write((db) {
      token.checkActive();
      final id = const Uuid().v4();
      db.execute(
        'INSERT INTO assistant_grants(grant_id,category,tool_id,scope_digest,'
        'destination,duration_kind,task_id,conversation_id,expires_at,max_uses,uses,created_at) '
        'VALUES(?,?,?,?,?,?,?,?,?,?,0,?)',
        [
          id,
          draft.category.name,
          draft.toolId,
          draft.scopeDigest,
          draft.destination,
          draft.duration.name,
          draft.taskId,
          draft.conversationId,
          draft.expiresAt?.toUtc().toIso8601String(),
          draft.duration == GrantDuration.once ? 1 : draft.maxUses,
          now.toUtc().toIso8601String(),
        ],
      );
      _audit(db, id, 'created', now, draft.taskId, {
        'category': draft.category.name,
        'duration': draft.duration.name,
      });
      return _get(db, id)!;
    });
  }

  static void _validate(GrantDraft draft, DateTime now) {
    if (draft.toolId.trim().isEmpty ||
        draft.scopeDigest.trim().isEmpty ||
        (draft.maxUses != null && draft.maxUses! <= 0) ||
        (draft.duration == GrantDuration.once &&
            draft.maxUses != null &&
            draft.maxUses != 1)) {
      throw ArgumentError('Invalid grant binding or use limit');
    }
    if ((draft.duration == GrantDuration.task &&
            (draft.taskId?.isEmpty ?? true)) ||
        (draft.duration == GrantDuration.conversation &&
            (draft.conversationId?.isEmpty ?? true)) ||
        (draft.duration == GrantDuration.timed && draft.expiresAt == null) ||
        (draft.expiresAt != null && !draft.expiresAt!.isAfter(now))) {
      throw ArgumentError('Invalid grant lifetime');
    }
    if (draft.category == GrantCategory.outbound) {
      if (draft.duration == GrantDuration.always) {
        throw ArgumentError('Outbound grants cannot last always');
      }
      if (draft.destination == null ||
          draft.destination!.trim().isEmpty ||
          (draft.duration != GrantDuration.once &&
              (draft.conversationId?.isEmpty ?? true))) {
        throw ArgumentError(
          'Outbound grants need a destination and conversation boundary',
        );
      }
    }
  }

  List<AssistantGrant> list({bool includeRevoked = true}) => [
    for (final row in database.raw.select(
      'SELECT * FROM assistant_grants '
      "${includeRevoked ? '' : 'WHERE revoked_at IS NULL '}ORDER BY created_at DESC,rowid DESC",
    ))
      AssistantGrant.fromRow(row),
  ];

  AssistantGrant? findMatching(GrantRequest request) {
    for (final grant in list(includeRevoked: false)) {
      if (_canUse(grant, request)) {
        return grant;
      }
    }
    return null;
  }

  bool _canUse(AssistantGrant grant, GrantRequest request) =>
      !_revoking.contains(grant.id) && grant.matches(request);

  /// Revalidation and increment share one transaction. A stale resolver result
  /// cannot bypass revocation, expiry, taint, binding or concurrent exhaustion.
  Future<AssistantGrant?> recordUse(String grantId, GrantRequest request) =>
      database.write((db) {
        final current = _get(db, grantId);
        if (current == null || !_canUse(current, request)) {
          return null;
        }
        db.execute('UPDATE assistant_grants SET uses=uses+1 WHERE grant_id=?', [
          grantId,
        ]);
        final result = _get(db, grantId)!;
        _audit(db, grantId, 'used', request.now, request.taskId, {
          'uses': result.uses,
        });
        return result;
      });

  /// Stops matching synchronously when requested, before the queued durable
  /// write. On a write failure it remains blocked locally until retry succeeds.
  Future<bool> revoke(String grantId, {required DateTime now, String? taskId}) {
    _revoking.add(grantId);
    return database
        .write((db) {
          final grant = _get(db, grantId);
          if (grant == null || grant.revokedAt != null) {
            return false;
          }
          db.execute(
            'UPDATE assistant_grants SET revoked_at=? WHERE grant_id=?',
            [now.toUtc().toIso8601String(), grantId],
          );
          _audit(db, grantId, 'revoked', now, taskId, {
            'reason': 'host_revocation',
          });
          return true;
        })
        .then((result) {
          _revoking.remove(grantId);
          return result;
        });
  }

  List<Map<String, Object?>> audit(String grantId) => [
    for (final row in database.raw.select(
      'SELECT grant_id,action,at,task_id,detail FROM assistant_grant_audit WHERE grant_id=? ORDER BY id',
      [grantId],
    ))
      Map<String, Object?>.from(row),
  ];

  static AssistantGrant? _get(Database db, String id) {
    final rows = db.select('SELECT * FROM assistant_grants WHERE grant_id=?', [
      id,
    ]);
    return rows.isEmpty ? null : AssistantGrant.fromRow(rows.single);
  }

  static void _audit(
    Database db,
    String id,
    String action,
    DateTime now,
    String? taskId,
    Map<String, Object?> detail,
  ) => db.execute(
    'INSERT INTO assistant_grant_audit(grant_id,action,at,task_id,detail) VALUES(?,?,?,?,?)',
    [id, action, now.toUtc().toIso8601String(), taskId, jsonEncode(detail)],
  );
}
