import 'package:muyon_module_api/muyon_module_api.dart';

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

/// Laya may propose a read-only tool only. Write, export and network tools are
/// removed before the chooser sees them, and a named write or external id is
/// dropped even if the chooser returns one. This is not the production
/// selector, and nothing here calls Laya.
class ReadOnlyLayaToolSelection implements ToolSelectionStrategy {
  const ReadOnlyLayaToolSelection(this._choose);

  final String? Function(String prompt, List<RegisteredToolInfo> readOnly)
  _choose;

  @override
  String get id => 'laya-readonly-v1';

  @override
  ToolSelection select({
    required String prompt,
    required AssistantScope scope,
    required List<RegisteredToolInfo> availableTools,
    required bool modelAvailable,
  }) {
    final readOnly = [
      for (final tool in availableTools)
        if (tool.available && tool.accessLevel == ToolAccessLevel.read) tool,
    ];
    final allow = readOnly.map((tool) => tool.descriptor.toolId).toSet();
    final named = _choose(prompt, readOnly);
    final chosen = named != null && allow.contains(named) ? named : null;
    return ToolSelection(
      candidateIds: chosen == null ? const <String>[] : <String>[chosen],
      ruleToolId: chosen,
    );
  }
}
