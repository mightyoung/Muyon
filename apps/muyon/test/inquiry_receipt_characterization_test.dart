import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';

/// WC-D step 1: pins the current behaviour of the generic write receipts
/// (`reg4c:` meta rows) before the lookup code is extracted. These tests must
/// keep passing unchanged through the refactor.
void main() {
  late Directory root;
  late MuyonHost host;
  late Store store;
  late String supplierId;
  late String otherSupplierId;
  var sequence = 0;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('wcd-characterize-');
    host = await MuyonHost.open(root.path);
    await host.activateInquiry();
    store = host.inquiry!.runtime.state.store;
    supplierId = store.save('supplier', {
      for (final field in Supplier.fields) field: null,
      'name': '公开夹具供应商',
      'aliases': <String>[],
      'categories': <String>[],
    });
    otherSupplierId = store.save('supplier', {
      for (final field in Supplier.fields) field: null,
      'name': '第二供应商',
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
    invocationId: 'wcd-call-${++sequence}',
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

  List<Map<String, Object?>> receiptRows() => [
    for (final row in store.db.select(
      "SELECT key,value FROM meta WHERE key LIKE 'reg4c:%'",
    ))
      Map<String, Object?>.from(row),
  ];

  test(
    'a retry after the object changed returns the original committed result',
    () async {
      final operationId = newUuid();
      final first = await approved(
        await request(
          'update_record',
          edit(supplierId),
          operationId: operationId,
        ),
      );
      expect(first.status, ToolCallStatus.succeeded);
      expect(first.data['version'], 2);

      // Someone else edits the same record afterwards.
      store.save('supplier', {
        ...store.get('supplier', supplierId)!.data,
        'notes': '之后的修改',
      }, id: supplierId);
      expect(store.get('supplier', supplierId)!.version, 3);

      // Same id, same parameters, now with a stale expected_version.
      final retry = await approved(
        await request(
          'update_record',
          edit(supplierId),
          operationId: operationId,
        ),
      );
      expect(retry.status, ToolCallStatus.succeeded);
      expect(retry.data, first.data);
      expect(
        store.get('supplier', supplierId)!.data['notes'],
        '之后的修改',
        reason: 'the retry must not write again',
      );
      expect(store.get('supplier', supplierId)!.version, 3);
    },
  );

  test('the same operation id with another selection is refused', () async {
    final operationId = newUuid();
    await approved(
      await request('update_record', edit(supplierId), operationId: operationId),
    );
    final widened = await approved(
      await request(
        'update_record',
        edit(supplierId, version: 2),
        selected: await selection([supplierId, otherSupplierId]),
        operationId: operationId,
      ),
    );
    expect(widened.status, ToolCallStatus.failed);
    expect(store.get('supplier', otherSupplierId)!.version, 1);
    expect(store.get('supplier', supplierId)!.version, 2);
  });

  test('the same operation id with another tool operation is refused', () async {
    final operationId = newUuid();
    await approved(
      await request('update_record', edit(supplierId), operationId: operationId),
    );
    final deleted = await approved(
      await request(
        'delete_record',
        {
          'type': 'supplier',
          'id': supplierId,
          'expected_version': 2,
          'referencing_records': <Object?>[],
        },
        operationId: operationId,
      ),
    );
    expect(deleted.status, ToolCallStatus.failed);
    expect(store.get('supplier', supplierId)!.deleted, isFalse);
  });

  test('a stored receipt keeps arguments and the committed result only', () async {
    final operationId = newUuid();
    final result = await approved(
      await request('update_record', edit(supplierId), operationId: operationId),
    );
    final rows = receiptRows();
    expect(rows, hasLength(1));
    expect(rows.single['key'], 'reg4c:$operationId');
    final stored = jsonDecode(rows.single['value'] as String) as Map;
    expect(stored.keys.toSet(), {'arguments', 'result'});
    final committed = stored['result'] as Map;
    expect(
      (committed['data'] as Map).keys.toSet(),
      {'operation_id', 'type', 'id', 'version', 'deleted'},
    );
    expect(committed['data'], result.data);
    // Audit §4: `changes` is not persisted with the receipt. Pinned as the
    // current behaviour; a later step that keeps changes must change this test.
    expect(committed.containsKey('changes'), isFalse);
  });

  test('a refused write leaves no receipt for its operation id', () async {
    final operationId = newUuid();
    final stale = await approved(
      await request(
        'update_record',
        edit(supplierId, version: 7),
        operationId: operationId,
      ),
    );
    expect(stale.status, ToolCallStatus.failed);
    expect(
      store.db.select(
        'SELECT key FROM meta WHERE key=?',
        ['reg4c:$operationId'],
      ),
      isEmpty,
    );
  });
}
