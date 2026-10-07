import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/host_tool_registrar.dart';
import 'package:muyon/app/module_host.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/fake_v2_module.dart';

class _Link implements ModuleLink {
  _Link(this.status);
  ModuleStatus status;
  int activations = 0;
  final ModuleRuntime runtimeValue = FakeRuntime(_resources);
  @override
  Future<ModuleState> activate(String moduleId) async {
    activations++;
    return ModuleState(status, status == ModuleStatus.ready ? null : 'down');
  }

  @override
  T? runtime<T extends ModuleRuntime>(String moduleId) {
    final value = runtimeValue;
    return value is T ? value : null;
  }
}

final _resources = ModuleResources(
  database: ManagedConnection(sqlite3.openInMemory()),
  files: _NoFiles(),
  capabilities: CapabilityRegistry().forModule('m', allowed: {}),
);

class _NoFiles implements ModuleFiles {
  @override
  String get rootPath => '/nowhere';
  @override
  Future<SelectedInput> freeze(SelectedInput input) async => input;
}

const _item = ObjectRef(
  moduleId: 'notes',
  objectType: 'note',
  objectId: 'n1',
  nativeProjectId: 'p1',
  revisionRef: '1',
);

void main() {
  late ManagedConnection db;
  late ToolRegistry registry;
  late List<ObjectRef> visible;
  late _Link link;

  setUp(() {
    db = ManagedConnection(sqlite3.openInMemory());
    installToolRegistrySchema(db.raw);
    visible = [_item];
    link = _Link(ModuleStatus.ready);
    registry = ToolRegistry(
      database: db,
      resolveScope: (scope) async =>
          ResolvedAssistantScope(requested: scope, objects: visible),
    );
  });
  tearDown(() => db.close());

  HostToolRegistrar registrar(
    String id, {
    NetworkPolicy network = NetworkPolicy.none,
    List<String> requires = const [],
  }) => HostToolRegistrar(
    id,
    registry,
    ModuleManifest(
      id: id,
      apiVersion: 2,
      network: network,
      requiredDependencies: requires,
    ),
    link,
  );

  ToolSpec spec(String name) =>
      ToolSpec(name: name, description: '读取一条测试记录，仅用于测试，不改动任何数据。');
  WriteToolSpec writeSpec(String name) => WriteToolSpec(
    name: name,
    description: '写入一条测试记录，仅用于测试，会修改数据。',
    parameterSchema: {
      'type': 'object',
      'properties': {
        'title': {'type': 'string'},
      },
      'required': ['title'],
      'additionalProperties': false,
    },
    targetTypes: {'note'},
  );
  ToolCallResult ok({List<ObjectRef> refs = const []}) => ToolCallResult(
    status: ToolCallStatus.succeeded,
    summary: 'done',
    objectRefs: refs,
  );

  group('identity and effect come from the host', () {
    test('ids, provider, effect and default scopes', () {
      final r = registrar('notes')
        ..read(spec('list'), (_) async => ok())
        ..write(writeSpec('add'), (_) async => ok());
      final read = registry.inspect('notes.list')!;
      expect(read.providerId, 'notes');
      expect(read.descriptor.moduleId, 'notes');
      expect(read.accessLevel, ToolAccessLevel.read);
      expect(read.descriptor.modelSelectable, isTrue);
      final write = registry.inspect('notes.add')!;
      expect(write.accessLevel, ToolAccessLevel.write);
      expect(r.registeredToolIds, ['notes.list', 'notes.add']);
    });

    test(
      'a read tool serves all scopes, a write tool only selected objects',
      () async {
        registrar('notes')
          ..read(spec('list'), (_) async => ok())
          ..write(writeSpec('add'), (_) async => ok());
        for (final scope in [
          const AssistantScope.global(),
          AssistantScope.workspace('w'),
          AssistantScope.selectedObjects([_item]),
        ]) {
          final prepared = await registry.prepare(
            ToolCallRequest(
              invocationId: 'r-${scope.kind.name}',
              toolId: 'notes.list',
              scope: scope,
            ),
          );
          expect(prepared.request.scope.kind, scope.kind);
        }
        await expectLater(
          registry.prepare(
            ToolCallRequest(
              invocationId: 'w1',
              toolId: 'notes.add',
              scope: const AssistantScope.global(),
              parameters: {'title': 'x'},
            ),
          ),
          throwsA(
            isA<ToolPlatformException>().having(
              (e) => e.code,
              'code',
              'scope_mismatch',
            ),
          ),
        );
      },
    );

    test('data modules are the module and its required dependencies', () async {
      visible = [
        _item,
        const ObjectRef(moduleId: 'dep', objectType: 't', objectId: '1'),
        const ObjectRef(moduleId: 'stranger', objectType: 't', objectId: '1'),
      ];
      registrar(
        'notes',
        requires: ['dep'],
      ).read(spec('list'), (ctx) async => ok());
      final prepared = await registry.prepare(
        ToolCallRequest(
          invocationId: 'g',
          toolId: 'notes.list',
          scope: const AssistantScope.global(),
        ),
      );
      expect(prepared.resolvedScope.moduleIds, {'notes', 'dep'});
    });

    test(
      'a write tool needs a one-use approval; the module cannot skip it',
      () async {
        var ran = 0;
        registrar('notes').write(writeSpec('add'), (_) async {
          ran++;
          return ok(refs: [_item]);
        });
        final request = ToolCallRequest(
          invocationId: 'add-1',
          toolId: 'notes.add',
          scope: AssistantScope.selectedObjects([_item]),
          parameters: {'title': 'x'},
        );
        await expectLater(
          registry.invoke(request),
          throwsA(
            isA<ToolPlatformException>().having(
              (e) => e.code,
              'code',
              'approval_required',
            ),
          ),
        );
        expect(ran, 0);
        final prepared = await registry.prepare(request);
        final grant = await registry.approve(prepared);
        final result = await registry.invoke(request.withApproval(grant));
        expect(result.status, ToolCallStatus.succeeded);
        expect(ran, 1);
        // The approval is consumed: replaying under a new id is refused.
        await expectLater(
          registry.invoke(
            ToolCallRequest(
              invocationId: 'add-2',
              toolId: 'notes.add',
              scope: AssistantScope.selectedObjects([_item]),
              parameters: {'title': 'x'},
              approvalId: grant,
            ),
          ),
          throwsA(isA<ToolPlatformException>()),
        );
        expect(ran, 1);
      },
    );

    test(
      'a write result outside the module or the selected project is refused',
      () async {
        registrar('notes').write(writeSpec('add'), (ctx) async {
          final title = ctx.call.request.parameters['title'];
          return ok(
            refs: [
              ObjectRef(
                moduleId: title == 'other-module' ? 'stranger' : 'notes',
                objectType: 'note',
                objectId: 'n2',
                nativeProjectId: title == 'other-project' ? 'p9' : 'p1',
              ),
            ],
          );
        });
        Future<ToolCallResult> write(String title) async {
          final request = ToolCallRequest(
            invocationId: 'w-$title',
            toolId: 'notes.add',
            scope: AssistantScope.selectedObjects([_item]),
            parameters: {'title': title},
          );
          final grant = await registry.approve(await registry.prepare(request));
          return registry.invoke(request.withApproval(grant));
        }

        // A new object in the selected project, of this module, is fine.
        expect((await write('inside')).status, ToolCallStatus.succeeded);
        expect(
          (await write('other-module')).summary,
          contains('result_scope_mismatch'),
        );
        expect(
          (await write('other-project')).summary,
          contains('result_scope_mismatch'),
        );
      },
    );
  });

  group('registration rules', () {
    test('names are validated, unique, and cannot collide once encoded', () {
      final notes = registrar('notes');
      expect(
        () => notes.read(spec('Bad Name'), (_) async => ok()),
        throwsArgumentError,
      );
      expect(
        () => notes.read(spec('9lives'), (_) async => ok()),
        throwsArgumentError,
      );
      notes.read(spec('list'), (_) async => ok());
      expect(
        () => notes.read(spec('list'), (_) async => ok()),
        throwsA(isA<ToolPlatformException>()),
      );
      // 'a.b__c' and 'a__b.c' would both be the function name a__b__c.
      registrar('a').read(spec('b__c'), (_) async => ok());
      expect(
        () => registrar('a__b').read(spec('c'), (_) async => ok()),
        throwsArgumentError,
      );
    });

    test('registerTools is the only time: a sealed registrar refuses', () {
      final r = registrar('notes')..read(spec('list'), (_) async => ok());
      r.seal();
      expect(() => r.read(spec('more'), (_) async => ok()), throwsStateError);
      expect(
        () => r.write(writeSpec('more'), (_) async => ok()),
        throwsStateError,
      );
      expect(
        () => r.channel(
          ChannelSpec(
            name: 'c',
            description: 'd',
            effect: ToolEffect.network,
            destination: const DestinationRule(publicWeb: true),
            parameterSchema: const {
              'type': 'object',
              'properties': <String, Object?>{},
            },
          ),
        ),
        throwsStateError,
      );
      expect(registry.inspect('notes.more'), isNull);
    });

    test(
      'an unavailable module answers with a failed result, not a handler call',
      () async {
        link.status = ModuleStatus.failed;
        var ran = 0;
        registrar('notes').read(spec('list'), (_) async {
          ran++;
          return ok();
        });
        final result = await registry.invoke(
          ToolCallRequest(
            invocationId: 'down',
            toolId: 'notes.list',
            scope: const AssistantScope.global(),
          ),
        );
        expect(result.status, ToolCallStatus.failed);
        expect(result.summary, contains('down'));
        expect(ran, 0);
        expect(link.activations, 1);
      },
    );

    test('a handler reaches its runtime through the context', () async {
      Object? seen;
      registrar('notes').read(spec('list'), (ctx) async {
        seen = await ctx.runtime<FakeRuntime>();
        return ok();
      });
      await registry.invoke(
        ToolCallRequest(
          invocationId: 'rt',
          toolId: 'notes.list',
          scope: const AssistantScope.global(),
        ),
      );
      expect(seen, same(link.runtimeValue));
    });
  });

  group('external tools and channels', () {
    ExternalToolSpec external({DestinationRule? rule}) => ExternalToolSpec(
      name: 'send',
      description: '联网发送测试内容，仅用于测试，会发送数据。',
      effect: ToolEffect.network,
      destination:
          rule ?? const DestinationRule(fixedHosts: {'api.example.com'}),
      parameterSchema: {
        'type': 'object',
        'properties': {
          'body': {'type': 'string'},
        },
        'additionalProperties': false,
      },
    );

    test(
      'a rule outside the manifest policy, or an empty one, cannot register',
      () {
        const policy = NetworkPolicy(fixedHosts: {'api.example.com'});
        expect(
          () => registrar('notes').external(external(), (_) async => ok()),
          throwsArgumentError,
          reason: 'the module declared no network at all',
        );
        expect(
          () => registrar('notes', network: policy).external(
            external(
              rule: const DestinationRule(fixedHosts: {'evil.example.org'}),
            ),
            (_) async => ok(),
          ),
          throwsArgumentError,
        );
        expect(
          () => registrar('notes', network: policy).external(
            external(rule: const DestinationRule(publicWeb: true)),
            (_) async => ok(),
          ),
          throwsArgumentError,
        );
        expect(
          () => registrar('notes', network: policy).external(
            external(rule: const DestinationRule()),
            (_) async => ok(),
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'a destination outside the rule is blocked before an approval exists',
      () async {
        var ran = 0;
        registrar(
          'notes',
          network: const NetworkPolicy(fixedHosts: {'api.example.com'}),
        ).external(external(), (_) async {
          ran++;
          return ok();
        });
        ToolCallRequest request(String destination) => ToolCallRequest(
          invocationId: 'x-${destination.hashCode}',
          toolId: 'notes.send',
          scope: AssistantScope.selectedObjects([_item]),
          parameters: {'body': 'hi'},
          destination: destination,
        );
        expect(
          registry.inspect('notes.send')!.accessLevel,
          ToolAccessLevel.external,
        );
        for (final bad in [
          'https://evil.example.org/x',
          'not a url',
          'https:///x',
        ]) {
          await expectLater(
            registry.prepare(request(bad)),
            throwsA(
              isA<ToolPlatformException>().having(
                (e) => e.code,
                'code',
                'destination_blocked',
              ),
            ),
            reason: bad,
          );
        }
        final prepared = await registry.prepare(
          request('https://api.example.com/v1'),
        );
        expect(prepared.request.destination, 'https://api.example.com/v1');
        expect(ran, 0);
      },
    );

    test('public web means https only, and still within the manifest', () {
      const open = DestinationRule(publicWeb: true);
      const policy = NetworkPolicy(publicWeb: true);
      expect(
        destinationAllowed('https://a.example.com/x', open, policy),
        isTrue,
      );
      expect(
        destinationAllowed('http://a.example.com/x', open, policy),
        isFalse,
      );
      expect(
        destinationAllowed('https://a.example.com/x', open, NetworkPolicy.none),
        isFalse,
      );
    });

    test(
      'a channel runs the effect only after review and a host approval',
      () async {
        final channel =
            registrar(
              'notes',
              network: const NetworkPolicy(publicWeb: true),
            ).channel(
              ChannelSpec(
                name: 'web',
                description: '网页读取通道',
                effect: ToolEffect.network,
                destination: const DestinationRule(publicWeb: true),
                parameterSchema: const {
                  'type': 'object',
                  'properties': {
                    'url': {'type': 'string'},
                  },
                  'additionalProperties': false,
                },
              ),
            );
        expect(
          registry.inspect('notes.web')!.descriptor.modelSelectable,
          isFalse,
        );
        var effects = 0;
        Future<String> run(String url, {ChannelReview? review}) => channel.run(
          ChannelRequest(destination: url, parameters: {'url': url}),
          (guard) async {
            guard();
            effects++;
            return 'fetched';
          },
          cancellation: ToolCancellationToken(),
          review: review,
        );
        // No review, a denied review, a blocked destination: no effect.
        await expectLater(run('https://a.example.com/'), throwsStateError);
        await expectLater(
          run('https://a.example.com/', review: (_) async => false),
          throwsStateError,
        );
        await expectLater(
          run('http://a.example.com/', review: (_) async => true),
          throwsA(isA<ToolPlatformException>()),
        );
        expect(effects, 0);
        ChannelPreview? shown;
        final value = await run(
          'https://a.example.com/',
          review: (preview) async {
            shown = preview;
            expect(effects, 0);
            return true;
          },
        );
        expect(value, 'fetched');
        expect(effects, 1);
        expect(shown!.destination, 'https://a.example.com/');
        expect(shown!.parameterDigest, isNotEmpty);
        // A receipt exists for the call; the module wrote none of it.
        expect(registry.receiptFor(shown!.invocationId)!.succeeded, isTrue);
      },
    );
  });

  test('the registrar exposes nothing that approves, records or sends', () {
    final r = registrar('notes') as dynamic;
    final forbidden = <String, void Function()>{
      'approve': () => r.approve,
      'invoke': () => r.invoke,
      'prepare': () => r.prepare,
      'register': () => r.register,
      'setAvailability': () => r.setAvailability,
      'receiptFor': () => r.receiptFor,
      'history': () => r.history,
      'database': () => r.database,
      'registry': () => r.registry,
      'tools': () => r.tools,
      'ledger': () => r.ledger,
      'outbound': () => r.outbound,
      'approvals': () => r.approvals,
      'receipts': () => r.receipts,
    };
    for (final entry in forbidden.entries) {
      expect(
        entry.value,
        throwsA(isA<NoSuchMethodError>()),
        reason: 'HostToolRegistrar must not have `${entry.key}`',
      );
    }
  });
}
