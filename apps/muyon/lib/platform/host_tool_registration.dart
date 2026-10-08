import 'package:muyon_module_api/muyon_module_api.dart';

import 'grants/host_effect_intent.dart';

/// Existing trusted host declarations; never part of the public module API.
typedef HostToolRegistration = void Function({
  required String providerId,
  required ToolDescriptor descriptor,
  required Future<ToolCallResult> Function(ToolCallContext) handler,
  Set<AssistantScopeKind> supportedScopes,
  Set<String>? dataModuleIds,
  Future<void> Function(ResolvedAssistantScope, ToolCallResult)? validateResult,
  void Function(ToolCallRequest)? preflight,
  HostEffectIntent? Function(ToolCallRequest, ResolvedAssistantScope)?
  effectIntent,
  bool available,
  String? unavailableReason,
});
