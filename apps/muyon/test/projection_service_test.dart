import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/projection_service.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

final _schema = ModuleSchema(
  version: 1,
  definitionDigest: 'cards-1',
  migrations: [
    ModuleMigration(
      version: 1,
      id: 'cards-1',
      definitionDigest: 'cards-1',
      migrate: (db) {
        db.execute('CREATE TABLE cards(id TEXT PRIMARY KEY, title TEXT)');
        ModuleChangeLog.createTable(db);
      },
    ),
  ],
);

ObjectRef _ref(String id) => ObjectRef(
  moduleId: 'cards',
  objectType: 'card',
  objectId: id,
  nativeProjectId: 'p1',
);

void main() {
  late Directory root;
  late StorageManager storage;
  late ManagedDatabase host;
  late ManagedConnection cards;
  late ProjectionService projections;

  Future<void> put(String id, String title) => cards.write((db) {
    db.execute('INSERT OR REPLACE INTO cards VALUES(?,?)', [id, title]);
    ModuleChangeLog.record(db, _ref(id), ChangeOp.upsert, summary: title);
  });
  Future<void> remove(String id) => cards.write((db) {
    db.execute('DELETE FROM cards WHERE id=?', [id]);
    ModuleChangeLog.record(db, _ref(id), ChangeOp.delete);
  });
  Map<String, String> catalog() => {
    for (final row in host.raw.select(
      "SELECT object_id,summary FROM object_catalog WHERE module_id='cards' ORDER BY object_id",
    ))
      row['object_id'] as String: row['summary'] as String,
  };

  setUp(() async {
    root = Directory.systemTemp.createTempSync('muyon-projection-');
    storage = StorageManager(root.path);
    host = await storage.open('muyon', WorkspaceRepository.schema);
    cards = await storage.open('cards', _schema);
    projections = ProjectionService(host);
  });
  tearDown(() async {
    await storage.close();
    root.deleteSync(recursive: true);
  });

  test(
    'applies upserts and deletes in order and advances the cursor',
    () async {
      await put('a', 'Alpha');
      await put('b', 'Beta');
      await put('a', 'Alpha 2');
      await remove('b');
      await projections.sync('cards', cards.raw);
      expect(catalog(), {'a': 'Alpha 2'});
      expect(projections.cursor('cards'), 4);
    },
  );

  test(
    'replay and overlapping runs are idempotent and never resurrect',
    () async {
      await put('a', 'Alpha');
      final early = projections.sync('cards', cards.raw);
      await remove('a');
      final late = projections.sync('cards', cards.raw);
      await Future.wait([early, late]);
      await projections.sync('cards', cards.raw);
      expect(catalog(), isEmpty);
      expect(projections.cursor('cards'), 2);
    },
  );

  test('modules without a change log are skipped', () async {
    final plain = await storage.open(
      'plain',
      ModuleSchema(
        version: 1,
        definitionDigest: 'plain-1',
        migrations: [
          ModuleMigration(
            version: 1,
            id: 'plain-1',
            definitionDigest: 'plain-1',
            migrate: (db) => db.execute('CREATE TABLE x(y)'),
          ),
        ],
      ),
    );
    await projections.sync('plain', plain.raw);
    expect(projections.cursor('plain'), 0);
  });

  test('watch syncs after each module commit and reports listeners', () async {
    final applied = <String>[];
    projections.onApplied = (moduleId, changes) =>
        applied.addAll(changes.map((c) => '${c.op.name}:${c.ref.objectId}'));
    projections.watch('cards', cards);
    await put('a', 'Alpha');
    await remove('a');
    await put('b', 'Beta');
    await projections.idle('cards');
    expect(catalog(), {'b': 'Beta'});
    expect(applied, ['upsert:a', 'delete:a', 'upsert:b']);
    expect(projections.errors, isEmpty);
  });
}
