import 'dart:convert';

import 'package:muyon_module_api/muyon_module_api.dart';

import '../workspace/workspace_repository.dart';
import 'projection_service.dart';

String scopeIdentity(ObjectRef ref) => jsonEncode([
  ref.moduleId,
  ref.objectType,
  ref.nativeProjectId,
  ref.objectId,
]);

/// Where one module's current objects come from. A v2 module is read through
/// [ModuleScopeSource]; a v1 module (and inquiry) through a source its legacy
/// bridge supplies. Everything else about resolving a scope is shared.
abstract interface class ScopeSource {
  String get moduleId;

  /// Makes the module usable (activation); never throws for an unavailable
  /// module, which then simply has no objects.
  Future<void> prepare();

  /// Every object the module currently has in global scope, as canonical refs.
  Future<List<ObjectRef>> enumerate();

  /// True when [resolve] answers for one ref without enumerating (v2
  /// modules). A source that cannot do that is looked up in its enumeration.
  bool get resolvesDirectly;

  /// The canonical current ref for [requested], or null when it is gone or the
  /// pinned revision / digest no longer matches. Only called when
  /// [resolvesDirectly].
  Future<ObjectRef?> resolve(ObjectRef requested);
}

/// The single entry that turns an [AssistantScope] into explicit object refs
/// (ADR-0004 §5.2). Domain objects stay in their modules; this only resolves
/// identities and versions.
class ScopeResolver {
  ScopeResolver({
    required this.sources,
    required this.workspaces,
    required this.knowledgeSources,
  });

  /// In the order their objects are listed.
  final List<ScopeSource> sources;
  final WorkspaceRepository workspaces;

  /// Source refs of knowledge-base documents whose content is still current.
  final Future<List<ObjectRef>> Function() knowledgeSources;

  Future<ResolvedAssistantScope> resolve(AssistantScope scope) async {
    final objects = <String, ObjectRef>{};
    void add(ObjectRef ref) => objects[scopeIdentity(ref)] = ref;
    final selecting = scope.kind == AssistantScopeKind.selectedObjects;
    final direct = <String, ScopeSource>{};
    for (final source in sources) {
      await source.prepare();
      if (source.resolvesDirectly) direct[source.moduleId] = source;
      // A selection of a directly resolvable module is checked one ref at a
      // time below; its whole catalog is not enumerated for that.
      if (selecting && source.resolvesDirectly) continue;
      (await source.enumerate()).forEach(add);
    }
    for (final ref in await knowledgeSources()) {
      objects.putIfAbsent(scopeIdentity(ref), () => ref);
    }
    if (scope.kind == AssistantScopeKind.global) {
      return ResolvedAssistantScope(
        requested: scope,
        objects: objects.values.toList(),
      );
    }
    final workspace = scope.workspaceId;
    if (workspace != null && !workspaces.all().any((w) => w.id == workspace)) {
      throw StateError('Unknown workspace');
    }
    bool inWorkspace(ObjectRef ref) {
      if (workspace == null) return true;
      final binding = workspaces.binding(workspace, ref.moduleId);
      return binding != null && binding.nativeProjectId == ref.nativeProjectId;
    }

    if (scope.kind == AssistantScopeKind.workspace) {
      return ResolvedAssistantScope(
        requested: scope,
        objects: objects.values.where(inWorkspace).toList(),
      );
    }
    final selected = <ObjectRef>[];
    for (final requested in scope.objects) {
      final source = direct[requested.moduleId];
      final current = source != null
          ? await source.resolve(requested)
          : objects[scopeIdentity(requested)];
      if (current == null ||
          !sameObjectIdentity(current, requested) ||
          !inWorkspace(current) ||
          (requested.revisionRef != null &&
              requested.revisionRef != current.revisionRef) ||
          (requested.contentDigest != null &&
              requested.contentDigest != current.contentDigest)) {
        throw StateError(
          'Selected object is missing, changed or outside workspace',
        );
      }
      selected.add(current);
    }
    return ResolvedAssistantScope(requested: scope, objects: selected);
  }
}

/// Reads a v2 module without a workspace binding: candidates from the host's
/// object catalog (the module's change log, applied by [ProjectionService]),
/// truth from [ScopeResolvable.openScopeSession] + `resolve`. The catalog is
/// never trusted: a candidate the module no longer resolves is dropped.
class ModuleScopeSource implements ScopeSource {
  ModuleScopeSource({
    required this.moduleId,
    required this.ontology,
    required this.workspaces,
    required this.projections,
    required this.runtime,
    required this.activate,
  });
  @override
  final String moduleId;
  final ModuleOntology ontology;
  final WorkspaceRepository workspaces;
  final ProjectionService projections;
  final ModuleRuntime? Function() runtime;
  final Future<void> Function() activate;

  @override
  Future<void> prepare() => activate();

  @override
  bool get resolvesDirectly => true;

  Set<String> get _types => {
    for (final type in ontology.objectTypes)
      if (type.inGlobalScope) type.name,
  };

  @override
  Future<List<ObjectRef>> enumerate() async {
    final module = runtime();
    if (module is! ScopeResolvable) return const [];
    final types = _types;
    if (types.isEmpty) return const [];
    await projections.idle(moduleId);
    final candidates = [
      for (final row in workspaces.database.raw.select(
        'SELECT project_id,object_type,object_id FROM object_catalog '
        'WHERE module_id=? ORDER BY project_id,object_type,object_id',
        [moduleId],
      ))
        if (types.contains(row['object_type']))
          ObjectRef(
            moduleId: moduleId,
            objectType: row['object_type'] as String,
            objectId: row['object_id'] as String,
            nativeProjectId:
                row['project_id'] == ProjectionService.globalProject
                ? null
                : row['project_id'] as String,
          ),
    ];
    final session = await (module as ScopeResolvable).openScopeSession();
    try {
      final views = await Future.wait([
        for (final ref in candidates) session.resolve(ref),
      ]);
      return [
        for (final view in views)
          if (view != null) view.ref,
      ];
    } finally {
      await session.dispose();
    }
  }

  @override
  Future<ObjectRef?> resolve(ObjectRef requested) async {
    final module = runtime();
    if (module is! ScopeResolvable) return null;
    final session = await (module as ScopeResolvable).openScopeSession();
    try {
      return (await session.resolve(requested))?.ref;
    } finally {
      await session.dispose();
    }
  }
}
