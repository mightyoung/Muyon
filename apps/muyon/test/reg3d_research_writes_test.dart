import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/research_module.dart';
import 'package:sqlite3/sqlite3.dart';

/// REG-3d: research.list_notes / list_bindings and the writes update_project,
/// set_note_entry, create_task, revise_task and confirm_binding, on the same
/// declaration -> registrar -> prepare / one approval / invoke / receipt chain
/// as REG-3c. Every guard has a negative test that fails without it.
void main() {
  late Directory root;
  late MuyonHost host;
  var invocation = 0;
  const stale =
      '0000000000000000000000000000000000000000000000000000000000000000';

  setUp(() async {
    root = Directory.systemTemp.createTempSync('reg3d-');
    host = await MuyonHost.open(p.join(root.path, 'data'));
  });
  tearDown(() async {
    await host.close();
    root.deleteSync(recursive: true);
  });

  Database rawDb() => host.research!.resources.database.raw;

  Future<ObjectRef> current(String type, String id, String project) async {
    final session = await host.research!.openScopeSession();
    try {
      return (await session.resolve(
        ObjectRef(
          moduleId: 'research',
          objectType: type,
          objectId: id,
          nativeProjectId: project,
        ),
      ))!.ref;
    } finally {
      await session.dispose();
    }
  }

  Future<void> research() async {
    await host.activateResearch();
    final s = host.research!.store;
    await s.write(() {
      for (final row in [
        ['P', '研究', '问题', '下一步'],
        ['Q', '另一项目', '另一问题', ''],
      ]) {
        s.db.execute(
          'INSERT INTO projects(id,title,question,next_step) VALUES(?,?,?,?)',
          row,
        );
      }
      for (final row in [
        ['DP', 'P', 'a.md'],
        ['DQ', 'Q', 'b.md'],
      ]) {
        s.db.execute(
          'INSERT INTO documents(id,project_id,relative_path,snapshot_path,sha256) VALUES(?,?,?,?,?)',
          [row[0], row[1], row[2], row[2], 'h'],
        );
      }
      for (final row in [
        ['E', 'P', '证据'],
        ['E2', 'P', '另一证据'],
        ['EQ', 'Q', '越界证据'],
      ]) {
        s.db.execute(
          'INSERT INTO entries(id,project_id,kind,title,data) VALUES(?,?,?,?,?)',
          [row[0], row[1], 'claim', row[2], '{}'],
        );
      }
    });
  }

  ToolCallRequest request(
    String tool,
    Map<String, Object?> params,
    List<ObjectRef> refs,
  ) => ToolCallRequest(
    invocationId: 'reg3d-${++invocation}',
    toolId: tool,
    parameters: params,
    scope: AssistantScope.selectedObjects(refs),
  );

  Future<ToolCallResult> invokeApproved(
    ToolCallRequest call, {
    ToolCancellationToken? cancellation,
  }) async {
    final approval = await host.tools.approve(await host.tools.prepare(call));
    return host.tools.invoke(
      call.withApproval(approval),
      cancellation: cancellation,
    );
  }

  Future<void> refuses(ToolCallRequest call, void Function() unchanged) async {
    final denied = await invokeApproved(call);
    expect(
      denied.status,
      ToolCallStatus.failed,
      reason: '${call.toolId} ${call.parameters.keys} ${denied.summary}',
    );
    expect(denied.changes, isEmpty);
    expect(host.tools.receiptFor(call.invocationId)!.state, 'failed');
    unchanged();
  }

  Future<void> unapproved(
    ToolCallRequest call,
    void Function() unchanged,
  ) async {
    await expectLater(host.tools.invoke(call), throwsA(isA<Exception>()));
    expect(host.tools.receiptFor(call.invocationId), isNull);
    unchanged();
  }

  Future<ToolCallResult> confirmed(ToolCallRequest call) async {
    final result = await invokeApproved(call);
    expect(result.status, ToolCallStatus.succeeded, reason: result.summary);
    expect(result.changes, isNotEmpty);
    expect(host.tools.receiptFor(call.invocationId)!.state, 'succeeded');
    return result;
  }

  int lastSequence() {
    final changes = ModuleChangeLog.since(rawDb(), 'research', 0);
    return changes.isEmpty ? 0 : changes.last.sequence;
  }

  List<ModuleChange> logged(int after, String type, String id) => [
    for (final c in ModuleChangeLog.since(rawDb(), 'research', after))
      if (c.ref.objectType == type && c.ref.objectId == id) c,
  ];

  String projectDigest(String id) {
    final row = rawDb().select(
      'SELECT title,question,next_step FROM projects WHERE id=?',
      [id],
    ).single;
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([row['title'], row['question'], row['next_step']]),
          ),
        )
        .toString();
  }

  Future<String> noteId(String doc, String text) async {
    final s = host.research!.store;
    await s.write(() => s.saveNote(doc, 'l1', text));
    return s.notes(doc).firstWhere((n) => n.text == text).id;
  }

  Future<Map<String, Object?>> bindingRow(String doc, String paper) async {
    final listed = await host.tools.invoke(
      request(
        'research.list_bindings',
        {'project_id': 'P'},
        [await current('project', 'P', 'P')],
      ),
    );
    expect(listed.status, ToolCallStatus.succeeded, reason: listed.summary);
    return Map<String, Object?>.from(
      (listed.data['bindings'] as List).cast<Map>().firstWhere(
        (b) => b['documentId'] == doc && b['paperId'] == paper,
      ),
    );
  }

  Future<void> bind(String doc, String paper, {bool ambiguous = true}) async {
    final s = host.research!.store;
    await s.write(
      () => s.insertBinding(
        PaperBinding(
          documentId: doc,
          paperId: paper,
          paperRev: 1,
          method: 'manifest',
          hashOk: true,
          ambiguous: ambiguous,
        ),
      ),
    );
  }

  Future<ObjectRef> taskRef(String id) => current('task', id, 'P');

  Future<String> seedTask({String title = '任务'}) async {
    final s = host.research!.store;
    final task = await s.write(
      () => s.saveTask(
        projectId: 'P',
        title: title,
        goal: '目标',
        spec: {
          'source': {'kind': 'experiments', 'id': 'x1', 'rev': 1},
          'command': 'manual-only',
          'parameters': {'seed': 1},
        },
      ),
    );
    return task.id;
  }

  test('declarations: the seven operations register tools and actions', () {
    final module = ResearchModule();
    final operations = {for (final op in module.coverage.operations) op.id: op};
    const reads = {
      'research.query.notes': ['research.list_notes'],
      'research.query.bindings': ['research.list_bindings'],
    };
    const writes = {
      'research.project.save': ['research.update_project'],
      'research.note.set_entry': ['research.set_note_entry'],
      'research.task.save': ['research.create_task', 'research.revise_task'],
      'research.binding.confirm': ['research.confirm_binding'],
    };
    for (final entry in {...reads, ...writes}.entries) {
      expect(operations[entry.key]!.notExposed, isNull, reason: entry.key);
      expect(operations[entry.key]!.tools, entry.value, reason: entry.key);
      for (final tool in entry.value) {
        expect(
          module.ontology.actions
              .where((a) => a.tool == tool)
              .single
              .operationId,
          entry.key,
        );
      }
    }
    for (final entry in writes.entries) {
      for (final tool in entry.value) {
        expect(
          module.ontology.actions
              .singleWhere((a) => a.tool == tool)
              .description,
          '本机写入，宿主确认与回执',
        );
      }
    }
    for (final entry in reads.entries) {
      expect(
        module.ontology.actions
            .singleWhere((a) => a.tool == entry.value.single)
            .description,
        '本机只读，不修改科研库',
      );
    }
    // binding.insert stays closed (decision 6): imports own it.
    expect(operations['research.binding.insert']!.notExposed, isNotNull);
    expect(operations['research.binding.insert']!.tools, isEmpty);
  });

  group('reads', () {
    test('list_notes returns notes of a selected document with digests, nothing else', () async {
      await research();
      final a = await noteId('DP', '甲');
      await noteId('DQ', '越界批注');
      final document = await current('document', 'DP', 'P');
      final result = await host.tools.invoke(
        request('research.list_notes', {'document_id': 'DP'}, [document]),
      );
      expect(result.status, ToolCallStatus.succeeded, reason: result.summary);
      final notes = (result.data['notes'] as List).cast<Map>();
      expect(notes.map((n) => n['id']), [a]);
      expect(notes.single['text'], '甲');
      final ref = await current('note', a, 'P');
      expect(notes.single['digest'], ref.contentDigest);
    });

    test(
      'list_notes refuses a document outside the selection or project',
      () async {
        await research();
        await noteId('DQ', '越界批注');
        final own = await current('document', 'DP', 'P');
        final denied = await host.tools.invoke(
          request('research.list_notes', {'document_id': 'DQ'}, [own]),
        );
        expect(denied.status, ToolCallStatus.failed);
        expect(denied.data, isEmpty);
      },
    );

    test('list_bindings returns project bindings with a digest and refuses other projects', () async {
      await research();
      await bind('DP', 'x');
      await bind('DQ', 'z');
      final row = await bindingRow('DP', 'x');
      expect(row['ambiguous'], isTrue);
      expect(row['digest'], hasLength(64));
      final all = await host.tools.invoke(
        request(
          'research.list_bindings',
          {'project_id': 'P'},
          [await current('project', 'P', 'P')],
        ),
      );
      expect(
        (all.data['bindings'] as List).map((b) => (b as Map)['documentId']),
        ['DP'],
      );
      final denied = await host.tools.invoke(
        request(
          'research.list_bindings',
          {'project_id': 'Q'},
          [await current('project', 'P', 'P')],
        ),
      );
      expect(denied.status, ToolCallStatus.failed);
    });

    test(
      'read_object exposes the digest or revision a write must quote',
      () async {
        await research();
        final task = await seedTask();
        final project = await current('project', 'P', 'P');
        final read = await host.tools.invoke(
          request(
            'research.read_object',
            {'type': 'project', 'id': 'P'},
            [project],
          ),
        );
        expect(
          (read.data['object'] as Map)['contentDigest'],
          projectDigest('P'),
        );
        final ref = await taskRef(task);
        final readTask = await host.tools.invoke(
          request('research.read_object', {'type': 'task', 'id': task}, [ref]),
        );
        expect((readTask.data['object'] as Map)['revision'], 1);
      },
    );
  });

  group('update_project', () {
    Map<String, Object?> params(String digest, {String id = 'P'}) => {
      'project_id': id,
      'question': '新问题',
      'next_step': '新下一步',
      'expected_digest': digest,
    };
    void untouched() {
      final row = rawDb().select(
        'SELECT question,next_step FROM projects WHERE id=?',
        ['P'],
      ).single;
      expect((row['question'], row['next_step']), ('问题', '下一步'));
    }

    test(
      'writes once after confirmation, logs the project, and replays safely',
      () async {
        await research();
        final selected = await current('project', 'P', 'P');
        final before = lastSequence();
        final call = request(
          'research.update_project',
          params(projectDigest('P')),
          [selected],
        );
        final result = await confirmed(call);
        expect(result.changes.single.ref.objectType, 'project');
        final row = rawDb().select(
          'SELECT question,next_step FROM projects WHERE id=?',
          ['P'],
        ).single;
        expect((row['question'], row['next_step']), ('新问题', '新下一步'));
        final entries = logged(before, 'project', 'P');
        expect(entries, isNotEmpty);
        expect(entries.last.op, ChangeOp.upsert);
        final after = lastSequence();
        // The selected project changed with this write, so the same approved
        // request no longer resolves; it is refused without a second write.
        await expectLater(invokeApproved(call), throwsStateError);

        expect(
          lastSequence(),
          after,
          reason: 'replay must not write or log again',
        );
      },
    );

    test(
      'refuses without approval, outside the selection, and on a stale digest',
      () async {
        await research();
        final selected = await current('project', 'P', 'P');
        final other = await current('project', 'Q', 'Q');
        await unapproved(
          request('research.update_project', params(projectDigest('P')), [
            selected,
          ]),
          untouched,
        );
        await refuses(
          request('research.update_project', params(projectDigest('P')), [
            other,
          ]),
          untouched,
        );
        await refuses(
          request('research.update_project', params(stale), [selected]),
          untouched,
        );
        await refuses(
          request(
            'research.update_project',
            params(projectDigest('Q'), id: 'Q'),
            [selected],
          ),
          untouched,
        );
      },
    );

    test(
      'a write that raced the confirmation is refused, not merged',
      () async {
        await research();
        final selected = await current('project', 'P', 'P');
        final call = request(
          'research.update_project',
          params(projectDigest('P')),
          [selected],
        );
        final approval = await host.tools.approve(
          await host.tools.prepare(call),
        );
        final s = host.research!.store;
        await s.write(
          () => s.saveProject('P', question: '别处改的', nextStep: '别处'),
        );
        // The selected project no longer matches: refused before any write.
        await expectLater(
          host.tools.invoke(call.withApproval(approval)),
          throwsStateError,
        );
        final row = rawDb().select('SELECT question FROM projects WHERE id=?', [
          'P',
        ]).single;
        expect(row['question'], '别处改的');
      },
    );
  });

  group('set_note_entry', () {
    Map<String, Object?> params(String note, String? entry, String digest) => {
      'note_id': note,
      'entry_id': entry,
      'expected_digest': digest,
    };
    String? entryOf(String note) =>
        rawDb().select('SELECT entry_id FROM notes WHERE id=?', [
              note,
            ]).single['entry_id']
            as String?;

    test(
      'links and clears an entry once per confirmation and logs the note',
      () async {
        await research();
        final note = await noteId('DP', '甲');
        var ref = await current('note', note, 'P');
        final entry = await current('entry', 'E', 'P');
        final before = lastSequence();
        final link = request(
          'research.set_note_entry',
          params(note, 'E', ref.contentDigest!),
          [ref, entry],
        );
        final result = await confirmed(link);
        expect(result.changes.any((c) => c.ref.objectType == 'note'), isTrue);
        expect(entryOf(note), 'E');
        expect(logged(before, 'note', note), isNotEmpty);
        final after = lastSequence();
        await expectLater(invokeApproved(link), throwsStateError);
        expect(lastSequence(), after);
        ref = await current('note', note, 'P');
        await confirmed(
          request(
            'research.set_note_entry',
            params(note, null, ref.contentDigest!),
            [ref],
          ),
        );
        expect(entryOf(note), isNull);
      },
    );

    test('refuses approval gaps, scope gaps, a stale digest and another project\'s entry', () async {
      await research();
      final note = await noteId('DP', '甲');
      final ref = await current('note', note, 'P');
      final entry = await current('entry', 'E', 'P');
      final foreign = await current('entry', 'EQ', 'Q');
      void none() => expect(entryOf(note), isNull);
      await unapproved(
        request(
          'research.set_note_entry',
          params(note, 'E', ref.contentDigest!),
          [ref, entry],
        ),
        none,
      );
      // the entry is not part of the selection
      await refuses(
        request(
          'research.set_note_entry',
          params(note, 'E', ref.contentDigest!),
          [ref],
        ),
        none,
      );
      await refuses(
        request('research.set_note_entry', params(note, 'E', stale), [
          ref,
          entry,
        ]),
        none,
      );
      // both objects are selected but belong to different projects
      await refuses(
        request(
          'research.set_note_entry',
          params(note, 'EQ', ref.contentDigest!),
          [ref, foreign],
        ),
        none,
      );
    });

    test('refuses when the entry changed after the note was confirmed (in-transaction requireCurrent)', () async {
      await research();
      final note = await noteId('DP', '甲');
      final ref = await current('note', note, 'P');
      final entry = await current('entry', 'E', 'P');
      final call = request(
        'research.set_note_entry',
        params(note, 'E', ref.contentDigest!),
        [ref, entry],
      );
      await _queued(
        host,
        call,
        (db) {
          db.execute(
            "UPDATE entries SET data='{\"changed\":true}' WHERE id='E'",
          );
        },
        (result) {
          expect(result.status, isNot(ToolCallStatus.succeeded));
          expect(entryOf(note), isNull);
        },
      );
    });
  });

  group('create_task / revise_task', () {
    Map<String, Object?> created({Object? parameters}) => {
      'project_id': 'P',
      'title': '新任务',
      'goal': '目标',
      'parameters': parameters ?? {'seed': 7},
      'data_references': ['dataset:1'],
      'code_reference': 'commit:abc',
      'environment': 'python 3.11',
      'expected_results': ['scores.json'],
    };
    int taskCount() =>
        rawDb().select('SELECT COUNT(*) AS n FROM tasks').single['n'] as int;

    test(
      'create_task makes revision 1 with the whitelisted spec only',
      () async {
        await research();
        final selected = await current('project', 'P', 'P');
        final before = lastSequence();
        final call = request('research.create_task', created(), [selected]);
        final result = await confirmed(call);
        final change = result.changes.single.ref;
        expect(change.objectType, 'task');
        final task = host.research!.store.taskRevision(change.objectId, 1)!;
        expect(task.spec, {
          'parameters': {'seed': 7},
          'dataReferences': ['dataset:1'],
          'codeReference': 'commit:abc',
          'environment': 'python 3.11',
          'expectedResults': ['scores.json'],
        });
        expect(logged(before, 'task', change.objectId), isNotEmpty);
        final count = taskCount();
        await invokeApproved(call);
        expect(
          taskCount(),
          count,
          reason: 'replay must not create a second task',
        );
      },
    );

    test('create_task refuses scope gaps, missing approval, extra spec keys and oversize input', () async {
      await research();
      final selected = await current('project', 'P', 'P');
      final other = await current('project', 'Q', 'Q');
      await unapproved(
        request('research.create_task', created(), [selected]),
        () => expect(taskCount(), 0),
      );
      await refuses(
        request('research.create_task', created(), [other]),
        () => expect(taskCount(), 0),
      );
      for (final key in ['command', 'source', 'spec']) {
        await expectLater(
          host.tools.prepare(
            request(
              'research.create_task',
              {...created(), key: 'x'},
              [selected],
            ),
          ),
          throwsA(isA<Exception>()),
          reason: key,
        );
      }
      await refuses(
        request(
          'research.create_task',
          created(parameters: {'blob': 'x' * 9000}),
          [selected],
        ),
        () => expect(taskCount(), 0),
      );
      expect(taskCount(), 0);
    });

    test('revise_task appends a revision, keeps non-whitelisted spec keys and quotes the revision', () async {
      await research();
      final id = await seedTask();
      final ref = await taskRef(id);
      final before = lastSequence();
      final call = request(
        'research.revise_task',
        {
          'task_id': id,
          'expected_revision': 1,
          'title': '改名',
          'goal': '新目标',
          'parameters': {'seed': 2},
        },
        [ref],
      );
      final result = await confirmed(call);
      expect(result.changes.single.ref.objectId, id);
      final s = host.research!.store;
      expect(s.taskRevision(id, 2)!.title, '改名');
      expect(s.taskRevision(id, 2)!.spec['parameters'], {'seed': 2});
      expect(s.taskRevision(id, 2)!.spec['command'], 'manual-only');
      expect(s.taskRevision(id, 2)!.spec['source'], {
        'kind': 'experiments',
        'id': 'x1',
        'rev': 1,
      });
      expect(s.taskRevision(id, 1)!.title, '任务');
      expect(logged(before, 'task', id), isNotEmpty);
      await invokeApproved(call);
      expect(
        s.taskRevision(id, 3),
        isNull,
        reason: 'replay must not append again',
      );
    });

    test(
      'revise_task refuses stale revisions, other projects and approval gaps',
      () async {
        await research();
        final id = await seedTask();
        final ref = await taskRef(id);
        final otherProject = await current('project', 'Q', 'Q');
        final s = host.research!.store;
        Map<String, Object?> params(int rev) => {
          'task_id': id,
          'expected_revision': rev,
          'title': '改',
          'goal': 'g',
        };
        void still1() => expect(s.taskRevision(id, 2), isNull);
        await unapproved(
          request('research.revise_task', params(1), [ref]),
          still1,
        );
        await refuses(
          request('research.revise_task', params(1), [otherProject]),
          still1,
        );
        // the number quoted differs from the revision that was selected
        await refuses(
          request('research.revise_task', params(2), [ref]),
          still1,
        );
        await s.write(
          () => s.saveTask(
            id: id,
            projectId: 'P',
            title: '别人改',
            goal: 'g',
            spec: {},
          ),
        );
        // the selected ref and the quoted revision say 1, but 2 now exists
        await refuses(
          request('research.revise_task', params(1), [ref]),
          () => expect(s.taskRevision(id, 3), isNull),
        );
      },
    );

    test('revise_task refuses a revision appended after approval (in-transaction check)', () async {
      await research();
      final id = await seedTask();
      final ref = await taskRef(id);
      final call = request(
        'research.revise_task',
        {'task_id': id, 'expected_revision': 1, 'title': '我的修订', 'goal': 'g'},
        [ref],
      );
      await _queued(
        host,
        call,
        (db) {
          db.execute("INSERT INTO tasks VALUES(?,?,?,?,?,?)", [
            id,
            2,
            'P',
            '并发修订',
            'g',
            '{}',
          ]);
        },
        (result) {
          expect(result.status, isNot(ToolCallStatus.succeeded));
          final s = host.research!.store;
          expect(s.taskRevision(id, 2)!.title, '并发修订');
          expect(s.taskRevision(id, 3), isNull);
        },
      );
    });
  });

  group('confirm_binding', () {
    Map<String, Object?> params(String paper, String digest) => {
      'document_id': 'DP',
      'paper_id': paper,
      'expected_digest': digest,
    };
    List<Map> bindings() => rawDb()
        .select('SELECT * FROM paper_bindings ORDER BY paper_id')
        .map(Map.from)
        .toList();

    test(
      'confirms the chosen candidate once and drops its competitors',
      () async {
        await research();
        await bind('DP', 'x');
        await bind('DP', 'y');
        final row = await bindingRow('DP', 'y');
        final document = await current('document', 'DP', 'P');
        final call = request(
          'research.confirm_binding',
          params('y', row['digest'] as String),
          [document],
        );
        await confirmed(call);
        expect(bindings().map((b) => (b['paper_id'], b['ambiguous'])), [
          ('y', 0),
        ]);
        await invokeApproved(call);
        expect(bindings().length, 1);
      },
    );

    test('refuses a missing row, a settled row, a stale digest, approval gaps and other projects', () async {
      await research();
      await bind('DP', 'x');
      await bind('DP', 'y');
      await bind('DP', 'done', ambiguous: false);
      final x = await bindingRow('DP', 'x');
      final done = await bindingRow('DP', 'done');
      final document = await current('document', 'DP', 'P');
      final foreign = await current('document', 'DQ', 'Q');
      void intact() =>
          expect(bindings().map((b) => b['paper_id']), ['done', 'x', 'y']);
      await unapproved(
        request(
          'research.confirm_binding',
          params('x', x['digest'] as String),
          [document],
        ),
        intact,
      );
      await refuses(
        request(
          'research.confirm_binding',
          params('x', x['digest'] as String),
          [foreign],
        ),
        intact,
      );
      await refuses(
        request('research.confirm_binding', params('x', stale), [document]),
        intact,
      );
      await refuses(
        request(
          'research.confirm_binding',
          params('ghost', x['digest'] as String),
          [document],
        ),
        intact,
      );
      await refuses(
        request(
          'research.confirm_binding',
          params('done', done['digest'] as String),
          [document],
        ),
        intact,
      );
    });

    test(
      'refuses a binding that changed after approval (in-transaction check)',
      () async {
        await research();
        await bind('DP', 'x');
        await bind('DP', 'y');
        final row = await bindingRow('DP', 'x');
        final document = await current('document', 'DP', 'P');
        final call = request(
          'research.confirm_binding',
          params('x', row['digest'] as String),
          [document],
        );
        await _queued(
          host,
          call,
          (db) {
            db.execute(
              "UPDATE paper_bindings SET paper_rev=9 WHERE paper_id='x'",
            );
          },
          (result) {
            expect(result.status, isNot(ToolCallStatus.succeeded));
            expect(bindings().map((b) => b['ambiguous']), [1, 1]);
          },
        );
      },
    );
  });

  // checkBeforeEffect must run inside the queued transaction: a call that is
  // cancelled while its write waits in the queue must not write.
  group('cancellation while queued', () {
    Future<void> check(
      String name,
      Future<(ToolCallRequest, void Function())> Function() build,
    ) async {
      test('$name writes nothing when cancelled while queued', () async {
        await research();
        final (call, unchanged) = await build();
        final token = ToolCancellationToken();
        await _queued(host, call, (db) {}, (result) {
          expect(result.status, isNot(ToolCallStatus.succeeded));
          expect(result.changes, isEmpty);
          unchanged();
        }, cancel: token);
      });
    }

    check('update_project', () async {
      final ref = await current('project', 'P', 'P');
      return (
        request(
          'research.update_project',
          {
            'project_id': 'P',
            'question': 'x',
            'next_step': 'y',
            'expected_digest': projectDigest('P'),
          },
          [ref],
        ),
        () => expect(
          rawDb().select('SELECT question FROM projects WHERE id=?', [
            'P',
          ]).single['question'],
          '问题',
        ),
      );
    });
    check('set_note_entry', () async {
      final note = await noteId('DP', '甲');
      final ref = await current('note', note, 'P');
      final entry = await current('entry', 'E', 'P');
      return (
        request(
          'research.set_note_entry',
          {
            'note_id': note,
            'entry_id': 'E',
            'expected_digest': ref.contentDigest,
          },
          [ref, entry],
        ),
        () => expect(
          rawDb().select('SELECT entry_id FROM notes WHERE id=?', [
            note,
          ]).single['entry_id'],
          isNull,
        ),
      );
    });
    check('create_task', () async {
      final ref = await current('project', 'P', 'P');
      return (
        request(
          'research.create_task',
          {'project_id': 'P', 'title': 't', 'goal': 'g'},
          [ref],
        ),
        () => expect(
          rawDb().select('SELECT COUNT(*) AS n FROM tasks').single['n'],
          0,
        ),
      );
    });
    check('revise_task', () async {
      final id = await seedTask();
      final ref = await taskRef(id);
      return (
        request(
          'research.revise_task',
          {'task_id': id, 'expected_revision': 1, 'title': 't', 'goal': 'g'},
          [ref],
        ),
        () => expect(
          rawDb().select('SELECT COUNT(*) AS n FROM tasks').single['n'],
          1,
        ),
      );
    });
    check('confirm_binding', () async {
      await bind('DP', 'x');
      await bind('DP', 'y');
      final row = await bindingRow('DP', 'x');
      final document = await current('document', 'DP', 'P');
      return (
        request(
          'research.confirm_binding',
          {
            'document_id': 'DP',
            'paper_id': 'x',
            'expected_digest': row['digest'],
          },
          [document],
        ),
        () => expect(
          rawDb()
              .select(
                'SELECT COUNT(*) AS n FROM paper_bindings WHERE ambiguous=1',
              )
              .single['n'],
          2,
        ),
      );
    });
  });
}

/// Approves [call], holds the database so the tool's write has to queue, runs
/// [concurrent] in that gap (and cancels [cancel] if given), then lets it run.
Future<void> _queued(
  MuyonHost host,
  ToolCallRequest call,
  void Function(Database db) concurrent,
  void Function(ToolCallResult result) verify, {
  ToolCancellationToken? cancel,
}) async {
  final original = host.research!.resources;
  final observed = _ObservedWrite(original.database);
  host.modules.setRuntimeForTesting(
    'research',
    ResearchRuntime(
      ModuleResources(
        database: observed,
        files: original.files,
        capabilities: original.capabilities,
      ),
    ),
  );
  final approval = await host.tools.approve(await host.tools.prepare(call));
  final entered = Completer<void>();
  final release = Completer<void>();
  final holding = (original.database as ExclusiveDatabase).exclusiveAsync<void>(
    (db) async {
      entered.complete();
      await release.future;
      concurrent(db);
    },
  );
  await entered.future;
  try {
    final token = cancel ?? ToolCancellationToken();
    final future = host.tools.invoke(
      call.withApproval(approval),
      cancellation: token,
    );
    await observed.queued.future.timeout(const Duration(seconds: 5));
    cancel?.cancel();
    release.complete();
    await holding;
    verify(await future);
  } finally {
    if (!release.isCompleted) release.complete();
    await holding;
  }
}

class _ObservedWrite implements ManagedDatabase {
  _ObservedWrite(this.delegate);
  final ManagedDatabase delegate;
  final queued = Completer<void>();
  @override
  Database get raw => delegate.raw;
  @override
  Future<T> write<T>(T Function(Database) body) {
    if (!queued.isCompleted) queued.complete();
    return delegate.write(body);
  }
}
