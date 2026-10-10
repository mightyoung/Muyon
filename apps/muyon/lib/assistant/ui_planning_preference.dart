import '../platform/foundation_repository.dart';
import '../workspace/workspace_repository.dart';

/// Presentation choice only; never alters tool/model authorization.
final class UiPlanningPreference {
  UiPlanningPreference(FoundationRepository repository)
      : settings = WorkspaceRepository(repository.database);
  final WorkspaceRepository settings;
  static const key = 'assistant.uiPlanning.enabled.v1';

  bool read({required bool fallback}) {
    try {
      final exists = settings.database.raw.select(
        'SELECT 1 FROM settings WHERE key=?', [key]).isNotEmpty;
      if (!exists) return fallback;
      return settings.setting(key) == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> save(bool enabled) => settings.setSetting(key, enabled);
}
