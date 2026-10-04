import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/workspace/workspace_repository.dart';

void main() {
  late Directory root;
  late StorageManager manager;
  setUp(() {
    root = Directory.systemTemp.createTempSync('muyon-storage-');
    manager = StorageManager(root.path);
  });
  tearDown(() async {
    await manager.close();
    root.deleteSync(recursive: true);
  });

  test('one owner, foreign keys and queue rollback isolation', () async {
    final futures = [
      manager.open('muyon', WorkspaceRepository.schema),
      manager.open('muyon', WorkspaceRepository.schema),
    ];
    final owners = await Future.wait(futures);
    expect(identical(owners[0], owners[1]), isTrue);
    expect(owners[0].raw.select('PRAGMA foreign_keys').single.values.single, 1);
    final repo = WorkspaceRepository(owners[0]);
    final a = repo.create('A');
    final failure = owners[0].write((db) {
      db.execute("INSERT INTO workspaces VALUES('bad','bad')");
      throw StateError('Fail');
    });
    final b = repo.create('B');
    await expectLater(failure, throwsStateError);
    await Future.wait([a, b]);
    expect(repo.all().map((w) => w.title), ['A', 'B']);
  });

  test('close drains writes and rejects new writes', () async {
    final owner = await manager.open('muyon', WorkspaceRepository.schema);
    final pending = WorkspaceRepository(owner).create('keep');
    final closing = owner.close();
    await pending;
    await closing;
    await expectLater(owner.write((db) => null), throwsStateError);
  });

  test('concurrent close callers await the same database drain', () async {
    final owner = await manager.open('muyon', WorkspaceRepository.schema);
    final release = Completer<void>();
    final pending = owner.exclusiveAsync((db) async {
      await release.future;
      db.execute("INSERT INTO workspaces VALUES('drain','drain')");
    });
    final first = owner.close();
    final second = owner.close();
    expect(identical(first, second), isTrue);
    var done = false;
    second.then((_) => done = true);
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);
    release.complete();
    await Future.wait([pending, first, second]);
    expect(done, isTrue);
  });

  test(
    'schema downgrade, same-version drift and failed migration preserve data',
    () async {
      final owner = await manager.open('muyon', WorkspaceRepository.schema);
      await WorkspaceRepository(owner).create('persist');
      await manager.close();
      manager = StorageManager(root.path);
      final newer = ModuleSchema(
        version: 3,
        definitionDigest: 'v3',
        migrations: [
          ...WorkspaceRepository.schema.migrations,
          ModuleMigration(
            version: 3,
            id: 'v3',
            definitionDigest: 'v3',
            migrate: (db) {
              db.execute('CREATE TABLE doomed(x)');
              throw StateError('Migration fails');
            },
          ),
        ],
      );
      await expectLater(manager.open('muyon', newer), throwsStateError);
      final reopened = await manager.open(
        'muyon',
        WorkspaceRepository.schema,
      );
      expect(WorkspaceRepository(reopened).all().single.title, 'persist');
      expect(
        reopened.raw.select(
          "SELECT name FROM sqlite_master WHERE name='doomed'",
        ),
        isEmpty,
      );
      await reopened.write((db) => db.execute('CREATE TABLE drift(x)'));
      await manager.close();
      manager = StorageManager(root.path);
      await expectLater(
        manager.open('muyon', WorkspaceRepository.schema),
        throwsStateError,
      );
    },
  );

  test('ahead version never opens or clears', () async {
    final owner = await manager.open('muyon', WorkspaceRepository.schema);
    owner.raw.userVersion = 99;
    await manager.close();
    manager = StorageManager(root.path);
    await expectLater(
      manager.open('muyon', WorkspaceRepository.schema),
      throwsStateError,
    );
    final inspect = sqlite3.open('${root.path}/muyon.sqlite');
    expect(inspect.userVersion, 99);
    inspect.close();
  });
}
