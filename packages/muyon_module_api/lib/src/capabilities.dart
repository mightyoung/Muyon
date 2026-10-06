/// Host registry. Providers are registered once and reused by module views.
/// Modules receive a grant snapshot, never the mutable registry itself.
class CapabilityRegistry {
  final Map<String, Object> _providers = {};

  void register<T extends Object>(String id, T provider) {
    if (id.isEmpty || _providers.containsKey(id)) {
      throw StateError('Duplicate or empty capability: $id');
    }
    _providers[id] = provider;
  }

  ModuleCapabilities forModule(
    String moduleId, {
    required Set<String> allowed,
  }) {
    final providers = <String, Object>{};
    for (final id in allowed) {
      final provider = _providers[id];
      if (provider == null) throw StateError('Unknown capability: $id');
      providers[id] = provider;
    }
    return ModuleCapabilities._(moduleId, providers);
  }
}

class ModuleCapabilities {
  ModuleCapabilities._(this.moduleId, Map<String, Object> providers)
    : _providers = Map.unmodifiable(providers);
  final String moduleId;
  final Map<String, Object> _providers;
  Set<String> get available => Set.unmodifiable(_providers.keys);

  T require<T extends Object>(String id) {
    final provider = _providers[id];
    if (provider is! T) throw StateError('Unavailable capability: $id');
    return provider;
  }
}
