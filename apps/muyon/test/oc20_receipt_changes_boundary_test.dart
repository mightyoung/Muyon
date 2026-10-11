import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/research_module.dart';

import 'support/reg3c_fixture.dart';

// OC-20: locks the CURRENT state of deferred item CR-13 N-3: ToolCallResult.toJson
// does not serialize `changes` and fromJson does not restore them, so a first
// delete/update result carries its ObjectChange list, while receiptFor() re-read
// from the database returns result.changes empty with only objectRefs surviving.
// When the receipt contract becomes versioned, these two tests must be rewritten.
void main() {
  late Directory root;
  late MuyonHost host;
  var invocation = 0;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('oc20-');
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
    invocationId: 'oc20-${++invocation}',
    toolId: tool,
    parameters: params,
    scope: AssistantScope.selectedObjects(refs),
  );

  Future<ToolCallResult> invokeApproved(ToolCallRequest call) =>
      invokeApprovedResearchCall(host, call);

  Future<ToolCallResult> confirmed(ToolCallRequest call) async {
    final result = await invokeApproved(call);
    expect(result.status, ToolCallStatus.succeeded, reason: result.summary);
    expect(result.changes, isNotEmpty);
    expect(host.tools.receiptFor(call.invocationId)!.state, 'succeeded');
    return result;
  }

  Future<List<OutlineSection>> seed(List<String> titles) =>
      seedPSections(host, titles);

  /// S1/S2/S3 with two evidence links under S1, in insertion order.
  Future<({List<OutlineSection> sections, List<String> linkIds})>
  seededChain() async {
    final created = await seed(['S1', 'S2', 'S3']);
    final store = host.research!.store;
    await seedPEvidenceLinks(store, created);
    final links = [
      for (final row in store.outline('P'))
        if (row['section_id'] == created.first.id) row['id'] as String,
    ];
    expect(links, hasLength(2));
    return (sections: created, linkIds: links);
  }

  Future<String> deleteDigest(ObjectRef section) async {
    final read = await host.tools.invoke(
      request(
        'research.read_object',
        {'type': 'section', 'id': section.objectId},
        [section],
      ),
    );
    expect(read.status, ToolCallStatus.succeeded, reason: read.summary);
    return (read.data['object'] as Map)['deleteDigest'] as String;
  }

  test('delete_section first result carries delete changes but persisted receipt has none', () async {
    await research();
    final chain = await seededChain();
    final sectionId = chain.sections.first.id;
    final first = await current('section', sectionId, 'P');
    final digest = await deleteDigest(first);
    final call = request(
      'research.delete_section',
      {'section_id': sectionId, 'expected_digest': digest},
      [first],
    );
    final result = await confirmed(call);
    expect(result.changes, hasLength(3));
    expect({for (final change in result.changes) change.op}, {ChangeOp.delete});
    expect(
      {for (final change in result.changes) change.ref.objectId},
      {sectionId, ...chain.linkIds},
    );

    // Re-read the persisted receipt: changes are not part of the stored
    // contract (CR-13 N-3); only the refs survive.
    final receipt = host.tools.receiptFor(call.invocationId)!;
    expect(receipt.state, 'succeeded');
    final persisted = receipt.result!;
    expect(persisted.changes, isEmpty);
    expect(persisted.objectRefs, isNotEmpty);
    expect(
      persisted.objectRefs.map((ref) => ref.toJson()).toList(),
      result.objectRefs.map((ref) => ref.toJson()).toList(),
    );
    expect(
      {for (final ref in persisted.objectRefs) ref.objectId},
      {sectionId, ...chain.linkIds},
    );
    for (final ref in persisted.objectRefs) {
      expect(ref.moduleId, 'research');
      expect(ref.nativeProjectId, 'P');
    }
  });

  test(
    'update_section persisted receipt keeps objectRefs without changes',
    () async {
      await research();
      final chain = await seededChain();
      final sectionId = chain.sections.first.id;
      final first = await current('section', sectionId, 'P');
      final call = request(
        'research.update_section',
        {
          'section_id': sectionId,
          'heading': '改后 S1',
          'level': 1,
          'argument': '',
          'support': 'unassessed',
          'expected_digest': first.contentDigest!,
        },
        [first],
      );
      final result = await confirmed(call);
      expect(result.changes, hasLength(3));
      expect(
        {for (final change in result.changes) change.op},
        {ChangeOp.upsert},
      );

      // Re-read the persisted receipt: changes are not part of the stored
      // contract (CR-13 N-3); objectRefs are kept exactly as returned.
      final receipt = host.tools.receiptFor(call.invocationId)!;
      expect(receipt.state, 'succeeded');
      final persisted = receipt.result!;
      expect(persisted.changes, isEmpty);
      expect(
        persisted.objectRefs.map((ref) => ref.toJson()).toList(),
        result.objectRefs.map((ref) => ref.toJson()).toList(),
      );
    },
  );
}
