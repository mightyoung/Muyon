import 'package:muspace_module_api/muspace_module_api.dart';

/// Selection proposes candidates only. It cannot grant tool or network consent.
abstract interface class ToolSelectionStrategy {
  String get id;
  ToolSelection select({
    required String prompt,
    required AssistantScope scope,
    required List<RegisteredToolInfo> availableTools,
    required bool modelAvailable,
  });
}

class ToolSelection {
  ToolSelection({
    required Iterable<String> candidateIds,
    this.ruleToolId,
    Map<String, Object?> ruleParameters = const {},
  }) : candidateIds = List.unmodifiable(candidateIds.toSet()),
       ruleParameters = freezeJsonMap(ruleParameters);
  final List<String> candidateIds;
  final String? ruleToolId;
  final Map<String, Object?> ruleParameters;
}

/// Preserve the explicit offline rule and let a configured model choose among
/// registered candidates. Missing models fall back to the local rule; a failed
/// network request never silently changes endpoint or grants tool authority.
class RuleAndModelToolSelection implements ToolSelectionStrategy {
  const RuleAndModelToolSelection();
  @override
  String get id => 'registered-rule-model-v1';
  @override
  ToolSelection select({
    required String prompt,
    required AssistantScope scope,
    required List<RegisteredToolInfo> availableTools,
    required bool modelAvailable,
  }) {
    final ids = availableTools
        .where((t) => t.available)
        .map((t) => t.descriptor.toolId)
        .toList();
    final exact = ids.contains(prompt.trim()) ? prompt.trim() : null;
    return ToolSelection(
      candidateIds: modelAvailable ? ids : [?exact],
      ruleToolId: modelAvailable ? null : exact,
    );
  }
}
