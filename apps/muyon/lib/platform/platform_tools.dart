import 'package:muyon_module_api/muyon_module_api.dart';

import '../app/host_tool_registrar.dart';
import '../app/module_host.dart';
import '../assistant/execution_store.dart';
import '../services/transfer/transfer_service.dart';
import 'foundation_repository.dart';
import 'tool_registry.dart';

/// Host metadata only: no object identities, content or business runtime.
///
/// Not registered by bootstrap yet: its shared global scope resolver prepares
/// business modules before filtering data modules, which can perform recovery
/// writes. Integration must wire the returned host metadata scope binding.
class PlatformReadTools {
  PlatformReadTools({
    required this.foundation,
    required this.executions,
    required this.transfer,
  });

  final FoundationRepository foundation;
  final ExecutionStore executions;
  final TransferService transfer;

  static const _global = {AssistantScopeKind.global};
  static const _limit = {'type': 'integer', 'minimum': 1, 'maximum': 20};
  static const _time = {'type': 'string', 'minLength': 1, 'maxLength': 40};

  static Map<String, Object?> _object(Map<String, Object?> fields) => {
    'type': 'object',
    'properties': fields,
    'required': fields.keys.toList(),
    'additionalProperties': false,
  };

  static Map<String, Object?> _items(Map<String, Object?> fields) => _object({
    'items': {
      'type': 'array',
      'maxItems': 20,
      'items': _object(fields),
    },
  });

  void registerTools(ToolRegistrar registrar) {
    if (registrar.moduleId != 'platform') {
      throw ArgumentError('Platform metadata requires the host platform identity');
    }
    void read(
      String name,
      String description,
      Map<String, Object?> resultSchema,
      Map<String, Object?> Function(ToolCallContext) query, {
      bool list = true,
      bool notifications = false,
    }) {
      registrar.read(
        ToolSpec(
          name: name,
          description: description,
          scopes: _global,
          operations: ['platform.query_$name'],
          supportsCancel: true,
          parameterSchema: {
            'type': 'object',
            'properties': {
              if (list) 'limit': _limit,
              if (notifications) 'unreadOnly': {'type': 'boolean'},
            },
            'additionalProperties': false,
          },
          resultSchema: resultSchema,
        ),
        (context) async {
          final call = context.call;
          call.cancellation.throwIfCancelled();
          if (call.request.scope.kind != AssistantScopeKind.global ||
              call.resolvedScope.requested.kind != AssistantScopeKind.global) {
            throw const ToolPlatformException(
              'scope_mismatch',
              'Platform metadata supports global scope only',
            );
          }
          // The registrar awaited its lifecycle link before entering us.
          // Recheck the existing host authority at the actual read boundary.
          call.checkBeforeEffect();
          try {
            final data = query(call);
            call.cancellation.throwIfCancelled();
            return ToolCallResult(
              status: ToolCallStatus.succeeded,
              summary: 'Platform metadata query completed.',
              data: data,
            );
          } on ToolCancelled {
            rethrow;
          } catch (_) {
            // Repository decoding/availability errors never expose raw stored
            // strings, paths, content, SQL or exception messages to the model.
            call.cancellation.throwIfCancelled();
            return ToolCallResult(
              status: ToolCallStatus.failed,
              summary: 'Platform metadata is temporarily unavailable.',
            );
          }
        },
      );
    }

    read(
      'executions',
      '读取全局个人执行记录的状态、更新时间和有上限的事件数量，仅返回元数据，不改动记录。',
      _items({
        'state': {
          'type': 'string',
          'maxLength': 40,
          'enum': [for (final state in PersonalTaskState.values) state.name],
        },
        'updatedAt': _time,
        'eventCount': {'type': 'integer', 'minimum': 0, 'maximum': 100},
      }),
      _executionMetadata,
    );
    read(
      'memories',
      '读取全局已验证且有效记忆的类别、修订号和更新时间，仅返回元数据，不返回来源和正文。',
      _items({
        'kind': {
          'type': 'string',
          'maxLength': 40,
          'enum': FoundationRepository.memoryKinds.toList(),
        },
        'revision': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 9007199254740991,
        },
        'updatedAt': _time,
      }),
      _memoryMetadata,
    );
    read(
      'notifications',
      '读取全局通知的已读状态和创建时间，仅返回元数据，排除项目和悬空任务通知，不标记已读。',
      _items({'read': {'type': 'boolean'}, 'createdAt': _time}),
      _notificationMetadata,
      notifications: true,
    );
    read(
      'device_status',
      '读取当前设备已有的通信监听开关，仅返回状态，不启动发现或监听，也不发送任何内容。',
      _object({'listening': {'type': 'boolean'}}),
      (_) => {'listening': transfer.listening},
      list: false,
    );
  }

  int _count(ToolCallContext call) => call.request.parameters['limit'] as int? ?? 10;

  Map<String, Object?> _executionMetadata(ToolCallContext call) {
    final items = <Map<String, Object?>>[];
    for (final task in foundation.tasks()) {
      call.cancellation.throwIfCancelled();
      if (task.scope.kind != AssistantScopeKind.global) continue;
      final count = executions.events(task.id).length;
      items.add({
        'state': task.state.name,
        'updatedAt': task.updatedAt.toUtc().toIso8601String(),
        'eventCount': count > 100 ? 100 : count,
      });
      if (items.length >= _count(call)) break;
    }
    return {'items': items};
  }

  Map<String, Object?> _memoryMetadata(ToolCallContext call) {
    final items = <Map<String, Object?>>[];
    for (final memory in foundation.memoriesFor(const AssistantScope.global())) {
      call.cancellation.throwIfCancelled();
      if (!FoundationRepository.memoryKinds.contains(memory.kind) ||
          memory.revision < 1 || memory.revision > 9007199254740991) {
        throw StateError('Invalid metadata');
      }
      items.add({
        'kind': memory.kind,
        'revision': memory.revision,
        'updatedAt': memory.updatedAt.toUtc().toIso8601String(),
      });
      if (items.length >= _count(call)) break;
    }
    return {'items': items};
  }

  Map<String, Object?> _notificationMetadata(ToolCallContext call) {
    final items = <Map<String, Object?>>[];
    final unreadOnly = call.request.parameters['unreadOnly'] as bool? ?? false;
    for (final notification in foundation.notifications(unreadOnly: unreadOnly)) {
      call.cancellation.throwIfCancelled();
      final taskId = notification.taskId;
      if (taskId != null) {
        final task = foundation.task(taskId);
        if (task == null || task.scope.kind != AssistantScopeKind.global) continue;
      }
      items.add({
        'read': notification.read,
        'createdAt': notification.createdAt.toUtc().toIso8601String(),
      });
      if (items.length >= _count(call)) break;
    }
    return {'items': items};
  }
}

/// Assembles the host identity using the same registrar and registry controls.
/// The caller must wire the returned binding into hostToolScopeResolver or
/// provide a pure metadata resolver; bootstrap's shared default is unsuitable.
PlatformMetadataScopeBinding registerPlatformReadTools({
  required ToolRegistry registry,
  required FoundationRepository foundation,
  required ExecutionStore executions,
  required TransferService transfer,
  required bool Function() isAvailable,
}) {
  final registrar = HostToolRegistrar(
    'platform',
    registry,
    ModuleManifest(id: 'platform', apiVersion: 2),
    _PlatformLink(isAvailable),
  );
  try {
    PlatformReadTools(
      foundation: foundation,
      executions: executions,
      transfer: transfer,
    ).registerTools(registrar);
  } finally {
    registrar.seal();
  }
  return PlatformMetadataScopeBinding._(
    registry,
    {for (final id in registrar.registeredToolIds)
      id: registry.inspect(id)!.descriptor},
    isAvailable,
  );
}

/// Only the successful host assembly above can bind actual registrations.
/// Owning registry and descriptor object identity both matter: same JSON is
/// insufficient, and a copied descriptor cannot cross registry boundaries.
class PlatformMetadataScopeBinding {
  PlatformMetadataScopeBinding._(
    this._registry,
    Map<String, ToolDescriptor> descriptors,
    this._isAvailable,
  ) : _descriptors = Map.unmodifiable(descriptors);

  final ToolRegistry _registry;
  final Map<String, ToolDescriptor> _descriptors;
  final bool Function() _isAvailable;

  void _requireCurrent() {
    if (!_isAvailable()) {
      throw const ToolPlatformException(
        'host_unavailable',
        'Host metadata is unavailable',
      );
    }
  }

  Future<HostScopeResolution?> resolve(
    ToolRegistry registry,
    RegisteredToolInfo tool,
    ToolCallRequest request,
  ) async {
    final expected = _descriptors[tool.descriptor.toolId];
    if (!identical(registry, _registry) ||
        expected == null ||
        !identical(expected, tool.descriptor) ||
        tool.providerId != 'platform' ||
        tool.descriptor.moduleId != 'platform' ||
        tool.descriptor.effect != ToolEffect.read ||
        tool.descriptor.apiVersion != expected.apiVersion ||
        request.toolId != tool.descriptor.toolId ||
        request.scope.kind != AssistantScopeKind.global) {
      return null;
    }
    _requireCurrent();
    return HostScopeResolution(
      identityKey: HostScopeResolution.platformMetadataKey,
      scope: ResolvedAssistantScope(requested: request.scope, objects: []),
      requireCurrent: _requireCurrent,
    );
  }
}

class _PlatformLink implements ModuleLink {
  _PlatformLink(this.isAvailable);
  final bool Function() isAvailable;

  @override
  Future<ModuleState> activate(String moduleId) async =>
      moduleId == 'platform' && isAvailable()
      ? const ModuleState(ModuleStatus.ready)
      : const ModuleState(ModuleStatus.failed, 'host_unavailable');

  @override
  T? runtime<T extends ModuleRuntime>(String moduleId) => null;
}
