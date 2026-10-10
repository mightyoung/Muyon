import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/inquiry_snapshots/inquiry_readonly_snapshot.dart';
import 'package:muyon/app/module_host.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import '../../../packages/supplier_core/test/fixtures.dart' as fixture;
import 'support/aiui6_snapshot_fixture.dart';

void main() {
  late InquirySnapshotFixture f;
  setUp(() async { f = await InquirySnapshotFixture.open(); });
  tearDown(() async { await f.close(); });

  for (final type in ['inquiry', 'quotation', 'project_item']) {
    test('real pinned $type snapshot preserves business records and authority', () async {
      final object = f.refs[type]!;
      final store = f.host.inquiry!.runtime.state.store;
      final before = fixture.content(store);
      final snapshot = await InquiryReadonlySnapshots.read(host: f.host,
        scope: AssistantScope.selectedObjects([object]), object: object);
      expect(snapshot.record.object, object);
      expect(snapshot.record.snapshotRef.revision.toString(), object.revisionRef);
      expect(snapshot.scene.label, {'inquiry': '询价单', 'quotation': '报价', 'project_item': '预算行'}[type]);
      expect(snapshot.record.fields, isNotEmpty);
      expect(fixture.content(store), before);
      expect(f.host.modules.state('research').status, ModuleStatus.inactive);
      expect(f.host.modules.state('prototype').status, ModuleStatus.inactive);
      expect(f.host.tools.history(), isEmpty);
      expect(f.host.workspaces.database.raw.select('SELECT * FROM tool_invocation_receipts'), isEmpty);
    });
  }
  test('suggested budget name never replaces saved fact or cost', () async {
    final object = f.refs['project_item']!;
    final snapshot = await InquiryReadonlySnapshots.read(host: f.host,
      scope: AssistantScope.selectedObjects([object]), object: object,
      suggestions: const {'name': '建议预算行', 'unit_cost': 'MODEL-PRICE', 'injected': 'UNKNOWN'});
    final name = snapshot.record.fields.singleWhere((field) => field.name == 'name');
    expect(name.value, '真实预算行');
    expect(name.suggestion, '建议预算行');
    final cost = snapshot.record.fields.singleWhere((field) => field.name == 'unit_cost');
    expect(cost.masked, isTrue);
    expect(cost.value, '已遮盖');
    expect(cost.suggestion, '已遮盖');
    expect(snapshot.record.fields.any((field) => field.name == 'injected'), isFalse);
    expect(f.host.inquiry!.runtime.state.store.get('project_item', object.objectId)!.data['unit_cost'], '987654.123');
  });
  test('global and out of selected scope reads fail closed', () async {
    final object = f.refs['project_item']!;
    await expectLater(InquiryReadonlySnapshots.read(host: f.host,
      scope: const AssistantScope.global(), object: object), throwsStateError);
    await expectLater(InquiryReadonlySnapshots.read(host: f.host,
      scope: AssistantScope.selectedObjects([f.refs['inquiry']!]), object: object), throwsStateError);
  });
  test('stale saved version and unpinned selection are rejected', () async {
    final object = f.refs['project_item']!;
    final store = f.host.inquiry!.runtime.state.store;
    store.save('project_item', {...store.get('project_item', object.objectId)!.data, 'name': '已更新'}, id: object.objectId);
    await expectLater(InquiryReadonlySnapshots.read(host: f.host,
      scope: AssistantScope.selectedObjects([object]), object: object), throwsStateError);
    final unpinned = ObjectRef(moduleId: object.moduleId, objectType: object.objectType,
      objectId: object.objectId, nativeProjectId: object.nativeProjectId);
    await expectLater(InquiryReadonlySnapshots.read(host: f.host,
      scope: AssistantScope.selectedObjects([unpinned]), object: unpinned), throwsStateError);
  });
  test('selection source budget rejects before reading extra objects', () async {
    final object = f.refs['inquiry']!;
    final objects = [object, for (var i = 0; i < InquiryReadonlySnapshots.maxSelectionObjects; i++)
      ObjectRef(moduleId: 'inquiry', objectType: 'inquiry', objectId: 'unread-$i',
        nativeProjectId: object.nativeProjectId, revisionRef: '1', contentDigest: 'not-read')];
    await expectLater(InquiryReadonlySnapshots.read(host: f.host,
      scope: AssistantScope.selectedObjects(objects), object: object), throwsStateError);
    expect(f.host.tools.history(), isEmpty);
  });
  test('unsupported object type cannot enter the scene adapter', () async {
    const object = ObjectRef(moduleId: 'inquiry', objectType: 'supplier',
      objectId: 'not-read', revisionRef: '1', contentDigest: 'not-read');
    await expectLater(InquiryReadonlySnapshots.read(host: f.host,
      scope: AssistantScope.selectedObjects([object]), object: object), throwsStateError);
  });
}
