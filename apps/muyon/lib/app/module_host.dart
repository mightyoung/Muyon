import 'dart:async';

import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../platform/file_gateway.dart';
import '../platform/module_grants.dart';
import '../platform/projection_service.dart';
import '../platform/scope_resolver.dart';
import '../platform/storage_manager.dart';
import '../platform/tool_registry.dart';
import '../workspace/import_coordinator.dart';
import '../workspace/workspace_repository.dart';
import 'host_tool_registrar.dart';
import 'module_registry.dart';

enum ModuleStatus { inactive, activating, ready, failed, closed }

class ModuleState {
  const ModuleState(this.status, [this.reason]);
  final ModuleStatus status;

  /// Why the module failed; null otherwise.
  final String? reason;
  static const inactive = ModuleState(ModuleStatus.inactive);
}

class ModuleStateChange {
  const ModuleStateChange(this.moduleId, this.state);
  final String moduleId;
  final ModuleState state;
}

/// What a tool needs from the host to run a module's handler.
abstract interface class ModuleLink {
  Future<ModuleState> activate(String moduleId);
  T? runtime<T extends ModuleRuntime>(String moduleId);
}

/// How one module appears on the home page and in menus.
class ModuleDeclaration {
  ModuleDeclaration({
    required this.moduleId,
    required this.displayName,
    this.tagline,
    this.iconKey,
    required List<ModuleSection> sections,
  }) : sections = List.unmodifiable(sections);
  final String moduleId;
  final String displayName;
  final String? tagline, iconKey;
  final List<ModuleSection> sections;
}

/// Everything the host still knows by name about a v1 module (or about
/// inquiry, which is not in the registry yet): its declaration, the fixed set
/// of capabilities it gets, and the steps that used to be hard-coded in
/// `bootstrap.dart`. REG-3 / REG-4 migrate the modules and delete this.
class LegacyModuleBridge {
  const LegacyModuleBridge({
    required this.id,
    required this.declaration,
    this.grants = const {},
    this.afterActivate,
    this.externalActivate,
    this.scopeSource,
  });
  final String id;
  final ModuleDeclaration declaration;

  /// Capabilities this v1 module is handed; recorded in `module_grants`.
  final Set<String> grants;

  /// Runs after `module.activate`, inside the failure boundary.
  final Future<void> Function(ModuleRuntime runtime)? afterActivate;

  /// For a module outside the registry: activates it and returns the failure
  /// reason, or null on success. `ModuleHost` then only reports the result.
  final Future<String?> Function()? externalActivate;
  final ScopeSource? scopeSource;
}

class _Slot {
  ModuleState state = ModuleState.inactive;
  ModuleRuntime? runtime;
  Future<ModuleState>? inflight;

  /// Set when the module could not be wired (for example its tools): it will
  /// not activate until the host restarts.
  String? blocked;
  int epoch = 0;
  bool revoking = false;
}

/// The one way a module becomes usable (ADR-0004 §6.1). Activation is
/// idempotent, concurrent calls share one run, a failure only marks that
/// module (and its tools) unavailable, and the next call retries.
class ModuleHost implements ModuleLink {
  ModuleHost({
    required this.registry,
    required this.storage,
    required this.workspaces,
    required this.projections,
    required this.capabilities,
    required this.grants,
    required this.tools,
    required this.notify,
    Iterable<LegacyModuleBridge> legacy = const [],
  }) : _legacy = {for (final bridge in legacy) bridge.id: bridge};

  final ModuleRegistry registry;
  final StorageManager storage;
  final WorkspaceRepository workspaces;
  final ProjectionService projections;
  final CapabilityRegistry capabilities;
  final ModuleGrants grants;
  final ToolRegistry tools;
  final Future<void> Function(String title, String body) notify;
  final Map<String, LegacyModuleBridge> _legacy;
  final Map<String, _Slot> _slots = {};
  final Map<String, List<String>> _toolIds = {};
  final _changes = StreamController<ModuleStateChange>.broadcast();
  final _runs = <Future<ModuleState>>{};
  var _closing = false;
  var _accepting = true;

  /// Freeze public activation admission while the host drains local work
  /// admitted before shutdown. Its existing dependency graph may still finish.
  void stopAdmission() => _accepting = false;
  Future<void>? _closeFuture;

  _Slot _slot(String id) => _slots.putIfAbsent(id, _Slot.new);

  Stream<ModuleStateChange> get changes => _changes.stream;
  ModuleState state(String id) => _slots[id]?.state ?? ModuleState.inactive;

  /// The failure reason while [id] is failed, else null.
  String? error(String id) {
    final state = this.state(id);
    return state.status == ModuleStatus.failed ? state.reason : null;
  }

  @override
  T? runtime<T extends ModuleRuntime>(String id) {
    final runtime = _slots[id]?.runtime;
    return runtime is T ? runtime : null;
  }

  /// Test seam: replaces the active runtime (a spy) without activating.
  void setRuntimeForTesting(String id, ModuleRuntime? runtime) {
    final slot = _slot(id);
    slot.runtime = runtime;
    if (runtime != null) slot.state = const ModuleState(ModuleStatus.ready);
  }

  void _set(String id, ModuleState state) {
    _slot(id).state = state;
    if (!_changes.isClosed) _changes.add(ModuleStateChange(id, state));
  }

  /// Declarations for the home page and menus: registered v2 modules first in
  /// registry order, then legacy ones, each group in catalog order.
  Iterable<ModuleDeclaration> declarations() => [
    for (final module in registry.modules)
      if (module is BusinessModuleV2 &&
          !_legacy.containsKey(module.manifest.id))
        ModuleDeclaration(
          moduleId: module.manifest.id,
          displayName: module.manifest.displayName ?? module.manifest.id,
          tagline: module.manifest.tagline,
          iconKey: module.manifest.iconKey,
          sections: module.sections,
        ),
    for (final bridge in _legacy.values) bridge.declaration,
  ];

  /// All sections, ordered by `order` then declaration order.
  Iterable<ModuleSection> sections() {
    final all = [for (final d in declarations()) ...d.sections];
    final indexed = [for (var i = 0; i < all.length; i++) (i, all[i])];
    indexed.sort((a, b) {
      final byOrder = a.$2.order.compareTo(b.$2.order);
      return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
    });
    return [for (final entry in indexed) entry.$2];
  }

  /// The active runtime of a registered module, activating it first when it
  /// has none; null for a module the registry does not have (inquiry is not a
  /// registered module yet) or one that fails to activate.
  Future<ModuleRuntime?> runtimeFor(String id) async {
    if (!registry.modules.any((m) => m.manifest.id == id)) return null;
    if (_slots[id]?.runtime == null) await activate(id);
    return _slots[id]?.runtime;
  }

  /// The section with [sectionId]'s module, or null.
  String? moduleOfSection(String sectionId) {
    for (final declaration in declarations()) {
      if (declaration.sections.any((s) => s.id == sectionId)) {
        return declaration.moduleId;
      }
    }
    return null;
  }

  /// Where scope objects come from, in listing order: the legacy modules as
  /// they always were, then every registered v2 module through its contract.
  List<ScopeSource> scopeSources() => [
    for (final bridge in _legacy.values)
      if (bridge.scopeSource != null) bridge.scopeSource!,
    for (final module in registry.modules)
      if (module is BusinessModuleV2 &&
          !_legacy.containsKey(module.manifest.id))
        ModuleScopeSource(
          moduleId: module.manifest.id,
          ontology: module.ontology,
          workspaces: workspaces,
          projections: projections,
          runtime: () => _slots[module.manifest.id]?.runtime,
          activate: () async {
            await activate(module.manifest.id);
          },
        ),
  ];

  /// Registers the tools every available v2 module declares. Called once at
  /// start-up, before any activation, so the assistant sees the full set.
  void registerTools() {
    for (final module in registry.modules) {
      if (module is! BusinessModuleV2) continue;
      final id = module.manifest.id;
      final registrar = HostToolRegistrar(id, tools, module.manifest, this);
      try {
        module.registerTools(registrar);
      } catch (error) {
        _slot(id).blocked = 'Tool registration failed: $error';
        _toolIds[id] = registrar.registeredToolIds;
        _withdraw(id, _slot(id).blocked!);
        _set(id, ModuleState(ModuleStatus.failed, _slot(id).blocked));
        continue;
      } finally {
        registrar.seal();
      }
      _toolIds[id] = registrar.registeredToolIds;
    }
  }

  void _withdraw(String id, String reason) {
    for (final toolId in _toolIds[id] ?? const <String>[]) {
      tools.setAvailability(toolId, available: false, reason: reason);
    }
  }

  void _restore(String id) {
    for (final toolId in _toolIds[id] ?? const <String>[]) {
      if (tools.inspect(toolId)?.available == false) {
        tools.setAvailability(toolId, available: true);
      }
    }
  }

  /// Activates [id]; never throws for a module failure. Failure is the
  /// returned state, recorded in `module_registry`, and the next call retries.
  @override
  Future<ModuleState> activate(String id) {
    if (!_accepting) return Future.error(StateError('Host is closing'));
    return _admit(id);
  }

  Future<ModuleState> _admit(String id) {
    if (_closing) return Future.error(StateError('Host is closing'));
    final slot = _slot(id);
    if (slot.revoking) return Future.value(slot.state);
    final existing = slot.inflight;
    if (existing != null) return existing;
    final epoch = ++slot.epoch;
    final run = _activate(id, slot, epoch);
    slot.inflight = run;
    _runs.add(run);
    unawaited(
      run.then<void>(
        (_) {
          _runs.remove(run);
        },
        onError: (Object error, StackTrace stack) {
          _runs.remove(run);
        },
      ),
    );
    return run;
  }

  bool _current(_Slot slot, int epoch) =>
      !_closing && !slot.revoking && slot.epoch == epoch;

  void _checkCurrent(_Slot slot, int epoch) {
    if (!_current(slot, epoch)) throw _Refused('Activation authority ended');
  }

  Future<ModuleState> _activate(String id, _Slot slot, int epoch) async {
    final bridge = _legacy[id];
    final external = bridge?.externalActivate;
    if (external != null) {
      final reason = await external();
      if (!_current(slot, epoch)) return slot.state;
      _set(
        id,
        reason == null
            ? const ModuleState(ModuleStatus.ready)
            : ModuleState(ModuleStatus.failed, reason),
      );
      if (reason != null) slot.inflight = null;
      return slot.state;
    }
    if (slot.runtime != null && slot.state.status == ModuleStatus.ready) {
      return slot.state;
    }
    _set(id, const ModuleState(ModuleStatus.activating));
    try {
      final blocked = slot.blocked;
      if (blocked != null) throw StateError(blocked);
      await _open(id, slot, bridge, epoch);
      _checkCurrent(slot, epoch);
      _set(id, const ModuleState(ModuleStatus.ready));
      await _record(id, 'ready', null);
      _checkCurrent(slot, epoch);
      _restore(id);
    } catch (error) {
      if (!_current(slot, epoch)) return slot.state;
      slot.runtime = null;
      final reason = error is _Refused ? error.message : error.toString();
      _set(id, ModuleState(ModuleStatus.failed, reason));
      _withdraw(id, reason);
      await _record(id, 'failed', reason);
      // After an await, so the caller's `??=` has already stored this future.
      // A module blocked at tool registration stays failed until restart.
      if (slot.blocked == null) slot.inflight = null;
    }
    return slot.state;
  }

  Future<void> _open(
    String id,
    _Slot slot,
    LegacyModuleBridge? bridge,
    int epoch,
  ) async {
    _checkCurrent(slot, epoch);
    final module = registry.require(id);
    final manifest = module.manifest;
    for (final dependency in manifest.requiredDependencies) {
      final state = await _admit(dependency);
      _checkCurrent(slot, epoch);
      if (state.status != ModuleStatus.ready) {
        throw _Refused(
          'Required module $dependency is unavailable: ${state.reason}',
        );
      }
    }
    for (final dependency in manifest.optionalDependencies) {
      if (registry.unavailable.containsKey(dependency) ||
          !registry.canAwaitOptional(id, dependency)) {
        continue;
      }
      try {
        registry.require(dependency);
      } on StateError {
        continue;
      }
      await _admit(dependency);
      _checkCurrent(slot, epoch);
    }
    final decisions = bridge != null && manifest.apiVersion == 1
        ? GrantPolicy.legacy(id, bridge.grants)
        : GrantPolicy.decide(manifest, revoked: grants.revoked(id));
    await grants.record(id, decisions);
    _checkCurrent(slot, epoch);
    final refused = [
      for (final d in decisions)
        if (!d.granted && d.required) d.capability,
    ];
    if (refused.isNotEmpty) {
      throw _Refused('capability_denied: ${refused.join(', ')}');
    }
    final granted = {
      for (final d in decisions)
        if (d.granted) d.capability,
    };
    final denied = {
      for (final d in decisions)
        if (!d.granted) d.capability,
    };
    final connection = await storage.open(id, module.schema);
    _checkCurrent(slot, epoch);
    final auxiliary = <String, ManagedDatabase>{
      if (module is BusinessModuleV2)
        for (final schema in module.auxiliarySchemas)
          schema.id: await storage.open(schema.id, schema.schema),
    };
    _checkCurrent(slot, epoch);
    if (_hasChangeLog(connection.raw)) projections.watch(id, connection);
    final runtime = await module.activate(
      ModuleResources(
        database: connection,
        files: FileGateway(p.join(storage.rootPath, 'modules', id, 'files')),
        capabilities: capabilities.forModule(
          id,
          allowed: granted,
          denied: denied,
          isActive: () => _current(slot, epoch),
        ),
        auxiliary: auxiliary,
      ),
    );
    _checkCurrent(slot, epoch);
    slot.runtime = runtime;
    if (manifest.features.contains(ModuleFeature.importPipeline)) {
      final recovery = await ImportCoordinator(workspaces).recover(id, runtime);
      if (recovery.conflicts.isNotEmpty) {
        await notify('导入未能完成绑定', recovery.conflicts.values.join('\n'));
      }
    }
    await bridge?.afterActivate?.call(runtime);
  }

  static bool _hasChangeLog(Database db) => db.select(
    "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
    [ModuleChangeLog.table],
  ).isNotEmpty;

  Future<void> _record(String id, String status, String? error) =>
      workspaces.database.write(
        (db) => db.execute(
          'INSERT OR REPLACE INTO module_registry VALUES(?,?,?)',
          [id, status, error],
        ),
      );

  /// The host withdraws a granted capability: the module fails with
  /// `capability_revoked` and its tools become unavailable; the grant stays
  /// denied on later activations.
  Future<void> revokeCapability(String id, String capability) async {
    final slot = _slot(id);
    ++slot.epoch;
    slot.revoking = true;
    slot.runtime = null;
    slot.inflight = null;
    final reason = 'capability_revoked: $capability';
    _set(id, ModuleState(ModuleStatus.failed, reason));
    _withdraw(id, reason);
    tools.cancelProvider(id);
    // Remain fail closed if durable revocation fails; a successful retry is
    // required before any new activation may be admitted.
    await grants.revoke(id, capability);
    await _record(id, 'failed', reason);
    slot.revoking = false;
  }

  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    stopAdmission();
    _closing = true;
    for (final entry in _slots.entries.toList()) {
      ++entry.value.epoch;
      entry.value.runtime = null;
      _withdraw(entry.key, 'Host is closing');
    }
    final drainingTools = tools.close();
    await Future.wait(_runs.toList());
    await drainingTools;
    for (final id in _slots.keys.toList()) {
      _slots[id]!.runtime = null;
      _set(id, const ModuleState(ModuleStatus.closed));
    }
    await _changes.close();
  }
}

/// A refusal with a stable reason text (not an exception's `toString`).
class _Refused implements Exception {
  _Refused(this.message);
  final String message;
}
