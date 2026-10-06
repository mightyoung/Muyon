import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('ModuleChangeLog', () {
    late Database db;
    setUp(() {
      db = sqlite3.openInMemory();
      ModuleChangeLog.createTable(db);
    });
    tearDown(() => db.close());

    ObjectRef ref(String id) => ObjectRef(
      moduleId: 'research',
      objectType: 'card',
      objectId: id,
      nativeProjectId: 'p1',
      revisionRef: 'r1',
      contentDigest: 'd1',
    );

    test('records in order and reads back after a cursor', () {
      ModuleChangeLog.record(db, ref('a'), ChangeOp.upsert, summary: 'A');
      ModuleChangeLog.record(db, ref('b'), ChangeOp.upsert);
      ModuleChangeLog.record(db, ref('a'), ChangeOp.delete);
      final all = ModuleChangeLog.since(db, 'research', 0);
      expect(all.map((c) => c.ref.objectId), ['a', 'b', 'a']);
      expect(all.last.op, ChangeOp.delete);
      expect(all.first.ref, ref('a'));
      expect(all.first.summary, 'A');
      expect(all[1].summary, isNull);
      final tail = ModuleChangeLog.since(db, 'research', all[1].sequence);
      expect(tail.single.op, ChangeOp.delete);
    });

    test('rolls back with the business transaction', () {
      db.execute('CREATE TABLE cards(id TEXT PRIMARY KEY)');
      db.execute('BEGIN');
      db.execute("INSERT INTO cards VALUES('a')");
      ModuleChangeLog.record(db, ref('a'), ChangeOp.upsert);
      db.execute('ROLLBACK');
      expect(ModuleChangeLog.since(db, 'research', 0), isEmpty);
    });

    test('rejects incomplete refs', () {
      expect(
        () => ModuleChangeLog.record(
          db,
          const ObjectRef(moduleId: '', objectType: 'card', objectId: 'a'),
          ChangeOp.upsert,
        ),
        throwsArgumentError,
      );
    });
  });

  group('RestrictedWebViewSpec', () {
    final spec = RestrictedWebViewSpec(
      entry: Uri.parse('https://proto.local/app/index.html'),
      allowedRoots: {Uri.parse('https://proto.local/app/')},
      bridgeChannels: {'feedback.submit'},
    );

    test('allows navigation only under declared roots', () {
      expect(
        spec.allowsNavigation(Uri.parse('https://proto.local/app/p/2')),
        isTrue,
      );
      expect(
        spec.allowsNavigation(Uri.parse('https://proto.local/other')),
        isFalse,
      );
      expect(
        spec.allowsNavigation(Uri.parse('https://proto.local/app/../other')),
        isFalse,
      );
      expect(
        spec.allowsNavigation(Uri.parse('https://proto.local/application')),
        isFalse,
      );
      expect(
        spec.allowsNavigation(Uri.parse('https://evil.example/app/')),
        isFalse,
      );
      expect(spec.allowsNavigation(Uri.parse('javascript:alert(1)')), isFalse);
      expect(spec.allowsNavigation(Uri.parse('data:text/html,x')), isFalse);
    });

    test('only declared bridge channels pass', () {
      expect(spec.allowsBridge('feedback.submit'), isTrue);
      expect(spec.allowsBridge('files.read'), isFalse);
    });

    test('entry must be inside an allowed root', () {
      expect(
        () => RestrictedWebViewSpec(
          entry: Uri.parse('https://evil.example/'),
          allowedRoots: {Uri.parse('https://proto.local/app/')},
        ),
        throwsArgumentError,
      );
    });
  });

  test('manifest keeps optional dependencies separate', () {
    final manifest = ModuleManifest(
      id: 'prototype',
      requiredDependencies: ['research'],
      optionalDependencies: ['inquiry'],
    );
    expect(manifest.requiredDependencies, ['research']);
    expect(manifest.optionalDependencies, ['inquiry']);
    expect(
      () => manifest.optionalDependencies.add('x'),
      throwsUnsupportedError,
    );
  });
}
