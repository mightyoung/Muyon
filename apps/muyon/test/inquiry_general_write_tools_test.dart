import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inquiry_module/src/app/shell.dart';
import 'package:inquiry_module/src/features/ai/ask_page.dart';
import 'package:inquiry_module/src/features/settings/ai_settings.dart';
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
      (await resolveAssistantScope(host, const AssistantScope.global())).objects
          .where((r) => (ids ?? [supplierId]).contains(r.objectId))
          .toList();
  Future<ToolCallRequest> request(
    String operation,
    Map<String, Object?> p, {
    List<ObjectRef>? selected,
    String? operationId,
  }) async => ToolCallRequest(
    invocationId: 'reg4c-call-${++sequence}',
    toolId: 'inquiry.$operation',
    scope: AssistantScope.selectedObjects(selected ?? await selection()),
    parameters: {'operation_id': operationId ?? newUuid(), ...p},
  );
  Future<ToolCallResult> approved(ToolCallRequest r) async {
    final prepared = await host.tools.prepare(r);
    return host.tools.invoke(
      r.withApproval(await host.tools.approve(prepared)),
    );
  }

  Map<String, Object?> edit(
    String id, {
    int version = 1,
    Map<String, Object?> values = const {'name': '改名'},
  }) => {
    'type': 'supplier',
    'id': id,
    'expected_version': version,
    'values': values,
  };

  test('registers four generic writes with the seven ontology types', () {
    for (final operation in [
      'create_record',
      'update_record',
      'delete_record',
      'restore_record',
    ]) {
      final info = host.tools.inspect('inquiry.$operation');
      expect(info, isNotNull, reason: operation);
      expect(info!.descriptor.effect, ToolEffect.write);
      final schema = info.descriptor.parameterSchema;
      expect(schema['additionalProperties'], false);
      expect((schema['properties'] as Map)['type']['enum'], [
        'supplier',
        'contact',
        'product',
        'project',
        'project_item',
        'inquiry',
        'quotation',
      ]);
      if (operation != 'create_record') {
        expect(schema['required'], contains('expected_version'));
      }
    }
  });

  test('coverage registers CRUD and gives specialized writes explicit deferred reasons', () {
    final module = host.registry.require('inquiry') as BusinessModuleV2;
    final operations = {for (final op in module.coverage.operations) op.id: op};
    for (final name in [
      'create_record',
      'update_record',
      'delete_record',
      'restore_record',
    ]) {
      expect(operations[name]!.kind, OpKind.write);
      expect(operations[name]!.tools, ['inquiry.$name']);
    }
    for (final name in [
      'product_param',
      'spec_records',
      'merge_duplicates',
      'award',
      'refresh_prices',
    ]) {
      expect(operations[name]!.notExposed!.kind, NotExposedKind.deferred);
      expect(operations[name]!.notExposed!.taskId, 'REG-4');
      expect(operations[name]!.notExposed!.reason, isNotEmpty);
      expect(operations[name]!.tools, isEmpty);
    }
  });

  test(
    'unapproved generic write never changes the Store or writes a receipt',
    () async {
      final r = await request('update_record', edit(supplierId));
      await expectLater(
        host.tools.invoke(r),
        throwsA(isA<ToolPlatformException>()),
      );
      expect(store.get('supplier', supplierId)!.version, 1);
      expect(
        store.db.select("SELECT key FROM meta WHERE key LIKE 'reg4c:%'"),
        isEmpty,
      );
    },
  );

  test(
    'updates only supplied fields and atomically retains a business receipt',
    () async {
      final operationId = newUuid();
      final r = await request(
        'update_record',
        edit(supplierId),
        operationId: operationId,
      );
      final result = await approved(r);
      expect(result.status, ToolCallStatus.succeeded);
      expect(store.get('supplier', supplierId)!.data['name'], '改名');
      expect(store.get('supplier', supplierId)!.data['aliases'], isEmpty);
      expect(store.get('supplier', supplierId)!.version, 2);
      final again = await approved(
        await request(
          'update_record',
          edit(supplierId),
          operationId: operationId,
        ),
      );
      expect(again.data, result.data);
      expect(
        again.objectRefs.map((r) => r.toJson()),
        result.objectRefs.map((r) => r.toJson()),
      );
      expect(store.get('supplier', supplierId)!.version, 2);
      expect(
        store.db.select("SELECT key FROM meta WHERE key LIKE 'reg4c:%'"),
        hasLength(1),
      );
      final conflict = await approved(
        await request(
          'update_record',
          edit(supplierId, version: 2, values: {'notes': '不同请求'}),
          operationId: operationId,
        ),
      );
      expect(conflict.status, ToolCallStatus.failed);
      expect(store.get('supplier', supplierId)!.data['notes'], isNull);
    },
  );

  test(
    'concurrent create confirmations share one committed domain receipt',
    () async {
      final operationId = newUuid();
      final parameters = {
        'type': 'product',
        'values': {'name': '并发物料', 'unit': '件'},
      };
      final requests = [
        await request('create_record', parameters, operationId: operationId),
        await request('create_record', parameters, operationId: operationId),
      ];
      final results = await Future.wait(requests.map(approved));
      expect(
        results.every((r) => r.status == ToolCallStatus.succeeded),
        isTrue,
      );
      expect(results[0].data, results[1].data);
      expect(
        store.db.select('SELECT id FROM product WHERE deleted=0'),
        hasLength(1),
      );
    },
  );

  test('a new project receives its own ref while the global selection stays narrow', () async {
    final result = await approved(
      await request('create_record', {
        'type': 'project',
        'values': {
          'code': 'NEW',
          'name': '新项目',
          'status': 'planning',
          'currency': 'CNY',
          'tax_mode': 'included',
          'markup_rate': '0',
        },
      }),
    );
    expect(result.status, ToolCallStatus.succeeded);
    expect(
      result.objectRefs.single.nativeProjectId,
      result.objectRefs.single.objectId,
    );
    expect(store.get('project', result.objectRefs.single.objectId)!.version, 1);
  });

  test('create refuses references outside the human selection', () async {
    final other = store.save('supplier', {
      ...store.get('supplier', supplierId)!.data,
      'name': '范围外供应商',
    });
    final result = await approved(
      await request('create_record', {
        'type': 'contact',
        'values': {'name': '联系人', 'phone': '000001', 'supplier_id': other},
      }),
    );
    expect(result.status, ToolCallStatus.failed);
    expect(store.db.select('SELECT id FROM contact'), isEmpty);
  });

  test(
    'explicit expected_version refuses a stale update even with fresh scope',
    () async {
      store.save('supplier', {
        ...store.get('supplier', supplierId)!.data,
        'notes': '已改动',
      }, id: supplierId);
      final result = await approved(
        await request('update_record', edit(supplierId)),
      );
      expect(result.status, ToolCallStatus.failed);
      expect(store.get('supplier', supplierId)!.data['name'], '公开夹具供应商');
      expect(store.get('supplier', supplierId)!.version, 2);
    },
  );

  test(
    'type-specific fields and protected fields fail before approval',
    () async {
      for (final values in [
        {'qty': '9'},
        {'unknown_field': 'x'},
        {'merged_into': supplierId},
        {'attachment_ids': <String>[]},
        {'source_attachment_ids': <String>[]},
        {'capture_mode': 'historical'},
        <String, Object?>{},
      ]) {
        await expectLater(
          host.tools.prepare(
            await request('update_record', edit(supplierId, values: values)),
          ),
          throwsA(isA<ToolPlatformException>()),
        );
      }
      expect(store.get('supplier', supplierId)!.version, 1);
    },
  );

  test('field size limits still fail before approval with compact schemas', () async {
    for (final values in <Map<String, Object?>>[
      {'name': 'a' * 2001},
      {'aliases': List.filled(501, 'a')},
      {'aliases': ['a' * 201]},
    ]) {
      await expectLater(
        host.tools.prepare(await request('update_record', edit(supplierId, values: values))),
        throwsA(isA<ToolPlatformException>()),
      );
      expect(store.get('supplier', supplierId)!.version, 1);
      expect(store.db.select("SELECT key FROM meta WHERE key LIKE 'reg4c:%'"), isEmpty);
    }
  });

  test('unselected target is refused without domain writes', () async {
    final other = store.save('supplier', {
      ...store.get('supplier', supplierId)!.data,
      'name': '未选中',
    });
    final result = await approved(await request('update_record', edit(other)));
    expect(result.status, ToolCallStatus.failed);
    expect(store.get('supplier', other)!.version, 1);
  });

  test(
    'create validates payload and repeats across new invocations only once',
    () async {
      final op = newUuid();
      final p = {
        'type': 'supplier',
        'values': {'name': '新供应商'},
      };
      final first = await approved(
        await request('create_record', p, operationId: op),
      );
      final second = await approved(
        await request('create_record', p, operationId: op),
      );
      expect(first.status, ToolCallStatus.succeeded);
      expect(second.data, first.data);
      expect(
        second.objectRefs.map((r) => r.toJson()),
        first.objectRefs.map((r) => r.toJson()),
      );
      expect(
        store.db.select('SELECT id FROM supplier WHERE deleted=0'),
        hasLength(2),
      );
      final invalid = await approved(
        await request('create_record', {
          'type': 'contact',
          'values': {'supplier_id': supplierId, 'name': '缺联系方式'},
        }),
      );
      expect(invalid.status, ToolCallStatus.failed);
      expect(store.db.select('SELECT id FROM contact'), isEmpty);
    },
  );

  test(
    'delete and restore require current version and preserve audit revisions',
    () async {
      final deleted = await approved(
        await request('delete_record', {
          'type': 'supplier',
          'id': supplierId,
          'expected_version': 1,
          'referencing_records': <Object?>[],
        }),
      );
      expect(deleted.status, ToolCallStatus.succeeded);
      expect(store.get('supplier', supplierId)!.deleted, isTrue);
      expect(store.get('supplier', supplierId)!.version, 2);
      expect((await selection()), isEmpty);
      final tombstone = deleted.objectRefs.single;
      final stale = await approved(
        await request(
          'restore_record',
          {'type': 'supplier', 'id': supplierId, 'expected_version': 1},
          selected: [tombstone],
        ),
      );
      expect(stale.status, ToolCallStatus.failed);
      final restored = await approved(
        await request(
          'restore_record',
          {'type': 'supplier', 'id': supplierId, 'expected_version': 2},
          selected: [tombstone],
        ),
      );
      expect(restored.status, ToolCallStatus.succeeded);
      expect(store.get('supplier', supplierId)!.deleted, isFalse);
      expect(store.get('supplier', supplierId)!.version, 3);
    },
  );

  test('quotation schema rejects all pricing and award fields', () async {
    for (final field in [
      'price',
      'deal_price',
      'awarded_on',
      'award_note',
      'extra_cost',
      'tax_rate',
      'currency',
      'tax_mode',
      'price_tiers',
      'price_basis',
    ]) {
      await expectLater(
        host.tools.prepare(
          await request('update_record', {
            'type': 'quotation',
            'id': newUuid(),
            'expected_version': 1,
            'values': {field: field == 'price_tiers' ? <Object?>[] : '1'},
          }),
        ),
        throwsA(isA<ToolPlatformException>()),
        reason: field,
      );
    }
  });

  ({String project, String item, String inquiry, String quote}) quoteFixture() {
    final project = store.save('project', {
      for (final field in Project.fields) field: null,
      'code': 'REG4C',
      'name': '公开项目',
      'status': 'active',
      'currency': 'CNY',
      'tax_mode': 'included',
      'markup_rate': '0',
    });
    final item = store.save('project_item', {
      for (final field in ProjectItem.fields) field: null,
      'project_id': project,
      'category': 'material',
      'name': '公开物料',
      'qty': '1',
      'unit': '件',
      'unit_cost': '0',
    });
    final inquiry = store.createInquiry(
      project,
      '公开询价',
      itemIds: [item],
      supplierIds: [supplierId],
    );
    final quote = store.quoteForInquiry(
      inquiry,
      item,
      supplierId,
      price: '20',
      context: (inquirer: '公开人员', asOf: null),
    );
    return (project: project, item: item, inquiry: inquiry, quote: quote);
  }

  test(
    'withdrawAward clears award fields but retains the awarded budget snapshot',
    () {
      final f = quoteFixture();
      final before = store.get('project_item', f.item)!.data;
      expect(before['unit_cost'], '0');
      store.award(f.quote, itemId: f.item, dealPrice: '18');
      expect(store.get('project_item', f.item)!.data['unit_cost'], '18');
      store.withdrawAward(f.quote);
      expect(store.get('quotation', f.quote)!.data['deal_price'], isNull);
      expect(store.get('quotation', f.quote)!.data['awarded_on'], isNull);
      expect(store.get('project_item', f.item)!.data['unit_cost'], '18');
      expect(store.get('project_item', f.item)!.data['quotation_id'], f.quote);
    },
  );

  test(
    'Store permits deleting a quoted contact; generic tool must refuse it',
    () async {
      final f = quoteFixture();
      final contact = store.save('contact', {
        for (final field in Contact.fields) field: null,
        'supplier_id': supplierId,
        'name': '公开联系人',
        'phone': '000000',
      });
      store.save('quotation', {
        ...store.get('quotation', f.quote)!.data,
        'contact_id': contact,
        'contact_snapshot': {
          'name': '公开联系人',
          'phone': '000000',
          'wechat': null,
          'email': null,
        },
      }, id: f.quote);
      expect(store.referencesTo('contact', contact), {
        'quotation.contact_id': 1,
      });
      store.transaction(() {
        store.delete('contact', contact);
        expect(store.get('contact', contact)!.deleted, isTrue);
        store.restore('contact', contact);
      });
      final version = store.get('contact', contact)!.version;
      final result = await approved(
        await request('delete_record', {
          'type': 'contact',
          'id': contact,
          'expected_version': version,
          'referencing_records': [
            {
              'type': 'quotation',
              'id': f.quote,
              'version': store.get('quotation', f.quote)!.version,
            },
          ],
        }, selected: await selection([contact, f.quote])),
      );
      expect(result.status, ToolCallStatus.failed);
      expect(store.get('contact', contact)!.deleted, isFalse);
      expect(store.get('quotation', f.quote)!.data['contact_id'], contact);
    },
  );

  test('quotation metadata patch retains all price and award fields', () async {
    final f = quoteFixture();
    store.award(f.quote, dealPrice: '18');
    final before = store.get('quotation', f.quote)!;
    final result = await approved(
      await request('update_record', {
        'type': 'quotation',
        'id': f.quote,
        'expected_version': before.version,
        'values': {'notes': '人工核对', 'lead_time_days': 3},
      }, selected: await selection([f.quote])),
    );
    expect(result.status, ToolCallStatus.succeeded);
    final after = store.get('quotation', f.quote)!;
    expect(after.data['notes'], '人工核对');
    expect(after.data['lead_time_days'], 3);
    for (final key in before.data.keys.where(
      (k) => k != 'notes' && k != 'lead_time_days',
    )) {
      expect(after.data[key], before.data[key], reason: key);
    }
  });

  test('delete preview refuses omitted or stale referring records', () async {
    final f = quoteFixture();
    final result = await approved(
      await request('delete_record', {
        'type': 'supplier',
        'id': supplierId,
        'expected_version': 1,
        'referencing_records': <Object?>[],
      }),
    );
    expect(result.status, ToolCallStatus.failed);
    expect(store.get('supplier', supplierId)!.deleted, isFalse);
    expect(store.get('quotation', f.quote), isNotNull);
  });

  testWidgets('hosted settings offer no Folio assistant permission selector', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiSettings(state: host.inquiry!.runtime.state),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<AssistantPermission>), findsNothing);
    expect(find.text('助手操作权限'), findsNothing);
    expect(find.text('助手联网查询'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'hosted Folio has no sidebar, palette or shortcut assistant route',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Shell(state: host.inquiry!.runtime.state, embedded: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('问数据'), findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit6);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byType(AskPage), findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final paletteSearch = find.byWidgetPredicate(
        (widget) => widget is TextField &&
            widget.decoration?.hintText ==
                '搜索项目、供应商、物料（支持拼音首字母），或输入命令',
      );
      expect(paletteSearch, findsOneWidget);
      await tester.enterText(paletteSearch, '问数据');
      await tester.pumpAndSettle();
      expect(find.text('打开 问数据'), findsNothing);
      expect(find.text('没有找到'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
