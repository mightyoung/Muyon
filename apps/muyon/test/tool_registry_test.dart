import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late ManagedConnection db;
  late ToolRegistry registry;
  late DateTime now;
  late List<ObjectRef> visible;
  var calls = 0;
  const item = ObjectRef(
    moduleId: 'research',
    objectType: 'document',
    objectId: 'one',
    nativeProjectId: 'p',
    revisionRef: 'v1',
    contentDigest: 'digest',
  );
  const schema = <String, Object?>{
    'type': 'object',
    'properties': {
      'count': {'type': 'integer', 'minimum': 1, 'maximum': 5},
      'label': {
        'type': 'string',
        'enum': ['ok', 'other'],
      },
    },
    'required': ['count'],
    'additionalProperties': false,
  };
  Future<ResolvedAssistantScope> resolve(AssistantScope scope) async {
    if (scope.kind == AssistantScopeKind.workspace &&
        scope.workspaceId != 'w') {
      throw StateError('Unknown workspace');
    }
    return ResolvedAssistantScope(requested: scope, objects: visible);
  }

  ToolCallRequest request({
    String id = 'call',
    String tool = 'test',
    int count = 1,
    String? destination,
    String? approval,
    String? key,
    AssistantScope? scope,
  }) => ToolCallRequest(
    invocationId: id,
    toolId: tool,
    scope: scope ?? const AssistantScope.global(),
    parameters: {'count': count},
    destination: destination,
    approvalId: approval,
    idempotencyKey: key,
  );
  void register({
    ToolEffect effect = ToolEffect.read,
    Future<ToolCallResult> Function(ToolCallContext)? handler,
    Future<void> Function(ResolvedAssistantScope, ToolCallResult)?
    validateResult,
  }) {
    registry.register(
      providerId: 'shared.documents',
      descriptor: ToolDescriptor(
        toolId: 'test',
        moduleId: 'platform',
        effect: effect,
        parameterSchema: schema,
        supportsCancel: true,
      ),
      dataModuleIds: {'research'},
      validateResult: validateResult,
      handler:
          handler ??
          (context) async {
            calls++;
            return ToolCallResult(
              status: ToolCallStatus.succeeded,
              summary: 'done',
              objectRefs: context.resolvedScope.objects,
            );
          },
    );
  }

  setUp(() {
    db = ManagedConnection(sqlite3.openInMemory());
    installToolRegistrySchema(db.raw);
    db.raw.execute('CREATE TABLE domain_writes(value TEXT)');
    now = DateTime.utc(2026, 10, 4);
    visible = [item];
    calls = 0;
    registry = ToolRegistry(
      database: db,
      resolveScope: resolve,
      clock: () => now,
    );
  });
  tearDown(() async {
    await db.close();
  });

  test('real provider discovery global explicit refs schema validation and result refs', () async {
    register();
    expect(registry.list().single.providerId, 'shared.documents');
    expect(registry.inspect('test')!.accessLevel, ToolAccessLevel.read);
    final result = await registry.invoke(request());
    expect(result.objectRefs, [item]);
    expect(result.executionId, 'call');
    expect(calls, 1);
    await expectLater(
      registry.invoke(request(id: 'bad', count: 0)),
      throwsA(
        isA<ToolPlatformException>().having(
          (e) => e.code,
          'code',
          'invalid_parameters',
        ),
      ),
    );
    await expectLater(
      registry.invoke(
        ToolCallRequest(
          invocationId: 'injection',
          toolId: 'test',
          scope: const AssistantScope.global(),
          parameters: {'count': 1, 'userConfirmed': true},
        ),
      ),
      throwsA(isA<ToolPlatformException>()),
    );
    expect(calls, 1);
    registry.setAvailability(
      'test',
      available: false,
      reason: 'provider offline',
    );
    expect(registry.list().single.unavailableReason, 'provider offline');
    await expectLater(
      registry.invoke(request(id: 'off')),
      throwsA(isA<ToolPlatformException>()),
    );
  });
  test(
    'global module narrowing and selected object expansion protection',
    () async {
      register();
      visible = [
        item,
        const ObjectRef(
          moduleId: 'inquiry',
          objectType: 'supplier',
          objectId: 'supplier',
        ),
      ];
      expect((await registry.invoke(request())).objectRefs, [item]);
      await expectLater(
        registry.invoke(
          request(
            id: 'selected',
            scope: AssistantScope.selectedObjects([item]),
          ),
        ),
        throwsArgumentError,
      );
    },
  );
  test('unsupported JSON schema cannot silently disable validation', () {
    expect(
      () => registry.register(
        providerId: 'p',
        descriptor: ToolDescriptor(
          toolId: 'unknown',
          moduleId: 'm',
          effect: ToolEffect.read,
          parameterSchema: {'type': 'object', 'oneOf': []},
        ),
        handler: (_) async =>
            ToolCallResult(status: ToolCallStatus.succeeded, summary: 'bad'),
      ),
      throwsA(isA<ToolPlatformException>()),
    );
  });
  test(
    'write requires host approval exact params and one atomic consumption',
    () async {
      register(effect: ToolEffect.write);
      await expectLater(
        registry.invoke(request(approval: 'model-says-yes')),
        throwsA(
          isA<ToolPlatformException>().having(
            (e) => e.code,
            'code',
            'approval_required',
          ),
        ),
      );
      final prepared = await registry.prepare(request());
      final approval = await registry.approve(prepared);
      await expectLater(
        registry.invoke(request(count: 2, approval: approval)),
        throwsA(isA<ToolPlatformException>()),
      );
      expect(calls, 0);
      final result = await registry.invoke(request(approval: approval));
      expect(result.status, ToolCallStatus.succeeded);
      expect(
        db.raw
            .select('SELECT state,consumed_at FROM tool_approvals')
            .single['state'],
        'consumed',
      );
      expect(
        db.raw
            .select('SELECT state,consumed_at FROM tool_approvals')
            .single['consumed_at'],
        isNotNull,
      );
      // Same identity returns receipt, never repeats side effects or consumes again.
      expect(
        (await registry.invoke(request())).status,
        ToolCallStatus.succeeded,
      );
      expect(calls, 1);
      await expectLater(
        registry.invoke(request(id: 'new', approval: approval)),
        throwsA(isA<ToolPlatformException>()),
      );
    },
  );
  test('external approval binds destination and expiry', () async {
    register(effect: ToolEffect.network);
    await expectLater(
      registry.prepare(request()),
      throwsA(isA<ToolPlatformException>()),
    );
    final original = request(destination: 'https://chosen.example/v1');
    final approval = await registry.approve(
      await registry.prepare(original),
      ttl: const Duration(seconds: 1),
    );
    await expectLater(
      registry.invoke(
        request(destination: 'https://other.example', approval: approval),
      ),
      throwsA(isA<ToolPlatformException>()),
    );
    now = now.add(const Duration(seconds: 2));
    await expectLater(
      registry.invoke(original.withApproval(approval)),
      throwsA(isA<ToolPlatformException>()),
    );
    expect(calls, 0);
  });
  test('changed object revision invalidates existing approval', () async {
    register(effect: ToolEffect.write);
    final approval = await registry.approve(await registry.prepare(request()));
    visible = [
      const ObjectRef(
        moduleId: 'research',
        objectType: 'document',
        objectId: 'one',
        nativeProjectId: 'p',
        revisionRef: 'v2',
        contentDigest: 'edited',
      ),
    ];
    await expectLater(
      registry.invoke(request(approval: approval)),
      throwsA(isA<ToolPlatformException>()),
    );
    expect(calls, 0);
  });
  test('new registry rejects old grants and durable receipt prevents replay after restart', () async {
    register(effect: ToolEffect.write);
    final oldGrant = await registry.approve(await registry.prepare(request()));
    registry = ToolRegistry(
      database: db,
      resolveScope: resolve,
      clock: () => now,
    );
    register(effect: ToolEffect.write);
    await expectLater(
      registry.invoke(request(approval: oldGrant)),
      throwsA(isA<ToolPlatformException>()),
    );
    final grant = await registry.approve(await registry.prepare(request()));
    await registry.invoke(request(approval: grant));
    registry = ToolRegistry(
      database: db,
      resolveScope: resolve,
      clock: () => now,
    );
    register(effect: ToolEffect.write);
    expect((await registry.invoke(request())).status, ToolCallStatus.succeeded);
    expect(calls, 1);
  });
  test('pending durable receipt is interrupted instead of repeated', () async {
    register(effect: ToolEffect.write);
    final prepared = await registry.prepare(request());
    db.raw.execute(
      'INSERT INTO tool_invocation_receipts VALUES(?,?,?,?,?,NULL)',
      ['call', 'call', prepared.identityDigest, 'test', 'running'],
    );
    final result = await registry.invoke(request());
    expect(result.status, ToolCallStatus.interrupted);
    expect(calls, 0);
  });
  test('concurrent identical invocations execute provider once', () async {
    final started = Completer<void>(), release = Completer<void>();
    register(
      handler: (context) async {
        calls++;
        started.complete();
        await release.future;
        return ToolCallResult(
          status: ToolCallStatus.succeeded,
          summary: 'once',
        );
      },
    );
    final first = registry.invoke(request());
    await started.future;
    final second = registry.invoke(request());
    release.complete();
    expect(
      (await Future.wait([first, second]))
          .every((r) => r.status == ToolCallStatus.succeeded),
      isTrue,
    );
    expect(calls, 1);
    await expectLater(
      registry.invoke(request(count: 2)),
      throwsA(isA<ToolPlatformException>()),
    );
  });
  test('cancellation before domain write blocks late mutation and discards artifacts', () async {
    final started = Completer<void>(), release = Completer<void>();
    register(
      effect: ToolEffect.write,
      handler: (context) async {
        started.complete();
        await release.future;
        await context.write(
          db,
          (database) =>
              database.execute("INSERT INTO domain_writes VALUES('bad')"),
        );
        return ToolCallResult(
          status: ToolCallStatus.succeeded,
          summary: 'late',
        );
      },
    );
    final approved = request().withApproval(
      await registry.approve(await registry.prepare(request())),
    );
    final cancellation = ToolCancellationToken();
    final call = registry.invoke(approved, cancellation: cancellation);
    await started.future;
    cancellation.cancel();
    release.complete();
    expect((await call).status, ToolCallStatus.cancelled);
    expect(db.raw.select('SELECT * FROM domain_writes'), isEmpty);
  });
  test(
    'out of scope result references are rejected rather than exposed',
    () async {
      register(
        handler: (_) async => ToolCallResult(
          status: ToolCallStatus.succeeded,
          summary: 'leak',
          objectRefs: [
            const ObjectRef(
              moduleId: 'research',
              objectType: 'document',
              objectId: 'secret',
              nativeProjectId: 'other',
            ),
          ],
        ),
      );
      final result = await registry.invoke(request());
      expect(result.status, ToolCallStatus.failed);
      expect(result.objectRefs, isEmpty);
    },
  );
  test(
    'approval expiry during provider preparation prevents domain write',
    () async {
      register(
        effect: ToolEffect.write,
        handler: (context) async {
          now = now.add(const Duration(minutes: 3));
          await context.write(
            db,
            (database) =>
                database.execute("INSERT INTO domain_writes VALUES('expired')"),
          );
          return ToolCallResult(
            status: ToolCallStatus.succeeded,
            summary: 'unexpected',
          );
        },
      );
      final approved = request().withApproval(
        await registry.approve(await registry.prepare(request())),
      );
      final result = await registry.invoke(approved);
      expect(result.status, ToolCallStatus.failed);
      expect(result.summary, contains('approval_expired'));
      expect(db.raw.select('SELECT * FROM domain_writes'), isEmpty);
    },
  );
}
