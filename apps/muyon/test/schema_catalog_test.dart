import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/schema_catalog.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

ModuleSchema _schema(int version) => ModuleSchema(
  version: version,
  definitionDigest: 'demo-$version',
  migrations: [
    for (var v = 1; v <= version; v++)
      ModuleMigration(
        version: v,
        id: 'demo-$v',
        definitionDigest: 'demo-$v',
        migrate: (db) => db.execute('CREATE TABLE t$v(x)'),
      ),
  ],
);

void main() {
  late Directory root;
  late StorageManager storage;
  late ManagedDatabase host;

  Future<void> openHost() async {
    storage = StorageManager(root.path);
    host = await storage.open('muyon', WorkspaceRepository.schema);
    await SchemaCatalog.attach(storage, host);
  }

  Map<String, Object?> row(String id) => host.raw.select(
    'SELECT * FROM schema_catalog WHERE module_id=?',
    [id],
  ).first;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('muyon-catalog-');
    await openHost();
  });
  tearDown(() async {
    await storage.close();
    root.deleteSync(recursive: true);
  });

  test(
    'host and every opened database are catalogued from real state',
    () async {
      expect(row('muyon')['migration_status'], 'ready');
      final demo = await storage.open('demo', _schema(2));
      final entry = row('demo');
      expect(entry['target_version'], 2);
      expect(entry['target_digest'], 'demo-2');
      expect(entry['observed_version'], 2);
      expect(
        entry['observed_digest'],
        StorageManager.structureDigest(demo.raw),
      );
      expect(entry['migration_status'], 'ready');
      expect(entry['last_error'], isNull);
    },
  );

  test('upgrade refreshes a stale catalog row', () async {
    await storage.open('demo', _schema(1));
    expect(row('demo')['observed_version'], 1);
    await storage.close();
    await openHost();
    await storage.open('demo', _schema(2));
    expect(row('demo')['observed_version'], 2);
    expect(row('demo')['migration_status'], 'ready');
  });

  test('newer database is blocked, recorded, and left untouched', () async {
    await storage.open('demo', _schema(2));
    await storage.close();
    await openHost();
    await expectLater(storage.open('demo', _schema(1)), throwsStateError);
    final entry = row('demo');
    expect(entry['migration_status'], 'blocked');
    expect(entry['observed_version'], 2);
    expect(entry['last_error'], contains('unsupported_schema'));
    final inspect = sqlite3.open('${root.path}/modules/demo/demo.sqlite');
    expect(inspect.userVersion, 2);
    expect(
      inspect.select("SELECT name FROM sqlite_master WHERE name='t2'"),
      isNotEmpty,
    );
    inspect.close();
  });

  test('structure drift is blocked and recorded without repair', () async {
    final demo = await storage.open('demo', _schema(1));
    await demo.write((db) => db.execute('CREATE TABLE intruder(x)'));
    await storage.close();
    await openHost();
    await expectLater(storage.open('demo', _schema(1)), throwsStateError);
    expect(row('demo')['migration_status'], 'blocked');
    expect(row('demo')['last_error'], contains('drift'));
  });

  test('failed migration rolls back and is recorded', () async {
    await storage.open('demo', _schema(1));
    await storage.close();
    await openHost();
    final broken = ModuleSchema(
      version: 2,
      definitionDigest: 'demo-2',
      migrations: [
        _schema(1).migrations.single,
        ModuleMigration(
          version: 2,
          id: 'demo-2',
          definitionDigest: 'demo-2',
          migrate: (db) {
            db.execute('CREATE TABLE half(x)');
            throw StateError('boom');
          },
        ),
      ],
    );
    await expectLater(storage.open('demo', broken), throwsStateError);
    expect(row('demo')['migration_status'], 'blocked');
    expect(row('demo')['observed_version'], 1);
    await storage.close();
    final inspect = sqlite3.open('${root.path}/modules/demo/demo.sqlite');
    expect(inspect.userVersion, 1);
    expect(
      inspect.select("SELECT name FROM sqlite_master WHERE name='half'"),
      isEmpty,
    );
    inspect.close();
    await openHost();
  });
}
