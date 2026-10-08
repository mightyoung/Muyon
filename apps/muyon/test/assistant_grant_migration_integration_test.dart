import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

List<List<Object?>> _history(Database db) => [
  for (final row in db.select(
    'SELECT * FROM schema_migrations ORDER BY version',
  ))
    row.values.toList(),
];

void main() {
  late Directory root;
  late StorageManager storage;
  String path() => '${root.path}/muyon.sqlite';
  void install(String fixture) {
    final db = sqlite3.open(path());
    db.execute(
      File('test/fixtures/host_schema/$fixture.sql').readAsStringSync(),
    );
    db.execute("INSERT INTO workspaces VALUES('sentinel','unchanged')");
    db.execute("INSERT INTO settings VALUES('sentinel','keep')");
    db.execute("""
INSERT INTO tool_approvals(id,session_id,tool_id,identity_digest,scope_digest,input_digest,issued_at,expires_at,state)
VALUES('old-approval','old-session','write','identity','scope','input','2026-10-07','2026-10-08','issued');
INSERT INTO tool_invocation_receipts(replay_key,invocation_id,identity_digest,tool_id,state,result_json)
VALUES('old-replay','old-invocation','identity','write','failed','{}');
INSERT INTO outbound_requests(id,caller,profile_id,endpoint,endpoint_identity,location,cloud_proxy,model_id,payload_sha256,payload_bytes,item_count,started_at,status)
VALUES('old-model','assistant','profile','https://old.test','old-endpoint','remote',0,'model','digest',17,1,'2026-10-07','interrupted');
""");
    final tables = db
        .select("SELECT name FROM sqlite_master WHERE type='table'")
        .map((r) => r['name'])
        .toSet();
    if (tables.contains('outbound_tool_requests')) {
      db.execute("""
INSERT INTO outbound_tool_requests(id,tool_id,channel,destination,payload_digest,bytes_sent,state,created_at)
VALUES('old-tool','external','mcp','https://old.test','digest',23,'cancelled','2026-10-07');
""");
    }
    if (tables.contains('assistant_grants')) {
      db.execute("""
INSERT INTO assistant_grants(grant_id,category,tool_id,scope_digest,duration_kind,uses,created_at,revoked_at)
VALUES('old-grant','write','write','scope','always',2,'2026-10-07','2026-10-08');
INSERT INTO assistant_grant_audit(grant_id,action,at,detail)
VALUES('old-grant','revoked','2026-10-08','{}');
""");
    }
    db.close();
  }

  Map<String, List<Map<String, Object?>>> data(Database db) => {
    for (final table in [
      'tool_approvals',
      'tool_invocation_receipts',
      'outbound_requests',
      'outbound_tool_requests',
      'assistant_grants',
      'assistant_grant_audit',
    ])
      if (db.select("SELECT 1 FROM sqlite_master WHERE name=?", [
        table,
      ]).isNotEmpty)
        table: [
          for (final row in db.select('SELECT * FROM $table')) Map.of(row),
        ],
  };
  void expectData(
    Database db,
    Map<String, List<Map<String, Object?>>> original,
  ) {
    for (final entry in original.entries) {
      final rows = db.select('SELECT * FROM ${entry.key}');
      expect(rows, hasLength(entry.value.length));
      for (var i = 0; i < rows.length; i++) {
        for (final cell in entry.value[i].entries) {
          expect(
            rows[i][cell.key],
            cell.value,
            reason: '${entry.key}.${cell.key}',
          );
        }
      }
    }
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('auth-wiring-schema-');
    storage = StorageManager(root.path);
  });
  tearDown(() async {
    await storage.close();
    root.deleteSync(recursive: true);
  });

  test(
    'real host registers 11 grants and 12 linkage without fake transport',
    () async {
      final db = (await storage.open('muyon', WorkspaceRepository.schema)).raw;
      expect(db.userVersion, 12);
      expect(_history(db).skip(10).map((r) => r[1]), [
        'assistant-grants',
        'assistant-authorization-links',
      ]);
      expect(db.select('SELECT * FROM assistant_grants'), isEmpty);
      for (final table in [
        'tool_approvals',
        'tool_invocation_receipts',
        'outbound_requests',
        'outbound_tool_requests',
      ]) {
        final columns = db
            .select('PRAGMA table_info($table)')
            .map((r) => r['name']);
        expect(
          columns,
          containsAll([
            'grant_id',
            'authorization_source',
            'review_decision_id',
          ]),
        );
      }
      expect(db.select('SELECT * FROM assistant_review_decisions'), isEmpty);
      expect(db.select('SELECT * FROM outbound_requests'), isEmpty);
      expect(db.select('SELECT * FROM outbound_tool_requests'), isEmpty);
    },
  );

  test(
    'review block is an independent fact and never an outbound request',
    () async {
      final db = (await storage.open('muyon', WorkspaceRepository.schema)).raw;
      db.execute(
        "INSERT INTO assistant_review_decisions(id,tool_id,payload_digest,decision,reviewed,created_at) VALUES('block','external','digest','block',1,'2026-10-08T00:00:00.000Z')",
      );
      expect(
        db
            .select('SELECT decision FROM assistant_review_decisions')
            .single['decision'],
        'block',
      );
      expect(db.select('SELECT * FROM outbound_requests'), isEmpty);
      expect(db.select('SELECT * FROM outbound_tool_requests'), isEmpty);
    },
  );
  test(
    'v12 unknown schema is rejected even with forged matching metadata',
    () async {
      install('canonical-v12');
      final db = sqlite3.open(path());
      db.execute('ALTER TABLE tool_approvals ADD COLUMN untrusted TEXT');
      db.execute('UPDATE host_schema_state SET structure_digest=?', [
        StorageManager.structureDigest(db),
      ]);
      db.close();
      await expectLater(
        storage.open('muyon', WorkspaceRepository.schema),
        throwsStateError,
      );
    },
  );
  for (final fixture in ['legacy-v10', 'repaired406ca95-v11']) {
    for (final table in ['schema_migrations', 'host_schema_state']) {
      test('$fixture $table metadata failure rolls back all upgrade data', () async {
        install(fixture);
        final before = sqlite3.open(path());
        final history = _history(before);
        final originalData = data(before);
        final digest = StorageManager.structureDigest(before);
        final version = before.userVersion;
        before.close();
        final target = ModuleSchema(
          version: 12,
          definitionDigest: 'foundation-v12',
          migrations: [
            ...WorkspaceRepository.schema.migrations.take(11),
            ModuleMigration(
              version: 12,
              id: 'assistant-authorization-links',
              definitionDigest: 'foundation-v12',
              migrate: (db) {
                WorkspaceRepository.schema.migrations.last.migrate(db);
                db.execute(
                  "CREATE TEMP TRIGGER deny_metadata BEFORE INSERT ON $table BEGIN SELECT RAISE(ABORT,'injected metadata'); END",
                );
              },
            ),
          ],
        );
        await expectLater(
          storage.open('muyon', target),
          throwsA(isA<SqliteException>()),
        );
        final after = sqlite3.open(path());
        expect(after.userVersion, version);
        expect(StorageManager.structureDigest(after), digest);
        expect(_history(after), history);
        expectData(after, originalData);
        after.close();
        await storage.close();
        storage = StorageManager(root.path);
        expect(
          (await storage.open(
            'muyon',
            WorkspaceRepository.schema,
          )).raw.userVersion,
          12,
        );
      });
    }
  }
  for (final fixture in [
    'legacy-v8',
    'legacy-v9',
    'legacy-v10',
    'canonical-v9',
    'repaired406ca95-v10',
    'repaired406ca95-v11',
    'canonical-v12',
    'repaired-v12',
  ]) {
    test(
      '$fixture upgrades and reopens at 12 preserving original facts and data',
      () async {
        install(fixture);
        final originalDb = sqlite3.open(path());
        final original = _history(originalDb);
        final originalData = data(originalDb);
        final hasAudit = originalDb
            .select(
              "SELECT name FROM sqlite_master WHERE name='host_migration_compatibility'",
            )
            .isNotEmpty;
        final facts = hasAudit
            ? originalDb
                  .select('SELECT * FROM host_migration_compatibility')
                  .single
                  .values
                  .toList()
            : null;
        originalDb.close();
        final first = await storage.open('muyon', WorkspaceRepository.schema);
        expect(first.raw.userVersion, 12);
        expect(_history(first.raw).take(original.length), original);
        expectData(first.raw, originalData);
        expect(
          first.raw.select('SELECT title FROM workspaces').single['title'],
          'unchanged',
        );
        expect(
          first.raw.select('SELECT value FROM settings').single['value'],
          'keep',
        );
        if (facts != null) {
          expect(
            first.raw
                .select('SELECT * FROM host_migration_compatibility')
                .single
                .values
                .toList(),
            facts,
          );
        }
        final digest = StorageManager.structureDigest(first.raw);
        await storage.close();
        storage = StorageManager(root.path);
        final reopened = await storage.open(
          'muyon',
          WorkspaceRepository.schema,
        );
        expect(reopened.raw.userVersion, 12);
        expect(StorageManager.structureDigest(reopened.raw), digest);
        expect(_history(reopened.raw).take(original.length), original);
        expectData(reopened.raw, originalData);
      },
    );

    if (!fixture.endsWith('v12')) {
      test(
        '$fixture rollback includes 11/12 DDL and compatibility guards',
        () async {
          install(fixture);
          final originalDb = sqlite3.open(path());
          final original = _history(originalDb);
          final originalData = data(originalDb);
          final digest = StorageManager.structureDigest(originalDb);
          final version = originalDb.userVersion;
          originalDb.close();
          final target = ModuleSchema(
            version: 12,
            definitionDigest: 'foundation-v12',
            migrations: [
              ...WorkspaceRepository.schema.migrations.take(11),
              ModuleMigration(
                version: 12,
                id: 'assistant-authorization-links',
                definitionDigest: 'foundation-v12',
                migrate: (db) {
                  WorkspaceRepository.schema.migrations.last.migrate(db);
                  throw StateError('injected after v12 DDL');
                },
              ),
            ],
          );
          await expectLater(storage.open('muyon', target), throwsStateError);
          final after = sqlite3.open(path());
          expect(after.userVersion, version);
          expect(StorageManager.structureDigest(after), digest);
          expect(_history(after), original);
          expectData(after, originalData);
          after.close();
          await storage.close();
          storage = StorageManager(root.path);
          expect(
            (await storage.open(
              'muyon',
              WorkspaceRepository.schema,
            )).raw.userVersion,
            12,
          );
        },
      );
    }
  }
}
