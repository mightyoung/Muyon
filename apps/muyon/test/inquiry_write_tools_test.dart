import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/inquiry_plugin.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon/platform/inquiry_write_tools.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:supplier_core/supplier_core.dart';

/// Inquiry write tools: same domain functions as the pages, run only after the
/// host approved the exact old → new change.
void main() {
  late Directory root;
  late MuyonHost host;
  late Store store;
  late String supplierId, projectId, itemId, otherItemId;

  Map<String, Object?> supplier(String name) => {
    'name': name,
    'aliases': <String>[],
    'address': null,
    'categories': <String>[],
    'notes': null,
    'merged_into': null,
    'rating': null,
    'rating_note': null,
  };
  Map<String, Object?> project(String code) => {
    'code': code,
    'name': '项目$code',
    'status': 'active',
    'type': 'market',
    'level': 'A',
    'customer': null,
    'contract_no': null,
    'contract_amount': null,
    'department': null,
    'leader': null,
    'start_date': null,
    'end_date': null,
    'currency': 'CNY',
    'tax_mode': 'included',
    'markup_rate': '0',
    'notes': null,
  };
  Map<String, Object?> item(
    String projectId,
    String name, {
    String qty = '10',
  }) => {
    'project_id': projectId,
    'category': 'material',
    'product_id': null,
    'name': name,
    'qty': qty,
    'unit': '米',
    'quotation_id': null,
    'unit_cost': '0',
    'unit_price': null,
    'notes': null,
  };

  setUp(() async {
    root = Directory.systemTemp.createTempSync('inquiry-write-');
    host = await MuyonHost.open(p.join(root.path, 'data'));
    await host.activateInquiry();
    store = host.inquiry!.runtime.state.store;
    supplierId = store.save('supplier', supplier('甲供应商'));
    projectId = store.save('project', project('P1'));
    itemId = store.save('project_item', item(projectId, '电缆'));
    otherItemId = store.save('project_item', item(projectId, '桥架', qty: '3'));
  });
  tearDown(() async {
    await host.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<List<ObjectRef>> refs(Iterable<String> ids) async {
    final all = await resolveAssistantScope(
      host,
      const AssistantScope.global(),
    );
    return [
      for (final r in all.objects)
        if (ids.contains(r.objectId)) r,
    ];
  }

  var n = 0;
  ToolCallRequest request(
    String tool,
    Map<String, Object?> parameters,
    List<ObjectRef> selected,
  ) => ToolCallRequest(
    invocationId: 'call-${++n}',
    toolId: tool,
    scope: AssistantScope.selectedObjects(selected),
    parameters: parameters,
  );

  Future<ToolCallResult> approved(
    ToolCallRequest r, {
    ToolCancellationToken? token,
  }) async {
    final prepared = await host.tools.prepare(r);
    final id = await host.tools.approve(prepared);
    return host.tools.invoke(r.withApproval(id), cancellation: token);
  }

  int count(String type) =>
      store.db.select('SELECT COUNT(*) c FROM $type WHERE deleted=0').first['c']
          as int;

  Future<String> makeInquiry() async => store.createInquiry(
    projectId,
    '电缆询价',
    itemIds: [itemId],
    supplierIds: [supplierId],
  );

  group('registration', () {
    test(
      'all four are write tools whose descriptions say what they change',
      () {
        for (final id in [
          'inquiry.create_inquiry',
          'inquiry.record_quote',
          'inquiry.set_item_qty',
          'inquiry.set_inquiry_status',
        ]) {
          final info = host.tools.inspect(id)!;
          expect(info.descriptor.effect, ToolEffect.write, reason: id);
          expect(info.descriptor.description, contains('会修改'), reason: id);
          expect(info.descriptor.description, isNot(contains('无需确认')));
          expect(
            info.descriptor.parameterSchema['additionalProperties'],
            false,
          );
        }
      },
    );
  });

  group('create_inquiry', () {
    Map<String, Object?> params() => {
      'project_id': projectId,
      'title': '新询价',
      'item_ids': [itemId, otherItemId],
      'supplier_ids': [supplierId],
    };

    test('refuses to run without host approval', () async {
      final selected = await refs([projectId, itemId, otherItemId, supplierId]);
      await expectLater(
        host.tools.invoke(
          request('inquiry.create_inquiry', params(), selected),
        ),
        throwsA(isA<ToolPlatformException>()),
      );
      expect(count('inquiry'), 0);
    });

    test(
      'runs once after approval and returns refs inside the project',
      () async {
        final selected = await refs([
          projectId,
          itemId,
          otherItemId,
          supplierId,
        ]);
        final r = request('inquiry.create_inquiry', params(), selected);
        final result = await approved(r);
        expect(result.status, ToolCallStatus.succeeded);
        expect(count('inquiry'), 1);
        final created = result.objectRefs.singleWhere(
          (x) => x.objectType == 'inquiry',
        );
        expect(created.nativeProjectId, projectId);
        expect(store.get('inquiry', created.objectId)!.data['status'], 'open');
        // Same invocation again is a replay, not a second inquiry.
        final prepared = await host.tools.prepare(r);
        final id = await host.tools.approve(prepared);
        await host.tools.invoke(r.withApproval(id));
        expect(count('inquiry'), 1);
      },
    );

    test('records and invited parties must all be selected', () async {
      final selected = await refs([
        projectId,
        itemId,
        supplierId,
      ]); // other item missing
      final result = await approved(
        request('inquiry.create_inquiry', params(), selected),
      );
      expect(result.status, ToolCallStatus.failed);
      expect(count('inquiry'), 0);
    });

    test('module validation failure leaves data unchanged', () async {
      // A budget line of another project cannot be put on this inquiry.
      final other = store.save('project', project('P2'));
      final foreign = store.save('project_item', item(other, '别的项目的线'));
      final selected = await refs([projectId, foreign, supplierId]);
      final result = await approved(
        request('inquiry.create_inquiry', {
          ...params(),
          'item_ids': [foreign],
        }, selected),
      );
      expect(result.status, ToolCallStatus.failed);
      expect(count('inquiry'), 0);
    });

    test('empty item or supplier lists never reach the module', () async {
      final selected = await refs([projectId, supplierId]);
      await expectLater(
        host.tools.prepare(
          request('inquiry.create_inquiry', {
            ...params(),
            'item_ids': <String>[],
          }, selected),
        ),
        throwsA(isA<ToolPlatformException>()),
      );
    });

    test('the change appears in the module change log', () async {
      final selected = await refs([projectId, itemId, otherItemId, supplierId]);
      final result = await approved(
        request('inquiry.create_inquiry', params(), selected),
      );
      final created = result.objectRefs.singleWhere(
        (x) => x.objectType == 'inquiry',
      );
      final db = await host.storage.open('inquiry', InquiryPlugin.schema);
      final log = ModuleChangeLog.since(db.raw, 'inquiry', 0);
      expect(
        log.any(
          (c) =>
              c.ref.objectType == 'inquiry' &&
              c.ref.objectId == created.objectId,
        ),
        isTrue,
      );
    });
  });

  group('record_quote', () {
    Future<Map<String, Object?>> params(
      String inquiryId, {
      String? expected,
      String price = '5',
    }) async => {
      'inquiry_id': inquiryId,
      'item_id': itemId,
      'supplier_id': supplierId,
      'price': price,
      'expected_current_price': expected,
    };

    test(
      'creates a quotation, then revises it only from the stated old price',
      () async {
        final inquiryId = await makeInquiry();
        final selected = await refs([inquiryId, itemId, supplierId, projectId]);
        final first = await approved(
          request('inquiry.record_quote', await params(inquiryId), selected),
        );
        expect(first.status, ToolCallStatus.succeeded);
        expect(count('quotation'), 1);

        final selected2 = await refs([
          inquiryId,
          itemId,
          supplierId,
          projectId,
        ]);
        final stale = await approved(
          request(
            'inquiry.record_quote',
            await params(inquiryId, expected: '9', price: '6'),
            selected2,
          ),
        );
        expect(stale.status, ToolCallStatus.failed);
        expect(
          stale.summary,
          contains('5'),
          reason: 'tells the real current price',
        );

        final revised = await approved(
          request(
            'inquiry.record_quote',
            await params(inquiryId, expected: '5', price: '6'),
            selected2,
          ),
        );
        expect(revised.status, ToolCallStatus.succeeded);
        expect(count('quotation'), 1, reason: 'revised, not duplicated');
        final quote =
            store.db
                    .select('SELECT data FROM quotation WHERE deleted=0')
                    .first['data']
                as String;
        expect(quote, contains('"6"'));
      },
    );

    test('a first quote must say there is no current price', () async {
      final inquiryId = await makeInquiry();
      final selected = await refs([inquiryId, itemId, supplierId, projectId]);
      await approved(
        request('inquiry.record_quote', await params(inquiryId), selected),
      );
      final result = await approved(
        request(
          'inquiry.record_quote',
          await params(inquiryId, price: '7'),
          await refs([inquiryId, itemId, supplierId, projectId]),
        ),
      );
      expect(
        result.status,
        ToolCallStatus.failed,
        reason: 'expected null but a quote exists',
      );
    });

    test('a bad price is rejected by the module and changes nothing', () async {
      final inquiryId = await makeInquiry();
      final selected = await refs([inquiryId, itemId, supplierId, projectId]);
      final result = await approved(
        request(
          'inquiry.record_quote',
          await params(inquiryId, price: '-3'),
          selected,
        ),
      );
      expect(result.status, ToolCallStatus.failed);
      expect(count('quotation'), 0);
    });

    test('unselected records are refused', () async {
      final inquiryId = await makeInquiry();
      final selected = await refs([
        inquiryId,
        itemId,
        projectId,
      ]); // supplier missing
      final result = await approved(
        request('inquiry.record_quote', await params(inquiryId), selected),
      );
      expect(result.status, ToolCallStatus.failed);
      expect(count('quotation'), 0);
    });
  });

  group('set_item_qty', () {
    Map<String, Object?> params({String from = '10', String to = '12'}) => {
      'item_id': itemId,
      'from_qty': from,
      'to_qty': to,
    };

    test('changes the quantity and shows old → new in the request', () async {
      final selected = await refs([itemId, projectId]);
      final r = request('inquiry.set_item_qty', params(), selected);
      expect(r.parameters['from_qty'], '10');
      expect(r.parameters['to_qty'], '12');
      final result = await approved(r);
      expect(result.status, ToolCallStatus.succeeded);
      expect(store.get('project_item', itemId)!.data['qty'], '12');
      expect(store.get('project_item', itemId)!.data['name'], '电缆');
      expect(result.objectRefs.single.objectId, itemId);
    });

    test('a wrong old value fails and tells the current one', () async {
      final result = await approved(
        request(
          'inquiry.set_item_qty',
          params(from: '99'),
          await refs([itemId, projectId]),
        ),
      );
      expect(result.status, ToolCallStatus.failed);
      expect(result.summary, contains('10'));
      expect(store.get('project_item', itemId)!.data['qty'], '10');
    });

    test('an invalid quantity is rejected by the module', () async {
      for (final bad in ['0', '-1', 'abc']) {
        final result = await approved(
          request(
            'inquiry.set_item_qty',
            params(to: bad),
            await refs([itemId, projectId]),
          ),
        );
        expect(result.status, ToolCallStatus.failed, reason: bad);
        expect(store.get('project_item', itemId)!.data['qty'], '10');
      }
    });

    test('an item outside the selection is refused', () async {
      final result = await approved(
        request(
          'inquiry.set_item_qty',
          params(),
          await refs([otherItemId, projectId]),
        ),
      );
      expect(result.status, ToolCallStatus.failed);
      expect(store.get('project_item', itemId)!.data['qty'], '10');
    });

    test('cancelling before the effect leaves the data unchanged', () async {
      final r = request(
        'inquiry.set_item_qty',
        params(),
        await refs([itemId, projectId]),
      );
      final prepared = await host.tools.prepare(r);
      final id = await host.tools.approve(prepared);
      final token = ToolCancellationToken()..cancel();
      try {
        final result = await host.tools.invoke(
          r.withApproval(id),
          cancellation: token,
        );
        expect(result.status, ToolCallStatus.cancelled);
      } on ToolCancelled {
        // cancelled before dispatch is also fine
      }
      expect(store.get('project_item', itemId)!.data['qty'], '10');
    });

    test(
      'a record that changed after the preview invalidates the approval',
      () async {
        final r = request(
          'inquiry.set_item_qty',
          params(),
          await refs([itemId, projectId]),
        );
        final prepared = await host.tools.prepare(r);
        final id = await host.tools.approve(prepared);
        store.save('project_item', {
          ...store.get('project_item', itemId)!.data,
          'notes': '别人改了',
        }, id: itemId);
        await expectLater(
          host.tools.invoke(r.withApproval(id)),
          throwsA(anything),
        );
        expect(store.get('project_item', itemId)!.data['qty'], '10');
      },
    );
  });

  group('set_inquiry_status', () {
    test('closes and reopens only from the stated status', () async {
      final inquiryId = await makeInquiry();
      Future<ToolCallResult> run(String from, String to) async => approved(
        request('inquiry.set_inquiry_status', {
          'inquiry_id': inquiryId,
          'from_status': from,
          'to_status': to,
        }, await refs([inquiryId, projectId])),
      );
      expect((await run('closed', 'open')).status, ToolCallStatus.failed);
      expect((await run('open', 'closed')).status, ToolCallStatus.succeeded);
      expect(store.get('inquiry', inquiryId)!.data['status'], 'closed');
      expect((await run('closed', 'open')).status, ToolCallStatus.succeeded);
      expect(store.get('inquiry', inquiryId)!.data['status'], 'open');
    });
  });

  group('result validation', () {
    test(
      'a result that points outside the selected project is rejected',
      () async {
        final inside = (await refs([projectId, itemId])).first;
        final scope = ResolvedAssistantScope(
          requested: AssistantScope.selectedObjects([inside]),
          objects: [inside],
        );
        final foreign = ToolCallResult(
          status: ToolCallStatus.succeeded,
          summary: 'x',
          objectRefs: [
            const ObjectRef(
              moduleId: 'inquiry',
              objectType: 'inquiry',
              objectId: 'z',
              nativeProjectId: 'other-project',
            ),
          ],
        );
        await expectLater(
          validateInquiryWriteResult(scope, foreign),
          throwsA(isA<ToolPlatformException>()),
        );
        final fine = ToolCallResult(
          status: ToolCallStatus.succeeded,
          summary: 'x',
          objectRefs: [
            ObjectRef(
              moduleId: 'inquiry',
              objectType: 'inquiry',
              objectId: 'new',
              nativeProjectId: projectId,
            ),
          ],
        );
        await validateInquiryWriteResult(scope, fine);
      },
    );
  });
}
