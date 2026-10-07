import 'package:flutter/widgets.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

/// A runtime with no import pipeline and a flag the tests can read.
class FakeRuntime with NoImportRuntime {
  FakeRuntime(this.resources);
  final ModuleResources resources;
  int sessions = 0;
  @override
  Future<ModuleSession> openSession(WorkspaceBinding binding) async {
    sessions++;
    throw UnimplementedError('FakeRuntime has no sessions');
  }
}

ModuleSchema fakeSchema() => ModuleSchema(
  version: 1,
  definitionDigest: 'fake-v1',
  migrations: [
    ModuleMigration(
      version: 1,
      id: 'fake-1',
      definitionDigest: 'fake-v1',
      migrate: (db) =>
          db.execute('CREATE TABLE fake_items(id TEXT PRIMARY KEY)'),
    ),
  ],
);

/// A minimal v2 module. [onRegisterTools] declares tools; [failActivation]
/// makes `activate` throw, to test failure isolation.
class FakeV2Module implements BusinessModuleV2 {
  FakeV2Module(
    String id, {
    Set<CapabilityRequest> capabilities = const {},
    Set<ModuleFeature> features = const {},
    NetworkPolicy network = NetworkPolicy.none,
    List<String> requires = const [],
    List<String> optional = const [],
    int apiVersion = 2,
    this.failActivation = false,
    this.onRegisterTools,
    List<ModuleSection>? sections,
    this.displayName,
    String? tagline,
    ModuleOntology? ontology,
    this.runtimeFactory,
  }) : manifest = ModuleManifest(
         id: id,
         apiVersion: apiVersion,
         displayName: displayName,
         tagline: tagline,
         requiredDependencies: requires,
         optionalDependencies: optional,
         capabilities: capabilities,
         features: features,
         network: network,
       ),
       ontology = ontology ?? ModuleOntology.empty(),
       sections = sections ?? const [];
  @override
  final ModuleManifest manifest;
  final String? displayName;
  bool failActivation;
  int activations = 0;
  ModuleRuntime? runtime;
  ModuleResources? lastResources;
  final void Function(ToolRegistrar registrar)? onRegisterTools;
  final ModuleRuntime Function(ModuleResources resources)? runtimeFactory;
  @override
  final List<ModuleSection> sections;
  @override
  final ModuleOntology ontology;
  @override
  ModuleSchema get schema => fakeSchema();
  @override
  List<ModuleRoute> get routes => const [];
  @override
  List<AuxiliarySchema> get auxiliarySchemas => const [];
  @override
  List<SearchSource> get searchSources => const [];
  @override
  CapabilityCoverage get coverage => CapabilityCoverage.empty;
  @override
  void registerTools(ToolRegistrar registrar) =>
      onRegisterTools?.call(registrar);
  @override
  Future<ModuleRuntime> activate(ModuleResources resources) async {
    activations++;
    lastResources = resources;
    if (failActivation) throw StateError('boom from ${manifest.id}');
    return runtime = runtimeFactory?.call(resources) ?? FakeRuntime(resources);
  }
}

ModuleSection fakeSection(String id, {Widget? body, String? label}) =>
    ModuleSection(
      id: id,
      label: label ?? id,
      builder: (_, _) => body ?? const SizedBox(),
    );

/// A runtime whose objects live in memory and that can resolve any of them
/// without a workspace binding (`ScopeResolvable`).
class ResolvableRuntime with NoImportRuntime implements ScopeResolvable {
  ResolvableRuntime(this.objects, {this.lie = false});

  /// Keyed `type/id`.
  final Map<String, ObjectRef> objects;

  /// Answers every `resolve` with a different object's identity.
  final bool lie;
  int sessionsOpened = 0, sessionsDisposed = 0;
  @override
  Future<ModuleSession> openSession(WorkspaceBinding binding) =>
      throw UnimplementedError();
  @override
  Future<ModuleSession> openScopeSession() async {
    sessionsOpened++;
    return _ScopeSession(this);
  }
}

class _ScopeSession implements ModuleSession {
  _ScopeSession(this.runtime);
  final ResolvableRuntime runtime;
  @override
  Future<ObjectView?> resolve(ObjectRef ref) async {
    final current = runtime.objects['${ref.objectType}/${ref.objectId}'];
    if (current == null) return null;
    if ((ref.revisionRef != null && ref.revisionRef != current.revisionRef) ||
        (ref.contentDigest != null &&
            ref.contentDigest != current.contentDigest)) {
      return null;
    }
    if (runtime.lie) {
      return ObjectView(
        ref: ObjectRef(
          moduleId: current.moduleId,
          objectType: current.objectType,
          objectId: 'someone-else',
          nativeProjectId: current.nativeProjectId,
        ),
        title: 'lie',
      );
    }
    return ObjectView(ref: current, title: current.objectId);
  }

  @override
  Widget? objectPage(BuildContext context, ObjectRef ref) => null;
  @override
  Future<void> flush() async {}
  @override
  Future<void> dispose() async => runtime.sessionsDisposed++;
}

ObjectTypeSpec fakeType(String name, {bool inGlobalScope = true}) =>
    ObjectTypeSpec(
      name: name,
      label: name,
      description: name,
      iconKey: name,
      titleField: 'title',
      inGlobalScope: inGlobalScope,
      versioned: true,
      fields: const [
        OntologyFieldSpec(
          name: 'title',
          label: 'Title',
          description: 'Title',
          kind: FieldKind.text,
          sensitivity: Sensitivity.none,
        ),
      ],
    );
