import 'dart:async';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:supplier_core/supplier_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'host exports round trip through strict standalone import and restore',
    () async {
      final root = Directory.systemTemp.createTempSync('host-exchange');
      addTearDown(() => root.deleteSync(recursive: true));
      final path = '${root.path}/inquiry.sqlite';
      var database = sqlite3.open(path);
      createSchema(database);
      registerFunctions(database);
      ensureSearchIndex(database);
      database.execute(
        'CREATE TABLE schema_migrations(version INTEGER PRIMARY KEY,migration_id TEXT UNIQUE NOT NULL,definition_digest TEXT NOT NULL,applied_at TEXT NOT NULL)',
      );
      database.execute(
        'CREATE TABLE host_schema_state(singleton INTEGER PRIMARY KEY CHECK(singleton=1),definition_digest TEXT NOT NULL,structure_digest TEXT NOT NULL)',
      );
      database.execute(
        "INSERT INTO schema_migrations VALUES(1,'inquiry-v1','host-definition','time')",
      );
      database.execute(
        "INSERT INTO host_schema_state VALUES(1,'host-definition','host-structure')",
      );
      database.userVersion = 1;
      Future<T> execute<T>(FutureOr<T> Function() action) async =>
          await action();
      final store = Store.attach(
        database,
        device: 'host',
        backgroundExecutor: execute,
      );
      Map<String, Object?> supplier(String name) => {
        for (final field in Supplier.fields) field: null,
        'name': name,
        'aliases': <String>[],
        'categories': <String>[],
      };
      final kept = store.save('supplier', supplier('Kept'));
      final snapshot = '${root.path}/snapshot.siq';
      store.exportTo(snapshot);
      final exported = sqlite3.open(snapshot);
      expect(exported.userVersion, 0);
      expect(
        exported.select(
          "SELECT name FROM sqlite_schema WHERE name IN ('schema_migrations','host_schema_state')",
        ),
        isEmpty,
      );
      exported.close();
      final standalone = Store.open(
        '${root.path}/standalone.db',
        device: 'standalone',
      );
      expect(() => standalone.previewImport(snapshot), returnsNormally);
      standalone.importFrom(snapshot);
      expect(standalone.get('supplier', kept)!.data['name'], 'Kept');
      standalone.close();
      final removed = store.save('supplier', supplier('Removed'));
      final originalSchema = database
          .select('SELECT name,sql FROM sqlite_schema ORDER BY name')
          .map((r) => [r['name'], r['sql']])
          .toList();
      store.replaceFrom(snapshot, safetyBackupPath: '${root.path}/safety.siq');
      expect(store.get('supplier', removed), isNull);
      expect(store.get('supplier', kept)!.data['name'], 'Kept');
      expect(
        database
            .select('SELECT name,sql FROM sqlite_schema ORDER BY name')
            .map((r) => [r['name'], r['sql']])
            .toList(),
        originalSchema,
      );
      store.close();
      database.close();
      database = sqlite3.open(path);
      expect(database.userVersion, 1);
      expect(
        database
            .select('SELECT structure_digest FROM host_schema_state')
            .single['structure_digest'],
        'host-structure',
      );
      expect(
        database
            .select('SELECT migration_id FROM schema_migrations')
            .single['migration_id'],
        'inquiry-v1',
      );
      database.close();
    },
  );
  test(
    'attached business store executes on host connection and cannot close it',
    () async {
      final database = sqlite3.openInMemory();
      addTearDown(database.close);
      createSchema(database);
      var dispatches = 0;
      Future<T> execute<T>(FutureOr<T> Function() action) async {
        dispatches++;
        return await action();
      }

      final store = Store.attach(
        database,
        device: 'host',
        backgroundExecutor: execute,
      );
      await store.inBackground((same) async {
        expect(identical(same, store), isTrue);
        expect(identical(same.db, database), isTrue);
        await Future<void>.value();
        same.transaction(
          () => same.db.execute(
            "INSERT INTO meta VALUES('host-test','retained')",
          ),
        );
      });
      expect(dispatches, 1);
      store.close();
      expect(
        database
            .select("SELECT value FROM meta WHERE key='host-test'")
            .single['value'],
        'retained',
      );
    },
  );
  test('attached jobs pause on close while database remains host-owned', () {
    final database = sqlite3.openInMemory();
    addTearDown(database.close);
    AiJobStore.initializeSchema(database);
    final jobs = AiJobStore.attach(database);
    final job = jobs.create(AiTask.values.first, {'question': 'test'});
    jobs.start(job.id);
    jobs.close();
    expect(
      database.select('SELECT status FROM jobs').single['status'],
      'paused',
    );
    expect(database.select('PRAGMA quick_check').single.values.single, 'ok');
  });
}
