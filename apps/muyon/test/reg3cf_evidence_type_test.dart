import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/research_module.dart';

void main() {
  late Directory root;
  late MuyonHost host;
  late String sectionId;
  var invocation = 0;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('reg3cf-evidence-');
    host = await MuyonHost.open(p.join(root.path, 'data'));
    await host.activateResearch();
    final store = host.research!.store;
    await store.write(() {
      store.db.execute(
        'INSERT INTO projects(id,title,question,next_step) VALUES(?,?,?,?)',
        ['P', '研究', '问题', '下一步'],
      );
      sectionId = store.addSection('P', '证据段落').id;
    });
  });

  tearDown(() async {
    await host.close();
    root.deleteSync(recursive: true);
  });

  Future<ObjectRef> current(String type, String id) async {
    final session = await host.research!.openScopeSession();
    try {
      return (await session.resolve(
        ObjectRef(
          moduleId: 'research',
          objectType: type,
          objectId: id,
          nativeProjectId: 'P',
        ),
      ))!.ref;
    } finally {
      await session.dispose();
    }
  }

  Future<void> importRun({
    required bool accepted,
    bool collision = false,
  }) async {
    final store = host.research!.store;
    final task = await store.write(() {
      if (collision) {
        store.db.execute(
          'INSERT INTO entries(id,project_id,kind,title,data) VALUES(?,?,?,?,?)',
          ['X', 'P', 'claim', '同号条目', '{}'],
        );
      }
      return store.saveTask(
        projectId: 'P',
        title: '结果导入任务',
        goal: '核对证据类型',
        spec: {},
      );
    });
    final file = File(p.join(root.path, 'result.json'))
      ..writeAsStringSync(
        jsonEncode({
          'format': 'research-result-v1',
          'runId': 'X',
          'taskId': task.id,
          'taskRevision': task.revision,
          'status': 'completed',
          'metrics': {'score': 1},
          'logs': <String>[],
          'artifacts': <String>[],
        }),
      );
    final run = await ResearchExchange(store).importResult(file.path);
    expect(run.id, 'X');
    expect(run.accepted, isFalse);
    if (accepted) await store.write(() => store.acceptRun(run.id));
    expect(store.runs('P').single.accepted, accepted);
    expect(store.entries('P').map((entry) => entry.id), collision ? ['X'] : []);
    // The importer takes runId from the result and only checks runs for an
    // existing ID, so this fixture exercises the supported cross-table collision.
    if (collision) {
      expect((await current('entry', 'X')).objectType, 'entry');
      expect((await current('run', 'X')).objectType, 'run');
    }
  }

  List<Map<String, Object?>> rows(String table) => [
    for (final row in host.research!.store.db.select(
      'SELECT * FROM $table ORDER BY rowid',
    ))
      Map<String, Object?>.from(row),
  ];

  Future<(ToolCallRequest, ToolCallResult)> cite(String type, String id) async {
    final section = await current('section', sectionId);
    final evidence = await current(type, id);
    final call = ToolCallRequest(
      invocationId: 'reg3cf-evidence-${++invocation}',
      toolId: 'research.cite',
      parameters: {
        'section_id': sectionId,
        'evidence_type': type,
        'evidence_id': id,
        'expected_digest': section.contentDigest!,
      },
      scope: AssistantScope.selectedObjects([section, evidence]),
    );
    final prepared = await host.tools.prepare(call);
    expect(prepared.resolvedScope.objects.map((ref) => ref.objectType), [
      'section',
      type,
    ]);
    final approval = await host.tools.approve(prepared);
    return (call, await host.tools.invoke(call.withApproval(approval)));
  }

  Future<void> refusesRun() async {
    final sections = rows('sections');
    final outline = rows('outline');
    final changes = rows('muyon_change_log');
    final (call, result) = await cite('run', 'X');
    expect(result.status, ToolCallStatus.failed);
    expect(result.changes, isEmpty);
    expect(host.tools.receiptFor(call.invocationId)!.state, 'failed');
    expect(rows('sections'), sections);
    expect(rows('outline'), outline);
    expect(rows('muyon_change_log'), changes);
  }

  for (final accepted in [false, true]) {
    test(
      'cite rejects imported ${accepted ? 'accepted' : 'unaccepted'} run sharing an entry ID',
      () async {
        await importRun(accepted: accepted, collision: true);
        await refusesRun();
      },
    );
  }

  test(
    'cite rejects an imported unaccepted run without an ID collision',
    () async {
      await importRun(accepted: false);
      await refusesRun();
    },
  );

  test(
    'cite writes an imported accepted run without an ID collision',
    () async {
      await importRun(accepted: true);
      final before = rows('muyon_change_log').length;
      final (call, result) = await cite('run', 'X');
      expect(result.status, ToolCallStatus.succeeded);
      expect(host.tools.receiptFor(call.invocationId)!.state, 'succeeded');
      expect(result.changes, hasLength(1));
      expect(result.changes.single.ref.objectType, 'outline');
      expect(rows('outline').single['evidence_id'], 'X');
      expect(rows('outline').single['section_id'], sectionId);
      expect(rows('muyon_change_log').length, before + 1);
    },
  );

  test('cite writes a note without an ID collision', () async {
    final store = host.research!.store;
    await store.write(() {
      store.db.execute(
        'INSERT INTO documents(id,project_id,relative_path,sha256) '
        'VALUES(?,?,?,?)',
        ['D', 'P', 'paper.md', 'fixture'],
      );
      store.saveNote('D', 'section 1', '阅读批注');
    });
    final noteId = rows('notes').single['id'] as String;
    final before = rows('muyon_change_log').length;
    final (call, result) = await cite('note', noteId);
    expect(result.status, ToolCallStatus.succeeded);
    expect(host.tools.receiptFor(call.invocationId)!.state, 'succeeded');
    expect(result.changes, hasLength(1));
    expect(result.changes.single.ref.objectType, 'outline');
    expect(rows('outline').single['evidence_id'], noteId);
    expect(rows('outline').single['section_id'], sectionId);
    expect(rows('muyon_change_log').length, before + 1);
  });
}
