import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/research_module.dart';

import 'change_log_test.dart' show migrated, project;
import 'research_runtime_test.dart' show TestDatabase;

/// REG-3d domain patches: saveTask expected revision, confirmBinding refusal of
/// a missing or settled row, and the project/note change log (schema v10).
void main() {
  late Directory root;
  late TestDatabase db;
  late WorkbenchStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('reg3d-domain-');
    db = migrated(version: 10);
    store = WorkbenchStore.attach(
      rootPath: root.path,
      database: db.raw,
      managed: db,
    );
    project(db, 'p');
    project(db, 'q');
    db.raw.execute(
      "INSERT INTO documents(id,project_id,relative_path,snapshot_path,sha256) VALUES('d','p','a.md','a.md','h')",
    );
  });
  tearDown(() {
    db.raw.close();
    root.deleteSync(recursive: true);
  });

  List<ObjectChangeRow> log(String type) => [
    for (final c in ModuleChangeLog.since(db.raw, 'research', 0))
      if (c.ref.objectType == type)
        ObjectChangeRow(c.ref.objectId, c.op, c.summary ?? ""),
  ];

  group('saveTask expected revision', () {
    test('the first revision of a new task expects 0', () {
      final task = store.saveTask(
        projectId: 'p',
        title: 't',
        goal: 'g',
        spec: {},
        expectedRevision: 0,
      );
      expect(task.revision, 1);
    });

    test(
      'a revision is saved only when the expected one is still the latest',
      () {
        final first = store.saveTask(
          projectId: 'p',
          title: 't',
          goal: 'g',
          spec: {},
        );
        final second = store.saveTask(
          id: first.id,
          projectId: 'p',
          title: 't2',
          goal: 'g',
          spec: {},
          expectedRevision: 1,
        );
        expect(second.revision, 2);
        expect(
          () => store.saveTask(
            id: first.id,
            projectId: 'p',
            title: 't3',
            goal: 'g',
            spec: {},
            expectedRevision: 1,
          ),
          throwsStateError,
        );
        expect(
          store
              .tasks('p')
              .where((t) => t.id == first.id)
              .map((t) => t.revision),
          [2],
        );
        expect(store.taskRevision(first.id, 3), isNull);
      },
    );

    test('an expected revision on an unknown task is refused', () {
      expect(
        () => store.saveTask(
          id: 'ghost',
          projectId: 'p',
          title: 't',
          goal: 'g',
          spec: {},
          expectedRevision: 2,
        ),
        throwsStateError,
      );
      expect(store.taskRevision('ghost', 1), isNull);
    });

    test('without an expected revision behaviour is unchanged', () {
      final first = store.saveTask(
        projectId: 'p',
        title: 't',
        goal: 'g',
        spec: {},
      );
      final again = store.saveTask(
        id: first.id,
        projectId: 'p',
        title: 'u',
        goal: 'g',
        spec: {},
      );
      expect(again.revision, 2);
    });
  });

  group('confirmBinding refuses empty confirmations', () {
    PaperBinding binding(String paper, {bool ambiguous = true}) => PaperBinding(
      documentId: 'd',
      paperId: paper,
      paperRev: 1,
      method: 'manifest',
      hashOk: true,
      ambiguous: ambiguous,
    );

    test('a missing target row is an error, not a silent success', () {
      store.insertBinding(binding('x'));
      expect(() => store.confirmBinding('d', 'ghost'), throwsStateError);
      // the competing candidate must survive a refused confirmation
      expect(store.bindings('p').single.paperId, 'x');
      expect(store.bindings('p').single.ambiguous, isTrue);
    });

    test('a row that is already confirmed is an error', () {
      store.insertBinding(binding('x', ambiguous: false));
      expect(() => store.confirmBinding('d', 'x'), throwsStateError);
      expect(store.bindings('p').single.method, 'manifest');
    });

    test('an ambiguous row still resolves and drops its competitors', () {
      store.insertBinding(binding('x'));
      store.insertBinding(binding('y'));
      store.confirmBinding('d', 'y');
      final left = store.bindings('p').single;
      expect(
        (left.paperId, left.ambiguous, left.method),
        ('y', false, 'manifest+manual'),
      );
    });
  });

  group('project and note change log (schema v10)', () {
    test('saving a project logs an upsert of that project', () async {
      await store.write(
        () => store.saveProject('p', question: 'q?', nextStep: 'n'),
      );
      final rows = log('project').where((r) => r.id == 'p').toList();
      expect(rows, isNotEmpty);
      expect(rows.last.op, ChangeOp.upsert);
    });

    test('creating, relinking and deleting a note are logged', () async {
      store.db.execute(
        "INSERT INTO entries(id,project_id,kind,title,data) VALUES('e','p','claim','E','{}')",
      );
      await store.write(() => store.saveNote('d', 'p1', '批注'));
      final id = store.notes('d').single.id;
      expect(log('note').where((r) => r.id == id).map((r) => r.op), [
        ChangeOp.upsert,
      ]);
      await store.write(() => store.setNoteEntry(id, 'e'));
      expect(log('note').where((r) => r.id == id).map((r) => r.op), [
        ChangeOp.upsert,
        ChangeOp.upsert,
      ]);
      store.db.execute('DELETE FROM notes WHERE id=?', [id]);
      expect(log('note').where((r) => r.id == id).last.op, ChangeOp.delete);
    });

    test('upgrading v9 seeds existing projects and notes', () {
      final old = migrated(version: 9);
      addTearDown(old.raw.close);
      project(old, 'p');
      old.raw.execute(
        "INSERT INTO documents(id,project_id,relative_path,snapshot_path,sha256) VALUES('d','p','a.md','a.md','h')",
      );
      old.raw.execute(
        "INSERT INTO notes(id,document_id,locator,text) VALUES('n','d','l','旧批注')",
      );
      expect(
        ModuleChangeLog.since(old.raw, 'research', 0).where(
          (c) => c.ref.objectType == 'project' || c.ref.objectType == 'note',
        ),
        isEmpty,
      );
      ResearchModule().schema.migrations[9].migrate(old.raw);
      final seeded = {
        for (final c in ModuleChangeLog.since(old.raw, 'research', 0))
          if (c.ref.objectType == 'project' || c.ref.objectType == 'note')
            c.ref.objectType: c.ref.objectId,
      };
      expect(seeded, {'project': 'p', 'note': 'n'});
    });

    test('the schema is version 10 and the new migration is the last', () {
      final schema = ResearchModule().schema;
      expect(schema.version, 10);
      expect(schema.migrations.last.version, 10);
      expect(schema.migrations.last.definitionDigest, 'research-schema-10');
    });
  });
}

class ObjectChangeRow {
  const ObjectChangeRow(this.id, this.op, this.summary);
  final String id;
  final ChangeOp op;
  final String summary;
}
