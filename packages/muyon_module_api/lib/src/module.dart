import 'package:flutter/widgets.dart';

import 'capabilities.dart';
import 'files.dart';
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
  }) : requiredDependencies = List.unmodifiable(requiredDependencies),
       optionalDependencies = List.unmodifiable(optionalDependencies);
  final String id;
  final int apiVersion;
  final String packageRevision;
  final List<String> requiredDependencies;

  /// Used when present; a missing optional dependency never disables the module.
  final List<String> optionalDependencies;
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
  });
  final ManagedDatabase database;
  final ModuleFiles files;
  final ModuleCapabilities capabilities;
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
