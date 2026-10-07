/// Function names for OpenAI-compatible `tools`, shared by the tool-selection
/// eval and the model providers.
library;

/// Function names allowed by OpenAI-compatible providers.
final _functionName = RegExp(r'^[a-zA-Z0-9_-]{1,64}$');

/// Registered ids use dots, which function names do not allow.
String encodeToolName(String toolId) => toolId.replaceAll('.', '__');

/// Function name → registered id. Decoding is a lookup, not a string rewrite,
/// so a returned name is registered only if it is exactly one we sent.
Map<String, String> toolIdsByFunctionNameOf(Iterable<String> toolIds) {
  final byName = <String, String>{};
  for (final id in toolIds) {
    final name = encodeToolName(id);
    if (!_functionName.hasMatch(name)) {
      throw ArgumentError('Tool id $id is not a valid function name: $name');
    }
    final previous = byName[name];
    if (previous != null && previous != id) {
      throw ArgumentError('Tool ids $previous and $id encode to $name');
    }
    byName[name] = id;
  }
  return byName;
}
