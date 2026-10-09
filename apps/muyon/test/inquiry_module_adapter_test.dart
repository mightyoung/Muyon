import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supplier_core/supplier_core.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/host_tool_registrar.dart';
import 'package:muyon/platform/grants/host_effect_intent.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/platform/module_grants.dart';
import 'package:muyon/platform/grants/host_tool_authorization.dart';
import 'package:muyon/platform/grants/outbound_content_reviewer.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/fake_v2_module.dart';

void main() {
  test('ready_activation_waits_for_its_pending_host_record', () async {
    final root = Directory.systemTemp.createTempSync(
      'reg4a-activation-record-',
    );
    final release = Completer<void>();
    final entered = Completer<void>();
    late MuyonHost host;
    late Future<void> blocked;
    final module = FakeV2Module(
      'record_gate',
      runtimeFactory: (resources) {
        blocked = (host.workspaces.database as ExclusiveDatabase)
            .exclusiveAsync((_) async {
              entered.complete();
              await release.future;
            });
        return FakeRuntime(resources);
      },
    );
    host = await MuyonHost.open(root.path, modules: [module]);
    final first = host.modules.activate('record_gate');
    try {
      await entered.future;
      await Future<void>.delayed(Duration.zero);
      var completed = false;
      final second = host.modules.activate('record_gate').then((value) {
        completed = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        completed,
        isFalse,
        reason: 'Ready runtime must not bypass pending activation persistence',
      );
      release.complete();
      await first;
      await second;
      await blocked;
    } finally {
      if (!release.isCompleted) release.complete();
      await first;
      await host.close();
      root.deleteSync(recursive: true);
    }
  });
  test('failed_deactivation_withdraws_internal_channels_and_scope', () async {
    final root = Directory.systemTemp.createTempSync('reg4a-withdraw-');
    final host = await MuyonHost.open(root.path);
    try {
      await host.activateInquiry();
      await host.grants.record(
        'inquiry',
        GrantPolicy.legacy('inquiry', {'tools'}),
      );
      host.workspaces.database.raw.execute(
        "CREATE TRIGGER fail_inquiry_revoke BEFORE UPDATE ON module_grants WHEN new.module_id='inquiry' BEGIN SELECT RAISE(ABORT, 'fixture durable revocation failure'); END",
      );
      await expectLater(
        host.modules.revokeCapability('inquiry', 'tools'),
        throwsA(anything),
      );
      expect(
        host.tools.list().where((tool) => tool.providerId == 'inquiry'),
        hasLength(19),
      );
      expect(
        host.tools
            .list()
            .where((tool) => tool.providerId == 'inquiry')
            .every((tool) => !tool.available),
        isTrue,
        reason: 'Both original internal channels must stop with the module',
      );
      expect(
        await host.modules
            .scopeSources()
            .singleWhere((source) => source.moduleId == 'inquiry')
            .enumerate(),
        isEmpty,
      );
    } finally {
      await host.close();
      root.deleteSync(recursive: true);
    }
  });
  test('scope_revision_and_store_effect_match', () async {
    final root = Directory.systemTemp.createTempSync('reg4a-effects-');
    final host = await MuyonHost.open(root.path);
    final legacy = ToolRegistry(
      database: host.workspaces.database,
      resolveScope: host.scopeResolver.resolve,
    );
    try {
      await host.activateInquiry();
      registerInquiryTools(host, register: legacy.register);
      final store = host.inquiry!.runtime.state.store;
      final project = store.save('project', {
        for (final field in Project.fields) field: null,
        'code': 'REG4A',
        'name': '差分项目',
        'status': 'active',
        'type': 'market',
        'level': 'A',
        'currency': 'CNY',
        'tax_mode': 'included',
        'markup_rate': '0',
      });
      final item = store.save('project_item', {
        for (final field in ProjectItem.fields) field: null,
        'project_id': project,
        'category': 'material',
        'name': '电缆',
        'qty': '10',
        'unit': '米',
        'unit_cost': '0',
      });
      final runtime =
          host.modules.runtime<ModuleRuntime>('inquiry')! as ScopeResolvable;
      final session = await runtime.openScopeSession();
      var all = await host.scopeResolver.resolve(const AssistantScope.global());
      for (final ref in all.objects.where((ref) => ref.moduleId == 'inquiry')) {
        expect((await session.resolve(ref))!.ref.toJson(), ref.toJson());
      }
      final before = all.objects.singleWhere((ref) => ref.objectId == item);
      final results = <ToolCallResult>[];
      var n = 0;
      for (final registry in [legacy, host.tools]) {
        all = await host.scopeResolver.resolve(const AssistantScope.global());
        final ref = all.objects.singleWhere((ref) => ref.objectId == item);
        final request = ToolCallRequest(
          invocationId: 'adapter-effect-${n++}',
          toolId: 'inquiry.set_item_qty',
          scope: AssistantScope.selectedObjects([ref]),
          parameters: {'item_id': item, 'from_qty': '10', 'to_qty': '12'},
        );
        expect(registry.isPureLocalWrite(request), isTrue);
        final prepared = await registry.prepare(request);
        expect(prepared.effectIntent, isNotNull);
        await expectLater(
          registry.invoke(request),
          throwsA(isA<ToolPlatformException>()),
        );
        expect(store.get('project_item', item)!.data['qty'], '10');
        final authorization = HostToolAuthorization(
          registry: registry,
          reviewer: const NoopReviewer(),
        );
        final approved = (await authorization.confirm(
          await authorization.review(prepared),
        ))!;
        results.add(await registry.invoke(request.withApproval(approved)));
        expect(store.get('project_item', item)!.data['qty'], '12');
        expect(
          registry.receiptFor(request.invocationId)!.result!.summary,
          results.last.summary,
        );
        store.save('project_item', {
          ...store.get('project_item', item)!.data,
          'qty': '10',
        }, id: item);
      }
      expect(results.map((r) => r.status).toSet(), {ToolCallStatus.succeeded});
      expect(results.first.summary, results.last.summary);
      expect(
        results.first.changes.map((c) => c.ref.objectId),
        results.last.changes.map((c) => c.ref.objectId),
      );
      expect(
        await session.resolve(before),
        isNull,
        reason: 'Old revision/digest must not resolve after writes',
      );
      await session.dispose();
      expect(
        store.get('project_item', item),
        isNotNull,
        reason: 'Session must not close the shared Store',
      );
      final current = (await host.scopeResolver.resolve(
        const AssistantScope.global(),
      )).objects.singleWhere((ref) => ref.objectId == item);
      final queued = ToolCallRequest(
        invocationId: 'adapter-queued-after-stop',
        toolId: 'inquiry.set_item_qty',
        scope: AssistantScope.selectedObjects([current]),
        parameters: {'item_id': item, 'from_qty': '10', 'to_qty': '12'},
      );
      final authorization = HostToolAuthorization(
        registry: host.tools,
        reviewer: const NoopReviewer(),
      );
      final queuedApproval = (await authorization.confirm(
        await authorization.review(await host.tools.prepare(queued)),
      ))!;
      host.modules.stopAdmission();
      await expectLater(
        host.tools.invoke(queued.withApproval(queuedApproval)),
        throwsStateError,
      );
      expect(
        store.get('project_item', item)!.data['qty'],
        '10',
        reason: 'An approved queued write must stop when admission ends',
      );
      host.modules.setRuntimeForTesting('inquiry', null);
      expect(
        await host.modules
            .scopeSources()
            .singleWhere((source) => source.moduleId == 'inquiry')
            .enumerate(),
        isEmpty,
        reason: 'A retained compatibility owner must not expose objects without an active V2 runtime',
      );
    } finally {
      await legacy.close();
      await host.close();
      root.deleteSync(recursive: true);
    }
  });

  test('legacy_and_v2_catalog_match', () async {
    final root = Directory.systemTemp.createTempSync('reg4a-catalog-');
    final host = await MuyonHost.open(root.path);
    try {
      final legacy = _RegistrationCatalog(
        database: host.workspaces.database,
        resolveScope: host.scopeResolver.resolve,
      );
      final adapted = _RegistrationCatalog(
        database: host.workspaces.database,
        resolveScope: host.scopeResolver.resolve,
      );
      registerInquiryTools(host, register: legacy.register);
      final module = host.registry.require('inquiry') as BusinessModuleV2;
      expect(module.ontology.unreviewedFields, isEmpty);
      expect(
        [
          for (final type in module.ontology.objectTypes)
            [
              type.name,
              for (final field in type.fields)
                [
                  field.name,
                  field.label,
                  field.description,
                  field.kind.name,
                  field.required,
                  field.values,
                  field.target,
                ],
            ],
        ],
        [
          for (final type in ontology.values)
            [
              type.name,
              for (final field in type.fields)
                [
                  field.name,
                  field.label,
                  field.description,
                  field.kind.name,
                  field.required,
                  field.values,
                  field.target,
                ],
            ],
        ],
      );
      Set<String> fieldsOf(Sensitivity sensitivity) => {
        for (final type in module.ontology.objectTypes)
          for (final field in type.fields)
            if (field.sensitivity == sensitivity) '${type.name}.${field.name}',
      };
      expect(fieldsOf(Sensitivity.personal), {
        'contact.name',
        'contact.phone',
        'contact.wechat',
        'contact.email',
        'quotation.contact_snapshot',
        'quotation.inquirer_name',
        'project.leader',
      });
      expect(fieldsOf(Sensitivity.commercial), {
        'project.customer',
        'project.contract_no',
        'project.contract_amount',
        'project.markup_rate',
        'project_item.unit_cost',
        'project_item.unit_price',
        'quotation.price',
        'quotation.extra_cost',
        'quotation.deal_price',
        'quotation.price_tiers',
      });

      final registrar = HostToolRegistrar(
        'inquiry',
        adapted,
        module.manifest,
        host.modules,
      );
      module.registerTools(registrar);
      registrar.seal();
      expect(
        adapted.entries,
        legacy.entries,
        reason: 'Preserve every original registration argument',
      );
      final catalog = adapted.entries;
      expect(
        catalog,
        jsonDecode(
          File('test/fixtures/inquiry_legacy_catalog.json').readAsStringSync(),
        ),
      );
      expect(
        catalog.map((entry) => (entry['descriptor'] as Map)['id']).toSet(),
        hasLength(catalog.length),
      );
    } finally {
      await host.close();
      root.deleteSync(recursive: true);
    }
  });
  test('activation_and_shutdown_share_owner', () async {
    final root = Directory.systemTemp.createTempSync('reg4a-adapter-');
    final host = await MuyonHost.open(root.path);
    try {
      final inquiryModules = host.registry.modules.where(
        (m) => m.manifest.id == 'inquiry',
      );
      expect(
        inquiryModules,
        hasLength(1),
        reason: 'Inquiry must enter the V2 catalog',
      );
      expect(inquiryModules.single, isA<BusinessModuleV2>());
      await Future.wait([
        host.activateInquiry(),
        host.modules.activate('inquiry'),
      ]);
      expect(host.inquiryError, isNull);
      expect(host.modules.runtime<ModuleRuntime>('inquiry'), isNotNull);
      final db = host.inquiry!.runtime.state.store.db;
      expect(
        identical(db, host.storage.connectionIfOpen('inquiry')!.raw),
        isTrue,
      );
      await host.close();
      await host.inquiry!.close(); // Shared owner close is idempotent too.
      expect(
        host.tools
            .list()
            .where((t) => t.providerId == 'inquiry')
            .every((t) => !t.available),
        isTrue,
      );
    } finally {
      await host.close();
      root.deleteSync(recursive: true);
    }
  });
}

/// Test-only recorder of the real registry registration contract.
class _RegistrationCatalog extends ToolRegistry {
  _RegistrationCatalog({required super.database, required super.resolveScope});
  final entries = <Map<String, Object?>>[];
  @override
  void register({
    required String providerId,
    required ToolDescriptor descriptor,
    required Future<ToolCallResult> Function(ToolCallContext) handler,
    Set<AssistantScopeKind> supportedScopes = const {
      ...AssistantScopeKind.values,
    },
    Set<String>? dataModuleIds,
    Future<void> Function(ResolvedAssistantScope, ToolCallResult)?
    validateResult,
    void Function(ToolCallRequest)? preflight,
    HostEffectIntent? Function(ToolCallRequest, ResolvedAssistantScope)?
    effectIntent,
    bool available = true,
    String? unavailableReason,
  }) {
    entries.add({
      'descriptor': {
        'id': descriptor.toolId,
        'effect': descriptor.effect.name,
        'description': descriptor.description,
        'parameters': descriptor.parameterSchema,
        'result': descriptor.resultSchema,
        'cancel': descriptor.supportsCancel,
        'selectable': descriptor.modelSelectable,
      },
      'available': available,
      'reason': unavailableReason,
      'scopes': supportedScopes.map((scope) => scope.name).toList()..sort(),
      'dataModules': dataModuleIds?.toList()?..sort(),
      'resultGuard': validateResult != null,
      'destinationGuard': preflight != null,
      'effectIntent': effectIntent != null,
    });
    super.register(
      providerId: providerId,
      descriptor: descriptor,
      handler: handler,
      supportedScopes: supportedScopes,
      dataModuleIds: dataModuleIds,
      validateResult: validateResult,
      preflight: preflight,
      effectIntent: effectIntent,
      available: available,
      unavailableReason: unavailableReason,
    );
  }
}
