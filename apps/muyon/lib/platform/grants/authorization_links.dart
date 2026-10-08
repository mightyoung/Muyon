import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

/// Review facts are separate from transport attempts. A blocked review never
/// manufactures a request, bytes sent, or a successful transport outcome.
abstract final class AuthorizationLinks {
  static final migration = ModuleMigration(
    version: 12,
    id: 'assistant-authorization-links',
    definitionDigest: 'foundation-v12',
    migrate: createTables,
  );

  static void createTables(Database db) {
    db.execute('''
CREATE TABLE assistant_review_decisions(
 id TEXT PRIMARY KEY, task_id TEXT, invocation_id TEXT,
 tool_id TEXT NOT NULL, destination_identity_digest TEXT,
 payload_digest TEXT NOT NULL,
 decision TEXT NOT NULL CHECK(decision IN ('allow','confirm','block')),
 reviewed INTEGER NOT NULL CHECK(reviewed IN (0,1)),
 reason TEXT, created_at TEXT NOT NULL
);
''');
    for (final table in [
      'tool_approvals',
      'tool_invocation_receipts',
      'outbound_requests',
      'outbound_tool_requests',
    ]) {
      db.execute(
        'ALTER TABLE $table ADD COLUMN grant_id TEXT REFERENCES assistant_grants(grant_id)',
      );
      db.execute('ALTER TABLE $table ADD COLUMN authorization_source TEXT');
      db.execute(
        'ALTER TABLE $table ADD COLUMN review_decision_id TEXT REFERENCES assistant_review_decisions(id)',
      );
    }
    db.execute('''
ALTER TABLE tool_approvals ADD COLUMN grant_context_digest TEXT;
ALTER TABLE tool_approvals ADD COLUMN invocation_id TEXT;
ALTER TABLE tool_approvals ADD COLUMN replay_key TEXT;
CREATE UNIQUE INDEX tool_grant_approval_invocation ON tool_approvals(invocation_id) WHERE grant_id IS NOT NULL;
CREATE UNIQUE INDEX tool_grant_approval_replay ON tool_approvals(replay_key) WHERE grant_id IS NOT NULL;
''');
  }
}
