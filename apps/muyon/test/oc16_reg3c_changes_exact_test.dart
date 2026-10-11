import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/research_module.dart';

import 'support/reg3c_fixture.dart';

// OC-16: pins the exactness of research write receipts: move_section lists
// every section whose position changed (both swapped neighbours) with digests
// read back after the write; update_section lists the section plus every
// changed outline link; a boundary no-op move has empty changes and says so.
void main() {
  late Directory root;
  late MuyonHost host;
  var invocation = 0;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('oc16-');
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
    invocationId: 'oc16-${++invocation}',
    toolId: tool,
    parameters: params,
    scope: AssistantScope.selectedObjects(refs),
  );

  Future<ToolCallResult> invokeApproved(ToolCallRequest call) =>
      invokeApprovedResearchCall(host, call);

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

  test('move_section changes list both swapped sections', () async {
    await research();
    final created = await seed(['S1', 'S2', 'S3']);
    final second = await current('section', created[1].id, 'P');
    final selected = await project('P');
    final digest = await orderDigest(selected);
    final result = await confirmed(
      request(
        'research.move_section',
        {'section_id': second.objectId, 'delta': -1, 'expected_digest': digest},
        [second],
      ),
    );
    expect(result.summary, '已移动提纲段落');
    expect(result.changes, hasLength(2));
    final ids = {for (final change in result.changes) change.ref.objectId};
    expect(ids, {created.first.id, created[1].id});
    expect(ids, isNot(contains(created.last.id)));
    for (final change in result.changes) {
      expect(change.op, ChangeOp.upsert);
      expect(change.ref.moduleId, 'research');
      expect(change.ref.objectType, 'section');
      expect(change.ref.nativeProjectId, 'P');
      final fresh = await current('section', change.ref.objectId, 'P');
      expect(change.ref.contentDigest, fresh.contentDigest);
    }
    expect(headings(), ['S2', 'S1', 'S3']);
  });

  test('update_section heading change lists the section and every linked outline row', () async {
    await research();
    final created = await seed(['S1', 'S2', 'S3']);
    final store = host.research!.store;
    await seedPEvidenceLinks(store, created);
    final links = {
      for (final row in store.outline('P'))
        if (row['section_id'] == created.first.id) row['id'] as String,
    };
    expect(links, hasLength(2));
    final first = await current('section', created.first.id, 'P');
    final result = await confirmed(
      request(
        'research.update_section',
        {
          'section_id': first.objectId,
          'heading': '改后 S1',
          'level': 1,
          'argument': '',
          'support': 'unassessed',
          'expected_digest': first.contentDigest!,
        },
        [first],
      ),
    );
    expect(result.changes, hasLength(3));
    final sectionChanges = [
      for (final change in result.changes)
        if (change.ref.objectType == 'section') change,
    ];
    final outlineChanges = [
      for (final change in result.changes)
        if (change.ref.objectType == 'outline') change,
    ];
    expect(sectionChanges, hasLength(1));
    expect(sectionChanges.single.ref.objectId, first.objectId);
    expect({for (final change in outlineChanges) change.ref.objectId}, links);
    for (final change in result.changes) {
      expect(change.op, ChangeOp.upsert);
      expect(change.ref.nativeProjectId, 'P');
    }
    expect(headings(), ['改后 S1', 'S2', 'S3']);
  });

  test('noop move at boundary has empty changes', () async {
    await research();
    final created = await seed(['S1', 'S2', 'S3']);
    final first = await current('section', created.first.id, 'P');
    final selected = await project('P');
    final digest = await orderDigest(selected);
    final call = request(
      'research.move_section',
      {'section_id': first.objectId, 'delta': -1, 'expected_digest': digest},
      [first],
    );
    final result = await invokeApproved(call);
    expect(result.status, ToolCallStatus.succeeded);
    expect(result.changes, isEmpty);
    expect(result.summary, contains('位置未变化'));
    expect(host.tools.receiptFor(call.invocationId)!.state, 'succeeded');
    expect(headings(), ['S1', 'S2', 'S3']);
  });
}
