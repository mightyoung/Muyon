import 'package:flutter/widgets.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;

import 'prototype_screens.dart';
import 'prototype_store.dart';

/// Business module for single-page prototypes shown in a restricted WebView.
class PrototypeModule implements BusinessModule {
  @override
  ModuleManifest get manifest => ModuleManifest(id: prototypeModuleId);

  @override
  ModuleSchema get schema => ModuleSchema(
    version: 1,
    definitionDigest: 'prototype-schema-1',
    migrations: [
      ModuleMigration(
        version: 1,
        id: 'prototype-1',
        definitionDigest: 'prototype-schema-1',
        migrate: createPrototypeTables,
      ),
    ],
  );

  @override
  List<ModuleRoute> get routes => [
    ModuleRoute(
      path: '/',
      builder: (context, session) =>
          PrototypeHome(store: (session as PrototypeSession).runtime.store),
    ),
  ];

  @override
  Future<PrototypeRuntime> activate(ModuleResources resources) async =>
      PrototypeRuntime(resources);
}

class PrototypeRuntime implements ModuleRuntime {
  PrototypeRuntime(this.resources)
    : store = PrototypeStore(
        database: resources.database,
        filesRoot: resources.files.rootPath,
      );
  final ModuleResources resources;
  final PrototypeStore store;

  // Prototypes are imported inside the module (build folder → copied, hashed
  // version); there is no workspace-level import intent for them.
  @override
  Future<ImportReceipt?> receipt(String operationId) async => null;
  @override
  Future<PreparedImport> prepareImport(
    SelectedInput input,
    ImportTarget target,
  ) => Future.error(UnsupportedError('原型通过模块页面导入'));
  @override
  Future<ImportReceipt> commitImport(
    PreparedImport input,
    ImportIntent intent,
  ) => Future.error(UnsupportedError('原型通过模块页面导入'));

  @override
  Future<PrototypeSession> openSession(WorkspaceBinding binding) async =>
      PrototypeSession(this, binding);
}

class PrototypeSession implements ModuleSession {
  PrototypeSession(this.runtime, this.binding);
  final PrototypeRuntime runtime;
  final WorkspaceBinding binding;

  @override
  Future<ObjectView?> resolve(ObjectRef ref) async {
    if (ref.moduleId != prototypeModuleId) return null;
    final store = runtime.store;
    switch (ref.objectType) {
      case 'page':
        final page = store.pages().where((x) => x.id == ref.objectId);
        if (page.isEmpty) return null;
        return ObjectView(ref: ref, title: page.first.title);
      case 'version':
        final version = store.version(ref.objectId);
        if (version == null) return null;
        final page = store.pages().firstWhere((x) => x.id == version.pageId);
        return ObjectView(
          ref: ref,
          title: '${page.title} ${version.label}',
          summary:
              '${version.fileCount} 个文件 · ${p.basename(version.directory)}',
        );
    }
    return null;
  }

  @override
  Widget? objectPage(BuildContext context, ObjectRef ref) => null;
  @override
  Future<void> flush() async {}
  @override
  Future<void> dispose() async {}
}
