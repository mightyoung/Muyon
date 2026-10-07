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
    Set<String> denied = const {},
    bool Function()? isActive,
  }) {
    final providers = <String, Object>{};
    for (final id in allowed) {
      final provider = _providers[id];
      if (provider == null) throw StateError('Unknown capability: $id');
      providers[id] = provider;
    }
    return ModuleCapabilities._(moduleId, providers, denied, isActive);
  }
}

class ModuleCapabilities {
  ModuleCapabilities._(
    this.moduleId,
    Map<String, Object> providers, [
    Set<String> denied = const {},
    this._isActive,
  ]) : _providers = Map.unmodifiable(providers),
       denied = Set.unmodifiable(denied);
  final String moduleId;
  final Map<String, Object> _providers;
  final bool Function()? _isActive;
  Set<String> get available => (_isActive?.call() ?? true)
      ? Set.unmodifiable(_providers.keys)
      : const <String>{};

  /// Requested capabilities the host declined, so a module can degrade.
  final Set<String> denied;

  T require<T extends Object>(String id) {
    if (!(_isActive?.call() ?? true)) {
      throw StateError('Module capability lifetime has ended');
    }
    final provider = _providers[id];
    if (provider is! T) throw StateError('Unavailable capability: $id');
    return provider;
  }
}
