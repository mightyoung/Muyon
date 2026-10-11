import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/host_tool_registrar.dart';
import 'package:muyon/app/host_ui_grant_authority.dart';
import 'package:muyon/app/module_host.dart';
import 'package:muyon/platform/grants/grants.dart';
import 'package:muyon/platform/grants/host_authorization_facts.dart';
import 'package:muyon/platform/grants/host_effect_intent.dart';
import 'package:muyon/platform/grants/host_tool_authorization.dart';
import 'package:muyon/platform/grants/local_export_target.dart';
import 'package:muyon/platform/grants/outbound_content_reviewer.dart';
import 'package:muyon/platform/grants/tool_grant_context.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/fake_v2_module.dart';

/// LE-05: the trusted local-export intent and its two-stage approval binding.
/// Nothing here writes a file or opens a UI; a "run" is a counter in a handler.
void main() {
  final scopeA = 'a' * 64;
  final scopeB = 'b' * 64;

  group('intent', () {
    final issuer = LocalExportTargetIssuer();
    HostEffectIntent make({
      LocalExportPhase phase = LocalExportPhase.generate,
      String scope = '',
      int version = 1,
      String name = 'report-1.md',
      String format = 'text/markdown',
      List<int> content = const [1, 2, 3],
      LocalExportTargetCapability? target,
      LocalExportTargetIssuer? from,
      LocalExportOverwrite overwrite = LocalExportOverwrite.createNew,
      String policy = 'p1',
    }) => HostEffectIntent.localExport(
      toolId: 'research.export',
      invocationId: 'call',
      phase: phase,
      scopeDigest: scope.isEmpty ? scopeA : scope,
      preparationVersion: version,
      fileName: name,
      format: format,
      content: content,
      sourceObjects: const [],
      targetIssuer: from ?? issuer,
      target: target,
      overwrite: overwrite,
      policyVersion: policy,
    );

    test('every bound field changes the digest', () {
      final target = issuer.issue('t1');
      final other = issuer.issue('t2');
      final base = make().digest;
      final saved = make(phase: LocalExportPhase.save, target: target).digest;
      expect(base, isNot(saved));
      expect(make(scope: scopeB).digest, isNot(base));
      expect(make(version: 2).digest, isNot(base));
      expect(make(name: 'report-2.md').digest, isNot(base));
      expect(make(format: 'text/plain').digest, isNot(base));
      expect(make(content: [1, 2, 4]).digest, isNot(base));
      expect(make(policy: 'p2').digest, isNot(base));
      expect(
        make(phase: LocalExportPhase.save, target: other).digest,
        isNot(saved),
      );
      expect(
        make(
          phase: LocalExportPhase.save,
          target: target,
          overwrite: LocalExportOverwrite.replace,
        ).digest,
        isNot(saved),
      );
      expect(make().digest, base, reason: 'stable for equal inputs');
    });

    test('content is frozen and is the payload digest', () {
      final bytes = [1, 2, 3];
      final frozen = make(content: bytes);
      final before = frozen.digest;
      bytes[0] = 9;
      expect(frozen.content, [1, 2, 3]);
      expect(frozen.digest, before);
      expect(() => frozen.content[0] = 0, throwsUnsupportedError);
      expect(frozen.payloadDigest, sha256.convert([1, 2, 3]).toString());
      expect(frozen.isLocalExport, isTrue);
      expect(frozen.isTransport, isFalse);
      expect(frozen.destinationDigest, isNull);
    });

    test('shape is validated', () {
      final target = issuer.issue('t');
      expect(() => make(content: const []), throwsArgumentError);
      expect(() => make(scope: 'zz'), throwsArgumentError);
      expect(() => make(version: 0), throwsArgumentError);
      expect(() => make(policy: ''), throwsArgumentError);
      for (final bad in ['', '../x', 'a/b', r'a\b', '.hidden/..', 'x' * 129]) {
        expect(() => make(name: bad), throwsArgumentError, reason: bad);
      }
      // generate carries no target and never replaces; save needs a target
      expect(() => make(target: target), throwsArgumentError);
      expect(
        () => make(overwrite: LocalExportOverwrite.replace),
        throwsArgumentError,
      );
      expect(() => make(phase: LocalExportPhase.save), throwsArgumentError);
    });

    test('a target capability must be live and issued by the host issuer', () {
      final mine = issuer.issue('mine');
      expect(
        make(phase: LocalExportPhase.save, target: mine).isLocalExport,
        isTrue,
      );
      final forgedIssuer = LocalExportTargetIssuer();
      final forged = forgedIssuer.issue('mine');
      expect(forged.identity, isNot(mine.identity));
      expect(
        () => make(phase: LocalExportPhase.save, target: forged),
        throwsArgumentError,
      );
      issuer.revoke(mine);
      expect(
        () => make(phase: LocalExportPhase.save, target: mine),
        throwsArgumentError,
      );
    });
  });

  group('registry and approval', () {
    late Directory root;
    late StorageManager storage;
    late ManagedConnection db;
    late GrantStore grants;
    late ToolRegistry registry;
    late LocalExportTargetIssuer issuer;
    late HostTaintState taint;
    late bool exportAllowed;
    late String policyRevision;
    late int runs;
    // The mutable inputs the host adapter would rebuild the intent from.
    late LocalExportPhase phase;
    late List<int> bytes;
    late String scopeDigest, fileName, format, policyVersion;
    late int preparationVersion;
    late LocalExportOverwrite overwrite;
    late LocalExportTargetCapability? target;
    late int invocation;
    final now = DateTime.utc(2026, 10, 11);

    HostToolAuthorization service([OutboundContentReviewer? reviewer]) =>
        HostToolAuthorization(
          registry: registry,
          reviewer: reviewer ?? const NoopReviewer(),
          taskFacts: (_) => HostTaskFacts(
            taskId: 'task',
            conversationId: 'conversation',
            taintState: taint,
            sourceDigests: const [],
          ),
        );

    ToolCallRequest request([LocalExportPhase? stage, String? id]) =>
        ToolCallRequest(
          invocationId: id ?? 'call-$invocation',
          toolId: 'research.export',
          scope: AssistantScope.global(),
          destination: localExportDestination(stage ?? phase),
        );

    Future<PreparedToolCall> prepare([LocalExportPhase? stage, String? id]) =>
        registry.prepare(request(stage, id));

    Future<String> approve(PreparedToolCall call) async {
      final outcome = await service().review(call);
      expect(outcome.action, ReviewAction.confirm);
      final id = await service().confirm(outcome);
      expect(id, isNotNull);
      return id!;
    }

    Future<bool> ran(ToolCallRequest signed) async {
      final before = runs;
      try {
        final result = await registry.invoke(signed);
        if (result.status != ToolCallStatus.succeeded) {
          expect(runs, before, reason: 'a refused call must not execute');
          return false;
        }
      } on Object {
        expect(runs, before, reason: 'a refused call must not execute');
        return false;
      }
      return runs == before + 1;
    }

    setUp(() async {
      root = Directory.systemTemp.createTempSync('le05-');
      storage = StorageManager(root.path);
      db = await storage.open('muyon', WorkspaceRepository.schema);
      grants = GrantStore(db);
      issuer = LocalExportTargetIssuer();
      taint = HostTaintState.clean;
      exportAllowed = true;
      policyRevision = 'rev-1';
      runs = 0;
      invocation = 0;
      phase = LocalExportPhase.generate;
      bytes = [1, 2, 3];
      scopeDigest = scopeA;
      fileName = 'report-1.md';
      format = 'text/markdown';
      policyVersion = 'p1';
      preparationVersion = 1;
      overwrite = LocalExportOverwrite.createNew;
      target = null;
      registry = ToolRegistry(
        database: db,
        grants: grants,
        clock: () => now,
        grantContext: (_) => ToolGrantContext(
          taskId: 'task',
          conversationId: 'conversation',
          taskTainted: taint != HostTaintState.clean,
          scopeRevision: 'scope-1',
          allowedModuleIds: const {'research'},
        ),
        resolveScope: (scope) async =>
            ResolvedAssistantScope(requested: scope, objects: const []),
        categoryAllowed: (effect) =>
            effect != ToolEffect.export || exportAllowed,
        policyRevision: () => policyRevision,
      );
      registry.register(
        providerId: 'research',
        descriptor: ToolDescriptor(
          toolId: 'research.export',
          moduleId: 'research',
          effect: ToolEffect.export,
          parameterSchema: const {'type': 'object'},
        ),
        effectIntent: (request, _) => HostEffectIntent.localExport(
          toolId: request.toolId,
          invocationId: request.invocationId,
          phase: phase,
          scopeDigest: scopeDigest,
          preparationVersion: preparationVersion,
          fileName: fileName,
          format: format,
          content: bytes,
          sourceObjects: const [],
          targetIssuer: issuer,
          target: target,
          overwrite: overwrite,
          policyVersion: policyVersion,
        ),
        handler: (context) async {
          context.checkBeforeEffect();
          runs++;
          return ToolCallResult(
            status: ToolCallStatus.succeeded,
            summary: 'done',
          );
        },
      );
    });
    tearDown(() async {
      await registry.close();
      await storage.close();
      root.deleteSync(recursive: true);
    });

    test('a manually approved generate call runs exactly once', () async {
      final call = await prepare();
      expect(call.effectIntent!.isLocalExport, isTrue);
      final signed = call.request.withApproval(await approve(call));
      expect(await ran(signed), isTrue);
      expect(runs, 1);
      // the approval is one-use
      expect(await ran(signed), isFalse);
      expect(runs, 1);
    });

    final changes = <String, void Function()>{
      'bytes': () => bytes = [1, 2, 4],
      'scope': () => scopeDigest = scopeB,
      'file name': () => fileName = 'report-2.md',
      'format': () => format = 'text/plain',
      'preparation version': () => preparationVersion = 2,
      'policy version': () => policyVersion = 'p2',
    };
    for (final entry in changes.entries) {
      test('changing the ${entry.key} after approval invalidates it', () async {
        final call = await prepare();
        final signed = call.request.withApproval(await approve(call));
        entry.value();
        expect(await ran(signed), isFalse);
        expect(runs, 0);
      });
    }

    test(
      'changing the host policy revision after approval invalidates it',
      () async {
        final call = await prepare();
        final signed = call.request.withApproval(await approve(call));
        policyRevision = 'rev-2';
        expect(await ran(signed), isFalse);
      },
    );

    test('target and overwrite are bound on the save stage', () async {
      phase = LocalExportPhase.save;
      target = issuer.issue('t1');
      for (final change in <String, void Function()>{
        'target': () => target = issuer.issue('t2'),
        'overwrite': () => overwrite = LocalExportOverwrite.replace,
      }.entries) {
        final call = await prepare(null, 'save-${change.key}');
        final signed = call.request.withApproval(await approve(call));
        change.value();
        expect(await ran(signed), isFalse, reason: change.key);
      }
      expect(runs, 0);
    });

    test(
      'a revoked target cannot be executed even with its approval',
      () async {
        phase = LocalExportPhase.save;
        final live = issuer.issue('t');
        target = live;
        final call = await prepare();
        final signed = call.request.withApproval(await approve(call));
        issuer.revoke(live);
        expect(await ran(signed), isFalse);
      },
    );

    test('a generate approval cannot execute the save stage', () async {
      final generate = await prepare(LocalExportPhase.generate, 'one');
      final approval = await approve(generate);
      // same invocation, now the save stage with a real target
      phase = LocalExportPhase.save;
      target = issuer.issue('t');
      final save = ToolCallRequest(
        invocationId: 'one',
        toolId: 'research.export',
        scope: AssistantScope.global(),
        destination: localExportDestination(LocalExportPhase.save),
        approvalId: approval,
      );
      expect(await ran(save), isFalse);
      // and under a fresh invocation id
      final other = ToolCallRequest(
        invocationId: 'two',
        toolId: 'research.export',
        scope: AssistantScope.global(),
        destination: localExportDestination(LocalExportPhase.save),
        approvalId: approval,
      );
      expect(await ran(other), isFalse);
      expect(runs, 0);
    });

    test('the request stage must match the intent stage', () async {
      // intent says generate, request says save, and the reverse
      phase = LocalExportPhase.generate;
      await expectLater(
        prepare(LocalExportPhase.save),
        throwsA(isA<ToolPlatformException>()),
      );
      phase = LocalExportPhase.save;
      target = issuer.issue('t');
      await expectLater(
        prepare(LocalExportPhase.generate),
        throwsA(isA<ToolPlatformException>()),
      );
    });

    test('read-only mode or outbound off means no proposal at all', () async {
      exportAllowed = false;
      await expectLater(
        prepare(),
        throwsA(
          isA<ToolPlatformException>().having(
            (e) => e.code,
            'code',
            'category_disabled',
          ),
        ),
      );
      exportAllowed = true;
      final call = await prepare();
      final signed = call.request.withApproval(await approve(call));
      exportAllowed = false;
      expect(await ran(signed), isFalse);
      expect(runs, 0);
    });

    for (final state in [HostTaintState.tainted, HostTaintState.unknown]) {
      test(
        'a ${state.name} task still needs a person and stays ${state.name}',
        () async {
          taint = state;
          final call = await prepare();
          // even a reviewer that says "allow" cannot skip the confirmation
          final outcome = await service(_Reviewer(const ReviewDecision.allow()))
              .review(call);
          expect(outcome.action, ReviewAction.confirm);
          expect(outcome.grantId, isNull);
          expect(await service().sign(outcome), isNull);
          final id = await service().confirm(outcome);
          expect(id, isNotNull);
          expect(await ran(call.request.withApproval(id!)), isTrue);
          expect(taint, state, reason: 'a manual confirmation does not clean');
          expect(
            db.raw
                .select('SELECT authorization_source FROM tool_approvals')
                .single['authorization_source'],
            'manual',
          );
        },
      );
    }

    test(
      'no grant, not even a once grant, can authorize a local export',
      () async {
        final call = await prepare();
        // A grant that would match any ordinary outbound call for this tool.
        final scope = toolGrantScopeDigest(call.request.scope, const {
          'research',
        });
        final destination = sha256
            .convert(utf8.encode(jsonEncode(call.request.destination)))
            .toString();
        final once = await withConfirmedHostUiGrant(
          (token) => grants.create(
            token: token,
            draft: GrantDraft(
              category: 'outbound',
              toolId: 'research.export',
              scopeDigest: scope,
              destination: destination,
              duration: GrantDuration.once,
              conversationId: 'conversation',
            ),
            now: now,
          ),
        );
        final outcome = await service(_Reviewer(const ReviewDecision.allow()))
            .review(call);
        expect(outcome.action, ReviewAction.confirm);
        expect(outcome.grantId, isNull);
        expect(await service().sign(outcome), isNull);
        await expectLater(
          registry.approveWithGrant(call, grantId: once.id),
          throwsA(isA<ToolPlatformException>()),
        );
        await expectLater(
          () => registry.authorizationRequest(call),
          throwsA(isA<ToolPlatformException>()),
        );
        expect(grants.list().single.uses, 0);
        expect(db.raw.select('SELECT * FROM tool_approvals'), isEmpty);
      },
    );

    test(
      'a local export tool without a host intent cannot be prepared',
      () async {
        registry.register(
          providerId: 'research',
          descriptor: ToolDescriptor(
            toolId: 'research.bare',
            moduleId: 'research',
            effect: ToolEffect.export,
            parameterSchema: const {'type': 'object'},
          ),
          handler: (_) async =>
              ToolCallResult(status: ToolCallStatus.succeeded, summary: 'x'),
        );
        await expectLater(
          registry.prepare(
            ToolCallRequest(
              invocationId: 'bare',
              toolId: 'research.bare',
              scope: AssistantScope.global(),
              destination: localExportDestination(LocalExportPhase.generate),
            ),
          ),
          throwsA(
            isA<ToolPlatformException>().having(
              (e) => e.code,
              'code',
              'intent_mismatch',
            ),
          ),
        );
      },
    );

    test('an intent for another tool or invocation is refused', () async {
      await expectLater(
        registry.prepare(
          ToolCallRequest(
            invocationId: 'x',
            toolId: 'research.export',
            scope: AssistantScope.global(),
            destination: 'https://example.test/not-a-local-export',
          ),
        ),
        throwsA(isA<ToolPlatformException>()),
      );
    });
  });

  group('registrar', () {
    late ManagedConnection db;
    late ToolRegistry registry;
    final issuer = LocalExportTargetIssuer();
    setUp(() {
      db = ManagedConnection(sqlite3.openInMemory());
      installToolRegistrySchema(db.raw);
      registry = ToolRegistry(
        database: db,
        resolveScope: (scope) async =>
            ResolvedAssistantScope(requested: scope, objects: const []),
      );
    });
    tearDown(() => db.close());

    HostToolRegistrar registrar({
      Set<CapabilityRequest> capabilities = const {},
      LocalExportIntentProvider? provider,
    }) => HostToolRegistrar(
      'research',
      registry,
      ModuleManifest(id: 'research', apiVersion: 2, capabilities: capabilities),
      _ReadyLink(),
      localExportIntent: provider,
    );
    ExternalToolSpec spec({DestinationRule? rule}) => ExternalToolSpec(
      name: 'export_report',
      description: '导出报告，仅用于测试。',
      effect: ToolEffect.export,
      destination: rule ?? const DestinationRule.localExport(),
    );
    Future<ToolCallResult> ok(ModuleToolContext _) async =>
        ToolCallResult(status: ToolCallStatus.succeeded, summary: 'ok');
    const capability = CapabilityRequest(
      id: localExportsCapabilityId,
      reason: '本机导出',
    );
    HostEffectIntent? intentFor(ToolCallRequest r, ResolvedAssistantScope _) =>
        HostEffectIntent.localExport(
          toolId: r.toolId,
          invocationId: r.invocationId,
          phase: LocalExportPhase.generate,
          scopeDigest: 'c' * 64,
          preparationVersion: 1,
          fileName: 'report-1.md',
          format: 'text/markdown',
          content: const [1],
          sourceObjects: const [],
          targetIssuer: issuer,
          overwrite: LocalExportOverwrite.createNew,
          policyVersion: 'p',
        );

    test('a localExport tool needs the local_exports capability', () {
      expect(() => registrar().external(spec(), ok), throwsArgumentError);
      expect(registry.inspect('research.export_report'), isNull);
      registrar(
        capabilities: {capability},
        provider: intentFor,
      ).external(spec(), ok);
      final info = registry.inspect('research.export_report')!;
      expect(info.descriptor.effect, ToolEffect.export);
      expect(info.accessLevel, ToolAccessLevel.external);
    });

    test('only the two host stage destinations pass the guard', () async {
      registrar(
        capabilities: {capability},
        provider: intentFor,
      ).external(spec(), ok);
      for (final bad in [
        'https://example.test/x',
        'file:///tmp/x',
        'local-export:other',
      ]) {
        await expectLater(
          registry.prepare(
            ToolCallRequest(
              invocationId: 'g',
              toolId: 'research.export_report',
              scope: AssistantScope.global(),
              destination: bad,
            ),
          ),
          throwsA(isA<ToolPlatformException>()),
          reason: bad,
        );
      }
    });

    test(
      'without a host intent provider the tool exists but cannot be prepared',
      () async {
        registrar(capabilities: {capability}).external(spec(), ok);
        await expectLater(
          registry.prepare(
            ToolCallRequest(
              invocationId: 'n',
              toolId: 'research.export_report',
              scope: AssistantScope.global(),
              destination: localExportDestination(LocalExportPhase.generate),
            ),
          ),
          throwsA(isA<ToolPlatformException>()),
        );
      },
    );

    test('network tools register exactly as before', () {
      expect(
        () => registrar().external(
          spec(rule: const DestinationRule(publicWeb: true)),
          ok,
        ),
        throwsArgumentError,
        reason: 'empty manifest network policy still refuses',
      );
    });
  });
}

class _Reviewer implements OutboundContentReviewer {
  _Reviewer(this.decision);
  final ReviewDecision decision;
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async =>
      decision;
}

class _ReadyLink implements ModuleLink {
  @override
  Future<ModuleState> activate(String moduleId) async =>
      const ModuleState(ModuleStatus.ready, null);
  @override
  T? runtime<T extends ModuleRuntime>(String moduleId) => null;
}
