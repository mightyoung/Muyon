import 'package:path/path.dart' as path;

/// Trusted host configuration for the experimental Rust Agent backend.
///
/// Null or disabled configuration preserves the ordinary Dart backend. Paths
/// come from the host, never from a model reply or a conversation setting.
final class CoreAgentProcessConfig {
  const CoreAgentProcessConfig({
    this.enabled = false,
    required this.executablePath,
    required this.stateRoot,
  });

  final bool enabled;
  final String executablePath;
  final String stateRoot;

  /// Disabled paths are deliberately unused. Enabled invalid paths never
  /// select the legacy backend as a fallback.
  void validate() {
    if (enabled &&
        (!path.isAbsolute(executablePath) || !path.isAbsolute(stateRoot))) {
      throw StateError('core_config_invalid');
    }
  }
}
