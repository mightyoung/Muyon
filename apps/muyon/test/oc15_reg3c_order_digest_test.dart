import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/research_module.dart';

import 'support/reg3c_fixture.dart';

// OC-15: pins that the outline order digest covers every section row field
// (position included), so changing any neighbour field invalidates an old
// expected_digest even when the enumeration order stays the same.
void main() {
  late Directory root;
  late MuyonHost host;
  var invocation = 0;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('oc15-');
    host = await MuyonHost.open(p.join(root.path, 'data'));
  });
  tearDown(() async {
    await host.close();
    root.deleteSync(recursive: true);
  });

  Future<ObjectRef> current(String type, String id, String project) =>
      currentResearchRef(host, type, id, project);

  Future<void> research() => seedPqeResearch(host);

  ToolCallRequest request(
    String tool,
    Map<String, Object?> params,
    List<ObjectRef> refs,
  ) => ToolCallRequest(
    invocationId: 'oc15-${++invocation}',
    toolId: tool,
    parameters: params,
    scope: AssistantScope.selectedObjects(refs),
  );

  Future<ToolCallResult> invokeApproved(ToolCallRequest call) =>
      invokeApprovedResearchCall(host, call);

  Future<void> refuses(ToolCallRequest call, void Function() unchanged) async {
    final denied = await invokeApproved(call);
    expect(denied.status, ToolCallStatus.failed);
    expect(denied.changes, isEmpty);
    expect(host.tools.receiptFor(call.invocationId)!.state, 'failed');
    unchanged();
  }

  Future<ToolCallResult> confirmed(ToolCallRequest call) async {
    final result = await invokeApproved(call);
    expect(result.status, ToolCallStatus.succeeded);
    expect(result.changes, isNotEmpty);
    expect(host.tools.receiptFor(call.invocationId)!.state, 'succeeded');
    return result;
  }

  List<String> headings() => host.research!.store
      .sections('P')
      .map((section) => section.heading)
      .toList();

  List<Map<String, Object?>> rows() => host.research!.store.db
      .select('SELECT * FROM sections WHERE project_id=? ORDER BY position', [
        'P',
      ])
      .map((row) => Map<String, Object?>.from(row))
      .toList();

  List<Map<String, Object?>> log() => host.research!.store.db
      .select('SELECT * FROM muyon_change_log ORDER BY rowid')
      .map((row) => Map<String, Object?>.from(row))
      .toList();

  Future<ObjectRef> project(String id) => current('project', id, id);

  Future<String> orderDigest(ObjectRef selected) async {
    final listed = await host.tools.invoke(
      request(
        'research.outline_sections',
        {'project_id': selected.objectId},
        [selected],
      ),
    );
    expect(listed.status, ToolCallStatus.succeeded, reason: listed.summary);
    return listed.data['orderDigest'] as String;
  }

  Future<List<OutlineSection>> seed(List<String> titles) =>
      seedPSections(host, titles);

  test('move_section refuses when a neighbour position changed but order is the same', () async {
    await research();
    final created = await seed(['S1', 'S2', 'S3']);
    final first = await current('section', created.first.id, 'P');
    final selected = await project('P');
    final digest = await orderDigest(selected);
    final store = host.research!.store;
    await store.write(
      () => store.db.execute('UPDATE sections SET position=? WHERE id=?', [
        created.last.position + 10,
        created.last.id,
      ]),
    );
    expect(headings(), ['S1', 'S2', 'S3'], reason: '前提：枚举顺序不变');
    final before = rows();
    final beforeLog = log();
    await refuses(
      request(
        'research.move_section',
        {'section_id': first.objectId, 'delta': 1, 'expected_digest': digest},
        [first],
      ),
      () {
        expect(rows(), before);
        expect(log(), beforeLog);
        expect(headings(), ['S1', 'S2', 'S3']);
      },
    );
  });

  test('move_section refuses when a neighbour argument changed', () async {
    await research();
    final created = await seed(['S1', 'S2', 'S3']);
    final first = await current('section', created.first.id, 'P');
    final selected = await project('P');
    final digest = await orderDigest(selected);
    final store = host.research!.store;
    await store.write(
      () => store.db.execute('UPDATE sections SET argument=? WHERE id=?', [
        '被改动的邻居论证',
        created[1].id,
      ]),
    );
    expect(store.sections('P')[1].argument, '被改动的邻居论证', reason: '前提：邻居字段已改动');
    final before = rows();
    final beforeLog = log();
    await refuses(
      request(
        'research.move_section',
        {'section_id': first.objectId, 'delta': 1, 'expected_digest': digest},
        [first],
      ),
      () {
        expect(rows(), before);
        expect(log(), beforeLog);
        expect(headings(), ['S1', 'S2', 'S3']);
      },
    );
  });

  test('add_section refuses when a neighbour level changed', () async {
    await research();
    final created = await seed(['S1', 'S2', 'S3']);
    final selected = await project('P');
    final digest = await orderDigest(selected);
    final store = host.research!.store;
    await store.write(
      () => store.db.execute('UPDATE sections SET level=? WHERE id=?', [
        2,
        created[1].id,
      ]),
    );
    expect(store.sections('P')[1].level, 2, reason: '前提：邻居层级已改动');
    final before = rows();
    final beforeLog = log();
    await refuses(
      request(
        'research.add_section',
        {
          'project_id': 'P',
          'heading': 'S4',
          'level': 1,
          'expected_digest': digest,
        },
        [selected],
      ),
      () {
        expect(rows(), before);
        expect(log(), beforeLog);
        expect(headings(), ['S1', 'S2', 'S3']);
      },
    );
  });

  test('move_section with fresh digest succeeds', () async {
    await research();
    final created = await seed(['S1', 'S2', 'S3']);
    final first = await current('section', created.first.id, 'P');
    final selected = await project('P');
    final digest = await orderDigest(selected);
    await confirmed(
      request(
        'research.move_section',
        {'section_id': first.objectId, 'delta': 1, 'expected_digest': digest},
        [first],
      ),
    );
    expect(headings(), ['S2', 'S1', 'S3']);
  });
}
