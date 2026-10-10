import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inquiry_module/src/app/shell.dart';
import 'package:inquiry_module/src/features/ai/ask_page.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';

void main() {
  late Directory root;
  late MuyonHost host;
  late Store store;
  late String supplierId;
  var sequence = 0;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('reg4c-');
    host = await MuyonHost.open(root.path);
    await host.activateInquiry();
    store = host.inquiry!.runtime.state.store;
    supplierId = store.save('supplier', {
      for (final field in Supplier.fields) field: null,
      'name': '公开夹具供应商',
      'aliases': <String>[],
      'categories': <String>[],
    });
  });
  tearDown(() async {
    await host.close();
    root.deleteSync(recursive: true);
  });

  Future<List<ObjectRef>> selection([List<String>? ids]) async =>
      (await resolveAssistantScope(host, const AssistantScope.global()))
          .objects.where((r) => (ids ?? [supplierId]).contains(r.objectId)).toList();
  Future<ToolCallRequest> request(String operation, Map<String, Object?> p,
      {List<ObjectRef>? selected, String? operationId}) async => ToolCallRequest(
    invocationId: 'reg4c-call-${++sequence}',
    toolId: 'inquiry.$operation',
    scope: AssistantScope.selectedObjects(selected ?? await selection()),
    parameters: {'operation_id': operationId ?? newUuid(), ...p},
  );
  Future<ToolCallResult> approved(ToolCallRequest r) async {
    final prepared = await host.tools.prepare(r);
    return host.tools.invoke(r.withApproval(host.tools.approve(prepared)));
  }
  Map<String, Object?> edit(String id, {int version = 1,
      Map<String, Object?> values = const {'name': '改名'}}) => {
    'type': 'supplier', 'id': id, 'expected_version': version, 'values': values,
  };

  test('registers four generic writes with the seven ontology types', () {
    for (final operation in ['create_record', 'update_record',
        'delete_record', 'restore_record']) {
      final info = host.tools.inspect('inquiry.$operation');
      expect(info, isNotNull, reason: operation);
      expect(info!.descriptor.effect, ToolEffect.write);
      final schema = info.descriptor.parameterSchema;
      expect(schema['additionalProperties'], false);
      expect((schema['properties'] as Map)['type']['enum'], [
        'supplier', 'contact', 'product', 'project', 'project_item',
        'inquiry', 'quotation',
      ]);
      if (operation != 'create_record') {
        expect(schema['required'], contains('expected_version'));
      }
    }
  });

  test('unapproved generic write never changes the Store or writes a receipt', () async {
    final r = await request('update_record', edit(supplierId));
    await expectLater(host.tools.invoke(r), throwsA(isA<ToolPlatformException>()));
    expect(store.get('supplier', supplierId)!.version, 1);
    expect(store.db.select("SELECT key FROM meta WHERE key LIKE 'reg4c:%'"), isEmpty);
  });

  test('updates only supplied fields and atomically retains a business receipt', () async {
    final operationId = newUuid();
    final r = await request('update_record', edit(supplierId), operationId: operationId);
    final result = await approved(r);
    expect(result.status, ToolCallStatus.succeeded);
    expect(store.get('supplier', supplierId)!.data['name'], '改名');
    expect(store.get('supplier', supplierId)!.data['aliases'], isEmpty);
    expect(store.get('supplier', supplierId)!.version, 2);
    final again = await approved(await request('update_record', edit(supplierId), operationId: operationId));
    expect(again.toJson(), result.toJson());
    expect(store.get('supplier', supplierId)!.version, 2);
    expect(store.db.select("SELECT key FROM meta WHERE key LIKE 'reg4c:%'"), hasLength(1));
    final conflict = await approved(await request('update_record', edit(supplierId,
        version: 2, values: {'notes': '不同请求'}), operationId: operationId));
    expect(conflict.status, ToolCallStatus.failed);
    expect(store.get('supplier', supplierId)!.data['notes'], isNull);
  });

  test('explicit expected_version refuses a stale update even with fresh scope', () async {
    store.save('supplier', {...store.get('supplier', supplierId)!.data,
        'notes': '已改动'}, id: supplierId);
    final result = await approved(await request('update_record', edit(supplierId)));
    expect(result.status, ToolCallStatus.failed);
    expect(store.get('supplier', supplierId)!.data['name'], '公开夹具供应商');
    expect(store.get('supplier', supplierId)!.version, 2);
  });

  test('type-specific fields and protected fields fail before approval', () async {
    for (final values in [
      {'qty': '9'}, {'unknown_field': 'x'}, {'merged_into': supplierId},
      {'attachment_ids': <String>[]}, {'source_attachment_ids': <String>[]},
      {'capture_mode': 'historical'}, <String, Object?>{},
    ]) {
      await expectLater(host.tools.prepare(await request('update_record',
          edit(supplierId, values: values))), throwsA(isA<ToolPlatformException>()));
    }
    expect(store.get('supplier', supplierId)!.version, 1);
  });

  test('unselected target is refused without domain writes', () async {
    final other = store.save('supplier', {...store.get('supplier', supplierId)!.data,
        'name': '未选中'});
    final result = await approved(await request('update_record', edit(other)));
    expect(result.status, ToolCallStatus.failed);
    expect(store.get('supplier', other)!.version, 1);
  });

  test('create validates payload and repeats across new invocations only once', () async {
    final op = newUuid();
    final p = {'type': 'supplier', 'values': {'name': '新供应商'}};
    final first = await approved(await request('create_record', p, operationId: op));
    final second = await approved(await request('create_record', p, operationId: op));
    expect(first.status, ToolCallStatus.succeeded);
    expect(second.toJson(), first.toJson());
    expect(store.db.select('SELECT id FROM supplier WHERE deleted=0'), hasLength(2));
    final invalid = await approved(await request('create_record', {
      'type': 'contact', 'values': {'supplier_id': supplierId, 'name': '缺联系方式'},
    }));
    expect(invalid.status, ToolCallStatus.failed);
    expect(store.db.select('SELECT id FROM contact'), isEmpty);
  });

  test('delete and restore require current version and preserve audit revisions', () async {
    final deleted = await approved(await request('delete_record', {
      'type': 'supplier', 'id': supplierId, 'expected_version': 1,
      'referencing_records': <Object?>[],
    }));
    expect(deleted.status, ToolCallStatus.succeeded);
    expect(store.get('supplier', supplierId)!.deleted, isTrue);
    expect(store.get('supplier', supplierId)!.version, 2);
    expect((await selection()), isEmpty);
    final tombstone = deleted.objectRefs.single;
    final stale = await approved(await request('restore_record', {
      'type': 'supplier', 'id': supplierId, 'expected_version': 1,
    }, selected: [tombstone]));
    expect(stale.status, ToolCallStatus.failed);
    final restored = await approved(await request('restore_record', {
      'type': 'supplier', 'id': supplierId, 'expected_version': 2,
    }, selected: [tombstone]));
    expect(restored.status, ToolCallStatus.succeeded);
    expect(store.get('supplier', supplierId)!.deleted, isFalse);
    expect(store.get('supplier', supplierId)!.version, 3);
  });

  test('quotation schema rejects all pricing and award fields', () async {
    for (final field in ['price', 'deal_price', 'awarded_on', 'award_note',
        'extra_cost', 'tax_rate', 'currency', 'tax_mode', 'price_tiers', 'price_basis']) {
      await expectLater(host.tools.prepare(await request('update_record', {
        'type': 'quotation', 'id': newUuid(), 'expected_version': 1,
        'values': {field: field == 'price_tiers' ? <Object?>[] : '1'},
      })), throwsA(isA<ToolPlatformException>()), reason: field);
    }
  });

  testWidgets('hosted Folio has no sidebar, palette or shortcut assistant route', (tester) async {
    await tester.view.reset();
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Shell(state: host.inquiry!.runtime.state, embedded: true)));
    await tester.pumpAndSettle();
    expect(find.text('问数据'), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit6);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(AskPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
