import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/scope_resolver.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/fake_v2_module.dart';

/// The v2 path of the single scope resolver: candidates from the host catalog,
/// truth from the module's own `resolve`, no workspace binding needed.
void main() {
  late Directory root;
  late MuyonHost host;
  late ResolvableRuntime runtime;
  late FakeV2Module module;

  ObjectRef ref(
    String type,
    String id, {
    String project = 'p1',
    String rev = '1',
    String digest = 'd1',
  }) => ObjectRef(
    moduleId: 'things',
    objectType: type,
    objectId: id,
    nativeProjectId: project,
    revisionRef: rev,
    contentDigest: digest,
  );

  Future<void> catalog(String type, String id, {String project = 'p1'}) =>
      host.workspaces.database.write(
        (db) => db.execute(
          'INSERT OR REPLACE INTO object_catalog VALUES(?,?,?,?,?)',
          ['things', project, type, id, id],
        ),
      );

  Future<void> open({bool lie = false, bool resolvable = true}) async {
    runtime = ResolvableRuntime({
      'item/a': ref('item', 'a'),
      'item/b': ref('item', 'b', rev: '7', digest: 'd7'),
      'card/c': ref('card', 'c'),
    }, lie: lie);
    module = FakeV2Module(
      'things',
      ontology: ModuleOntology(
        objectTypes: [fakeType('item'), fakeType('card', inGlobalScope: false)],
      ),
      runtimeFactory: (r) => resolvable ? runtime : FakeRuntime(r),
    );
    host = await MuyonHost.open(root.path, modules: [module]);
  }

  setUp(() => root = Directory.systemTemp.createTempSync('scope-v2-'));
  tearDown(() async {
    await host.close();
    root.deleteSync(recursive: true);
  });

  Iterable<ObjectRef> mine(ResolvedAssistantScope s) =>
      s.objects.where((r) => r.moduleId == 'things');

  test('global scope lists catalog candidates the module still resolves, canonically', () async {
    await open();
    await catalog('item', 'a');
    await catalog('item', 'b');
    await catalog('item', 'gone'); // catalog lag: deleted in the module
    await catalog('card', 'c'); // a type that is not in global scope
    final scope = await host.scopeResolver.resolve(
      const AssistantScope.global(),
    );
    expect(mine(scope).toList(), [
      ref('item', 'a'),
      ref('item', 'b', rev: '7', digest: 'd7'),
    ]);
    expect(
      module.activations,
      1,
      reason: 'resolving a scope activates the module',
    );
    expect(runtime.sessionsOpened, runtime.sessionsDisposed);
  });

  test(
    'a selection is resolved by the module, even for types the catalog skips',
    () async {
      await open();
      final card = ref('card', 'c');
      final scope = await host.scopeResolver.resolve(
        AssistantScope.selectedObjects([card]),
      );
      expect(scope.objects, [card]);
      // An unpinned request gets the current canonical ref back.
      final unpinned = await host.scopeResolver.resolve(
        AssistantScope.selectedObjects([
          const ObjectRef(
            moduleId: 'things',
            objectType: 'item',
            objectId: 'b',
            nativeProjectId: 'p1',
          ),
        ]),
      );
      expect(unpinned.objects.single, ref('item', 'b', rev: '7', digest: 'd7'));
    },
  );

  test(
    'a stale pin, a missing object or a module that lies is refused',
    () async {
      await open();
      for (final bad in [
        ref('item', 'b', rev: '1', digest: 'd7'),
        ref('item', 'b', rev: '7', digest: 'old'),
        ref('item', 'ghost'),
      ]) {
        await expectLater(
          host.scopeResolver.resolve(AssistantScope.selectedObjects([bad])),
          throwsStateError,
          reason: '$bad',
        );
      }
      await host.close();
      root.deleteSync(recursive: true);
      root.createSync();
      await open(lie: true);
      // Unpinned, so only the identity check can catch the substitution.
      await expectLater(
        host.scopeResolver.resolve(
          AssistantScope.selectedObjects([
            const ObjectRef(
              moduleId: 'things',
              objectType: 'item',
              objectId: 'a',
              nativeProjectId: 'p1',
            ),
          ]),
        ),
        throwsStateError,
      );
    },
  );

  test('a workspace sees only what its binding covers', () async {
    await open();
    await catalog('item', 'a');
    await catalog('item', 'b', project: 'p2');
    runtime.objects['item/b'] = ref(
      'item',
      'b',
      project: 'p2',
      rev: '7',
      digest: 'd7',
    );
    final workspace = await host.workspaces.create('W');
    await host.workspaces.bind(
      WorkspaceBinding(
        workspaceId: workspace.id,
        moduleId: 'things',
        nativeProjectId: 'p1',
      ),
    );
    final scope = await host.scopeResolver.resolve(
      AssistantScope.workspace(workspace.id),
    );
    expect(mine(scope).map((r) => r.objectId), ['a']);
    await expectLater(
      host.scopeResolver.resolve(
        AssistantScope.selectedObjects([
          runtime.objects['item/b']!,
        ], workspaceId: workspace.id),
      ),
      throwsStateError,
    );
  });

  test(
    'a module that cannot resolve without a binding contributes nothing',
    () async {
      await open(resolvable: false);
      await catalog('item', 'a');
      final scope = await host.scopeResolver.resolve(
        const AssistantScope.global(),
      );
      expect(mine(scope), isEmpty);
    },
  );

  test(
    'a module that fails to activate drops out; the rest still resolve',
    () async {
      await open();
      module.failActivation = true;
      await catalog('item', 'a');
      final scope = await host.scopeResolver.resolve(
        const AssistantScope.global(),
      );
      expect(mine(scope), isEmpty);
      expect(host.modules.error('things'), contains('boom'));
    },
  );

  test('scope identity is module, type, project, id', () {
    expect(
      scopeIdentity(ref('item', 'a')),
      scopeIdentity(ref('item', 'a', rev: '9')),
    );
    expect(
      scopeIdentity(ref('item', 'a')),
      isNot(scopeIdentity(ref('item', 'a', project: 'p2'))),
    );
  });
}
