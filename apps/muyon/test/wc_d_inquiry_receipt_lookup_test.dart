import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/adapters/inquiry_module.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon/platform/inquiry_receipt_lookup.dart';
import 'package:muyon/platform/inquiry_write_receipts.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';

/// WC-D step 3: read-only lookup of committed generic write receipts.
void main() {
  late Directory root;
  late MuyonHost host;
  late Store store;
  late String supplierId;
  late String otherSupplierId;
  var sequence = 0;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('wc-d-lookup-');
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
    required String operationId,
  }) async => ToolCallRequest(
    invocationId: 'wc-d-call-${++sequence}',
    toolId: 'inquiry.$operation',
    scope: AssistantScope.selectedObjects(selected ?? await selection()),
    parameters: {'operation_id': operationId, ...p},
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

  /// What the caller computes from the original request, not from storage.
  Future<BusinessReceiptQuery> queryFor(
    String operationId, {
    String operation = 'update_record',
    required Map<String, Object?> parameters,
    List<ObjectRef>? selected,
    String? toolId,
    String? domainIdentity,
  }) async {
    final objects = selected ?? await selection();
    final identity = GenericWriteIdentity(
      operation: operation,
      parameters: {'operation_id': operationId, ...parameters},
      workspaceId: null,
      objects: objects,
    );
    return BusinessReceiptQuery(
      operationId: operationId,
      requestDigest: identity.requestDigest,
      toolId: toolId ?? identity.toolId,
      scopeDigest: identity.scopeDigest,
      domainIdentity: domainIdentity ?? inquiryDomainIdentity(store.db),
    );
  }

  Future<String> commitUpdate({List<ObjectRef>? selected}) async {
    final operationId = newUuid();
    final result = await approved(
      await request(
        'update_record',
        edit(supplierId),
        selected: selected,
        operationId: operationId,
      ),
    );
    expect(result.status, ToolCallStatus.succeeded);
    return operationId;
  }

  test('a committed update is found after the object changes, with its old version', () async {
    final operationId = await commitUpdate();
    final query = await queryFor(
      operationId,
      parameters: edit(supplierId),
    );

    final first = lookupInquiryReceipt(store.db, query);
    expect(first.status, BusinessReceiptStatus.matched);
    expect(first.succeeded, isTrue);
    expect(first.receipt!.resultData['version'], 2);

    store.save('supplier', {
      ...store.get('supplier', supplierId)!.data,
      'notes': '之后的修改',
    }, id: supplierId);
    expect(store.get('supplier', supplierId)!.version, 3);

    final later = lookupInquiryReceipt(store.db, query);
    expect(later.status, BusinessReceiptStatus.matched);
    expect(later.receipt!.resultData['version'], 2);
  });

  test('the same id with other parameters, scope, tool or domain is an identity conflict', () async {
    final operationId = await commitUpdate();
    final base = await queryFor(operationId, parameters: edit(supplierId));
    final cases = <String, BusinessReceiptQuery>{
      'parameters': await queryFor(
        operationId,
        parameters: edit(supplierId, values: {'notes': '别的内容'}),
      ),
      'scope': await queryFor(
        operationId,
        parameters: edit(supplierId),
        selected: await selection([supplierId, otherSupplierId]),
      ),
      'tool': await queryFor(
        operationId,
        parameters: edit(supplierId),
        toolId: 'inquiry.delete_record',
      ),
      'domain library': await queryFor(
        operationId,
        parameters: edit(supplierId),
        domainIdentity: 'inquiry-db:another-library',
      ),
    };
    expect(lookupInquiryReceipt(store.db, base).succeeded, isTrue);
    for (final entry in cases.entries) {
      final result = lookupInquiryReceipt(store.db, entry.value);
      expect(
        result.status,
        BusinessReceiptStatus.identityConflict,
        reason: entry.key,
      );
      expect(result.succeeded, isFalse, reason: entry.key);
    }
  });

  test('a corrupt or inconsistent receipt is unreadable, never notFound', () async {
    final operationId = await commitUpdate();
    final query = await queryFor(operationId, parameters: edit(supplierId));
    final key = 'reg4c:$operationId';
    final original = store.db.select('SELECT value FROM meta WHERE key=?', [key]).single['value'] as String;

    store.db.execute('UPDATE meta SET value=? WHERE key=?', ['{not json', key]);
    expect(lookupInquiryReceipt(store.db, query).status, BusinessReceiptStatus.unreadable);

    final record = jsonDecode(original) as Map<String, Object?>;
    final committed = record['result'] as Map<String, Object?>;
    (committed['objectRefs'] as List).cast<Map<String, Object?>>().single['objectId'] = otherSupplierId;
    store.db.execute('UPDATE meta SET value=? WHERE key=?', [jsonEncode(record), key]);
    expect(lookupInquiryReceipt(store.db, query).status, BusinessReceiptStatus.unreadable);
  });

  test('an unknown operation id is notFound', () async {
    final query = await queryFor(newUuid(), parameters: edit(supplierId));
    final result = lookupInquiryReceipt(store.db, query);
    expect(result.status, BusinessReceiptStatus.notFound);
    expect(result.succeeded, isFalse);
  });

  test('the lookup writes nothing: no rows, log, approvals, receipts or notifications', () async {
    final operationId = await commitUpdate();
    final matched = await queryFor(operationId, parameters: edit(supplierId));
    final conflict = await queryFor(
      operationId,
      parameters: edit(supplierId, values: {'notes': 'x'}),
    );
    final missing = await queryFor(newUuid(), parameters: edit(supplierId));

    List<Object?> snapshot() {
      final db = store.db;
      final foundation = host.foundation.database.raw;
      return [
        db.select('SELECT COUNT(*) AS n, SUM(version) AS v FROM supplier').single.values.toList(),
        db.select('SELECT COUNT(*) AS n FROM meta').single.values.toList(),
        db.select('SELECT COUNT(*) AS n FROM muyon_change_log').single.values.toList(),
        foundation.select('SELECT COUNT(*) AS n FROM tool_approvals').single.values.toList(),
        foundation.select('SELECT COUNT(*) AS n FROM tool_invocation_receipts').single.values.toList(),
        foundation.select('SELECT COUNT(*) AS n FROM notifications').single.values.toList(),
      ];
    }

    final before = snapshot();
    lookupInquiryReceipt(store.db, matched);
    lookupInquiryReceipt(store.db, conflict);
    lookupInquiryReceipt(store.db, missing);
    expect(snapshot(), before);
  });

  test('the module declares the businessReceipts feature', () {
    final manifest = InquiryBusinessModule(() => host).manifest;
    expect(manifest.features, contains(ModuleFeature.businessReceipts));
  });
}
