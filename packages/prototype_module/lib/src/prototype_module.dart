import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;

import 'prototype_screens.dart';
import 'module_tools.dart';
import 'module_declarations.dart';
import 'models.dart';
import 'prototype_store.dart';
import 'prototype_web_page.dart';

/// Business module for single-page prototypes shown in a restricted WebView.
class PrototypeModule implements BusinessModuleV2 {
  @override
  ModuleManifest get manifest => ModuleManifest(
    id: prototypeModuleId, apiVersion: 2, displayName: '原型页面',
    tagline: '导入单页原型，评审版本并记录反馈（不是完整业务系统）',
    iconKey: 'web', features: {ModuleFeature.objectPages},
  );

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
  // Legacy API compatibility; the v2 host consumes sections, not routes.
  List<ModuleRoute> get routes => [ModuleRoute(path:'/', builder:(context, session) =>
    PrototypeHome(store:(session as PrototypeSession).runtime.store))];
  @override
  ModuleOntology get ontology => prototypeOntology;
  @override
  CapabilityCoverage get coverage => prototypeCoverage;
  @override
  List<AuxiliarySchema> get auxiliarySchemas => const [];
  @override
  List<SearchSource> get searchSources => const []; // REG-3b.
  @override
  List<ModuleSection> get sections => [ModuleSection(
    id: prototypeModuleId, label: '原型页面', showInModuleMenu: false,
    builder: (context, host) => PrototypeHome(
      store: host.runtime<PrototypeRuntime>()!.store,
    ),
  )];
  @override
  void registerTools(ToolRegistrar registrar) => registerPrototypeTools(registrar);

  @override
  Future<PrototypeRuntime> activate(ModuleResources resources) async =>
      PrototypeRuntime(resources);
}

class PrototypeRuntime implements ModuleRuntime, ScopeResolvable, ScopeCandidates, ObjectPages {
  PrototypeRuntime(this.resources)
    : store = PrototypeStore(
        database: resources.database,
        filesRoot: resources.files.rootPath,
      );
  final ModuleResources resources;
  final PrototypeStore store;

  @override
  Future<ModuleSession> openScopeSession() async => PrototypeSession(this,
    const WorkspaceBinding(workspaceId: '', moduleId: prototypeModuleId,
      nativeProjectId: ''),
  );

  @override
  Future<List<ObjectRef>> scopeCandidates() async => prototypeScopeRefs(store);

  @override
  Future<ObjectPageLease?> open(BuildContext context, ObjectRef ref) async {
    final session = await openScopeSession();
    var transferred = false;
    try {
      final view = await session.resolve(ref);
      if (view == null || !context.mounted) return null;
      final page = session.objectPage(context, view.ref);
      if (page == null) return null;
      transferred = true;
      return ObjectPageLease(title: view.title, page: page, dispose: session.dispose);
    } finally {
      if (!transferred) await session.dispose();
    }
  }

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
  bool _disposed = false;
  void _ensureActive() {
    if (_disposed) throw StateError('Session disposed');
  }
  ObjectView? _view(ObjectRef requested, ObjectRef current, String title, {String? summary}) {
    if ((requested.nativeProjectId != null && requested.nativeProjectId != current.nativeProjectId) ||
        requested.revisionRef != null ||
        (requested.contentDigest != null && requested.contentDigest != current.contentDigest)) {
      return null;
    }
    return ObjectView(ref: current, title: title, summary: summary);
  }
  ObjectRef _ref(String type, String id, String pageId, {String? digest}) => ObjectRef(
    moduleId: prototypeModuleId, objectType: type, objectId: id,
    nativeProjectId: pageId, contentDigest: digest,
  );

  @override
  Future<ObjectView?> resolve(ObjectRef ref) async {
    _ensureActive();
    if (ref.moduleId != prototypeModuleId) return null;
    final store = runtime.store;
    switch (ref.objectType) {
      case 'page':
        final page = store.pages().where((x) => x.id == ref.objectId);
        if (page.isEmpty) return null;
        return _view(ref, _ref('page', page.first.id, page.first.id), page.first.title);
      case 'feedback':
        final feedback = store.feedbackById(ref.objectId);
        if (feedback == null) return null;
        final page = store.pages().where((x) => x.id == feedback.pageId);
        if (page.isEmpty) return null;
        return _view(
          ref, _ref('feedback', feedback.id, feedback.pageId,
            digest: sha256.convert(utf8.encode(feedback.text)).toString()),
          '${page.first.title} 反馈',
          summary: feedback.text,
        );
      case 'version':
        final version = store.version(ref.objectId);
        if (version == null) return null;
        final page = store.pages().where((x) => x.id == version.pageId);
        if (page.isEmpty) return null;
        return _view(
          ref, _ref('version', version.id, version.pageId, digest: version.digest),
          '${page.first.title} ${version.label}',
          summary:
              '${version.fileCount} 个文件 · ${p.basename(version.directory)}',
        );
    }
    return null;
  }

  @override
  Widget? objectPage(BuildContext context, ObjectRef ref) {
    _ensureActive();
    if (ref.moduleId != prototypeModuleId) return null;
    final canonical = prototypeScopeRefs(runtime.store).where((r) =>
      r.objectType == ref.objectType && r.objectId == ref.objectId).firstOrNull;
    if (canonical == null || _view(ref, canonical, '') == null) return null;
    final store = runtime.store;
    PrototypePage? pageOf(String id) =>
        store.pages().where((x) => x.id == id).firstOrNull;
    switch (ref.objectType) {
      case 'page':
        final page = pageOf(ref.objectId);
        return page == null ? null : _detail(store, page);
      case 'version':
        final version = store.version(ref.objectId);
        final page = version == null ? null : pageOf(version.pageId);
        if (version == null || page == null) return null;
        return PrototypeWebPage(
          store: store,
          version: version,
          title: page.title,
          webViewBuilder: defaultPrototypeWebView,
        );
      case 'feedback':
        final feedback = store.feedbackById(ref.objectId);
        final page = feedback == null ? null : pageOf(feedback.pageId);
        return page == null
            ? null
            : _detail(store, page, focusFeedbackId: feedback!.id);
    }
    return null;
  }

  Widget _detail(
    PrototypeStore store,
    PrototypePage page, {
    String? focusFeedbackId,
  }) => PrototypeDetail(
    store: store,
    page: page,
    pickDirectory: pickBuildDirectory,
    webViewBuilder: defaultPrototypeWebView,
    focusFeedbackId: focusFeedbackId,
  );

  @override
  Future<void> flush() async { _ensureActive(); }
  @override
  Future<void> dispose() async { _disposed = true; }
}
