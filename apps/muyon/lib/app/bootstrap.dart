import 'dart:async';

import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:prototype_module/prototype_module.dart';
import 'package:research_module/research_module.dart';

import '../platform/file_gateway.dart';
import '../platform/outbound_ledger.dart';
import '../platform/projection_service.dart';
import '../platform/schema_catalog.dart';
import '../platform/storage_manager.dart';
import '../workspace/import_coordinator.dart';
import '../workspace/workspace_repository.dart';
import 'module_registry.dart';
import '../assistant/execution_store.dart';
import '../assistant/dream/dream_service.dart';
import '../assistant/personal_agent.dart';
import '../platform/foundation_repository.dart';
import '../platform/memory_review.dart';
import '../platform/tool_registry.dart';
import '../platform/business_tools.dart';
import '../services/knowledge/index_invalidation.dart';
import '../services/public_services.dart';
import '../services/models/model_gateway.dart';
import '../services/models/secret_store.dart';
import '../services/models/profile_repository.dart';
import 'inquiry_plugin.dart';

import 'package:uuid/uuid.dart';

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
  late final DreamService dream;
  late final ProjectionService projections;
  late final OutboundLedger outbound;
  Future<bool> Function(InquiryModelApprovalPreview preview)?
  approveInquiryModelRequest;
  ResearchRuntime? research;
  String? researchError;
  PrototypeRuntime? prototype;
  String? prototypeError;
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

  static Future<MuyonHost> open(String rootPath) async {
    final storage = StorageManager(rootPath);
    try {
      final database = await storage.open('muyon', WorkspaceRepository.schema);
      await SchemaCatalog.attach(storage, database);
      await ExecutionStore(database).recoverInterrupted();
      final host = MuyonHost._(
        storage,
        WorkspaceRepository(database),
        ModuleRegistry([ResearchModule(), PrototypeModule()]),
        CapabilityRegistry(),
      );
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
      host.tools = ToolRegistry(
        database: database,
        resolveScope: (scope) => resolveAssistantScope(host, scope),
      );
      host.services = await PublicServices.open(
        storage: storage,
        workspaces: host.workspaces,
        gateway: OpenAiModelGateway(
          const MethodChannelSecretStore(),
          ledger: host.outbound,
        ),
        tools: host.tools,
      );
      host.projections.onApplied = host.services.knowledge.followProjections(
        (ref) => confirmIndexedSource(
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
      );
      host.dream = DreamService(
        host.foundation,
        gateway: host.services.gateway,
      );
      registerBusinessTools(host);
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

  Future<void>? _activating;
  Future<void>? _activatingPrototype;
  Future<void>? _openingInquiry;
  Future<void> activateInquiry() {
    if (_closing) return Future.error(StateError('Host is closing'));
    return _openingInquiry ??= _activateInquiry();
  }

  Future<void> _activateInquiry() async {
    try {
      var device = workspaces.setting('deviceId') as String?;
      if (device == null) {
        device = const Uuid().v4();
        await workspaces.setSetting('deviceId', device);
      }
      inquiry = await InquiryPlugin.open(
        storage,
        deviceId: device,
        modelProfiles: ProfileRepository(workspaces),
        modelGateway: services.gateway,
        approveModelRequest: (preview) =>
            approveInquiryModelRequest?.call(preview) ?? Future.value(false),
      );
      projections.watch(
        'inquiry',
        await storage.open('inquiry', InquiryPlugin.schema),
      );
      await workspaces.database.write((db) {
        db.execute('INSERT OR REPLACE INTO module_registry VALUES(?,?,?)', [
          'inquiry',
          'ready',
          null,
        ]);
      });
      inquiryError = null;
    } catch (e) {
      inquiryError = e.toString();
      _openingInquiry = null;
    }
  }

  Future<void> activateResearch() {
    if (_closing) return Future.error(StateError('Host is closing'));
    return _activating ??= _activateResearch();
  }

  Future<void> _activateResearch() async {
    if (research != null) return;
    try {
      final module = registry.require('research');
      final connection = await storage.open('research', module.schema);
      final files = FileGateway(
        p.join(storage.rootPath, 'modules', 'research', 'files'),
      );
      projections.watch('research', connection);
      research = await module.activate(
        ModuleResources(
          database: connection,
          files: files,
          capabilities: capabilities.forModule(
            'research',
            allowed: {'knowledge', 'models', 'tools'},
          ),
        ),
      ) as ResearchRuntime;
      await workspaces.database.write((db) {
        db.execute('INSERT OR REPLACE INTO module_registry VALUES(?,?,?)', [
          'research',
          'ready',
          null,
        ]);
      });
      final recovery = await ImportCoordinator(workspaces)
          .recover('research', research!);
      if (recovery.conflicts.isNotEmpty) {
        await foundation.notify(
          title: '导入未能完成绑定',
          body: recovery.conflicts.values.join('\n'),
        );
      }
      researchError = null;
    } catch (error) {
      research = null;
      researchError = error.toString();
      await workspaces.database.write(
        (db) => db.execute(
          'INSERT OR REPLACE INTO module_registry VALUES(?,?,?)',
          ['research', 'failed', researchError],
        ),
      );
      _activating = null;
    }
  }

  /// Opens the prototype module on first use. A failure is recorded in
  /// [prototypeError] and `module_registry`; the host and other modules keep
  /// working, and the next call retries.
  Future<void> activatePrototype() {
    if (_closing) return Future.error(StateError('Host is closing'));
    return _activatingPrototype ??= _activatePrototype();
  }

  Future<void> _activatePrototype() async {
    if (prototype != null) return;
    try {
      final module = registry.require(prototypeModuleId);
      final connection = await storage.open(prototypeModuleId, module.schema);
      projections.watch(prototypeModuleId, connection);
      prototype = await module.activate(
        ModuleResources(
          database: connection,
          files: FileGateway(
            p.join(storage.rootPath, 'modules', prototypeModuleId, 'files'),
          ),
          capabilities: capabilities.forModule(
            prototypeModuleId,
            allowed: const {},
          ),
        ),
      ) as PrototypeRuntime;
      await workspaces.database.write(
        (db) => db.execute(
          'INSERT OR REPLACE INTO module_registry VALUES(?,?,?)',
          [prototypeModuleId, 'ready', null],
        ),
      );
      prototypeError = null;
    } catch (error) {
      prototype = null;
      prototypeError = error.toString();
      await workspaces.database.write(
        (db) => db.execute(
          'INSERT OR REPLACE INTO module_registry VALUES(?,?,?)',
          [prototypeModuleId, 'failed', prototypeError],
        ),
      );
      _activatingPrototype = null;
    }
  }

  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    _closing = true;
    await personalAgent.close();
    await _openingInquiry;
    await _activating;
    await _activatingPrototype;
    await inquiry?.close();
    await services.transfer.close();
    await Future.wait(_platformOperations.toList());
    await services.close();
    memoryReview.dispose();
    foundation.dispose();
    await storage.close();
  }
}
