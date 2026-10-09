import 'package:flutter/widgets.dart';

import 'capabilities.dart';
import 'files.dart';
import 'module_v2.dart';
import 'references.dart';
import 'storage.dart';

abstract interface class BusinessModule {
  ModuleManifest get manifest;
  ModuleSchema get schema;
  List<ModuleRoute> get routes;
  Future<ModuleRuntime> activate(ModuleResources resources);
}

class ModuleManifest {
  ModuleManifest({
    required this.id,
    this.apiVersion = 1,
    this.packageRevision = '0.1.0',
    List<String> requiredDependencies = const [],
    List<String> optionalDependencies = const [],
    this.displayName,
    this.tagline,
    this.iconKey,
    Set<CapabilityRequest> capabilities = const {},
    Set<ModuleFeature> features = const {},
    this.network = NetworkPolicy.none,
  }) : requiredDependencies = List.unmodifiable(requiredDependencies),
       optionalDependencies = List.unmodifiable(optionalDependencies),
       capabilities = Set.unmodifiable(capabilities),
       features = Set.unmodifiable(features);
  final String id;
  final int apiVersion;
  final String packageRevision;
  final List<String> requiredDependencies;

  /// Used when present; a missing optional dependency never disables the module.
  final List<String> optionalDependencies;

  /// v2 additions; every default keeps v1 behavior.
  final String? displayName, tagline, iconKey;

  /// Platform capabilities this module asks for; the host decides and records.
  final Set<CapabilityRequest> capabilities;

  /// Optional interfaces this module declares it implements.
  final Set<ModuleFeature> features;

  /// Where this module's external tools may go.
  final NetworkPolicy network;
}

class ModuleRoute {
  const ModuleRoute({required this.path, required this.builder});
  final String path;
  final Widget Function(BuildContext context, ModuleSession session) builder;
}

class ModuleResources {
  const ModuleResources({
    required this.database,
    required this.files,
    required this.capabilities,
    this.auxiliary = const {},
  });
  final ManagedDatabase database;
  final ModuleFiles files;
  final ModuleCapabilities capabilities;

  /// Databases of [BusinessModuleV2.auxiliarySchemas], by id.
  final Map<String, ManagedDatabase> auxiliary;
}

abstract interface class ModuleRuntime {
  Future<ImportReceipt?> receipt(String operationId);
  Future<PreparedImport> prepareImport(
    SelectedInput input,
    ImportTarget target,
  );
  Future<ImportReceipt> commitImport(PreparedImport input, ImportIntent intent);
  Future<ModuleSession> openSession(WorkspaceBinding binding);
}

abstract interface class ModuleSession {
  Future<ObjectView?> resolve(ObjectRef ref);

  /// Business page for a resolved object, or null when the module has no
  /// dedicated page for this type. Callers resolve the ref first.
  Widget? objectPage(BuildContext context, ObjectRef ref);
  Future<void> flush();
  Future<void> dispose();
}

/// Optional: resolves references of any project without a workspace binding
/// (ADR-0004 §5.1). [ModuleSession.openSession] stays the per-binding session.
abstract interface class ScopeResolvable {
  Future<ModuleSession> openScopeSession();
}

/// For v2 modules with no import pipeline: the v1 import trio, unsupported.
/// Do not declare `ModuleFeature.importPipeline` when using it.
mixin NoImportRuntime implements ModuleRuntime {
  @override
  Future<ImportReceipt?> receipt(String operationId) async => null;
  @override
  Future<PreparedImport> prepareImport(
    SelectedInput input,
    ImportTarget target,
  ) => Future.error(UnsupportedError('This module has no import pipeline'));
  @override
  Future<ImportReceipt> commitImport(
    PreparedImport input,
    ImportIntent intent,
  ) => Future.error(UnsupportedError('This module has no import pipeline'));
}

/// Optional module-owned candidate ordering for an existing catalog. These
/// refs carry identity only; the host always confirms each through resolve.
/// Keeps legacy listing order without moving domain SQL into the host.
abstract interface class ScopeCandidates {
  Future<List<ObjectRef>> scopeCandidates();
}
