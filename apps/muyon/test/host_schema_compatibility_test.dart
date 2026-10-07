import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/grants/grant_store.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

ModuleSchema schema11({bool fail = false}) => ModuleSchema(
  version: 11,
  definitionDigest: 'foundation-v11',
  migrations: [
    ...WorkspaceRepository.schema.migrations,
    ModuleMigration(
      version: 11,
      id: GrantStore.migration.id,
      definitionDigest: GrantStore.migration.definitionDigest,
      migrate: (db) {
        GrantStore.createTables(db);
        if (fail) throw StateError('injected after AUTH DDL');
      },
    ),
  ],
);

List<List<Object?>> history(Database db) => db
    .select('SELECT * FROM schema_migrations ORDER BY version')
    .map((r) => r.values.toList())
    .toList();

void main() {
  late Directory root;
  late StorageManager manager;
  String getPath() => '${root.path}/muyon.sqlite';
  void install(String fixture) {
    final db = sqlite3.open(getPath());
    try {
      db.execute(
        File('test/fixtures/host_schema/$fixture.sql').readAsStringSync(),
      );
      db.execute("INSERT INTO workspaces VALUES('sentinel','keep me')");
      db.execute("INSERT INTO settings VALUES('sentinel','keep setting')");
    } finally {
      db.close();
    }
  }

  void restart() {
    manager = StorageManager(root.path);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('historical-host-');
    restart();
  });
  tearDown(() async {
    await manager.close();
    root.deleteSync(recursive: true);
  });

  for (final fixture in [
    'legacy-v8',
    'legacy-v9',
    'legacy-v10',
    'canonical-v9',
  ]) {
    test(
      '$fixture upgrades and reopens without rewriting original applied facts',
      () async {
        install(fixture);
        final before = sqlite3.open(getPath());
        final original = history(before);
        before.close();
        final owner = await manager.open('muyon', WorkspaceRepository.schema);
        expect(owner.raw.userVersion, 10);
        expect(history(owner.raw).take(original.length).toList(), original);
        expect(
          owner.raw.select('SELECT title FROM workspaces').single['title'],
          'keep me',
        );
        expect(
          owner.raw.select('SELECT value FROM settings').single['value'],
          'keep setting',
        );
        expect(
          owner.raw.select(
            "SELECT name FROM sqlite_master WHERE name='outbound_tool_requests'",
          ),
          hasLength(1),
        );
        final repaired = fixture == 'legacy-v9' || fixture == 'legacy-v10';
        if (repaired) {
          expect(
            owner.raw
                .select(
                  'SELECT source_version,completed FROM host_migration_compatibility',
                )
                .single['completed'],
            1,
          );
          expect(
            () => owner.raw.execute(
              "UPDATE host_migration_compatibility SET repaired_at='changed'",
            ),
            throwsA(isA<SqliteException>()),
          );
          expect(
            () => owner.raw.execute('DELETE FROM host_migration_compatibility'),
            throwsA(isA<SqliteException>()),
          );
        }
        await manager.close();
        restart();
        final reopened = await manager.open(
          'muyon',
          WorkspaceRepository.schema,
        );
        expect(history(reopened.raw).take(original.length).toList(), original);
        await manager.close();
        restart();
        final upgraded = await manager.open('muyon', schema11());
        expect(upgraded.raw.userVersion, 11);
        expect(history(upgraded.raw).take(original.length).toList(), original);
        await manager.close();
        restart();
        expect((await manager.open('muyon', schema11())).raw.userVersion, 11);
      },
    );
  }
  test(
    'fresh canonical v10 contains real ledger and no compatibility fiction',
    () async {
      final owner = await manager.open('muyon', WorkspaceRepository.schema);
      expect(owner.raw.userVersion, 10);
      expect(history(owner.raw)[8][1], 'outbound-tool-requests');
      expect(
        owner.raw.select(
          "SELECT name FROM sqlite_master WHERE name='host_migration_compatibility'",
        ),
        isEmpty,
      );
    },
  );
  test('INSERT OR REPLACE cannot replace a completed repair fact', () async {
    install('legacy-v10');
    final owner = await manager.open('muyon', WorkspaceRepository.schema);
    final original = owner.raw
        .select('SELECT * FROM host_migration_compatibility')
        .single
        .values
        .toList();
    expect(
      owner.raw.select('PRAGMA recursive_triggers').single.values.single,
      0,
    );
    expect(
      () => owner.raw.execute(
        '''
INSERT OR REPLACE INTO host_migration_compatibility
SELECT repair_id,source_version,source_definition_digest,source_structure_digest,
source_history_json,canonical_migration_id,canonical_definition_digest,completed,?
FROM host_migration_compatibility
''',
        ['2026-10-09T00:00:00.000Z'],
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(
      owner.raw
          .select('SELECT * FROM host_migration_compatibility')
          .single
          .values
          .toList(),
      original,
    );
    await manager.close();
    restart();
    final reopened = await manager.open('muyon', WorkspaceRepository.schema);
    expect(
      reopened.raw
          .select('SELECT * FROM host_migration_compatibility')
          .single
          .values
          .toList(),
      original,
    );
  });

  for (final fixture in ['legacy-v8', 'legacy-v9', 'legacy-v10']) {
    test(
      '$fixture faults roll back repair DDL, audit, metadata and migrations together',
      () async {
        install(fixture);
        final before = sqlite3.open(getPath());
        final original = history(before);
        final fingerprint = StorageManager.structureDigest(before);
        final version = before.userVersion;
        final metadata = before
            .select('SELECT * FROM host_schema_state')
            .single
            .values
            .toList();
        before.close();
        // v8/v9 fail after migration 10; v10 fails after migration 11.
        final target = fixture == 'legacy-v10'
            ? schema11(fail: true)
            : ModuleSchema(
                version: 10,
                definitionDigest: 'foundation-v10',
                migrations: [
                  ...WorkspaceRepository.schema.migrations.take(9),
                  ModuleMigration(
                    version: 10,
                    id: 'module-grants',
                    definitionDigest: 'foundation-v10',
                    migrate: (db) {
                      WorkspaceRepository.schema.migrations.last.migrate(db);
                      throw StateError('injected after module grants DDL');
                    },
                  ),
                ],
              );
        await expectLater(manager.open('muyon', target), throwsStateError);
        final inspected = sqlite3.open(getPath());
        expect(inspected.userVersion, version);
        expect(history(inspected), original);
        expect(StorageManager.structureDigest(inspected), fingerprint);
        expect(
          inspected
              .select('SELECT * FROM host_schema_state')
              .single
              .values
              .toList(),
          metadata,
        );
        expect(
          inspected.select('SELECT title FROM workspaces').single['title'],
          'keep me',
        );
        inspected.close();
        expect(
          (await manager.open(
            'muyon',
            WorkspaceRepository.schema,
          )).raw.userVersion,
          10,
        );
      },
    );
  }

  for (final fixture in ['legacy-v8', 'canonical-v9']) {
    test(
      '$fixture rejects altered canonical migration DDL despite matching ids',
      () async {
        install(fixture);
        final before = sqlite3.open(getPath());
        final fingerprint = StorageManager.structureDigest(before);
        final original = history(before);
        before.close();
        final target = ModuleSchema(
          version: 10,
          definitionDigest: 'foundation-v10',
          migrations: [
            ...WorkspaceRepository.schema.migrations.take(9),
            ModuleMigration(
              version: 10,
              id: 'module-grants',
              definitionDigest: 'foundation-v10',
              migrate: (db) {
                WorkspaceRepository.schema.migrations.last.migrate(db);
                db.execute('CREATE TABLE unexpected(x)');
              },
            ),
          ],
        );
        await expectLater(manager.open('muyon', target), throwsStateError);
        final inspected = sqlite3.open(getPath());
        expect(StorageManager.structureDigest(inspected), fingerprint);
        expect(history(inspected), original);
        inspected.close();
      },
    );
  }

  for (final version in [10, 11]) {
    test('previous repaired v$version receives guard without rewriting facts', () async {
      install('repaired406ca95-v$version');
      final before = sqlite3.open(getPath());
      final original = history(before);
      final fact = before
          .select('SELECT * FROM host_migration_compatibility')
          .single
          .values
          .toList();
      before.close();
      final target = version == 10 ? WorkspaceRepository.schema : schema11();
      final owner = await manager.open('muyon', target);
      expect(history(owner.raw), original);
      expect(
        owner.raw
            .select('SELECT * FROM host_migration_compatibility')
            .single
            .values
            .toList(),
        fact,
      );
      expect(
        owner.raw.select(
          "SELECT name FROM sqlite_master WHERE name='host_compatibility_no_insert'",
        ),
        hasLength(1),
      );
      for (final statement in [
        'INSERT OR REPLACE',
        'REPLACE',
        'INSERT OR IGNORE',
      ]) {
        expect(
          () => owner.raw.execute(
            '$statement INTO host_migration_compatibility SELECT * FROM host_migration_compatibility',
          ),
          throwsA(isA<SqliteException>()),
        );
      }
      await manager.close();
      restart();
      final reopened = await manager.open('muyon', target);
      expect(history(reopened.raw), original);
      expect(
        reopened.raw
            .select('SELECT * FROM host_migration_compatibility')
            .single
            .values
            .toList(),
        fact,
      );
    });
  }
  test('guard upgrade rolls back with a later migration fault', () async {
    install('repaired406ca95-v10');
    final before = sqlite3.open(getPath());
    final original = history(before);
    final fingerprint = StorageManager.structureDigest(before);
    final fact = before
        .select('SELECT * FROM host_migration_compatibility')
        .single
        .values
        .toList();
    before.close();
    await expectLater(
      manager.open('muyon', schema11(fail: true)),
      throwsStateError,
    );
    final inspected = sqlite3.open(getPath());
    expect(StorageManager.structureDigest(inspected), fingerprint);
    expect(history(inspected), original);
    expect(
      inspected
          .select('SELECT * FROM host_migration_compatibility')
          .single
          .values
          .toList(),
      fact,
    );
    expect(
      inspected.select(
        "SELECT name FROM sqlite_master WHERE name='host_compatibility_no_insert'",
      ),
      isEmpty,
    );
    inspected.close();
    expect(
      (await manager.open('muyon', WorkspaceRepository.schema)).raw.userVersion,
      10,
    );
  });
  final corruptions = <String, void Function(Database)>{
    'unknown table with forged metadata': (db) =>
        db.execute('CREATE TABLE foreign_table(x)'),
    'unknown migration id': (db) => db.execute(
      "UPDATE schema_migrations SET migration_id='unknown' WHERE version=3",
    ),
    'unknown digest': (db) => db.execute(
      "UPDATE schema_migrations SET definition_digest='unknown' WHERE version=9",
    ),
    'missing migration': (db) =>
        db.execute('DELETE FROM schema_migrations WHERE version=4'),
    'extra migration': (db) => db.execute(
      "INSERT INTO schema_migrations VALUES(99,'extra','extra','2026-10-07T00:00:00Z')",
    ),
    'unexpected real ledger': (db) =>
        db.execute('CREATE TABLE outbound_tool_requests(x)'),
    'unknown definition': (db) =>
        db.execute("UPDATE host_schema_state SET definition_digest='unknown'"),
    'bad applied timestamp': (db) => db.execute(
      "UPDATE schema_migrations SET applied_at='not-a-date' WHERE version=9",
    ),
  };
  for (final corruption in corruptions.entries) {
    test('${corruption.key} rejects without changing disk facts', () async {
      install('legacy-v10');
      final db = sqlite3.open(getPath());
      corruption.value(db);
      db.execute('UPDATE host_schema_state SET structure_digest=?', [
        StorageManager.structureDigest(db),
      ]);
      final fingerprint = StorageManager.structureDigest(db);
      final rows = history(db);
      db.close();
      await expectLater(
        manager.open('muyon', WorkspaceRepository.schema),
        throwsStateError,
      );
      final inspected = sqlite3.open(getPath());
      expect(inspected.userVersion, 10);
      expect(history(inspected), rows);
      expect(StorageManager.structureDigest(inspected), fingerprint);
      expect(
        inspected.select('SELECT title FROM workspaces').single['title'],
        'keep me',
      );
      inspected.close();
    });
  }
  for (final fixture in ['canonical-v9', 'legacy-v9']) {
    test(
      '$fixture validates every migration timestamp after upgrade',
      () async {
        install(fixture);
        await manager.open('muyon', WorkspaceRepository.schema);
        await manager.close();
        restart();
        final db = sqlite3.open(getPath());
        db.execute(
          "UPDATE schema_migrations SET applied_at='invalid' WHERE version=10",
        );
        db.close();
        await expectLater(
          manager.open('muyon', WorkspaceRepository.schema),
          throwsStateError,
        );
      },
    );
  }
  for (final kind in ['history', 'schema', 'audit']) {
    test('repaired database rejects subsequent $kind tampering', () async {
      install('legacy-v10');
      await manager.open('muyon', WorkspaceRepository.schema);
      await manager.close();
      restart();
      final db = sqlite3.open(getPath());
      if (kind == 'history') {
        db.execute(
          "UPDATE schema_migrations SET applied_at='2026-10-08T00:00:00Z' WHERE version=9",
        );
      }
      if (kind == 'schema') {
        db.execute(
          'ALTER TABLE outbound_tool_requests ADD COLUMN unexpected TEXT',
        );
      }
      if (kind == 'audit') {
        db.execute('DROP TRIGGER host_compatibility_no_update');
        db.execute(
          "UPDATE host_migration_compatibility SET source_structure_digest='forged'",
        );
      }
      db.execute('UPDATE host_schema_state SET structure_digest=?', [
        StorageManager.structureDigest(db),
      ]);
      db.close();
      await expectLater(
        manager.open('muyon', WorkspaceRepository.schema),
        throwsStateError,
      );
    });
  }
}
