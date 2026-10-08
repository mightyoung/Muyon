import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

/// Authoritative host facts, obtained again after every queue/await boundary.
/// Never take these values from model parameters or a tool result.
class ToolGrantContext {
  ToolGrantContext({
    required this.taskId,
    required this.conversationId,
    required this.taskTainted,
    required this.scopeRevision,
    required Set<String> allowedModuleIds,
  }) : allowedModuleIds = Set.unmodifiable(allowedModuleIds);
  final String taskId, conversationId;
  final bool taskTainted;

  /// Host-maintained version of resolved scope authority. Must change when
  /// object revisions, workspace bindings or scope visibility change. It is
  /// sampled before resolution and inside signing, never from model input.
  final String scopeRevision;
  final Set<String> allowedModuleIds;
}

/// Stable permission scope, distinct from the revision-bound approval digest.
String toolGrantScopeDigest(
  AssistantScope scope,
  Set<String> allowedModuleIds,
) {
  final modules = allowedModuleIds.toList()..sort();
  if (modules.any((id) => id.trim().isEmpty)) {
    throw ArgumentError('Explicit module boundary required');
  }
  final identities = [
    for (final ref in scope.objects)
      jsonEncode([
        ref.moduleId,
        ref.nativeProjectId,
        ref.objectType,
        ref.objectId,
      ]),
  ]..sort();
  return sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'version': 1,
            'kind': scope.kind.name,
            'workspaceId': scope.workspaceId,
            'objects': identities,
            'allowedModuleIds': modules,
          }),
        ),
      )
      .toString();
}
