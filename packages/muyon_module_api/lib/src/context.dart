import 'dart:convert';

import 'references.dart';

/// Accepts only JSON values and recursively copies collections, so subsequent
/// UI edits cannot alter a frozen authorization or execution record.
Map<String, Object?> freezeJsonMap(Map<String, Object?> value) =>
    _freeze(value) as Map<String, Object?>;

Object? _freeze(Object? value) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double && value.isFinite) return value;
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.unmodifiable(
      value.map((key, item) => MapEntry(key, _freeze(item))),
    );
  }
  throw ArgumentError('Contract payloads must contain JSON values only');
}

class ContextRef {
  ContextRef({
    required this.workspaceId,
    required this.moduleId,
    required this.nativeProjectId,
    this.currentObjectRef,
    List<ObjectRef> selectedObjectRefs = const [],
  }) : selectedObjectRefs = List.unmodifiable(selectedObjectRefs) {
    for (final ref in [
      if (currentObjectRef != null) currentObjectRef!,
      ...selectedObjectRefs,
    ]) {
      if (ref.moduleId != moduleId || ref.nativeProjectId != nativeProjectId) {
        throw ArgumentError('Context objects must belong to the bound project');
      }
    }
  }
  final String workspaceId;
  final String moduleId;
  final String nativeProjectId;
  final ObjectRef? currentObjectRef;
  final List<ObjectRef> selectedObjectRefs;
  Map<String, Object?> toJson() => {
    'workspaceId': workspaceId,
    'moduleId': moduleId,
    'nativeProjectId': nativeProjectId,
    'currentObjectRef': currentObjectRef?.toJson(),
    'selectedObjectRefs': selectedObjectRefs
        .map((ref) => ref.toJson())
        .toList(),
  };
  bool sameSnapshot(ContextRef other) =>
      jsonEncode(toJson()) == jsonEncode(other.toJson());
}

enum ToolEffect { read, write, export, network }

class ToolDescriptor {
  ToolDescriptor({
    required this.toolId,
    required this.moduleId,
    this.apiVersion = 1,
    required this.effect,
    Map<String, Object?> parameterSchema = const {},
    Map<String, Object?> resultSchema = const {},
    Set<String> contextTypes = const {},
    this.supportsCancel = false,
    this.supportsPause = false,
    this.supportsResume = false,
    this.description = '',
  }) : parameterSchema = freezeJsonMap(parameterSchema),
       resultSchema = freezeJsonMap(resultSchema),
       contextTypes = Set.unmodifiable(contextTypes);
  final String toolId;
  final String moduleId;
  final int apiVersion;
  final ToolEffect effect;
  final Map<String, Object?> parameterSchema;
  final Map<String, Object?> resultSchema;
  final Set<String> contextTypes;
  final bool supportsCancel;
  final bool supportsPause;
  final bool supportsResume;

  /// What the tool does, shown to people and to the model for selection.
  /// Untrusted when it comes from an external server; never an authorization.
  final String description;
}

class Invocation {
  Invocation({
    required this.invocationId,
    required this.toolId,
    required this.contextSnapshot,
    required this.inputDigest,
    required this.permissionDecisionId,
    this.endpoint,
    this.destination,
    Set<String> dataCategories = const {},
  }) : dataCategories = Set.unmodifiable(dataCategories);
  final String invocationId;
  final String toolId;
  final ContextRef contextSnapshot;
  final String inputDigest;
  final String permissionDecisionId;
  final String? endpoint;
  final String? destination;
  final Set<String> dataCategories;
}

enum PermissionAuthority { hostReadPolicy, userAction, explicitScope }

/// Constructed by the host action gate, never parsed from model/document text.
class PermissionDecision {
  PermissionDecision({
    required this.id,
    required this.toolId,
    required this.effect,
    required this.contextSnapshot,
    required this.inputDigest,
    required this.authority,
    required this.expiresAt,
    required this.allowed,
    this.endpoint,
    this.destination,
    Set<String> dataCategories = const {},
  }) : dataCategories = Set.unmodifiable(dataCategories);
  final String id;
  final String toolId;
  final ToolEffect effect;
  final ContextRef contextSnapshot;
  final String inputDigest;
  final PermissionAuthority authority;
  final DateTime expiresAt;
  final bool allowed;
  final String? endpoint;
  final String? destination;
  final Set<String> dataCategories;

  bool authorizes(
    Invocation invocation,
    ToolDescriptor tool, {
    required DateTime now,
  }) =>
      allowed &&
      now.isBefore(expiresAt) &&
      id == invocation.permissionDecisionId &&
      toolId == invocation.toolId &&
      tool.toolId == toolId &&
      tool.moduleId == contextSnapshot.moduleId &&
      tool.effect == effect &&
      inputDigest == invocation.inputDigest &&
      contextSnapshot.sameSnapshot(invocation.contextSnapshot) &&
      endpoint == invocation.endpoint &&
      destination == invocation.destination &&
      dataCategories.length == invocation.dataCategories.length &&
      dataCategories.containsAll(invocation.dataCategories) &&
      (effect == ToolEffect.read ||
          authority != PermissionAuthority.hostReadPolicy);
}

enum ExecutionState {
  queued,
  running,
  succeeded,
  failed,
  cancelled,
  interrupted,
}

class InvocationResult {
  InvocationResult({
    required this.state,
    required this.summary,
    required this.executionId,
    List<ArtifactRef> artifactRefs = const [],
    List<ObjectRef> objectRefs = const [],
  }) : artifactRefs = List.unmodifiable(artifactRefs),
       objectRefs = List.unmodifiable(objectRefs);
  final ExecutionState state;
  final String summary;
  final String executionId;
  final List<ArtifactRef> artifactRefs;
  final List<ObjectRef> objectRefs;
}

class AgentExecutionRecord {
  AgentExecutionRecord({
    required this.executionId,
    this.parentConversationId,
    required this.toolId,
    required this.contextSnapshot,
    this.profileId,
    required this.executionDeviceId,
    required this.state,
    required this.stage,
    this.waitReason,
    List<ArtifactRef> artifactRefs = const [],
    List<ObjectRef> resultRefs = const [],
    this.error,
    required this.createdAt,
    required this.updatedAt,
    this.finishedAt,
    this.previousAttemptId,
  }) : artifactRefs = List.unmodifiable(artifactRefs),
       resultRefs = List.unmodifiable(resultRefs);
  final String executionId;
  final String? parentConversationId;
  final String toolId;
  final ContextRef contextSnapshot;
  final String? profileId;
  final String executionDeviceId;
  final ExecutionState state;
  final String stage;
  final String? waitReason;
  final List<ArtifactRef> artifactRefs;
  final List<ObjectRef> resultRefs;
  final String? error;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? finishedAt;
  final String? previousAttemptId;
}

class ConversationRef {
  const ConversationRef({required this.id, required this.context});
  final String id;
  final ContextRef context;
}
