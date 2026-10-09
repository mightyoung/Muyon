import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/module_host.dart';
import 'package:muyon/platform/module_grants.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:prototype_module/prototype_module.dart';
import 'package:research_module/research_module.dart';

// The v1 module identity, physical schema and fixed host grant vocabulary.
// Real ModuleHost/ModuleGrants write the pre-upgrade database, not fake rows.
class _V1Research implements BusinessModule {
  @override
  ModuleManifest get manifest => ModuleManifest(id: 'research');
  @override
  ModuleSchema get schema => ResearchModule().schema;
  @override
  List<ModuleRoute> get routes => const [];
  @override
  Future<ModuleRuntime> activate(ModuleResources resources) =>
      ResearchModule().activate(resources);
}

class _Reads implements ToolRegistrar {
  @override
  String get moduleId => 'prototype';
  final handlers = <String, ModuleToolHandler>{};
  @override
  void read(ToolSpec spec, ModuleToolHandler handler) {
    handlers[spec.name] = handler;
  }
  @override
  void write(WriteToolSpec spec, ModuleToolHandler handler) {}
  @override
  void external(ExternalToolSpec spec, ModuleToolHandler handler) =>
      throw UnimplementedError();
  @override
  HostChannel channel(ChannelSpec spec) => throw UnimplementedError();
}

class _ReadBarrier implements ModuleToolContext {
  _ReadBarrier(this.call, this.value, this.entered, this.release);
  @override
  final ToolCallContext call;
  final PrototypeRuntime value;
  final Completer<void> entered, release;
  @override
  Future<T> runtime<T extends ModuleRuntime>() async {
    entered.complete();
    await release.future;
    return value as T;
  }
}

void main() {
  late Directory root;
  MuyonHost? host;
  setUp(() => root = Directory.systemTemp.createTempSync('reg3a-upgrade-'));
  tearDown(() async {
    await host?.close();
    root.deleteSync(recursive: true);
  });

  test('v1 tools withdrawal survives v2 manifest removal and two restarts', () async {
    final path = p.join(root.path, 'data');
    final old = host = await MuyonHost.open(path, modules: [_V1Research()]);
    final legacy = ModuleHost(
      registry: old.registry, storage: old.storage, workspaces: old.workspaces,
      projections: old.projections, capabilities: old.capabilities,
      grants: old.grants, tools: old.tools, notify: (_, _) async {},
      legacy: [LegacyModuleBridge(
        id: 'research', grants: {'knowledge', 'models', 'tools'},
        declaration: ModuleDeclaration(moduleId: 'research', displayName: '科研', sections: []),
      )],
    );
    try {
      expect((await legacy.activate('research')).status, ModuleStatus.ready);
      expect(old.grants.forModule('research').map((d) => d.capability).toSet(),
          {'knowledge', 'models', 'tools'});
      expect(old.grants.forModule('research').every((d) => d.granted), isTrue);
      final store = legacy.runtime<ResearchRuntime>('research')!.store;
      await store.write(() => store.db.execute(
        'INSERT INTO projects(id,title,question,next_step) VALUES(?,?,?,?)',
        ['kept', '升级保留', '', ''],
      ));
      await legacy.revokeCapability('research', 'tools');
      expect(old.grants.revoked('research'), {'tools'});
    } finally {
      await legacy.close();
      await old.close();
      host = null;
    }

    // Open the exact same host/module database with the real v2 module.
    for (var restart = 0; restart < 2; restart++) {
      final next = host = await MuyonHost.open(path, modules: [ResearchModule()]);
      expect(next.tools.inspect('research.objects')!.available, isFalse);
      expect((await next.modules.activate('research')).status, ModuleStatus.failed);
      expect(next.modules.runtime<ResearchRuntime>('research'), isNull);
      expect(next.grants.revoked('research'), {'tools'});
      final tombstone = next.grants.forModule('research')
          .singleWhere((d) => d.capability == 'tools');
      expect(tombstone.granted, isFalse);
      expect(tombstone.policy, 'revoked');
      await expectLater(next.tools.invoke(ToolCallRequest(
        invocationId: 'revoked-upgrade-$restart', toolId: 'research.objects',
        scope: const AssistantScope.global(),
      )), throwsA(isA<Exception>()));
      await next.close();
      host = null;
    }

    final next = host = await MuyonHost.open(path, modules: [ResearchModule()]);
    await expectLater(next.modules.reconsiderCapability('research', 'not-a-capability'),
        throwsStateError);
    expect((await next.modules.reconsiderCapability('research', 'tools')).status,
        ModuleStatus.ready);
    expect(next.grants.revoked('research'), isEmpty);
    expect(next.grants.forModule('research').any((d) => d.capability == 'tools'), isFalse);
    expect(next.research!.resources.capabilities.available, isEmpty);
    expect(next.research!.store.projects().single.title, '升级保留');
    expect(next.tools.inspect('research.objects')!.available, isTrue);
    expect((await next.tools.invoke(ToolCallRequest(
      invocationId: 'acknowledged-upgrade', toolId: 'research.objects',
      scope: const AssistantScope.global(),
    ))).status, ToolCallStatus.succeeded);
    await expectLater(next.modules.reconsiderCapability('research', 'tools'), throwsStateError);
    await next.close();
    host = await MuyonHost.open(path, modules: [ResearchModule()]);
    expect((await host!.modules.activate('research')).status, ModuleStatus.ready);
    expect(host!.grants.forModule('research').any((d) => d.capability == 'tools'), isFalse);
    expect(host!.research!.store.projects().single.id, 'kept');
  });

  test('recording a stale decision cannot replace a queued withdrawal', () async {
    host = await MuyonHost.open(p.join(root.path, 'record'));
    final grants = host!.grants;
    const decision = GrantDecision(moduleId: 'fixture', capability: 'tools',
      required: true, reason: 'v1 fixed grant', granted: true, policy: 'legacy');
    await grants.record('fixture', [decision]);
    await grants.revoke('fixture', 'tools');
    await grants.record('fixture', [decision]);
    expect(grants.revoked('fixture'), {'tools'});
    expect(grants.forModule('fixture').single.granted, isFalse);
    await grants.record('fixture', []);
    expect(grants.revoked('fixture'), {'tools'});
  });

  for (final changed in ['page', 'version', 'feedback', 'feedback-owner']) {
    test('page_detail refuses $changed changes while runtime awaits', () async {
      final current = host = await MuyonHost.open(p.join(root.path, changed));
      await current.activatePrototype();
      final runtime = current.prototype!;
      final build = Directory(p.join(root.path, 'build'))..createSync();
      File(p.join(build.path, 'index.html')).writeAsStringSync('<p>页面</p>');
      final version = await runtime.store.importBuild(sourceDir: build.path, title: '原型');
      final feedback = await runtime.store.addFeedback(versionId: version.id, text: '旧正文');
      final selection = AssistantScope.selectedObjects([
        ObjectRef(moduleId: 'prototype', objectType: 'page', objectId: version.pageId,
            nativeProjectId: version.pageId),
        ObjectRef(moduleId: 'prototype', objectType: 'version', objectId: version.id,
            nativeProjectId: version.pageId, contentDigest: version.digest),
        // Resolve the actual digest rather than reproducing its algorithm.
        (await current.scopeResolver.resolve(AssistantScope.selectedObjects([
          ObjectRef(moduleId: 'prototype', objectType: 'feedback', objectId: feedback.id,
              nativeProjectId: version.pageId),
        ]))).objects.single,
      ]);
      final positive = await current.tools.invoke(ToolCallRequest(
        invocationId: 'before-$changed', toolId: 'prototype.page_detail',
        parameters: {'page_id': version.pageId}, scope: selection,
      ));
      expect(positive.status, ToolCallStatus.succeeded);
      expect((positive.data['feedback'] as List).single['text'], '旧正文');

      final captured = _Reads();
      PrototypeModule().registerTools(captured);
      final entered = Completer<void>(), release = Completer<void>();
      // Exercise the real module handler through the real registry/receipt
      // path, pausing only its ModuleToolContext.runtime future.
      current.tools.register(providerId: 'prototype',
        descriptor: ToolDescriptor(toolId: 'prototype.barrier_detail',
            moduleId: 'prototype', effect: ToolEffect.read, description: '测试屏障',
            parameterSchema: const {
              'type': 'object',
              'properties': {'page_id': {'type': 'string'}},
              'required': ['page_id'],
              'additionalProperties': false,
            }),
        supportedScopes: {AssistantScopeKind.selectedObjects}, dataModuleIds: {'prototype'},
        handler: (call) => captured.handlers['page_detail']!(
            _ReadBarrier(call, runtime, entered, release)),
      );
      final pending = current.tools.invoke(ToolCallRequest(
        invocationId: 'paused-$changed', toolId: 'prototype.barrier_detail',
        parameters: {'page_id': version.pageId}, scope: selection,
      ));
      try {
        await entered.future.timeout(const Duration(seconds: 5));
        await runtime.store.database.write((db) {
          switch (changed) {
            case 'page':
              db.execute('DELETE FROM prototype_feedback WHERE page_id=?', [version.pageId]);
              db.execute('DELETE FROM prototype_versions WHERE page_id=?', [version.pageId]);
              db.execute('DELETE FROM prototype_pages WHERE id=?', [version.pageId]);
            case 'version':
              db.execute('UPDATE prototype_versions SET digest=? WHERE id=?', ['changed', version.id]);
            case 'feedback':
              db.execute('UPDATE prototype_feedback SET body=? WHERE id=?', ['新正文', feedback.id]);
            case 'feedback-owner':
              db.execute('INSERT INTO prototype_pages VALUES(?,?,?)',
                  ['other-page', '另页', DateTime.now().toUtc().toIso8601String()]);
              db.execute('UPDATE prototype_feedback SET page_id=? WHERE id=?', ['other-page', feedback.id]);
          }
        });
      } finally {
        release.complete();
      }
      final result = await pending;
      expect(result.status, ToolCallStatus.failed);
      expect(result.objectRefs, isEmpty);
      expect(result.data, isEmpty);
      expect(current.tools.receiptFor('paused-$changed')!.state, 'failed');
      if (changed == 'feedback') {
        final fresh = (await current.scopeResolver.resolve(AssistantScope.selectedObjects([
          ObjectRef(moduleId: 'prototype', objectType: 'feedback', objectId: feedback.id,
              nativeProjectId: version.pageId),
        ]))).objects.single;
        final freshResult = await current.tools.invoke(ToolCallRequest(
          invocationId: 'fresh-$changed', toolId: 'prototype.page_detail',
          parameters: {'page_id': version.pageId}, scope: AssistantScope.selectedObjects([
            selection.objects[0], selection.objects[1], fresh,
          ]),
        ));
        expect(freshResult.status, ToolCallStatus.succeeded);
        expect((freshResult.data['feedback'] as List).single['text'], '新正文');
        expect(fresh.contentDigest, isNot(selection.objects.last.contentDigest));
      }
    });
  }
}
