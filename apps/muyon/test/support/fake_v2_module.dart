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
    int apiVersion = 2,
    this.failActivation = false,
    this.onRegisterTools,
    List<ModuleSection>? sections,
    this.displayName,
  }) : manifest = ModuleManifest(
         id: id,
         apiVersion: apiVersion,
         displayName: displayName,
         requiredDependencies: requires,
         capabilities: capabilities,
         features: features,
         network: network,
       ),
       sections = sections ?? const [];
  @override
  final ModuleManifest manifest;
  final String? displayName;
  bool failActivation;
  int activations = 0;
  FakeRuntime? runtime;
  final void Function(ToolRegistrar registrar)? onRegisterTools;
  @override
  final List<ModuleSection> sections;
  @override
  ModuleSchema get schema => fakeSchema();
  @override
  List<ModuleRoute> get routes => const [];
  @override
  ModuleOntology get ontology => ModuleOntology.empty();
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
    if (failActivation) throw StateError('boom from ${manifest.id}');
    return runtime = FakeRuntime(resources);
  }
}

ModuleSection fakeSection(String id) =>
    ModuleSection(id: id, label: id, builder: (_, _) => const SizedBox());
