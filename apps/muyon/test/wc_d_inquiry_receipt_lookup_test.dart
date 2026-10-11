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
    final query = await queryFor(operationId, parameters: edit(supplierId));

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

  test(
    'a corrupt or inconsistent receipt is unreadable, never notFound',
    () async {
      final operationId = await commitUpdate();
      final query = await queryFor(operationId, parameters: edit(supplierId));
      final key = 'reg4c:$operationId';
      final original =
          store.db.select('SELECT value FROM meta WHERE key=?', [
                key,
              ]).single['value']
              as String;

      store.db.execute('UPDATE meta SET value=? WHERE key=?', [
        '{not json',
        key,
      ]);
      expect(
        lookupInquiryReceipt(store.db, query).status,
        BusinessReceiptStatus.unreadable,
      );

      final record = jsonDecode(original) as Map<String, Object?>;
      final committed = record['result'] as Map<String, Object?>;
      (committed['objectRefs'] as List)
              .cast<Map<String, Object?>>()
              .single['objectId'] =
          otherSupplierId;
      store.db.execute('UPDATE meta SET value=? WHERE key=?', [
        jsonEncode(record),
        key,
      ]);
      expect(
        lookupInquiryReceipt(store.db, query).status,
        BusinessReceiptStatus.unreadable,
      );
    },
  );

  // These rows are deliberately corrupted after a real committed write;
  // they are not evidence that the writer normally produces malformed rows.
  final corruptions = <String, void Function(Map<String, Object?>)>{
    for (final field in ['type', 'id', 'version', 'deleted', 'operation_id'])
      for (final missing in [true, false])
        '${missing ? 'missing' : 'null'} data.$field': (record) {
          final data = (record['result'] as Map)['data'] as Map;
          if (missing) {
            data.remove(field);
          } else {
            data[field] = null;
          }
        },
    for (final field in ['type', 'id', 'expected_version', 'operation_id'])
      for (final missing in [true, false])
        '${missing ? 'missing' : 'null'} request.$field': (record) {
          final args = jsonDecode(record['arguments'] as String) as Map;
          final parameters = args['parameters'] as Map;
          if (missing) {
            parameters.remove(field);
          } else {
            parameters[field] = null;
          }
          record['arguments'] = jsonEncode(args);
        },
    'unsupported operation': (record) {
      final args = jsonDecode(record['arguments'] as String) as Map;
      args['operation'] = 'unknown_record';
      record['arguments'] = jsonEncode(args);
    },
    'version disagrees with revision': (record) {
      ((record['result'] as Map)['data'] as Map)['version'] = 999;
    },
    'version and revision disagree with committed baseline': (record) {
      ((record['result'] as Map)['data'] as Map)['version'] = 999;
      (((record['result'] as Map)['objectRefs'] as List).single
              as Map)['revisionRef'] =
          '999';
    },
    'result type and ref disagree with request type': (record) {
      ((record['result'] as Map)['data'] as Map)['type'] = 'product';
      (((record['result'] as Map)['objectRefs'] as List).single
              as Map)['objectType'] =
          'product';
    },
    'zero version': (record) {
      ((record['result'] as Map)['data'] as Map)['version'] = 0;
      (((record['result'] as Map)['objectRefs'] as List).single
              as Map)['revisionRef'] =
          '0';
    },
    'fractional version': (record) {
      ((record['result'] as Map)['data'] as Map)['version'] = 2.5;
    },
    'string deleted': (record) {
      ((record['result'] as Map)['data'] as Map)['deleted'] = 'false';
    },
    'update marked deleted': (record) {
      ((record['result'] as Map)['data'] as Map)['deleted'] = true;
    },
    for (final missing in [true, false])
      '${missing ? 'missing' : 'null'} revision': (record) {
        final ref =
            (((record['result'] as Map)['objectRefs'] as List).single as Map);
        if (missing) {
          ref.remove('revisionRef');
        } else {
          ref['revisionRef'] = null;
        }
      },
  };
  for (final entry in corruptions.entries) {
    test('stored receipt integrity rejects ${entry.key}', () async {
      final operationId = await commitUpdate();
      final query = await queryFor(operationId, parameters: edit(supplierId));
      final key = 'reg4c:$operationId';
      final record = jsonDecode(
        store.db.select('SELECT value FROM meta WHERE key=?', [
              key,
            ]).single['value']
            as String,
      ) as Map<String, Object?>;
      entry.value(record);
      store.db.execute('UPDATE meta SET value=? WHERE key=?', [
        jsonEncode(record),
        key,
      ]);
      final before = store.db.select('SELECT total_changes() AS n').single['n'];
      final result = lookupInquiryReceipt(store.db, query);
      expect(result.status, BusinessReceiptStatus.unreadable);
      expect(result.succeeded, isFalse);
      expect(result.receipt, isNull);
      expect(
        store.db.select('SELECT total_changes() AS n').single['n'],
        before,
      );
    });
  }

  test(
    'stored receipt integrity binds result target to original request',
    () async {
      final operationId = await commitUpdate();
      final query = await queryFor(operationId, parameters: edit(supplierId));
      final key = 'reg4c:$operationId';
      final record = jsonDecode(
        store.db.select('SELECT value FROM meta WHERE key=?', [
              key,
            ]).single['value']
            as String,
      ) as Map<String, Object?>;
      final result = record['result'] as Map;
      (result['data'] as Map)['id'] = otherSupplierId;
      ((result['objectRefs'] as List).single as Map)['objectId'] =
          otherSupplierId;
      store.db.execute('UPDATE meta SET value=? WHERE key=?', [
        jsonEncode(record),
        key,
      ]);
      final found = lookupInquiryReceipt(store.db, query);
      expect(found.status, BusinessReceiptStatus.unreadable);
      expect(found.succeeded, isFalse);
    },
  );

  for (final operation in [
    'create_record',
    'delete_record',
    'restore_record',
  ]) {
    test('valid $operation receipt preserves committed result', () async {
      var objects = await selection();
      if (operation == 'restore_record') {
        final deleted = await approved(
          await request('delete_record', {
            'type': 'supplier',
            'id': supplierId,
            'expected_version': 1,
            'referencing_records': <Object?>[],
          }, operationId: newUuid()),
        );
        expect(deleted.status, ToolCallStatus.succeeded);
        objects = deleted.objectRefs;
      }
      final parameters = <String, Object?>{
        'type': 'supplier',
        if (operation == 'create_record')
          'values': {'name': '新供应商'}
        else ...{
          'id': supplierId,
          'expected_version': store.get('supplier', supplierId)!.version,
          if (operation == 'delete_record') 'referencing_records': <Object?>[],
        },
      };
      final operationId = newUuid();
      final committed = await approved(
        await request(
          operation,
          parameters,
          selected: objects,
          operationId: operationId,
        ),
      );
      expect(committed.status, ToolCallStatus.succeeded);
      final query = await queryFor(
        operationId,
        operation: operation,
        parameters: parameters,
        selected: objects,
      );
      final found = lookupInquiryReceipt(store.db, query);
      expect(found.status, BusinessReceiptStatus.matched);
      expect(found.succeeded, isTrue);
      for (final field in ['type', 'id', 'version', 'deleted']) {
        expect(found.receipt!.resultData[field], committed.data[field]);
      }
      final key = 'reg4c:$operationId';
      final record = jsonDecode(
        store.db.select('SELECT value FROM meta WHERE key=?', [
              key,
            ]).single['value']
            as String,
      ) as Map;
      final result = record['result'] as Map;
      final data = result['data'] as Map;
      if (operation == 'create_record') {
        data['version'] = 2;
        ((result['objectRefs'] as List).single as Map)['revisionRef'] = '2';
      } else {
        data['deleted'] = operation != 'delete_record';
      }
      store.db.execute('UPDATE meta SET value=? WHERE key=?', [
        jsonEncode(record),
        key,
      ]);
      final corrupt = lookupInquiryReceipt(store.db, query);
      expect(corrupt.status, BusinessReceiptStatus.unreadable);
      expect(corrupt.succeeded, isFalse);
    });
  }

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
        db
            .select('SELECT COUNT(*) AS n, SUM(version) AS v FROM supplier')
            .single
            .values
            .toList(),
        db.select('SELECT COUNT(*) AS n FROM meta').single.values.toList(),
        db
            .select('SELECT COUNT(*) AS n FROM muyon_change_log')
            .single
            .values
            .toList(),
        foundation
            .select('SELECT COUNT(*) AS n FROM tool_approvals')
            .single
            .values
            .toList(),
        foundation
            .select('SELECT COUNT(*) AS n FROM tool_invocation_receipts')
            .single
            .values
            .toList(),
        foundation
            .select('SELECT COUNT(*) AS n FROM notifications')
            .single
            .values
            .toList(),
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

  Map<String, Object?> storedRecord(String operationId) => jsonDecode(
    store.db.select('SELECT value FROM meta WHERE key=?', [
          'reg4c:$operationId',
        ]).single['value']
        as String,
  ) as Map<String, Object?>;

  void storeRecord(String operationId, Map<String, Object?> record) =>
      store.db.execute('UPDATE meta SET value=? WHERE key=?', [
        jsonEncode(record),
        'reg4c:$operationId',
      ]);

  /// Edits the stored request (`arguments`) only; the caller's query stays
  /// the original request, so any accepted tampering would show as a conflict.
  void tamperArguments(
    Map<String, Object?> record,
    void Function(Map<String, Object?> args) change,
  ) {
    final args =
        jsonDecode(record['arguments'] as String) as Map<String, Object?>;
    change(args);
    record['arguments'] = jsonEncode(args);
  }

  test(
    'a create receipt whose result id is not a lowercase UUID is unreadable',
    () async {
      final operationId = newUuid();
      final parameters = <String, Object?>{
        'type': 'supplier',
        'values': {'name': '新供应商'},
      };
      final committed = await approved(
        await request('create_record', parameters, operationId: operationId),
      );
      expect(committed.status, ToolCallStatus.succeeded);
      final query = await queryFor(
        operationId,
        operation: 'create_record',
        parameters: parameters,
      );
      expect(lookupInquiryReceipt(store.db, query).succeeded, isTrue);

      final record = storedRecord(operationId);
      final result = record['result'] as Map<String, Object?>;
      (result['data'] as Map)['id'] = 'not-a-uuid';
      ((result['objectRefs'] as List).single as Map)['objectId'] = 'not-a-uuid';
      storeRecord(operationId, record);

      final found = lookupInquiryReceipt(store.db, query);
      expect(found.status, BusinessReceiptStatus.unreadable);
      expect(found.succeeded, isFalse);
      expect(found.receipt, isNull);
    },
  );

  final structureCases = <String, void Function(Map<String, Object?> args)>{
    'create values removed': (a) => (a['parameters'] as Map).remove('values'),
    'create values null': (a) => (a['parameters'] as Map)['values'] = null,
    'create values string': (a) => (a['parameters'] as Map)['values'] = 'x',
    'update values removed': (a) => (a['parameters'] as Map).remove('values'),
    'update values null': (a) => (a['parameters'] as Map)['values'] = null,
    'update values string': (a) => (a['parameters'] as Map)['values'] = 'x',
    'delete referencing_records removed': (a) =>
        (a['parameters'] as Map).remove('referencing_records'),
    'delete referencing_records null': (a) =>
        (a['parameters'] as Map)['referencing_records'] = null,
    'delete referencing_records map': (a) =>
        (a['parameters'] as Map)['referencing_records'] = <String, Object?>{},
    'scope removed': (a) => a.remove('scope'),
    'scope null': (a) => a['scope'] = null,
    'scope number': (a) => a['scope'] = 3,
    'scope empty object': (a) => a['scope'] = '{}',
    'scope object item not a tuple': (a) => a['scope'] = jsonEncode({
      'workspace': null,
      'objects': ['not-a-tuple'],
    }),
  };
  for (final entry in structureCases.entries) {
    final operation = entry.key.startsWith('create')
        ? 'create_record'
        : entry.key.startsWith('delete')
        ? 'delete_record'
        : 'update_record';
    test(
      'historical $operation receipt with ${entry.key} is unreadable',
      () async {
        final operationId = newUuid();
        late Map<String, Object?> parameters;
        if (operation == 'create_record') {
          parameters = {
            'type': 'supplier',
            'values': {'name': '新供应商'},
          };
        } else if (operation == 'update_record') {
          parameters = edit(supplierId);
        } else {
          parameters = {
            'type': 'supplier',
            'id': supplierId,
            'expected_version': 1,
            'referencing_records': <Object?>[],
          };
        }
        final committed = await approved(
          await request(operation, parameters, operationId: operationId),
        );
        expect(committed.status, ToolCallStatus.succeeded);
        final query = await queryFor(
          operationId,
          operation: operation,
          parameters: parameters,
        );
        final record = storedRecord(operationId);
        tamperArguments(record, entry.value);
        storeRecord(operationId, record);

        final found = lookupInquiryReceipt(store.db, query);
        expect(found.status, BusinessReceiptStatus.unreadable);
        expect(found.succeeded, isFalse);
        expect(found.receipt, isNull);
      },
    );
  }

  test('runtime acceptance: the four lookup outcomes change no totals and notify nobody', () async {
    final runtime = host.modules.runtime<InquiryModuleRuntime>('inquiry')!;
    final operationId = await commitUpdate();
    final matchedQuery = await queryFor(
      operationId,
      parameters: edit(supplierId),
    );
    final conflictQuery = await queryFor(
      operationId,
      parameters: edit(supplierId, values: {'notes': '别的内容'}),
    );
    final missingQuery = await queryFor(
      newUuid(),
      parameters: edit(supplierId),
    );
    final corruptOperation = newUuid();
    store.db.execute('INSERT INTO meta(key,value) VALUES(?,?)', [
      'reg4c:$corruptOperation',
      '{not json',
    ]);
    final corruptQuery = await queryFor(
      corruptOperation,
      parameters: edit(supplierId),
    );
    final rowsBefore = store.db
        .select('SELECT COUNT(*) AS n FROM supplier')
        .single['n'];
    final versionBefore = store.get('supplier', supplierId)!.version;

    var notified = 0;
    void onChange() => notified++;
    final state = host.inquiry!.runtime.state;
    state.addListener(onChange);
    addTearDown(() => state.removeListener(onChange));

    final paths = <(String, BusinessReceiptQuery, BusinessReceiptStatus)>[
      ('matched', matchedQuery, BusinessReceiptStatus.matched),
      (
        'identityConflict',
        conflictQuery,
        BusinessReceiptStatus.identityConflict,
      ),
      ('notFound', missingQuery, BusinessReceiptStatus.notFound),
      ('unreadable', corruptQuery, BusinessReceiptStatus.unreadable),
    ];
    for (final (name, query, status) in paths) {
      final domainBefore = store.db
          .select('SELECT total_changes() AS n')
          .single['n'];
      final hostBefore = host.foundation.database.raw
          .select('SELECT total_changes() AS n')
          .single['n'];
      final result = await runtime.lookupBusinessReceipt(query);
      expect(result.status, status, reason: name);
      expect(
        store.db.select('SELECT total_changes() AS n').single['n'],
        domainBefore,
        reason: '$name changed the domain library',
      );
      expect(
        host.foundation.database.raw
            .select('SELECT total_changes() AS n')
            .single['n'],
        hostBefore,
        reason: '$name changed the host library',
      );
    }
    expect(notified, 0);
    expect(
      store.db.select('SELECT COUNT(*) AS n FROM supplier').single['n'],
      rowsBefore,
    );
    expect(store.get('supplier', supplierId)!.version, versionBefore);
  });
}
