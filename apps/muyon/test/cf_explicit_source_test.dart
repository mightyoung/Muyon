import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/inquiry_ui_planning_source.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'support/aiui6_snapshot_fixture.dart';

void main() {
  late InquirySnapshotFixture f;
  setUp(() async => f = await InquirySnapshotFixture.open());
  tearDown(() async => f.close());

  Future<PersonalTask> taskFor(List<ObjectRef> refs) async {
    final conversation = await f.host.foundation.createConversation(
      scope: AssistantScope.selectedObjects(refs),
    );
    return f.host.personalAgent.start(
      conversationId: conversation.id, prompt: '本地只读事实',
    );
  }

  for (final selection in ['multi', 'duplicate', 'mixed', 'unsupported']) {
    test('rejects $selection selection instead of silently choosing a target', () async {
      final selected = f.refs['project_item']!;
      const unsupported = ObjectRef(moduleId: 'inquiry', objectType: 'supplier',
        objectId: 'not-read', revisionRef: '1', contentDigest: 'not-read');
      const foreign = ObjectRef(moduleId: 'research', objectType: 'note',
        objectId: 'not-read', revisionRef: '1', contentDigest: 'not-read');
      final refs = switch (selection) {
        'multi' => [selected, f.refs['quotation']!],
        'duplicate' => [selected, selected],
        'mixed' => [selected, foreign],
        _ => [unsupported],
      };
      final task = await taskFor(refs);
      expect(await InquiryUiPlanningSource(f.host).read(task), isNull);
      expect(f.host.tools.history(), isEmpty);
    });
  }

  test('real single target keeps masked and lossy field provenance conservative', () async {
    final ref = f.refs['project_item']!;
    final task = await taskFor([ref]);
    final result = (await InquiryUiPlanningSource(f.host).read(task))!;
    expect(result.snapshot.facts['saved-source']!.state, FactState.verified);
    expect(result.snapshot.facts['saved-name']!.value, '真实预算行');
    expect(result.snapshot.facts['saved-name']!.state, FactState.unverified);
    expect(result.snapshot.facts['saved-requirement']!.state, FactState.unverified);
    expect(result.snapshot.facts['saved-unit_cost']!.state, FactState.notDisclosed);
    expect(result.snapshot.facts['saved-unit_cost']!.value, '已遮盖');
    expect(jsonEncode(result.snapshot.facts.values.map((fact) => fact.value).toList()),
      isNot(contains('987654.123')));
    expect(result.snapshot.facts.values.every((fact) => fact.object == ref), isTrue);
    expect(result.snapshot.facts.keys.any((key) => key.contains('suggestion')), isFalse);
  });

  for (final change in ['failed', 'internal', 'conversation', 'deleted']) {
    test('late $change task cannot publish a source after an awaited read', () async {
      final task = await taskFor([f.refs['project_item']!]);
      final other = await f.host.foundation.createConversation(scope: task.scope);
      final reading = InquiryUiPlanningSource(f.host).read(task);
      scheduleMicrotask(() {
        final db = f.host.foundation.database.raw;
        if (change == 'deleted') {
          db.execute('DELETE FROM execution_records WHERE id=?', [task.id]);
        } else {
          final payload = <String, Object?>{...task.payload};
          switch (change) {
            case 'failed': payload['state'] = 'failed';
            case 'internal': payload['uiPlanningInternal'] = true;
            case 'conversation': payload['conversationId'] = other.id;
          }
          db.execute('UPDATE execution_records SET payload=? WHERE id=?',
            [jsonEncode(payload), task.id]);
        }
      });
      expect(await reading, isNull);
    });
  }

  test('model-shaped target payload cannot enlarge host selection', () async {
    final ref = f.refs['project_item']!;
    final task = await taskFor([ref]);
    final supplied = task.copy({'target': f.refs['quotation']!.toJson(),
      'scope': AssistantScope.selectedObjects([f.refs['quotation']!]).toJson()});
    final result = (await InquiryUiPlanningSource(f.host).read(supplied))!;
    expect(result.snapshot.facts.values.every((fact) => fact.object == ref), isTrue);
  });
}
