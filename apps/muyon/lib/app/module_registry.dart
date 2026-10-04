import 'package:muyon_module_api/muyon_module_api.dart';

/// Static module catalog. A module with an unsupported API version, a missing
/// or unavailable required dependency, or a dependency cycle is marked
/// unavailable with a reason; healthy modules and the host keep working.
class ModuleRegistry {
  static const supportedApiVersion = 1;

  ModuleRegistry(Iterable<BusinessModule> modules) {
    final all = <String, BusinessModule>{};
    for (final module in modules) {
      if (all.containsKey(module.manifest.id)) {
        throw StateError('Duplicate module ${module.manifest.id}');
      }
      all[module.manifest.id] = module;
    }
    final visiting = <String>{};
    final done = <String>{};
    void visit(String id) {
      if (done.contains(id)) return;
      if (!visiting.add(id)) {
        // Every module still on the stack is part of, or depends on, the cycle.
        for (final member in visiting) {
          _unavailable[member] ??= 'Dependency cycle through $id';
        }
        return;
      }
      final manifest = all[id]!.manifest;
      if (manifest.apiVersion != supportedApiVersion) {
        _unavailable[id] = 'Unsupported module API v${manifest.apiVersion}';
      }
      for (final dependency in manifest.requiredDependencies) {
        if (!all.containsKey(dependency)) {
          _unavailable[id] ??= 'Missing required module $dependency';
          continue;
        }
        visit(dependency);
        if (_unavailable.containsKey(dependency)) {
          _unavailable[id] ??= 'Required module $dependency is unavailable';
        }
      }
      visiting.remove(id);
      done.add(id);
    }

    all.keys.forEach(visit);
    for (final entry in all.entries) {
      if (!_unavailable.containsKey(entry.key)) {
        _modules[entry.key] = entry.value;
      }
    }
  }

  final Map<String, BusinessModule> _modules = {};
  final Map<String, String> _unavailable = {};

  /// Module id → human-readable reason, for settings and module status UI.
  Map<String, String> get unavailable => Map.unmodifiable(_unavailable);

  BusinessModule require(String id) =>
      _modules[id] ??
      (throw StateError(_unavailable[id] ?? 'Unknown module: $id'));
  Iterable<BusinessModule> get modules => _modules.values;
}
