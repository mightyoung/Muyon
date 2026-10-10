import 'dart:async';

import '../platform/inquiry_ui_planning_source.dart';
import '../assistant/ui_presentation_preference.dart';
import '../services/knowledge/registered_research_source.dart';

import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:prototype_module/prototype_module.dart';
import 'package:research_module/research_module.dart';

import '../platform/module_grants.dart';
import '../platform/outbound_ledger.dart';
import '../platform/projection_service.dart';
import '../platform/schema_catalog.dart';
import '../platform/storage_manager.dart';
import '../platform/grants/host_scope_authority.dart';
import '../platform/grants/grant_store.dart';
import '../platform/grants/host_authorization_policy.dart';
import '../platform/grants/host_model_authorization.dart';
import '../assistant/model_request_gate.dart';
import '../platform/grants/outbound_content_reviewer.dart';
import '../workspace/workspace_repository.dart';
import '../platform/scope_resolver.dart';
import 'module_catalog.dart';
import 'module_host.dart';
import 'module_registry.dart';
import 'legacy_module_bridge.dart';
import 'accepted_research_imports.dart';
import '../assistant/execution_store.dart';
import '../assistant/dream/dream_service.dart';
import '../assistant/personal_agent.dart';
import '../platform/foundation_repository.dart';
import '../platform/memory_review.dart';
import '../platform/tool_registry.dart';
import '../platform/business_tools.dart';
import '../services/knowledge/index_invalidation.dart';
import '../services/transfer/task_coordinator.dart';
import '../services/public_services.dart';
import '../services/models/model_gateway.dart';
import '../services/models/model_provider.dart';
import '../services/models/secret_store.dart';
import '../services/models/profile_repository.dart';
import 'inquiry_plugin.dart';
import 'adapters/inquiry_module.dart';
import 'research_task_bridge.dart';

import 'package:uuid/uuid.dart';

/// Settings key and value of the one-time capability migration.
const modelProfilesSchemaKey = 'modelProfilesSchema';
const modelProfilesSchemaVersion = 2;

/// Set when the migration changed profiles, so the settings page can tell the
/// person once ("streaming is now on for your models"); the page reads it with
/// [pendingModelProfilesNotice] and clears it with
/// [clearModelProfilesNotice].
const modelProfilesNoticeKey = 'modelProfilesMigrationNotice';

/// How many profiles the migration changed, while its notice is still to be
/// shown; null when there is nothing to tell.
int? pendingModelProfilesNotice(WorkspaceRepository workspaces) {
  final notice = workspaces.setting(modelProfilesNoticeKey);
  if (notice is! Map || notice['pending'] != true) return null;
  final count = notice['migrated'];
  return count is int && count > 0 ? count : null;
}

/// The notice has been shown: it does not come back.
Future<void> clearModelProfilesNotice(WorkspaceRepository workspaces) =>
    workspaces.setSetting(modelProfilesNoticeKey, {'pending': false});

/// One-time, idempotent: a saved chat profile with no `capabilities` gets
/// `{streaming: true, source: migrated}` written out (every other capability
/// conservative); embedding profiles are untouched (ADR-0005 §4.3). Runs once
/// per workspace database, marked by [modelProfilesSchemaKey], so a person who
/// turns streaming off is not changed back on the next start. Deliberately not
/// part of `ProfileRepository.all()`: reading stays free of side effects.
/// Returns how many profiles were changed.
Future<int> migrateModelProfileCapabilities(
  WorkspaceRepository workspaces,
) async {
  final done = workspaces.setting(modelProfilesSchemaKey);
  if (done is int && done >= modelProfilesSchemaVersion) return 0;
  final stored = workspaces.setting('modelProfiles');
  var changed = 0;
  if (stored is List) {
    final migrated = <Object?>[];
    for (final item in stored) {
      if (item is Map &&
          !item.containsKey('capabilities') &&
          (item['purpose'] as String? ?? 'chat') == ModelPurpose.chat.name) {
        migrated.add({
          ...item,
          'capabilities': const ModelCapabilities(
            streaming: true,
            source: CapabilitySource.migrated,
          ).toJson(),
        });
        changed++;
      } else {
        migrated.add(item);
      }
    }
    if (changed > 0) {
      await workspaces.setSetting('modelProfiles', migrated);
      await workspaces.setSetting(modelProfilesNoticeKey, {
        'pending': true,
        'migrated': changed,
      });
    }
  }
  await workspaces.setSetting(
    modelProfilesSchemaKey,
    modelProfilesSchemaVersion,
  );
  return changed;
}

class MuyonHost {
  MuyonHost._(this.storage, this.workspaces, this.registry, this.capabilities);
  final StorageManager storage;
  final WorkspaceRepository workspaces;
  final ModuleRegistry registry;
  final CapabilityRegistry capabilities;
  late final FoundationRepository foundation;
  late final MemoryReviewService memoryReview;
  late final ToolRegistry tools;
  late final PublicServices services;
  late final PersonalAgent personalAgent;
  late final TaskCoordinator tasks;
  late final ResearchTaskBridge researchTasks;
  late final DreamService dream;
  late final ProjectionService projections;
  late final OutboundLedger outbound;
  Future<bool> Function(InquiryModelApprovalPreview preview)?
  approveInquiryModelRequest;
  late final AcceptedResearchImports acceptedResearchImports;
  late final ModuleGrants grants;
  late final ModuleHost modules;
  late final ScopeResolver scopeResolver;
  late final HostScopeAuthority scopeAuthority;
  late final GrantStore assistantGrants;
  late final HostAuthorizationPolicy authorizationPolicy;

  // v1 accessors, kept as thin delegates to [modules] until REG-5; a number of
  // host files and tests still use them.
  ResearchRuntime? get research => modules.runtime<ResearchRuntime>('research');
  set research(ResearchRuntime? value) =>
      modules.setRuntimeForTesting('research', value);
  String? get researchError => modules.error('research');
  PrototypeRuntime? get prototype =>
      modules.runtime<PrototypeRuntime>(prototypeModuleId);
  String? get prototypeError => modules.error(prototypeModuleId);
  InquiryPlugin? inquiry;
  String? inquiryError;
  bool _closing = false;
  Future<void>? _closeFuture;
  final Set<Future<void>> _platformOperations = {};

  Future<T> trackOperation<T>(Future<T> Function() operation) {
    if (_closing) return Future.error(StateError('Host is closing'));
    final result = Future<T>.sync(operation);
    late final Future<void> drain;
    drain = result
        .then<void>((_) {}, onError: (Object error, StackTrace stack) {})
        .whenComplete(() => _platformOperations.remove(drain));
    _platformOperations.add(drain);
    return result;
  }

  Future<String> runPlatformOperation(
    String label,
    Future<String> Function() operation,
  ) {
    if (_closing) return Future.error(StateError('Host is closing'));
    return trackOperation(() => _runPlatformOperation(label, operation));
  }

  Future<String> _runPlatformOperation(
    String label,
    Future<String> Function() operation,
  ) async {
    final conversation = await foundation.createConversation(
      title: '设备连接 · $label',
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final task = PersonalTask({
      'kind': 'personal',
      'owner': 'platform',
      'executionId': const Uuid().v4(),
      'conversationId': conversation.id,
      'prompt': label,
      'scope': const AssistantScope.global().toJson(),
      'state': 'queued',
      'stage': 'queued',
      'executionDeviceId': workspaces.setting('deviceId'),
      'createdAt': now,
      'updatedAt': now,
      'objectRefs': <Object?>[],
      'profile': null,
    });
    await foundation.createTask(task);
    await foundation.updateTask(
      task.copy({'state': 'running', 'stage': label}),
      expected: {PersonalTaskState.queued},
    );
    try {
      if (_closing) throw StateError('Host is closing');
      final result = await operation();
      await foundation.updateTask(
        task.copy({'state': 'succeeded', 'stage': '完成', 'summary': result}),
        expected: {PersonalTaskState.running},
        assistantAnswer: result,
      );
      await foundation.notify(title: label, body: result, taskId: task.id);
      return result;
    } catch (error) {
      await foundation.updateTask(
        task.copy({'state': 'failed', 'stage': '失败', 'error': '$error'}),
        expected: {PersonalTaskState.running},
      );
      rethrow;
    }
  }

  static Future<MuyonHost> open(
    String rootPath, {
    Future<String?> Function(TaskOffer offer)? taskExecutor,
    OutboundContentReviewer? localToolReviewer,
    OutboundContentReviewer? localModelReviewer,

    /// Replaces the module catalog; for tests of the generic module path.
    Iterable<BusinessModule>? modules,
  }) async {
    final storage = StorageManager(rootPath);
    try {
      final database = await storage.open('muyon', WorkspaceRepository.schema);
      await SchemaCatalog.attach(storage, database);
      await ExecutionStore(database).recoverInterrupted();
      late final MuyonHost host;
      host = MuyonHost._(
        storage,
        WorkspaceRepository(database),
        ModuleRegistry(
          modules ??
              [
                InquiryBusinessModule(() => host),
                ...moduleCatalog(researchRuntime: () => host.research),
              ],
          knownCapabilities: hostCapabilityIds,
        ),
        CapabilityRegistry(),
      );
      await migrateModelProfileCapabilities(host.workspaces);
      host.foundation = FoundationRepository(database);
      host.projections = ProjectionService(database);
      host.outbound = OutboundLedger(database);
      await host.outbound.recoverInterrupted();
      host.memoryReview = MemoryReviewService(host.foundation);
      await host.foundation.recoverInterrupted();
      var device = host.workspaces.setting('deviceId') as String?;
      if (device == null) {
        device = const Uuid().v4();
        await host.workspaces.setSetting('deviceId', device);
      }
      host.assistantGrants = GrantStore(database);
      host.authorizationPolicy = HostAuthorizationPolicy(database);
      host.tools = ToolRegistry(
        database: database,
        resolveScope: (scope) => host.scopeResolver.resolve(scope),
        grants: host.assistantGrants,
        categoryAllowed: (effect) =>
            host.authorizationPolicy.current.allowsTool(effect),
        policyRevision: () => host.authorizationPolicy.current.revision,
        grantContext: (request) =>
            host.personalAgent.hostGrantContext(request, host.scopeAuthority),
      );
      host.grants = ModuleGrants(database);
      host.modules = ModuleHost(
        registry: host.registry,
        storage: storage,
        workspaces: host.workspaces,
        projections: host.projections,
        capabilities: host.capabilities,
        grants: host.grants,
        tools: host.tools,
        notify: (title, body) =>
            host.foundation.notify(title: title, body: body),
        legacy: legacyBridges(host),
      );
      host.services = await PublicServices.open(
        storage: storage,
        workspaces: host.workspaces,
        gateway: OpenAiModelGateway(
          const MethodChannelSecretStore(),
          ledger: host.outbound,
          authorizationPolicy: host.authorizationPolicy,
        ),
        tools: host.tools,
      );
      host.acceptedResearchImports = AcceptedResearchImports(host);
      host.services.transfer.onAccepted = host.acceptedResearchImports.accept;
      host.projections.onApplied = host.services.knowledge.followProjections(
        (ref) => ref.moduleId == 'research' && ref.objectType == 'document'
            ? confirmRegisteredResearchDocument(
                ref,
                sources: () => host.registry.modules
                    .whereType<BusinessModuleV2>()
                    .where((module) => module.manifest.id == 'research')
                    .expand((module) => module.searchSources)
                    .toList(),
                authorityRevision: () =>
                    host.modules.scopeAuthorityRevision('research'),
              )
            : confirmIndexedSource(
                ref,
                research: () => host.research,
                inquiry: () => host.inquiry,
              ),
      );
      host.services.transfer.onPendingReceived = () {
        if (host._closing) return;
        unawaited(
          host
              .trackOperation(
                () => host.foundation.notify(
                  title: '收到设备数据包',
                  body: '私有收件区有新的待核验文件，请本人核验接纳。',
                ),
              )
              .catchError((Object error) {}),
        );
      };
      host.personalAgent = PersonalAgent(
        repository: host.foundation,
        gateway: host.services.gateway,
        tools: host.tools,
        executionDeviceId: device,
        uiPlanningSource: InquiryUiPlanningSource(host).read,
        presentationPreference: UiPresentationPreference(host.foundation),
        uiPlanningMode: UiPlanningMode.motivation,
        uiPlanningEnabled: false,
        gate: HostPolicyModelGate(host.authorizationPolicy),
        modelAuthorization: HostModelAuthorization(
          repository: host.foundation,
          policy: host.authorizationPolicy,
          grants: host.assistantGrants,
          configuredProfiles: () => ProfileRepository(host.workspaces).all(),
          reviewer: ReviewerChain([
            const NoopReviewer(),
            ?localModelReviewer,
          ], timeout: const Duration(seconds: 2)),
        ),
        toolReviewer: ReviewerChain([
          const NoopReviewer(),
          ?localToolReviewer,
        ], timeout: const Duration(seconds: 2)),
      );
      host.dream = DreamService(
        host.foundation,
        gateway: host.services.gateway,
      );
      host.researchTasks = ResearchTaskBridge(host);
      host.tasks = TaskCoordinator(
        database: database,
        deviceId: device,
        send: host.services.transfer.sendTaskEnvelope,
        executor: taskExecutor ?? host.researchTasks.start,
        peerReachable: () => host.services.transfer.pairedOnline().isNotEmpty,
        onOfferAttachment: host.researchTasks.saveOfferAttachment,
        onResultReceived: host.researchTasks.saveReturnedResult,
      );
      host.services.transfer.onTaskEnvelope = host.tasks.receive;
      await host.services.transfer.deliverPendingTaskEnvelopes();
      host.scopeResolver = ScopeResolver(
        sources: host.modules.scopeSources(),
        workspaces: host.workspaces,
        knowledgeSources: () async => [
          for (final document in host.services.knowledge.documents())
            if (await host.services.knowledge.isCurrent(document.id))
              document.source,
        ],
      );
      registerNonInquiryBusinessTools(host);
      host.scopeAuthority = HostScopeAuthority(
        workspaces: host.workspaces,
        sources: {
          'inquiry': HostScopeSource.deferred(
            connection: () => storage.connectionIfOpen('inquiry'),
            authorityRevision: () {
              final lifecycle = host.modules.scopeAuthorityRevision('inquiry');
              final inquiry = host.inquiry;
              return host._closing ||
                      lifecycle == null ||
                      inquiry == null ||
                      host.inquiryError != null
                  ? null
                  : '$lifecycle:${identityHashCode(inquiry)}';
            },
            managedFilesRoot: () => host.inquiry?.runtime.state.dataDir.path,
          ),
          // First production proof covers the known managed PrototypeStore.
          // Other adapters remain unknown until their complete file coverage
          // is established; a projection or origin is not a substitute.
          prototypeModuleId: HostScopeSource.deferred(
            connection: () => storage.connectionIfOpen(prototypeModuleId),
            authorityRevision: () =>
                host.modules.scopeAuthorityRevision(prototypeModuleId),
            managedFilesRoot: () => host.prototype?.store.filesRoot,
          ),
        },
        contextSources: [
          HostScopeSource.deferred(
            connection: () => storage.connectionIfOpen('public_knowledge'),
            authorityRevision: () => host._closing ? null : 'host-knowledge',
            managedFilesRoot: () => host.services.knowledge.rootPath,
          ),
        ],
      );
      host.modules.registerTools();
      host.capabilities.register('knowledge', host.services.knowledge);
      host.capabilities.register('models', host.services.gateway);
      host.capabilities.register('ocr', host.services.ocr);
      host.capabilities.register('transfer', host.services.transfer);
      host.capabilities.register('tools', host.tools);
      return host;
    } catch (_) {
      await storage.close();
      rethrow;
    }
  }

  /// Compatibility entry: activation and failure state belong to ModuleHost.
  Future<void> activateInquiry() async {
    if (_closing) throw StateError('Host is closing');
    final state = await modules.activate('inquiry');
    inquiryError = state.reason;
  }

  Future<void> activateResearch() => _activateModule('research');

  /// Opens the prototype module on first use. A failure is recorded in
  /// [prototypeError] and `module_registry`; the host and other modules keep
  /// working, and the next call retries.
  Future<void> activatePrototype() => _activateModule(prototypeModuleId);

  Future<void> _activateModule(String id) {
    if (_closing) return Future.error(StateError('Host is closing'));
    return modules.activate(id).then<void>((_) {});
  }

  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    _closing = true;
    modules.stopAdmission();
    // Withdraw external tool authority immediately, but finish local imports
    // already admitted by the person before invalidating their runtimes.
    final closingTools = tools.close();
    await personalAgent.close();
    await services.transfer.close();
    await Future.wait(_platformOperations.toList());
    await modules.close();
    await closingTools;
    await inquiry?.close();
    await services.close();
    memoryReview.dispose();
    foundation.dispose();
    await storage.close();
  }
}
