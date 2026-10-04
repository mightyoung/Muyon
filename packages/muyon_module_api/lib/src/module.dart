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
  }) : requiredDependencies = List.unmodifiable(requiredDependencies);
  final String id;
  final int apiVersion;
  final String packageRevision;
  final List<String> requiredDependencies;
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
  Future<void> flush();
  Future<void> dispose();
}
