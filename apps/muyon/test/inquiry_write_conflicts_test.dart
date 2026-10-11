import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon/platform/inquiry_record_tools.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';

void main() {
  late Directory root;
  late MuyonHost host;
  late Store store;
  late String supplier;
  final handlers = <String, Future<ToolCallResult> Function(ToolCallContext)>{};
  var sequence = 0;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('wc-c-');
    host = await MuyonHost.open(root.path);
    await host.activateInquiry();
    store = host.inquiry!.runtime.state.store;
    supplier = store.save('supplier', {
      for (final field in Supplier.fields) field: null,
      'name': '冲突夹具',
      'aliases': <String>[],
      'categories': <String>[],
    });
    registerInquiryRecordTools(
      host,
      register:
          ({
            required providerId,
            required descriptor,
            required handler,
            supportedScopes = const {},
            dataModuleIds,
            validateResult,
            preflight,
            effectIntent,
            available = true,
            unavailableReason,
          }) {
            handlers[descriptor.toolId] = handler;
          },
    );
  });
  tearDown(() async {
    await host.close();
    root.deleteSync(recursive: true);
  });

  Future<List<ObjectRef>> refs([List<String>? ids]) async =>
      (await resolveAssistantScope(host, const AssistantScope.global())).objects
          .where((r) => (ids ?? [supplier]).contains(r.objectId))
          .toList();

  Future<ToolCallRequest> request(
    String operation,
    Map<String, Object?> p, {
    List<ObjectRef>? selected,
    String? operationId,
    String? workspace,
  }) async => ToolCallRequest(
    invocationId: 'wc-c-${++sequence}',
    toolId: 'inquiry.$operation',
    scope: AssistantScope.selectedObjects(
      selected ?? await refs(),
      workspaceId: workspace,
    ),
    parameters: {'operation_id': operationId ?? newUuid(), ...p},
  );

  Future<ToolCallResult> direct(ToolCallRequest r, {void Function()? guard}) =>
      handlers[r.toolId]!(
        ToolCallContext(
          request: r,
          resolvedScope: ResolvedAssistantScope(
            requested: r.scope,
            objects: r.scope.objects,
          ),
          cancellation: ToolCancellationToken(),
          checkAuthorization: guard,
        ),
      );

  Future<ToolCallResult> approved(ToolCallRequest r) async {
    final prepared = await host.tools.prepare(r);
    return host.tools.invoke(
      r.withApproval(await host.tools.approve(prepared)),
    );
  }

  Map<String, Object?> edit({int version = 1}) => {
    'type': 'supplier',
    'id': supplier,
    'expected_version': version,
    'values': {'name': '改名'},
  };

  // Compare every stored byte, including payloads, versions, tombstones,
  // change_log and reg4c business receipts, rather than only row counts.
  String snapshot() => jsonEncode({
    for (final table in store.db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ))
      table['name'] as String: [
        for (final row in store.db.select(
            'SELECT * FROM ${table['name']}',
        ))
          row.values.toList(),
      ],
  });

  Future<void> conflict(
    Future<ToolCallResult> Function() invoke,
    String code, {
    Object? version,
  }) async {
    final before = snapshot();
    final result = await invoke();
    expect(result.status, ToolCallStatus.failed);
    expect(result.data['error_code'], code);
    if (version != null) expect(result.data['current_version'], version);
    expect(result.objectRefs, isEmpty);
    expect(result.changes, isEmpty);
    expect(
      snapshot(),
      before,
      reason: 'Conflict must roll back all domain state and receipts',
    );
  }

  test('changed selected snapshot is scope_changed', () async {
    final r = await request('update_record', edit());
    store.save('supplier', {
      ...store.get('supplier', supplier)!.data,
      'notes': '外部改动',
    }, id: supplier);
    await conflict(() => direct(r), 'scope_changed', version: 2);
  });

  test('changed workspace binding is scope_changed', () async {
    final project = store.save('project', {
      for (final field in Project.fields) field: null,
      'code': 'WC-C',
      'name': '项目 A',
      'status': 'active',
      'currency': 'CNY',
      'tax_mode': 'included',
      'markup_rate': '0',
    });
    final other = store.save('project', {
      ...store.get('project', project)!.data,
      'code': 'WC-C-B',
      'name': '项目 B',
    });
    final workspace = await host.workspaces.create('冲突工作区');
    await host.workspaces.bind(
      WorkspaceBinding(
        workspaceId: workspace.id,
        moduleId: 'inquiry',
        nativeProjectId: project,
      ),
    );
    final r = await request(
      'update_record',
      {
        'type': 'project',
        'id': project,
        'expected_version': 1,
        'values': {'name': '改名'},
      },
      selected: await refs([project]),
      workspace: workspace.id,
    );
    await host.workspaces.writeScopeAuthority(
      (db) => db.execute(
        'UPDATE workspace_module_bindings SET native_project_id=? WHERE workspace_id=? AND module_id=?',
        [other, workspace.id, 'inquiry'],
      ),
    );
    await conflict(() => direct(r), 'scope_changed', version: 1);
  });

  for (final changeScope in [false, true]) {
    test(
      'operation ID reuse with changed ${changeScope ? 'scope' : 'parameters'} is structured',
      () async {
        final op = newUuid();
        final p = {
          'type': 'supplier',
          'values': {'name': '新供应商'},
        };
        expect(
          (await approved(await request('create_record', p, operationId: op)))
              .status,
          ToolCallStatus.succeeded,
        );
        final selected = await refs();
        if (changeScope) {
          final other = store.save('supplier', {
            ...store.get('supplier', supplier)!.data,
            'name': '另一对象',
          });
          selected.addAll(await refs([other]));
        }
        final r = await request(
          'create_record',
          changeScope
              ? p
              : {
                  'type': 'supplier',
                  'values': {'name': '不同参数'},
                },
          operationId: op,
          selected: selected,
        );
        await conflict(() => approved(r), 'operation_id_reuse');
      },
    );
  }

  test(
    'fresh selection with stale expected_version reports current version',
    () async {
      store.save('supplier', {
        ...store.get('supplier', supplier)!.data,
        'notes': '已改动',
      }, id: supplier);
      final r = await request('update_record', edit());
      await conflict(() => approved(r), 'version_conflict', version: 2);
    },
  );

  test('target state mismatch is version_conflict', () async {
    final r = await request('restore_record', {
      'type': 'supplier',
      'id': supplier,
      'expected_version': 1,
    });
    await conflict(() => approved(r), 'version_conflict', version: 1);
  });

  for (final stale in [false, true]) {
    test(
      'delete ${stale ? 'changed reference version' : 'incomplete reference preview'} is referencing_changed',
      () async {
        final contact = store.save('contact', {
          for (final field in Contact.fields) field: null,
          'supplier_id': supplier,
          'name': '联系人',
          'phone': '000000',
        });
        final preview = [
          {
            'type': 'contact',
            'id': contact,
            'version': store.get('contact', contact)!.version,
          },
        ];
        if (stale) {
          store.save('contact', {
            ...store.get('contact', contact)!.data,
            'name': '新版本联系人',
          }, id: contact);
          expect(store.get('contact', contact)!.version, 2);
          expect(preview.single['version'], 1);
        }
        // Fresh selection isolates the preview version from selection staleness.
        final r = await request('delete_record', {
          'type': 'supplier',
          'id': supplier,
          'expected_version': 1,
          'referencing_records': stale ? preview : <Object?>[],
        }, selected: await refs([supplier, contact]));
        await conflict(() => approved(r), 'referencing_changed');
      },
    );
  }

  test(
    'late conflict rolls back nested writes and receipts before conversion',
    () async {
      final r = await request('update_record', edit());
      await conflict(
        () => direct(
          r,
          guard: () {
            store.save('supplier', {
              ...store.get('supplier', supplier)!.data,
              'name': '必须回滚',
            }, id: supplier);
            store.db.execute('INSERT INTO meta(key,value) VALUES (?,?)', [
              'reg4c:rollback-probe',
              '{}',
            ]);
            throw WriteConflict(code: 'version_conflict', currentVersion: 2);
          },
        ),
        'version_conflict',
        version: 2,
      );
    },
  );

  test('structured conflict does not renew consumed human approval', () async {
    final r = await request('update_record', edit(version: 99));
    final prepared = await host.tools.prepare(r);
    final authorized = r.withApproval(await host.tools.approve(prepared));
    await conflict(
      () => host.tools.invoke(authorized),
      'version_conflict',
      version: 1,
    );
    final retry = ToolCallRequest(
      invocationId: 'wc-c-retry-${++sequence}',
      toolId: authorized.toolId,
      scope: authorized.scope,
      parameters: authorized.parameters,
      approvalId: authorized.approvalId,
    );
    await expectLater(
      host.tools.invoke(retry),
      throwsA(isA<ToolPlatformException>()),
    );
  });
}
