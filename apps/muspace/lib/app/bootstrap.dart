import 'package:muspace_module_api/muspace_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/research_module.dart';

import '../platform/file_gateway.dart';
import '../platform/storage_manager.dart';
import '../workspace/import_coordinator.dart';
import '../workspace/workspace_repository.dart';
import 'module_registry.dart';
import '../assistant/execution_store.dart';
import '../assistant/personal_agent.dart';
import '../platform/foundation_repository.dart';
import '../platform/tool_registry.dart';
import '../platform/business_tools.dart';
import '../services/public_services.dart';
import '../services/models/model_gateway.dart';
import '../services/models/secret_store.dart';
import 'inquiry_plugin.dart';

import 'package:uuid/uuid.dart';

class MuSpaceHost {
  MuSpaceHost._(
    this.storage,
    this.workspaces,
    this.registry,
    this.capabilities,
  );
  final StorageManager storage;
  final WorkspaceRepository workspaces;
  final ModuleRegistry registry;
  final CapabilityRegistry capabilities;
  late final FoundationRepository foundation;
  late final ToolRegistry tools;
  late final PublicServices services;
  late final PersonalAgent personalAgent;
  ResearchRuntime? research;
  String? researchError;
  InquiryPlugin? inquiry;
  String? inquiryError;
  bool _closing = false;
  Future<void>? _closeFuture;

  static Future<MuSpaceHost> open(String rootPath) async {
    final storage = StorageManager(rootPath);
    try {
      final database = await storage.open(
        'muspace',
        WorkspaceRepository.schema,
      );
      await ExecutionStore(database).recoverInterrupted();
      final host = MuSpaceHost._(
        storage,
        WorkspaceRepository(database),
        ModuleRegistry([ResearchModule()]),
        CapabilityRegistry(),
      );
      host.foundation = FoundationRepository(database);
      await host.foundation.recoverInterrupted();
      var device = host.workspaces.setting('deviceId') as String?;
      if (device == null) {
        device = const Uuid().v4();
        await host.workspaces.setSetting('deviceId', device);
      }
      host.tools = ToolRegistry(database: database,
        resolveScope: (scope) => resolveAssistantScope(host, scope));
      host.services = await PublicServices.open(storage: storage,
        workspaces: host.workspaces,
        gateway: OpenAiModelGateway(const MethodChannelSecretStore()),tools: host.tools);
      host.personalAgent = PersonalAgent(repository: host.foundation,
        gateway: host.services.gateway,tools: host.tools,executionDeviceId: device);
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
      inquiry = await InquiryPlugin.open(storage, deviceId: device);
      final connection = await storage.open('inquiry', InquiryPlugin.schema);
      await workspaces.database.write((db) {
        db.execute('INSERT OR REPLACE INTO module_registry VALUES(?,?,?)', [
          'inquiry',
          'ready',
          null,
        ]);
        db.execute(
          'INSERT OR REPLACE INTO schema_catalog VALUES(?,?,?,?,?,?)',
          [
            'inquiry',
            InquiryPlugin.schema.version,
            InquiryPlugin.schema.definitionDigest,
            connection.raw.userVersion,
            StorageManager.structureDigest(connection.raw),
            'ready',
          ],
        );
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
    final module = registry.require('research');
    try {
      final connection = await storage.open('research', module.schema);
      final files = FileGateway(
        p.join(storage.rootPath, 'modules', 'research', 'files'),
      );
      research = await module.activate(
        ModuleResources(
          database: connection,
          files: files,
          capabilities: capabilities.forModule('research', allowed: {'knowledge','models','tools'}),
        ),
      ) as ResearchRuntime;
      await workspaces.database.write((db) {
        db.execute('INSERT OR REPLACE INTO module_registry VALUES(?,?,?)', [
          'research',
          'ready',
          null,
        ]);
        db.execute(
          'INSERT OR REPLACE INTO schema_catalog VALUES(?,?,?,?,?,?)',
          [
            'research',
            module.schema.version,
            module.schema.definitionDigest,
            connection.raw.userVersion,
            StorageManager.structureDigest(connection.raw),
            'ready',
          ],
        );
      });
      final coordinator = ImportCoordinator(workspaces);
      for (final intent in coordinator.pending('research')) {
        final receipt = await research!.receipt(intent.operationId);
        if (receipt != null) await coordinator.activate(receipt);
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

  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    _closing = true;
    await personalAgent.close();
    await _openingInquiry;
    await _activating;
    await inquiry?.close();
    await services.close();
    foundation.dispose();
    await storage.close();
  }
}
