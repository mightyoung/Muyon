import 'package:muspace_module_api/muspace_module_api.dart';

class ModuleRegistry {
  ModuleRegistry(Iterable<BusinessModule> modules) {
    for (final module in modules) {
      final manifest = module.manifest;
      if (manifest.apiVersion != 1 || _modules.containsKey(manifest.id)) {
        throw StateError('Unsupported or duplicate module ${manifest.id}');
      }
      _modules[manifest.id] = module;
    }
    final visiting = <String>{};
    final visited = <String>{};
    void visit(String id) {
      if (visited.contains(id)) return;
      if (!visiting.add(id)) throw StateError('Module dependency cycle: $id');
      final module = _modules[id];
      if (module == null) throw StateError('Missing required module: $id');
      for (final dependency in module.manifest.requiredDependencies) {
        visit(dependency);
      }
      visiting.remove(id);
      visited.add(id);
    }

    for (final id in _modules.keys) {
      visit(id);
    }
  }
  final Map<String, BusinessModule> _modules = {};
  BusinessModule require(String id) =>
      _modules[id] ?? (throw StateError('Unknown module: $id'));
  Iterable<BusinessModule> get modules => _modules.values;
}
