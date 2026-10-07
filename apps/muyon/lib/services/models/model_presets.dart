/// Suggested capabilities for common models (ADR-0005 §10.2). A table of
/// suggestions only: nothing here takes effect until the person adopts it
/// (the test-connection result carries these values as "detected", and
/// "采用" writes them), and a model that is not listed is simply unknown.
library;

final class ModelPreset {
  const ModelPreset(
    this.prefix, {
    required this.contextTokens,
    required this.maxOutputTokens,
    this.nativeTools = true,
    this.streaming = true,
  });

  /// Lower-case model id prefix.
  final String prefix;
  final int contextTokens, maxOutputTokens;
  final bool nativeTools, streaming;
}

/// Longest matching prefix wins, so a specific model overrides its family.
const modelPresets = <ModelPreset>[
  ModelPreset('deepseek-chat', contextTokens: 128000, maxOutputTokens: 8192),
  ModelPreset(
    'deepseek-reasoner',
    contextTokens: 128000,
    maxOutputTokens: 32768,
    nativeTools: false,
  ),
  ModelPreset('gpt-4o', contextTokens: 128000, maxOutputTokens: 16384),
  ModelPreset('gpt-4.1', contextTokens: 1047576, maxOutputTokens: 32768),
  ModelPreset('gpt-4-turbo', contextTokens: 128000, maxOutputTokens: 4096),
  ModelPreset('qwen-max', contextTokens: 32768, maxOutputTokens: 8192),
  ModelPreset('qwen-plus', contextTokens: 131072, maxOutputTokens: 8192),
  ModelPreset('qwen2.5', contextTokens: 32768, maxOutputTokens: 8192),
  ModelPreset('glm-4', contextTokens: 128000, maxOutputTokens: 4096),
  ModelPreset('moonshot-v1-128k', contextTokens: 131072, maxOutputTokens: 8192),
  ModelPreset('moonshot-v1-32k', contextTokens: 32768, maxOutputTokens: 8192),
  ModelPreset('llama3.1', contextTokens: 131072, maxOutputTokens: 4096),
  ModelPreset(
    'llama3',
    contextTokens: 8192,
    maxOutputTokens: 2048,
    nativeTools: false,
  ),
];

/// The preset for [modelId] (case-insensitive, an optional `vendor/` prefix
/// is ignored), or null when the model is not in the table.
ModelPreset? presetFor(String modelId) {
  var id = modelId.trim().toLowerCase();
  final slash = id.lastIndexOf('/');
  if (slash >= 0) id = id.substring(slash + 1);
  ModelPreset? best;
  for (final preset in modelPresets) {
    if (id.startsWith(preset.prefix) &&
        (best == null || preset.prefix.length > best.prefix.length)) {
      best = preset;
    }
  }
  return best;
}
