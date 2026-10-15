import 'package:muyon_module_api/muyon_module_api.dart';

import '../foundation_repository.dart';
import '../grants/host_authorization_facts.dart';
import '../tool_registry.dart';
import 'process.dart';

/// Trusted host snapshot, never deserialized from module/model declarations.
class PluginHostSnapshot {
  PluginHostSnapshot({required this.revision, required this.allowed,
    required this.bindingRevision, required this.sourceRevision,
    required this.ruleRevision, required this.scope,
    required Iterable<ObjectRef> objects}) : objects = List.unmodifiable(objects);
  final String revision, bindingRevision, sourceRevision, ruleRevision;
  final bool allowed;
  final AssistantScope scope;
  final List<ObjectRef> objects;
}

/// Host-owned adapter binding. Projection is not permission or a receipt.
class PluginReadBinding {
  const PluginReadBinding({required this.toolId, required this.operation,
    required this.bindingId, required this.externalSource, required this.project});
  final String toolId, operation, bindingId;
  final bool externalSource;
  final Map<String, Object?> Function(ToolCallResult) project;
}

/// Concrete refusing API shell for the real Agent dispatch seam. The stub
/// cannot mint authority, invoke handlers, register contributions or publish
/// model projections. These behaviors are deliberately RED.
class PluginReadBridge {
  PluginReadBridge({required this.registry, required this.repository,
    required this.process, required this.snapshot, required this.reviewProjection});
  final ToolRegistry registry;
  final FoundationRepository repository;
  final PluginContractProcess process;
  final Future<PluginHostSnapshot> Function(ToolCallRequest request) snapshot;
  final Future<bool> Function(Map<String, Object?> value, HostTaskFacts facts)
      reviewProjection;

  Future<bool> enroll(Map<String, Object?> bundle, PluginReadBinding binding) async => false;

  Future<ToolCallResult> invoke(PersonalTask task, ToolCallRequest request,
      ToolCancellationToken cancellation) async {
    throw const ToolPlatformException('plugin_contract_unsupported',
        'Registered plugin reads are not implemented');
  }

  /// Stub source is unknown and therefore conservative. No plugin label is
  /// interpreted as trusted/clean before host metadata is implemented.
  bool requiresSourceFacts(ToolCallRequest request) => true;

  Object? projectionFor(String invocationId, String receiptIdentity) => null;
  Future<void> close() => process.close();
}
