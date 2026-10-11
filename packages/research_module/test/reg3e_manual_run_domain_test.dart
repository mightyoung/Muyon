import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/research_module.dart';

import 'change_log_test.dart' show migrated, project;
import 'research_runtime_test.dart' show TestDatabase;

void main() {
  late Directory root;
  late TestDatabase db;
  late WorkbenchStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('reg3e-domain-');
    db = migrated(version: 10);
    store = WorkbenchStore.attach(
      rootPath: root.path,
      database: db.raw,
      managed: db,
    );
    project(db, 'p');
    project(db, 'q');
  });
  tearDown(() {
    db.raw.close();
    root.deleteSync(recursive: true);
  });

  ResearchTask task(String projectId) => store.saveTask(
    projectId: projectId,
    title: 'Manual experiment',
    goal: 'Record observations',
    spec: {},
  );

  List<Map<String, Object?>> runChanges() => [
    for (final row in db.raw.select(
      "SELECT * FROM ${ModuleChangeLog.table} WHERE object_type='run' ORDER BY sequence",
    ))
      Map<String, Object?>.from(row),
  ];

  Map<String, Object?> runRow(String id) => Map<String, Object?>.from(
    db.raw.select('SELECT * FROM runs WHERE id=?', [id]).single,
  );

  group('REG-3e manual run creation', () {
    test('an old task revision is rejected without a run or change log', () {
      final first = task('p');
      store.saveTask(
        id: first.id,
        projectId: 'p',
        title: 'Revised',
        goal: first.goal,
        spec: first.spec,
        expectedRevision: first.revision,
      );
      final before = runChanges();

      expect(() => store.startManualRun(first), throwsStateError);

      expect(db.raw.select('SELECT * FROM runs'), isEmpty);
      expect(runChanges(), before);
    });

    test(
      'latest revision creates only a local record and logs its creation',
      () {
        final sentinel = File('${root.path}/command-must-not-run');
        final first = task('p');
        final latest = store.saveTask(
          id: first.id,
          projectId: 'p',
          title: 'Revised',
          goal: first.goal,
          spec: {'command': 'touch "${sentinel.path}"'},
          expectedRevision: first.revision,
        );
        final before = runChanges().length;

        final run = store.scoped('p').startManualRun(latest);

        expect(run.taskId, latest.id);
        expect(run.taskRevision, latest.revision);
        expect(run.status, 'running');
        expect(run.accepted, isFalse);
        expect(run.data['_localManual'], isTrue);
        expect(run.data['logs'], isEmpty);
        expect(run.data['artifacts'], isEmpty);
        expect(sentinel.existsSync(), isFalse);
        expect(runChanges().length, before + 1);
        expect(runChanges().last['object_id'], run.id);
        expect(runChanges().last['op'], 'upsert');
      },
    );

    test('a foreign task is rejected by the scoped domain', () {
      final foreign = task('q');
      final before = runChanges();

      expect(() => store.scoped('p').startManualRun(foreign), throwsStateError);

      expect(db.raw.select('SELECT * FROM runs'), isEmpty);
      expect(runChanges(), before);
    });

    test('an unknown task revision is rejected without writes', () {
      const missing = ResearchTask(
        id: 'missing',
        projectId: 'p',
        title: 'Missing',
        goal: '',
        revision: 1,
        spec: {},
      );

      expect(() => store.startManualRun(missing), throwsStateError);

      expect(db.raw.select('SELECT * FROM runs'), isEmpty);
      expect(runChanges(), isEmpty);
    });
  });

  group('REG-3e manual run update', () {
    test('a scoped domain rejects a foreign manual run without writes', () {
      final run = store.startManualRun(task('q'));
      final before = runRow(run.id);
      final logs = runChanges();

      expect(
        () => store
            .scoped('p')
            .updateManualRun(
              run.id,
              status: 'completed',
              metrics: {'score': 1},
              log: 'Foreign modification',
              conclusion: 'Must be refused',
            ),
        throwsStateError,
      );

      expect(runRow(run.id), before);
      expect(runChanges(), logs);
    });

    test('an imported run cannot be edited as a local manual run', () {
      final selected = task('p');
      db.raw.execute('INSERT INTO runs VALUES(?,?,?,?,?,?)', [
        'imported',
        selected.id,
        selected.revision,
        'running',
        0,
        jsonEncode({'status': 'running', 'logs': <String>[]}),
      ]);
      final before = runRow('imported');
      final logs = runChanges();

      expect(
        () => store
            .scoped('p')
            .updateManualRun(
              'imported',
              status: 'completed',
              metrics: {},
              log: 'Cannot edit an import',
              conclusion: '',
            ),
        throwsStateError,
      );

      expect(runRow('imported'), before);
      expect(runChanges(), logs);
    });

    test(
      'legacy imported spoof marker is rejected by the domain without writes',
      () async {
        final t = task('p');
        final file = File('${root.path}/spoof.json')
          ..writeAsStringSync(
            jsonEncode({
              'runId': 'spoof',
              'taskId': t.id,
              'taskRevision': t.revision,
              'status': 'running',
              'metrics': {},
              'logs': [],
              'artifacts': [],
              '_localManual': true,
            }),
          );
        final imported = await ResearchExchange(store).importResult(file.path);
        final data = {...imported.data, '_localManual': true};
        await store.write(
          () => db.raw.execute('UPDATE runs SET data=? WHERE id=?', [
            jsonEncode(data),
            imported.id,
          ]),
        );
        final before = runRow(imported.id);
        final changes = runChanges();
        expect(
          () => store.updateManualRun(
            imported.id,
            status: 'completed',
            metrics: {'score': 7},
            log: 'new log',
            conclusion: 'new conclusion',
          ),
          throwsStateError,
        );
        expect(runRow(imported.id), before);
        expect(runChanges(), changes);
      },
    );

    test('an unsupported status is rejected without writes', () {
      final run = store.startManualRun(task('p'));
      final before = runRow(run.id);
      final logs = runChanges();

      expect(
        () => store.updateManualRun(
          run.id,
          status: 'accepted',
          metrics: {},
          log: '',
          conclusion: '',
        ),
        throwsFormatException,
      );

      expect(runRow(run.id), before);
      expect(runChanges(), logs);
    });

    for (final status in ['running', 'completed', 'failed', 'blocked']) {
      test('$status is allowed for a local manual run and logs the update', () {
        final run = store.startManualRun(task('p'));
        final before = runChanges().length;

        final updated = store
            .scoped('p')
            .updateManualRun(
              run.id,
              status: status,
              metrics: {'score': 2},
              log: ' Observation ',
              conclusion: ' Result ',
            );

        expect(updated.status, status);
        expect(updated.data['_localManual'], isTrue);
        expect(updated.data['metrics'], {'score': 2});
        expect(updated.data['logs'], ['Observation']);
        expect(updated.data['conclusion'], 'Result');
        expect(runChanges().length, before + 1);
        expect(runChanges().last['object_id'], run.id);
        expect(runChanges().last['op'], 'upsert');
      });
    }
  });
}
