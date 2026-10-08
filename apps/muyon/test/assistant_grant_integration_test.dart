import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/host_ui_grant_authority.dart';
import 'package:muyon/platform/grants/grants.dart';
import 'package:muyon/platform/grants/tool_grant_context.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory root;
  late StorageManager storage;
  late ManagedConnection db;
  late GrantStore grants;
  late ToolRegistry registry;
  late DateTime now;
  late ToolGrantContext context;
  late List<ObjectRef> objects;
  var calls = 0;
  const original = ObjectRef(
    moduleId: 'research',
    objectType: 'doc',
    objectId: 'd',
    nativeProjectId: 'p',
    revisionRef: '1',
    contentDigest: 'one',
  );
  const changed = ObjectRef(
    moduleId: 'research',
    objectType: 'doc',
    objectId: 'd',
    nativeProjectId: 'p',
    revisionRef: '2',
    contentDigest: 'two',
  );
  ToolGrantContext facts({
    bool tainted = false,
    String task = 'task',
    String conversation = 'conversation',
    Set<String> modules = const {'research'},
  }) => ToolGrantContext(
    taskId: task,
    conversationId: conversation,
    taskTainted: tainted,
    scopeRevision: 'host-maintained',
    allowedModuleIds: modules,
  );
  ToolCallRequest request(
    String id, {
    String tool = 'write',
    String? destination,
    AssistantScope? scope,
  }) => ToolCallRequest(
    invocationId: id,
    toolId: tool,
    scope: scope ?? AssistantScope.workspace('w'),
    destination: destination,
  );
  void register(
    String id,
    ToolEffect effect, {
    Future<ToolCallResult> Function(ToolCallContext)? handler,
  }) {
    registry.register(
      providerId: 'host.test',
      descriptor: ToolDescriptor(
        toolId: id,
        moduleId: 'platform',
        effect: effect,
        parameterSchema: const {
          'type': 'object',
          'properties': <String, Object?>{},
          'additionalProperties': false,
        },
      ),
      handler:
          handler ??
          (call) async {
            call.checkAuthorization!();
            calls++;
            return ToolCallResult(
              status: ToolCallStatus.succeeded,
              summary: 'executed',
            );
          },
    );
  }

  Future<AssistantGrant> create(
    PreparedToolCall prepared, {
    GrantDuration duration = GrantDuration.once,
    DateTime? expiresAt,
    int? maxUses,
  }) {
    final bound = registry.authorizationRequest(prepared);
    return withConfirmedHostUiGrant(
      (token) => grants.create(
        token: token,
        draft: GrantDraft(
          category: bound.category.name,
          toolId: bound.toolId,
          scopeDigest: bound.scopeDigest,
          destination: bound.destination,
          duration: duration,
          taskId: bound.taskId,
          conversationId: bound.conversationId,
          expiresAt: expiresAt,
          maxUses: maxUses,
        ),
        now: now,
      ),
    );
  }

  Future<String> issue(PreparedToolCall prepared, AssistantGrant grant) async {
    final result = await registry.approveWithGrant(prepared, grantId: grant.id);
    expect(
      result,
      isNotNull,
      reason: 'matching host grant must issue an approval',
    );
    return result!;
  }

  int uses(AssistantGrant grant) =>
      grants.list().singleWhere((g) => g.id == grant.id).uses;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('auth-host-integration-');
    storage = StorageManager(root.path);
    db = await storage.open('muyon', WorkspaceRepository.schema);
    grants = GrantStore(db);
    db.raw.execute("INSERT INTO settings(key,value) VALUES('scope_epoch','0')");
    now = DateTime.utc(2026, 10, 8);
    context = facts();
    objects = [original];
    calls = 0;
    registry = ToolRegistry(
      database: db,
      grants: grants,
      grantContext: (_) => ToolGrantContext(
        taskId: context.taskId,
        conversationId: context.conversationId,
        taskTainted: context.taskTainted,
        allowedModuleIds: context.allowedModuleIds,
        scopeRevision:
            db.raw
                    .select(
                      "SELECT value FROM settings WHERE key='scope_epoch'",
                    )
                    .single['value']
                as String,
      ),
      clock: () => now,
      resolveScope: (scope) async =>
          ResolvedAssistantScope(requested: scope, objects: objects),
    );
    register('write', ToolEffect.write);
    register('external', ToolEffect.network);
    register('read', ToolEffect.read);
  });
  tearDown(() async {
    await registry.close();
    await storage.close();
    root.deleteSync(recursive: true);
  });

  test('one-use consumption audit issuance execution and replay are linked exactly once', () async {
    final call = request('one');
    final prepared = await registry.prepare(call);
    final grant = await create(prepared);
    final approval = await issue(prepared, grant);
    expect(uses(grant), 1);
    expect(grants.audit(grant.id).map((r) => r['action']), ['created', 'used']);
    expect(
      (await registry.invoke(call.withApproval(approval))).status,
      ToolCallStatus.succeeded,
    );
    expect(
      (await registry.invoke(call.withApproval(approval))).status,
      ToolCallStatus.succeeded,
    );
    expect(
      await registry.approveWithGrant(prepared, grantId: grant.id),
      approval,
    );
    expect(uses(grant), 1);
    expect(calls, 1);
    expect(
      db.raw
          .select('SELECT grant_id,authorization_source FROM tool_approvals')
          .single
          .values
          .toList(),
      [grant.id, 'grant'],
    );
    expect(
      db.raw
          .select(
            'SELECT grant_id,authorization_source FROM tool_invocation_receipts',
          )
          .single
          .values
          .toList(),
      [grant.id, 'grant'],
    );
  });
  test('competing last use issues only one distinct invocation', () async {
    final a = await registry.prepare(request('a'));
    final b = await registry.prepare(request('b'));
    final grant = await create(a);
    final results = await Future.wait([
      registry.approveWithGrant(a, grantId: grant.id),
      registry.approveWithGrant(b, grantId: grant.id),
    ]);
    expect(results.whereType<String>(), hasLength(1));
    expect(uses(grant), 1);
    expect(db.raw.select('SELECT * FROM tool_approvals'), hasLength(1));
  });
  test('approval insert failure rolls back use and audit', () async {
    final prepared = await registry.prepare(request('fault'));
    final grant = await create(prepared);
    db.raw.execute(
      "CREATE TEMP TRIGGER deny_approval BEFORE INSERT ON tool_approvals BEGIN SELECT RAISE(ABORT,'injected'); END",
    );
    await expectLater(
      registry.approveWithGrant(prepared, grantId: grant.id),
      throwsA(isA<SqliteException>()),
    );
    expect(uses(grant), 0);
    expect(grants.audit(grant.id).map((r) => r['action']), ['created']);
    expect(db.raw.select('SELECT * FROM tool_approvals'), isEmpty);
    expect(calls, 0);
  });
  for (final kind in [
    'revoked',
    'expired',
    'tainted',
    'task',
    'conversation',
    'modules',
    'workspace',
    'destination',
    'tool',
  ]) {
    test('$kind binding change denies issuance without consuming', () async {
      final prepared = await registry.prepare(
        request(
          'bind',
          tool: 'external',
          destination: 'https://same.test/a?key=sensitive',
        ),
      );
      final grant = await create(
        prepared,
        duration: GrantDuration.task,
        expiresAt: now.add(const Duration(minutes: 1)),
      );
      if (kind == 'revoked') await grants.revoke(grant.id, now: now);
      if (kind == 'expired') now = now.add(const Duration(minutes: 2));
      if (kind == 'tainted') context = facts(tainted: true);
      if (kind == 'task') context = facts(task: 'other');
      if (kind == 'conversation') context = facts(conversation: 'other');
      if (kind == 'modules') context = facts(modules: {'research', 'inquiry'});
      final candidate = kind == 'workspace'
          ? await registry.prepare(
              request(
                'bind',
                tool: 'external',
                destination: 'https://same.test/a?key=sensitive',
                scope: AssistantScope.workspace('other'),
              ),
            )
          : kind == 'destination'
          ? await registry.prepare(
              request(
                'bind',
                tool: 'external',
                destination: 'https://same.test/b?key=sensitive',
              ),
            )
          : kind == 'tool'
          ? await registry.prepare(request('bind', tool: 'write'))
          : prepared;
      expect(
        await registry.approveWithGrant(candidate, grantId: grant.id),
        isNull,
      );
      expect(uses(grant), 0);
      expect(db.raw.select('SELECT * FROM tool_approvals'), isEmpty);
      expect(calls, 0);
    });
  }
  for (final kind in ['revoked', 'expired', 'tainted', 'modules']) {
    test('$kind after issuance prevents actual effect', () async {
      final call = request('effect');
      final prepared = await registry.prepare(call);
      final grant = await create(
        prepared,
        expiresAt: now.add(const Duration(minutes: 1)),
      );
      final approval = await issue(prepared, grant);
      if (kind == 'revoked') await grants.revoke(grant.id, now: now);
      if (kind == 'expired') now = now.add(const Duration(minutes: 2));
      if (kind == 'tainted') context = facts(tainted: true);
      if (kind == 'modules') context = facts(modules: {'inquiry'});
      try {
        expect(
          (await registry.invoke(call.withApproval(approval))).status,
          isNot(ToolCallStatus.succeeded),
        );
      } on ToolPlatformException {
        /* rejection before receipt */
      }
      expect(calls, 0);
    });
  }
  test(
    'revision stable permission still invalidates exact approval preview',
    () async {
      final call = request('revision');
      final prepared = await registry.prepare(call);
      final grant = await create(prepared, duration: GrantDuration.always);
      final before = registry.authorizationRequest(prepared).scopeDigest;
      objects = [changed];
      final current = await registry.prepare(call);
      expect(registry.authorizationRequest(current).scopeDigest, before);
      expect(current.identityDigest, isNot(prepared.identityDigest));
      await expectLater(
        registry.approveWithGrant(prepared, grantId: grant.id),
        throwsA(isA<ToolPlatformException>()),
      );
      expect(uses(grant), 0);
      final approval = await issue(current, grant);
      objects = [original];
      await expectLater(
        registry.invoke(call.withApproval(approval)),
        throwsA(isA<ToolPlatformException>()),
      );
      expect(calls, 0);
    },
  );
  test(
    'selected identity is order stable revision free and never broadens',
    () {
      final other = const ObjectRef(
        moduleId: 'research',
        objectType: 'doc',
        objectId: 'other',
        nativeProjectId: 'p',
      );
      final a = toolGrantScopeDigest(
        AssistantScope.selectedObjects([original, other], workspaceId: 'w'),
        {'research'},
      );
      expect(
        toolGrantScopeDigest(
          AssistantScope.selectedObjects([other, changed], workspaceId: 'w'),
          {'research'},
        ),
        a,
      );
      expect(
        toolGrantScopeDigest(
          AssistantScope.selectedObjects([other], workspaceId: 'w'),
          {'research'},
        ),
        isNot(a),
      );
      expect(
        toolGrantScopeDigest(AssistantScope.workspace('w'), {'research'}),
        isNot(a),
      );
      expect(
        toolGrantScopeDigest(
          AssistantScope.selectedObjects([original, other], workspaceId: 'w'),
          {'research', 'inquiry'},
        ),
        isNot(a),
      );
    },
  );
  test(
    'new nullable linkage does not break manual approvals or read receipts',
    () async {
      final call = request('manual');
      final approval = await registry.approve(await registry.prepare(call));
      expect(
        (await registry.invoke(call.withApproval(approval))).status,
        ToolCallStatus.succeeded,
      );
      expect(
        (await registry.invoke(request('read-call', tool: 'read'))).status,
        ToolCallStatus.succeeded,
      );
      expect(calls, 2);
    },
  );
  test(
    'revocation while effect awaits blocks synchronously before durable write',
    () async {
      final entered = Completer<void>();
      final effect = Completer<void>();
      register(
        'barrier',
        ToolEffect.write,
        handler: (call) async {
          entered.complete();
          await effect.future;
          call.checkAuthorization!();
          calls++;
          return ToolCallResult(
            status: ToolCallStatus.succeeded,
            summary: 'effect',
          );
        },
      );
      final call = request('barrier-call', tool: 'barrier');
      final grant = await create(await registry.prepare(call));
      final approval = await issue(await registry.prepare(call), grant);
      final result = registry.invoke(call.withApproval(approval));
      await entered.future;
      final holding = Completer<void>();
      final release = Completer<void>();
      final held = db.exclusiveAsync((_) async {
        holding.complete();
        await release.future;
      });
      await holding.future;
      final revoke = grants.revoke(grant.id, now: now);
      effect.complete();
      // No timer: draining the microtask queue lets the guarded handler finish;
      // the receipt write remains queued behind the database barrier.
      await Future<void>.value();
      await Future<void>.value();
      expect(calls, 0);
      release.complete();
      await held;
      await revoke;
      expect((await result).status, ToolCallStatus.failed);
      expect(calls, 0);
    },
  );
  test(
    'failed revocation still blocks unused issued approval locally',
    () async {
      final call = request('revoke-fault');
      final prepared = await registry.prepare(call);
      final grant = await create(prepared);
      final approval = await issue(prepared, grant);
      db.raw.execute(
        "CREATE TEMP TRIGGER deny_revoke BEFORE UPDATE OF revoked_at ON assistant_grants BEGIN SELECT RAISE(ABORT,'injected'); END",
      );
      await expectLater(
        grants.revoke(grant.id, now: now),
        throwsA(isA<SqliteException>()),
      );
      expect(grants.list().single.revokedAt, isNull);
      await expectLater(
        registry.invoke(call.withApproval(approval)),
        throwsA(isA<ToolPlatformException>()),
      );
      expect(calls, 0);
    },
  );
  test(
    'scope revision changes while handler awaits prevent actual effect',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      register(
        'revision-barrier',
        ToolEffect.write,
        handler: (call) async {
          entered.complete();
          await release.future;
          call.checkAuthorization!();
          calls++;
          return ToolCallResult(
            status: ToolCallStatus.succeeded,
            summary: 'effect',
          );
        },
      );
      final call = request('revision-effect', tool: 'revision-barrier');
      final prepared = await registry.prepare(call);
      final grant = await create(prepared);
      final approval = await issue(prepared, grant);
      final result = registry.invoke(call.withApproval(approval));
      await entered.future;
      await db.write((owner) {
        objects = [changed];
        owner.execute("UPDATE settings SET value='1' WHERE key='scope_epoch'");
      });
      release.complete();
      expect((await result).status, ToolCallStatus.failed);
      expect(calls, 0);
      expect(uses(grant), 1, reason: 'Committed signing is not refunded');
    },
  );
  test('queue wait uses fresh host facts and fresh clock before atomic consumption', () async {
    final prepared = await registry.prepare(request('queue'));
    final grant = await create(
      prepared,
      expiresAt: now.add(const Duration(minutes: 1)),
    );
    final holding = Completer<void>();
    final release = Completer<void>();
    final held = db.exclusiveAsync((_) async {
      holding.complete();
      await release.future;
    });
    await holding.future;
    final approval = registry.approveWithGrant(prepared, grantId: grant.id);
    now = now.add(const Duration(minutes: 2));
    context = facts(tainted: true);
    release.complete();
    await held;
    expect(await approval, isNull);
    expect(uses(grant), 0);
  });
  test('manual and read cannot secretly consume rule grants', () async {
    final prepared = await registry.prepare(request('manual-grant'));
    final grant = await create(prepared, duration: GrantDuration.always);
    final approval = await registry.approve(prepared);
    await registry.invoke(prepared.request.withApproval(approval));
    await registry.invoke(request('read-no-grant', tool: 'read'));
    expect(uses(grant), 0);
    await expectLater(
      registry.approveWithGrant(
        await registry.prepare(request('read-refusal', tool: 'read')),
        grantId: grant.id,
      ),
      throwsA(isA<ToolPlatformException>()),
    );
    expect(uses(grant), 0);
  });
  test(
    'queued revision change rejects stale signing without consuming once',
    () async {
      final prepared = await registry.prepare(request('queued-revision'));
      final grant = await create(prepared);
      final held = Completer<void>();
      final release = Completer<void>();
      final barrier = db.exclusiveAsync((owner) async {
        held.complete();
        await release.future;
        objects = [changed];
        owner.execute("UPDATE settings SET value='1' WHERE key='scope_epoch'");
      });
      await held.future;
      final signing = registry.approveWithGrant(prepared, grantId: grant.id);
      await Future<void>.value();
      await Future<void>.value();
      release.complete();
      await barrier;
      await expectLater(signing, throwsA(isA<ToolPlatformException>()));
      expect(uses(grant), 0);
      expect(grants.audit(grant.id).map((r) => r['action']), ['created']);
      expect(db.raw.select('SELECT * FROM tool_approvals'), isEmpty);
      expect(calls, 0);
      final current = await registry.prepare(prepared.request);
      expect(
        await registry.approveWithGrant(current, grantId: grant.id),
        isNotNull,
      );
    },
  );
  test(
    'host module boundary cannot authorize resolved objects outside it',
    () async {
      objects = [
        original,
        const ObjectRef(
          moduleId: 'inquiry',
          objectType: 'supplier',
          objectId: 'outside',
        ),
      ];
      final prepared = await registry.prepare(request('outside'));
      expect(
        () => registry.authorizationRequest(prepared),
        throwsA(isA<ToolPlatformException>()),
      );
      expect(db.raw.select('SELECT * FROM tool_approvals'), isEmpty);
      expect(calls, 0);
    },
  );
  test('authorization identity hides credential-bearing destination', () async {
    final prepared = await registry.prepare(
      request(
        'secret',
        tool: 'external',
        destination: 'https://same.test/a?token=do-not-persist',
      ),
    );
    final grant = await create(prepared);
    await issue(prepared, grant);
    expect(
      db.raw
          .select('SELECT destination FROM assistant_grants')
          .single['destination'],
      isNot(contains('do-not-persist')),
    );
    expect(
      db.raw
          .select('SELECT destination FROM tool_approvals')
          .single['destination'],
      isNot(contains('do-not-persist')),
    );
  });
}
