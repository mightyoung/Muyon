import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muspace_module_api/muspace_module_api.dart';
import 'package:research_module/research_module.dart';
import 'package:sqlite3/sqlite3.dart';

class TestDatabase implements ManagedDatabase {
  TestDatabase(this.raw);
  @override
  final Database raw;
  Future<void> _tail = Future.value();
  @override
  Future<T> write<T>(T Function(Database) body) {
    final result = _tail.then((_) {
      raw.execute('BEGIN IMMEDIATE');
      try {
        final value = body(raw);
        raw.execute('COMMIT');
        return value;
      } catch (_) {
        raw.execute('ROLLBACK');
        rethrow;
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}

class TestFiles implements ModuleFiles {
  TestFiles(this.rootPath);
  @override
  final String rootPath;
  @override
  Future<SelectedInput> freeze(SelectedInput input) async => input;
}

void main() {
  late Directory temp;
  late TestDatabase database;
  late ModuleResources resources;
  late ResearchRuntime runtime;
  const binding = WorkspaceBinding(
    workspaceId: 'workspace-a',
    moduleId: 'research',
    nativeProjectId: 'native-a',
  );
  setUp(() async {
    temp = Directory.systemTemp.createTempSync('research-runtime-');
    database = TestDatabase(sqlite3.openInMemory());
    database.raw.execute('PRAGMA foreign_keys=ON');
    for (final migration in ResearchModule().schema.migrations) {
      migration.migrate(database.raw);
    }
    resources = ModuleResources(
      database: database,
      files: TestFiles(temp.path),
      capabilities: CapabilityRegistry().forModule('research', allowed: {}),
    );
    runtime = await ResearchModule().activate(resources);
  });
  tearDown(() {
    database.raw.close();
    temp.deleteSync(recursive: true);
  });
  Future<PreparedImport> prepare({
    ImportTarget target = const ImportTarget.create(binding),
    String text = '# Evidence',
  }) async {
    final source = Directory('${temp.path}/input')..createSync();
    File('${source.path}/paper.md').writeAsStringSync(text);
    return runtime.prepareImport(
      SelectedInput(path: source.path, displayName: 'Research'),
      target,
    );
  }

  ImportIntent intent(
    PreparedImport prepared, [
    String operationId = 'operation-1',
  ]) => ImportIntent(
    operationId: operationId,
    workspaceId: prepared.target.binding.workspaceId,
    moduleId: 'research',
    targetProjectId: prepared.target.binding.nativeProjectId,
    kind: prepared.target.kind,
    inputDigest: prepared.inputDigest,
    stagingToken: prepared.stagingToken,
  );

  test(
    'prepare is DB-free; concurrent commit and restart receipt are idempotent',
    () async {
      final prepared = await prepare();
      expect(runtime.store.projects(), isEmpty);
      final operation = intent(prepared);
      await Future.wait([
        runtime.commitImport(prepared, operation),
        runtime.commitImport(prepared, operation),
      ]);
      expect(runtime.store.projects().single.id, 'native-a');
      expect(database.raw.select('SELECT * FROM change_log'), hasLength(1));
      final reopened = await ResearchModule().activate(resources);
      expect(
        (await reopened.receipt(operation.operationId))!.targetProjectId,
        'native-a',
      );
      expect(
        (await reopened.commitImport(prepared, operation)).operationId,
        operation.operationId,
      );
      final second = await prepare(
        target: const ImportTarget.refresh(binding),
        text: '# Revised',
      );
      await expectLater(
        runtime.commitImport(second, intent(second)),
        throwsStateError,
      );
      expect(runtime.store.documents('native-a'), hasLength(1));
    },
  );

  test('prepared snapshot survives source edits and runtime restart', () async {
    final prepared = await prepare();
    File('${temp.path}/input/paper.md').writeAsStringSync('changed original');
    final reopened = await ResearchModule().activate(resources);
    await reopened.commitImport(prepared, intent(prepared));
    final doc = reopened.store.documents('native-a').single;
    expect(File(doc.absolutePath).readAsStringSync(), '# Evidence');
  });

  test(
    'bad refresh rolls back and does not erase an independent note',
    () async {
      final created = await prepare();
      await runtime.commitImport(created, intent(created));
      final doc = runtime.store.documents('native-a').single;
      final scoped = runtime.store.scoped('native-a');
      await scoped.write(() => scoped.saveNote(doc.id, 'page 1', 'retain me'));
      File('${temp.path}/input/claims.jsonl').writeAsStringSync('{broken');
      final bad = await prepare(target: const ImportTarget.refresh(binding));
      await expectLater(
        runtime.commitImport(bad, intent(bad, 'bad')),
        throwsFormatException,
      );
      expect(scoped.notes(doc.id).single.text, 'retain me');
      expect(await runtime.receipt('bad'), isNull);
      expect(database.raw.select('SELECT * FROM change_log'), hasLength(1));
    },
  );

  test(
    'scoped store rejects foreign documents tasks runs and outline',
    () async {
      final a = await prepare();
      await runtime.commitImport(a, intent(a));
      const b = WorkspaceBinding(
        workspaceId: 'workspace-b',
        moduleId: 'research',
        nativeProjectId: 'native-b',
      );
      final next = await prepare(target: const ImportTarget.create(b));
      await runtime.commitImport(next, intent(next, 'operation-2'));
      final foreign = runtime.store.documents('native-b').single;
      final scoped = runtime.store.scoped('native-a');
      expect(() => scoped.documents('native-b'), throwsStateError);
      expect(() => scoped.saveNote(foreign.id, '', 'wrong'), throwsStateError);
      final task = runtime.store.saveTask(
        projectId: 'native-b',
        title: 'Task',
        goal: '',
        spec: {},
      );
      final run = runtime.store.startManualRun(task);
      expect(() => scoped.acceptRun(run.id), throwsStateError);
      expect(
        () => scoped.taskRevision(task.id, task.revision),
        throwsStateError,
      );
      final section = runtime.store.addSection('native-b', 'Foreign');
      expect(() => scoped.deleteSection(section.id), throwsStateError);
      final session = await runtime.openSession(binding);
      expect(
        await session.resolve(
          ObjectRef(
            moduleId: 'research',
            objectType: 'document',
            objectId: foreign.id,
            nativeProjectId: 'native-a',
          ),
        ),
        isNull,
      );
      await session.dispose();
      await expectLater(
        session.resolve(
          const ObjectRef(
            moduleId: 'research',
            objectType: 'entry',
            objectId: 'x',
            nativeProjectId: 'native-a',
          ),
        ),
        throwsStateError,
      );
      scoped.close();
      expect(database.raw.select('SELECT 1'), hasLength(1));
    },
  );

  test(
    'task prepare preserves native identity and receipt survives restart',
    () async {
      final sender = WorkbenchStore.open('${temp.path}/sender');
      sender.db.execute(
        "INSERT INTO projects(id,title,question,next_step) VALUES('native-a','Sender','','')",
      );
      final task = sender.saveTask(
        projectId: 'native-a',
        title: 'External task',
        goal: 'Measure',
        spec: {
          'unknown': {'preserved': true},
        },
      );
      final zip = await ResearchExchange(sender)
          .exportTask(task, '${temp.path}/out');
      sender.close();
      final preparedTask = await runtime.prepareTask(
        SelectedInput(path: zip, displayName: 'task.zip'),
      );
      expect(preparedTask.projectId, 'native-a');
      expect(runtime.store.projects(), isEmpty);
      const wrong = WorkspaceBinding(
        workspaceId: 'wrong',
        moduleId: 'research',
        nativeProjectId: 'other',
      );
      await expectLater(
        runtime.prepareTaskImport(
          preparedTask,
          const ImportTarget.create(wrong),
        ),
        throwsStateError,
      );
      final prepared = await runtime.prepareTaskImport(
        preparedTask,
        const ImportTarget.create(binding),
      );
      final reopened = await ResearchModule().activate(resources);
      final receipt = await reopened.commitImport(prepared, intent(prepared));
      expect(receipt.result['taskId'], task.id);
      expect(
        reopened.store.taskRevision(task.id, task.revision)!.spec,
        task.spec,
      );
      expect(
        (await reopened.receipt(receipt.operationId))!.targetProjectId,
        'native-a',
      );
      final repeatedTask = await reopened.prepareTask(
        SelectedInput(path: zip, displayName: 'task.zip'),
      );
      final repeated = await reopened.prepareTaskImport(
        repeatedTask,
        const ImportTarget.refresh(binding),
      );
      await reopened.commitImport(repeated, intent(repeated, 'repeat-task'));
      expect(reopened.store.tasks('native-a'), hasLength(1));
    },
  );

  test(
    'modified staging is rejected before any project or receipt commits',
    () async {
      final prepared = await prepare();
      final path = runtime.store.resolvePath(prepared.stagingToken);
      File('$path/paper.md').writeAsStringSync('changed snapshot');
      await expectLater(
        runtime.commitImport(prepared, intent(prepared)),
        throwsStateError,
      );
      expect(runtime.store.projects(), isEmpty);
      expect(await runtime.receipt('operation-1'), isNull);
    },
  );
}
