import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/research_module.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:research_module/src/core/lan_transfer.dart';

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
    'hosted sender and receiver reject before any file or network effect',
    () async {
      final staging = Directory('${temp.path}/lan-outbox');
      final destination = Directory('${temp.path}/lan-inbox');
      await expectLater(
        LanShareSession.start(
          file: File('${temp.path}/missing.zip'),
          stagingDirectory: staging,
          bindAddress: InternetAddress.loopbackIPv4,
        ),
        throwsStateError,
      );
      await expectLater(
        LanTransferReceiver.receive(
          url: Uri.parse('http://127.0.0.1:1'),
          code: 'code',
          destination: destination,
        ),
        throwsStateError,
      );
      expect(staging.existsSync(), false);
      expect(destination.existsSync(), false);
      expect(() => WorkbenchStore.open(temp.path), throwsStateError);
      expect(File('${temp.path}/workbench.sqlite').existsSync(), false);
    },
  );

  test(
    'host uses injected connection across scoped sessions and disposal',
    () async {
      expect(identical(runtime.store.db, database.raw), true);
      final prepared = await prepare();
      await runtime.commitImport(prepared, intent(prepared));
      final session = await runtime.openSession(binding);
      expect(identical(session.store.db, database.raw), true);
      session.store.close();
      await session.dispose();
      expect(database.raw.select('SELECT * FROM projects'), hasLength(1));
      expect(File('${temp.path}/workbench.sqlite').existsSync(), false);
    },
  );

  testWidgets('object pages recheck scope existence digest and disposal', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final prepared = await prepare();
      await runtime.commitImport(prepared, intent(prepared));
    });
    final session = await runtime.openSession(binding);
    final doc = session.services.documents().single;
    ObjectRef ref({String? project = 'native-a', String? id, String? digest}) =>
        ObjectRef(
          moduleId: 'research',
          objectType: 'document',
          objectId: id ?? doc.id,
          nativeProjectId: project,
          contentDigest: digest,
        );
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    final page = session.objectPage(context, ref(digest: doc.sha256));
    expect(page, isA<ReaderPage>());
    expect((page! as ReaderPage).document.id, doc.id);
    expect(session.objectPage(context, ref(project: 'other')), isNull);
    expect(session.objectPage(context, ref(id: 'missing')), isNull);
    expect(session.objectPage(context, ref(digest: 'stale')), isNull);
    expect(await session.resolve(ref(digest: 'stale')), isNull);
    await session.dispose();
    expect(() => session.objectPage(context, ref()), throwsStateError);
  });

  test(
    'resolve supports scoped cards tasks runs and outline with exact revisions',
    () async {
      final prepared = await prepare();
      await runtime.commitImport(prepared, intent(prepared));
      final store = runtime.store;
      final task = await store.write(
        () => store.saveTask(
          projectId: 'native-a',
          title: 'v1',
          goal: '',
          spec: {},
        ),
      );
      await store.write(
        () => store.saveTask(
          id: task.id,
          projectId: 'native-a',
          title: 'v2',
          goal: '',
          spec: {},
        ),
      );
      final run = await store.write(() => store.startManualRun(task));
      final section = await store.write(
        () => store.addSection('native-a', 'Section'),
      );
      final card = await CardStore(database).save(
        projectId: 'native-a',
        cardId: 'c',
        expectedHead: null,
        bodyMarkdown: 'Card',
      );
      final session = await runtime.openSession(binding);
      ObjectRef ref(
        String type,
        String id, {
        String? revision,
        String? digest,
        String project = 'native-a',
      }) => ObjectRef(
        moduleId: 'research',
        objectType: type,
        objectId: id,
        nativeProjectId: project,
        revisionRef: revision,
        contentDigest: digest,
      );
      expect(
        (await session.resolve(ref('task', task.id, revision: '1')))!.title,
        'v1',
      );
      expect((await session.resolve(ref('task', task.id)))!.title, 'v2');
      expect(
        await session.resolve(ref('task', task.id, revision: '999')),
        isNull,
      );
      expect(await session.resolve(ref('run', run.id)), isNotNull);
      expect(await session.resolve(ref('section', section.id)), isNotNull);
      expect(
        await session.resolve(
          ref(
            'card',
            'c',
            revision: card.revision.revisionId,
            digest: card.revision.contentDigest,
          ),
        ),
        isNotNull,
      );
      expect(
        await session.resolve(ref('card', 'c', revision: 'wrong')),
        isNull,
      );
      expect(await session.resolve(ref('card', 'c', project: 'other')), isNull);
    },
  );

  test(
    'canonical document versions and soft deletion publish current identity',
    () async {
      final prepared = await prepare();
      await runtime.commitImport(prepared, intent(prepared));
      final cards = CardStore(database);
      final cursor = ModuleChangeLog.since(
        database.raw,
        'research',
        0,
      ).last.sequence;
      final key = await cards.registerDocument(
        projectId: 'native-a',
        localDocumentId: 'canonical',
        bytes: [1],
        fileName: 'source.pdf',
      );
      var changes = ModuleChangeLog.since(database.raw, 'research', cursor);
      expect(changes, hasLength(1));
      expect(changes.single.ref.objectId, 'canonical');
      expect(changes.single.summary, 'source.pdf');
      final oldDigest = changes.single.ref.contentDigest;
      await cards.registerDocument(
        projectId: 'native-a',
        localDocumentId: 'canonical',
        bytes: [2],
        fileName: 'updated.pdf',
      );
      changes = ModuleChangeLog.since(database.raw, 'research', cursor);
      expect(changes.last.op, ChangeOp.upsert);
      expect(changes.last.ref.contentDigest, isNot(oldDigest));
      await cards.deleteDocument('native-a', key);
      changes = ModuleChangeLog.since(database.raw, 'research', cursor);
      expect(changes.last.op, ChangeOp.delete);
      expect(changes.last.summary, 'updated.pdf');
    },
  );

  test(
    'task revision deletion keeps latest task until final revision is gone',
    () async {
      final prepared = await prepare();
      await runtime.commitImport(prepared, intent(prepared));
      final store = runtime.store;
      final task = await store.write(
        () => store.saveTask(
          projectId: 'native-a',
          title: 'First',
          goal: '',
          spec: {},
        ),
      );
      await store.write(
        () => store.saveTask(
          id: task.id,
          projectId: 'native-a',
          title: 'Latest',
          goal: '',
          spec: {},
        ),
      );
      await store.write(
        () => database.raw.execute(
          'DELETE FROM tasks WHERE id=? AND revision=1',
          [task.id],
        ),
      );
      var changes = ModuleChangeLog.since(database.raw, 'research', 0);
      expect(changes.last.op, ChangeOp.upsert);
      expect(changes.last.summary, 'Latest');
      expect(changes.last.ref.revisionRef, '2');
      await store.write(
        () => database.raw.execute('DELETE FROM tasks WHERE id=?', [task.id]),
      );
      changes = ModuleChangeLog.since(database.raw, 'research', 0);
      expect(changes.last.op, ChangeOp.delete);
    },
  );

  testWidgets(
    'scope and version checks cover reused local IDs and unavailable focused pages',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      await tester.runAsync(() async {
        database.raw.execute(
          "INSERT INTO projects(id,title,question,next_step) VALUES('native-a','A','',''),('native-b','B','','')",
        );
        database.raw.execute(
          "INSERT INTO documents(id,project_id,relative_path,snapshot_path,sha256) VALUES('doc-a','native-a','a.md','a.md','hash-a'),('doc-b','native-b','b.md','b.md','hash-b')",
        );
        database.raw.execute(
          "INSERT INTO entries VALUES('entry-a','native-a','claims','Entry A','{}')",
        );
        final cards = CardStore(database);
        final cardA = await cards.save(
          projectId: 'native-a',
          cardId: 'same-card',
          expectedHead: null,
          bodyMarkdown: 'Card A',
        );
        final cardB = await cards.save(
          projectId: 'native-b',
          cardId: 'same-card',
          expectedHead: null,
          bodyMarkdown: 'Card B',
        );
        await cards.registerDocument(
          projectId: 'native-a',
          localDocumentId: 'same-doc',
          bytes: [1],
          fileName: 'A.pdf',
        );
        final docB = await cards.registerDocument(
          projectId: 'native-b',
          localDocumentId: 'same-doc',
          bytes: [2],
          fileName: 'B.pdf',
        );
        final task = await runtime.store.write(
          () => runtime.store.saveTask(
            projectId: 'native-a',
            title: 'Task',
            goal: '',
            spec: {},
          ),
        );
        final run = await runtime.store.write(
          () => runtime.store.startManualRun(task),
        );
        final section = await runtime.store.write(
          () => runtime.store.addSection('native-a', 'Section'),
        );
        await runtime.store.write(
          () => runtime.store.cite(section.id, 'entry-a'),
        );
        final outlineId =
            database.raw.select('SELECT id FROM outline').single['id']
                as String;
        final sessionA = await runtime.openSession(binding);
        final sessionB = await runtime.openSession(
          const WorkspaceBinding(
            workspaceId: 'w-b',
            moduleId: 'research',
            nativeProjectId: 'native-b',
          ),
        );
        ObjectRef ref(
          String type,
          String id, {
          String project = 'native-a',
          String module = 'research',
          String? revision,
          String? digest,
        }) => ObjectRef(
          moduleId: module,
          objectType: type,
          objectId: id,
          nativeProjectId: project,
          revisionRef: revision,
          contentDigest: digest,
        );
        expect(
          (await sessionA.resolve(ref('card', 'same-card')))!.title,
          'Card A',
        );
        expect(
          (await sessionB.resolve(
            ref('card', 'same-card', project: 'native-b'),
          ))!.title,
          'Card B',
        );
        expect(
          (await sessionA.resolve(ref('document', 'same-doc')))!.title,
          'A.pdf',
        );
        expect(
          (await sessionB.resolve(
            ref('document', 'same-doc', project: 'native-b'),
          ))!.title,
          'B.pdf',
        );
        expect(
          await sessionA.resolve(
            ref('card', 'same-card', revision: cardB.revision.revisionId),
          ),
          isNull,
        );
        expect(
          await sessionA.resolve(
            ref('card', 'same-card', digest: cardB.revision.contentDigest),
          ),
          isNull,
        );
        expect(
          await sessionA.resolve(
            ref('card', 'same-card', revision: cardA.revision.revisionId),
          ),
          isNotNull,
        );
        for (final object in [
          ref('document', 'doc-a'),
          ref('document', 'same-doc'),
          ref('card', 'same-card'),
          ref('entry', 'entry-a'),
          ref('task', task.id),
          ref('run', run.id),
          ref('section', section.id),
          ref('outline', outlineId),
        ]) {
          expect(await sessionA.resolve(object), isNotNull);
          expect(await sessionB.resolve(object), isNull);
          final wrongModule = ref(
            object.objectType,
            object.objectId,
            module: 'inquiry',
          );
          expect(await sessionA.resolve(wrongModule), isNull);
          expect(sessionA.objectPage(context, wrongModule), isNull);
          expect(sessionB.objectPage(context, object), isNull);
          expect(
            await sessionA.resolve(ref(object.objectType, 'missing')),
            isNull,
          );
          expect(
            sessionA.objectPage(context, ref(object.objectType, 'missing')),
            isNull,
          );
          expect(
            await sessionA.resolve(
              ref(object.objectType, object.objectId, revision: 'invalid'),
            ),
            isNull,
          );
          expect(
            await sessionA.resolve(
              ref(object.objectType, object.objectId, digest: 'invalid'),
            ),
            isNull,
          );
          if (object.objectType == 'document') {
            // 'doc-a' is this session's document (asserted below); 'same-doc'
            // belongs to the other project, so it has no page here.
            expect(
              sessionA.objectPage(context, object),
              object.objectId == 'same-doc' ? isNull : isA<ReaderPage>(),
            );
          } else {
            expect(
              sessionA.objectPage(context, object)?.runtimeType,
              switch (object.objectType) {
                'entry' => ResearchEntryPage,
                'outline' => ResearchOutlinePage,
                'section' => ResearchSectionPage,
                'task' => ResearchTaskPage,
                'run' => ResearchRunPage,
                'card' => ResearchCardPage,
                _ => null,
              },
              reason: object.objectType,
            );
          }
        }
        expect(
          (sessionA.objectPage(context, ref('document', 'doc-a'))!
                  as ReaderPage)
              .document
              .projectId,
          'native-a',
        );
        await cards.deleteDocument('native-b', docB);
        expect(
          await sessionB.resolve(
            ref('document', 'same-doc', project: 'native-b'),
          ),
          isNull,
        );
        await runtime.store.write(
          () => database.raw.execute("DELETE FROM documents WHERE id='doc-a'"),
        );
        expect(await sessionA.resolve(ref('document', 'doc-a')), isNull);
        expect(sessionA.objectPage(context, ref('document', 'doc-a')), isNull);
      });
    },
  );

  test(
    'v9 appends the projection migration without changing prior versions',
    () {
      final schema = ResearchModule().schema;
      expect(schema.version, 9);
      expect(schema.definitionDigest, 'research-schema-9');
      expect(
        schema.migrations.map((m) => m.version),
        orderedEquals(List.generate(9, (i) => i + 1)),
      );
      expect(
        database.raw.select(
          "SELECT name FROM sqlite_master WHERE name='muyon_change_log'",
        ),
        hasLength(1),
      );
    },
  );

  test('host import emits same-transaction document changes once', () async {
    final prepared = await prepare();
    await runtime.commitImport(prepared, intent(prepared));
    final changes = ModuleChangeLog.since(database.raw, 'research', 0);
    final doc = runtime.store.documents('native-a').single;
    final change = changes.singleWhere((c) => c.ref.objectType == 'document');
    expect(change.ref.objectId, doc.id);
    expect(change.ref.nativeProjectId, 'native-a');
    expect(change.summary, 'paper.md');
    expect(change.op, ChangeOp.upsert);
    await runtime.commitImport(prepared, intent(prepared));
    expect(
      ModuleChangeLog.since(database.raw, 'research', 0).length,
      changes.length,
    );
    File('${temp.path}/input/claims.jsonl').writeAsStringSync('{broken');
    final bad = await prepare(target: const ImportTarget.refresh(binding));
    await expectLater(
      runtime.commitImport(bad, intent(bad, 'bad')),
      throwsFormatException,
    );
    expect(
      ModuleChangeLog.since(database.raw, 'research', 0).length,
      changes.length,
    );
  });

  test(
    'domain changes include summaries revisions deletes and rollback',
    () async {
      final prepared = await prepare();
      await runtime.commitImport(prepared, intent(prepared));
      final scoped = runtime.store.scoped('native-a');
      await scoped.write(() {
        database.raw.execute(
          "INSERT INTO entries VALUES('e','native-a','claims','Evidence','{}')",
        );
        final task = scoped.saveTask(
          projectId: 'native-a',
          title: 'Experiment',
          goal: '',
          spec: {},
        );
        scoped.startManualRun(task);
        scoped.addOutline('native-a', 'Argument', 'e');
      });
      final card = await CardStore(database).save(
        projectId: 'native-a',
        cardId: 'card',
        expectedHead: null,
        bodyMarkdown: 'Card body',
      );
      final changes = ModuleChangeLog.since(database.raw, 'research', 0);
      for (final type in [
        'document',
        'entry',
        'task',
        'run',
        'outline',
        'section',
        'card',
      ]) {
        final change = changes.lastWhere((c) => c.ref.objectType == type);
        expect(change.ref.nativeProjectId, 'native-a');
        expect(change.summary, isNotEmpty, reason: type);
      }
      final cardChange = changes.lastWhere((c) => c.ref.objectType == 'card');
      expect(cardChange.ref.objectId, 'card');
      expect(cardChange.ref.revisionRef, card.revision.revisionId);
      expect(cardChange.ref.contentDigest, card.revision.contentDigest);
      await expectLater(
        scoped.write(() {
          database.raw.execute(
            "UPDATE entries SET title='rolled back' WHERE id='e'",
          );
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(
        ModuleChangeLog.since(database.raw, 'research', 0).length,
        changes.length,
      );
      await scoped.write(
        () => database.raw.execute("DELETE FROM entries WHERE id='e'"),
      );
      final removed = ModuleChangeLog.since(
        database.raw,
        'research',
        changes.last.sequence,
      ).single;
      expect(removed.op, ChangeOp.delete);
      expect(removed.summary, 'Evidence');
    },
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
      final senderRoot = Directory.systemTemp.createTempSync(
        'research-sender-',
      );
      addTearDown(() => senderRoot.deleteSync(recursive: true));
      final sender = WorkbenchStore.open(senderRoot.path);
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
