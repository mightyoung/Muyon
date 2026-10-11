import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';

// OC-14: characterizes the current inquire update_record value semantics:
// the candidate payload is assembled as all-fields default -> previous record
// -> values, so an omitted key keeps the old value while explicit
// null / '' / 0 / false / [] are passed through to the domain normalizers.
// These tests pin what the code does today; they do not judge it.
void main() {
  late Directory root;
  late MuyonHost host;
  late Store store;
  late String supplierId;
  var sequence = 0;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('oc14-');
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
    invocationId: 'oc14-call-${++sequence}',
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

  Map<String, Object?> update(
    String type,
    String id, {
    required Map<String, Object?> values,
    int version = 1,
  }) => {'type': type, 'id': id, 'expected_version': version, 'values': values};

  String fullSupplier() => store.save('supplier', {
    for (final field in Supplier.fields) field: null,
    'name': '语义夹具供应商',
    'aliases': <String>['别名A', '别名B'],
    'address': '旧地址',
    'categories': <String>['类别A'],
    'notes': '旧备注',
    'rating': 'preferred',
    'rating_note': '旧评价',
  });

  String fullContact() => store.save('contact', {
    for (final field in Contact.fields) field: null,
    'supplier_id': supplierId,
    'name': '公开联系人',
    'phone': '13800000000',
    'wechat': 'wx-public',
    'email': 'public@example.com',
    'notes': '联系人备注',
  });

  ({String project, String item, String inquiry, String quote}) quoteFixture() {
    final project = store.save('project', {
      for (final field in Project.fields) field: null,
      'code': 'OC14',
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
      leadTimeDays: 5,
      notes: '报价备注',
    );
    return (project: project, item: item, inquiry: inquiry, quote: quote);
  }

  test(
    'omitted fields keep previous values and the update bumps the version',
    () async {
      final id = fullSupplier();
      final result = await approved(
        await request(
          'update_record',
          update('supplier', id, values: {'address': '新地址'}),
          selected: await selection([id]),
        ),
      );
      expect(result.status, ToolCallStatus.succeeded);
      final after = store.get('supplier', id)!;
      expect(after.data['address'], '新地址');
      expect(after.data['name'], '语义夹具供应商');
      expect(after.data['aliases'], ['别名A', '别名B']);
      expect(after.data['categories'], ['类别A']);
      expect(after.data['notes'], '旧备注');
      expect(after.data['rating'], 'preferred');
      expect(after.data['rating_note'], '旧评价');
      expect(after.version, 2);
    },
  );

  test('explicit null clears contact phone and quotation notes', () async {
    final contactId = fullContact();
    final contactResult = await approved(
      await request(
        'update_record',
        update('contact', contactId, values: {'phone': null}),
        selected: await selection([contactId]),
      ),
    );
    expect(contactResult.status, ToolCallStatus.succeeded);
    final contact = store.get('contact', contactId)!;
    expect(contact.data['phone'], isNull);
    expect(contact.data['wechat'], 'wx-public');
    expect(contact.data['email'], 'public@example.com');
    expect(contact.data['notes'], '联系人备注');
    expect(contact.version, 2);

    final f = quoteFixture();
    final before = store.get('quotation', f.quote)!;
    expect(before.data['notes'], '报价备注');
    final quoteResult = await approved(
      await request(
        'update_record',
        update('quotation', f.quote, values: {'notes': null}),
        selected: await selection([f.quote]),
      ),
    );
    expect(quoteResult.status, ToolCallStatus.succeeded);
    final quote = store.get('quotation', f.quote)!;
    expect(quote.data['notes'], isNull);
    expect(quote.version, before.version + 1);
  });

  test('empty string clears contact phone like null', () async {
    final contactId = fullContact();
    final result = await approved(
      await request(
        'update_record',
        update('contact', contactId, values: {'phone': ''}),
        selected: await selection([contactId]),
      ),
    );
    expect(result.status, ToolCallStatus.succeeded);
    final after = store.get('contact', contactId)!;
    expect(after.data['phone'], isNull);
    expect(after.data['wechat'], 'wx-public');
    expect(after.data['email'], 'public@example.com');
    expect(after.version, 2);
  });

  test('integer zero is stored as zero, not treated as omitted', () async {
    final f = quoteFixture();
    expect(store.get('quotation', f.quote)!.data['lead_time_days'], 5);
    final result = await approved(
      await request(
        'update_record',
        update('quotation', f.quote, values: {'lead_time_days': 0}),
        selected: await selection([f.quote]),
      ),
    );
    expect(result.status, ToolCallStatus.succeeded);
    final after = store.get('quotation', f.quote)!;
    expect(after.data['lead_time_days'], 0);
    expect(after.data['notes'], '报价备注');
    expect(after.version, 2);
  });

  test('boolean false is refused because no exposed record type has a boolean field', () async {
    for (final type in [
      'supplier',
      'contact',
      'product',
      'project',
      'project_item',
      'inquiry',
      'quotation',
    ]) {
      expect(
        ontology[type]!.fields.where((f) => f.kind == Kind.boolean),
        isEmpty,
        reason: type,
      );
    }
    final id = fullSupplier();
    await expectLater(
      host.tools.prepare(
        await request(
          'update_record',
          update('supplier', id, values: {'notes': false}),
          selected: await selection([id]),
        ),
      ),
      throwsA(isA<ToolPlatformException>()),
    );
    final after = store.get('supplier', id)!;
    expect(after.data['notes'], '旧备注');
    expect(after.version, 1);
  });

  test('empty list replaces aliases with an empty list', () async {
    final id = fullSupplier();
    final result = await approved(
      await request(
        'update_record',
        update('supplier', id, values: {'aliases': <String>[]}),
        selected: await selection([id]),
      ),
    );
    expect(result.status, ToolCallStatus.succeeded);
    final after = store.get('supplier', id)!;
    expect(after.data['aliases'], <String>[]);
    expect(after.data['aliases'], isNotNull);
    expect(after.data['categories'], ['类别A']);
    expect(after.data['notes'], '旧备注');
    expect(after.version, 2);
  });

  test('empty values map is refused before approval', () async {
    final id = fullSupplier();
    await expectLater(
      host.tools.prepare(
        await request(
          'update_record',
          update('supplier', id, values: <String, Object?>{}),
          selected: await selection([id]),
        ),
      ),
      throwsA(isA<ToolPlatformException>()),
    );
    final after = store.get('supplier', id)!;
    expect(after.data['notes'], '旧备注');
    expect(after.version, 1);
  });
}
