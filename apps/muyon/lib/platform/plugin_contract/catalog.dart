import 'package:muyon_module_api/muyon_module_api.dart';
import '../../assistant/tool_selection.dart';

/// Refusing declaration mapping shell until its behavioral test is RED.
class PluginCatalog {
  static Map<String, Object?> mapRead({required ModuleOntology ontology,
    required ToolDescriptor descriptor, required Set<String> admittedTypes,
    required String bindingId}) => {};
}
class PluginCatalogSelection implements ToolSelectionStrategy {
  PluginCatalogSelection(Iterable<String> visible);
  @override
  String get id => 'plugin-contract-directory-v1';
  @override
  ToolSelection select({required String prompt, required AssistantScope scope,
    required List<RegisteredToolInfo> availableTools, required bool modelAvailable}) =>
      ToolSelection(candidateIds: const []);
}
