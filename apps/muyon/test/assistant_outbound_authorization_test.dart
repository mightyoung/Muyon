import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/grants/host_effect_intent.dart';
import 'package:muyon/app/host_ui_grant_authority.dart';
import 'package:muyon/app/inquiry_web_authority.dart';
import 'package:muyon/app/inquiry_hub_authority.dart';
import 'package:supplier_core/supplier_core.dart';
import 'package:muyon/platform/grants/grants.dart';
import 'package:muyon/platform/grants/host_authorization_facts.dart';
import 'package:muyon/platform/grants/host_tool_authorization.dart';
import 'package:muyon/platform/grants/tool_grant_context.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/platform/outbound_tool_ledger.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

void main() {
  reviewTests();
  channelReviewTests();
  HostEffectIntent intent({
    String path = '/rpc?token=secret-one',
    String identity = 'server-A',
    List<int> content = const [1, 2],
  }) => HostEffectIntent.transport(
    toolId: 'send',
    invocationId: 'call',
    endpoint: Uri.parse('https://example.test$path'),
    endpointIdentity: identity,
    content: content,
  );
  test(
    'permission identity includes full endpoint and configured identity',
    () {
      final base = intent();
      expect(base.destinationDigest, hasLength(64));
      expect(
        intent(path: '/other?token=secret-one').destinationDigest,
        isNot(base.destinationDigest),
      );
      expect(
        intent(path: '/rpc?token=secret-two').destinationDigest,
        isNot(base.destinationDigest),
      );
      expect(
        intent(identity: 'server-B').destinationDigest,
        isNot(base.destinationDigest),
      );
      expect(base.displayDestination, isNot(contains('secret-one')));
      expect(base.displayDestination, contains('/rpc'));
    },
  );
  test('review and transport share frozen bytes with digest binding', () {
    final bytes = utf8.encode('actual serialized RPC');
    final frozen = intent(content: bytes);
    final digest = frozen.digest;
    bytes[0] = 0;
    expect(utf8.decode(frozen.content), 'actual serialized RPC');
    expect(frozen.payloadDigest, hasLength(64));
    expect(frozen.digest, digest);
    expect(intent(content: [3, 4]).digest, isNot(digest));
    expect(() => frozen.content[0] = 0, throwsUnsupportedError);
  });
  test('unknown identity and non-transport endpoints are rejected', () {
    expect(() => intent(identity: ''), throwsArgumentError);
    expect(
      () => HostEffectIntent.transport(
        toolId: 'send',
        invocationId: 'call',
        endpoint: Uri.parse('file:///tmp/local'),
        endpointIdentity: 'x',
        content: [1],
      ),
      throwsArgumentError,
    );
  });
}

class _Review implements OutboundContentReviewer {
  _Review(this.run);
  final Future<ReviewDecision> Function(OutboundReviewRequest) run;
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) => run(request);
}

void reviewTests() {
  group('real host review persistence', () {
    late Directory root;
    late StorageManager storage;
    late ManagedConnection db;
    late GrantStore grants;
    late ToolRegistry registry;
    late PreparedToolCall call;
    late HostTaintState taint;
    late String revision;
    late List<int> bytes;
    late String endpointIdentity;
    var sends = 0;
    HostAuthorizationLink? transportLink;
    Future<void> Function(HostAuthorizationLink?)? onSend;
    final endpoint = Uri.parse('https://example.test/rpc?token=never-persist');
    final now = DateTime.utc(2026, 10, 8);
    HostToolAuthorization service(OutboundContentReviewer reviewer) =>
        HostToolAuthorization(
          registry: registry,
          reviewer: reviewer,
          taskFacts: (_) => HostTaskFacts(
            taskId: 'task',
            conversationId: 'conversation',
            taintState: taint,
            sourceDigests: const [],
          ),
        );
    Future<AssistantGrant> grant() {
      final request = registry.authorizationRequest(call);
      return withConfirmedHostUiGrant(
        (token) => grants.create(
          token: token,
          draft: GrantDraft(
            category: 'outbound',
            toolId: request.toolId,
            scopeDigest: request.scopeDigest,
            destination: request.destination,
            duration: GrantDuration.once,
            conversationId: 'conversation',
          ),
          now: now,
        ),
      );
    }

    setUp(() async {
      root = Directory.systemTemp.createTempSync('auth-b2-review-');
      storage = StorageManager(root.path);
      db = await storage.open('muyon', WorkspaceRepository.schema);
      grants = GrantStore(db);
      // Trusted fixture inputs; production clean proof remains unconnected.
      taint = HostTaintState.clean;
      revision = 'scope-1';
      bytes = [1, 2];
      endpointIdentity = 'configured-A';
      sends = 0;
      transportLink = null;
      onSend = null;
      registry = ToolRegistry(
        database: db,
        grants: grants,
        clock: () => now,
        grantContext: (_) => ToolGrantContext(
          taskId: 'task',
          conversationId: 'conversation',
          taskTainted: taint != HostTaintState.clean,
          scopeRevision: revision,
          allowedModuleIds: const {'prototype'},
        ),
        resolveScope: (scope) async =>
            ResolvedAssistantScope(requested: scope, objects: const []),
      );
      registry.register(
        providerId: 'host.fixture',
        descriptor: ToolDescriptor(
          toolId: 'send',
          moduleId: 'platform',
          effect: ToolEffect.network,
          parameterSchema: const {'type': 'object'},
        ),
        effectIntent: (request, _) => HostEffectIntent.transport(
          toolId: request.toolId,
          invocationId: request.invocationId,
          endpoint: endpoint,
          endpointIdentity: endpointIdentity,
          content: bytes,
        ),
        handler: (context) async {
          context.checkBeforeEffect();
          transportLink = registry.authorizationLink(context.request);
          await onSend?.call(transportLink);
          sends++;
          return ToolCallResult(
            status: ToolCallStatus.succeeded,
            summary: 'sent',
          );
        },
      );
      call = await registry.prepare(
        ToolCallRequest(
          invocationId: 'call',
          toolId: 'send',
          scope: AssistantScope.global(),
          destination: endpoint.toString(),
        ),
      );
    });
    tearDown(() async {
      await registry.close();
      await storage.close();
      root.deleteSync(recursive: true);
    });
    test(
      'Noop keeps unreviewed allow with actual grant but consumes nothing',
      () async {
        final source = await grant();
        final outcome = await service(const NoopReviewer()).review(call);
        expect(outcome.action, ReviewAction.allow);
        expect(outcome.reviewed, false);
        expect(outcome.grantId, source.id);
        expect(outcome.reviewDecisionId, isNotNull);
        expect(grants.list().single.uses, 0);
        expect(db.raw.select('SELECT * FROM tool_approvals'), isEmpty);
        final row = db.raw
            .select('SELECT * FROM assistant_review_decisions')
            .single;
        expect(row['reviewed'], 0);
        expect(
          row['destination_identity_digest'],
          call.effectIntent!.destinationDigest,
        );
        expect(row['payload_digest'], call.effectIntent!.payloadDigest);
        expect(
          jsonEncode(Map<String, Object?>.from(row)),
          isNot(contains('never-persist')),
        );
      },
    );
    test(
      'allow cannot supply absent authorization or unknown clean proof',
      () async {
        final outcome = await service(
          _Review((_) async => const ReviewDecision.allow()),
        ).review(call);
        expect(outcome.action, ReviewAction.confirm);
        expect(outcome.grantId, isNull);
        expect(outcome.reviewDecisionId, isNotNull);
        await grant();
        taint = HostTaintState.unknown;
        expect(
          (await service(const NoopReviewer()).review(call)).action,
          ReviewAction.confirm,
        );
        expect(grants.list().single.uses, 0);
      },
    );
    test(
      'block persists independently with no approval or transport row',
      () async {
        await grant();
        final outcome = await service(
          _Review((_) async => const ReviewDecision.block('never-persist')),
        ).review(call);
        expect(outcome.action, ReviewAction.block);
        final row = db.raw
            .select('SELECT * FROM assistant_review_decisions')
            .single;
        expect(row['decision'], 'block');
        expect(row['reason'], 'review_block');
        expect(db.raw.select('SELECT * FROM tool_approvals'), isEmpty);
        expect(db.raw.select('SELECT * FROM outbound_tool_requests'), isEmpty);
        expect(grants.list().single.uses, 0);
      },
    );
    test('exception and timeout confirm with fixed safe reason', () async {
      await grant();
      final chain = ReviewerChain([
        _Review((_) async => throw StateError('never-persist')),
      ], timeout: const Duration(milliseconds: 10));
      final outcome = await service(chain).review(call);
      expect(outcome.action, ReviewAction.confirm);
      expect(outcome.reviewed, false);
      final waiting = Completer<ReviewDecision>();
      final timed = await service(
        ReviewerChain([
          _Review((_) => waiting.future),
        ], timeout: const Duration(milliseconds: 10)),
      ).review(call);
      expect(timed.action, ReviewAction.confirm);
      waiting.complete(const ReviewDecision.allow());
      for (final row in db.raw.select(
        'SELECT * FROM assistant_review_decisions',
      )) {
        expect(row['reason'], 'review_confirm');
        expect(
          jsonEncode(Map<String, Object?>.from(row)),
          isNot(contains('never-persist')),
        );
      }
    });
    for (final change in [
      'revocation',
      'taint',
      'scope',
      'bytes',
      'endpoint identity',
    ]) {
      test('$change during review cannot authorize stale effect', () async {
        final source = await grant();
        final entered = Completer<void>();
        final release = Completer<ReviewDecision>();
        final pending = service(
          _Review((_) {
            entered.complete();
            return release.future;
          }),
        ).review(call);
        await entered.future;
        switch (change) {
          case 'revocation':
            await grants.revoke(source.id, now: now);
          case 'taint':
            taint = HostTaintState.tainted;
          case 'scope':
            revision = 'scope-2';
          case 'bytes':
            bytes = [3, 4];
          case 'endpoint identity':
            endpointIdentity = 'configured-B';
        }
        release.complete(const ReviewDecision.allow());
        final outcome = await pending;
        expect(outcome.action, ReviewAction.confirm);
        expect(outcome.grantId, isNull);
        expect(grants.list().single.uses, 0);
        expect(db.raw.select('SELECT * FROM tool_approvals'), isEmpty);
      });
    }
    test(
      'reviewed grant signs atomically and receipt carries actual source',
      () async {
        final source = await grant();
        final auth = service(const NoopReviewer());
        final outcome = await auth.review(call);
        final approval = await auth.sign(outcome);
        expect(approval, isNotNull);
        expect(grants.list().single.uses, 1);
        final row = db.raw.select('SELECT * FROM tool_approvals').single;
        expect(row['grant_id'], source.id);
        expect(row['review_decision_id'], outcome.reviewDecisionId);
        final result = await registry.invoke(
          ToolCallRequest(
            invocationId: 'call',
            toolId: 'send',
            scope: AssistantScope.global(),
            destination: endpoint.toString(),
            approvalId: approval,
          ),
        );
        expect(result.status, ToolCallStatus.succeeded);
        expect(sends, 1);
        final receipt = db.raw
            .select('SELECT * FROM tool_invocation_receipts')
            .single;
        expect(receipt['grant_id'], source.id);
        expect(receipt['authorization_source'], 'grant');
        expect(receipt['review_decision_id'], outcome.reviewDecisionId);
        expect(await auth.sign(outcome), approval);
        expect(grants.list().single.uses, 1);
      },
    );
    test(
      'block cannot be bypassed by direct registry manual confirmation',
      () async {
        await grant();
        final auth = service(
          _Review((_) async => const ReviewDecision.block('deny')),
        );
        final outcome = await auth.review(call);
        expect(await auth.sign(outcome), isNull);
        await expectLater(
          registry.approve(call),
          throwsA(isA<ToolPlatformException>()),
        );
        expect(sends, 0);
        expect(grants.list().single.uses, 0);
        expect(db.raw.select('SELECT * FROM tool_approvals'), isEmpty);
      },
    );
    test('approval INSERT failure rolls back grant use and audit, keeps actual review', () async {
      await grant();
      final auth = service(const NoopReviewer());
      final outcome = await auth.review(call);
      db.raw.execute(
        "CREATE TRIGGER refuse_sign BEFORE INSERT ON tool_approvals BEGIN SELECT RAISE(ABORT,'fail'); END",
      );
      await expectLater(auth.sign(outcome), throwsA(anything));
      expect(grants.list().single.uses, 0);
      expect(
        grants
            .audit(grants.list().single.id)
            .where((row) => row['action'] == 'used'),
        isEmpty,
      );
      expect(db.raw.select('SELECT * FROM tool_approvals'), isEmpty);
      expect(
        db.raw.select('SELECT * FROM assistant_review_decisions'),
        hasLength(1),
      );
      expect(sends, 0);
    });
    test('queued signing rechecks content before consumption', () async {
      await grant();
      final auth = service(const NoopReviewer());
      final outcome = await auth.review(call);
      final entered = Completer<void>(), release = Completer<void>();
      final busy = db.exclusiveAsync((_) async {
        entered.complete();
        await release.future;
        bytes = [9];
      });
      await entered.future;
      final pending = auth.sign(outcome);
      final denied = expectLater(
        pending,
        throwsA(isA<ToolPlatformException>()),
      );
      await Future<void>.value();
      await Future<void>.value();
      release.complete();
      await busy;
      await denied;
      expect(grants.list().single.uses, 0);
      expect(db.raw.select('SELECT * FROM tool_approvals'), isEmpty);
    });
    test(
      'manual confirmation has real review and no invented grant ID',
      () async {
        final auth = service(const NoopReviewer());
        final outcome = await auth.review(call);
        expect(outcome.action, ReviewAction.confirm);
        final approval = await auth.confirm(outcome);
        expect(approval, isNotNull);
        final row = db.raw.select('SELECT * FROM tool_approvals').single;
        expect(row['grant_id'], isNull);
        expect(row['authorization_source'], 'manual');
        expect(row['review_decision_id'], outcome.reviewDecisionId);
        expect(row['destination'], isNot(contains('never-persist')));
        expect(grants.list(), isEmpty);
      },
    );
    test(
      'actual outbound attempt carries source and reviewed payload',
      () async {
        final source = await grant();
        final auth = service(const NoopReviewer());
        final outcome = await auth.review(call);
        final approval = await auth.sign(outcome);
        final request = ToolCallRequest(
          invocationId: 'call',
          toolId: 'send',
          scope: AssistantScope.global(),
          destination: endpoint.toString(),
          approvalId: approval,
        );
        final ledger = OutboundToolLedger(db);
        var wireBytes = 0;
        onSend = (link) async {
          expect(link, isNotNull);
          await expectLater(
            ledger.run(
              toolId: 'send',
              channel: 'mcp',
              destination: endpoint,
              payload: [9],
              authorization: link,
              operation: (_) async {
                wireBytes++;
              },
            ),
            throwsA(isA<ToolPlatformException>()),
          );
          await ledger.run(
            toolId: 'send',
            channel: 'mcp',
            destination: endpoint,
            payload: call.effectIntent!.content,
            authorization: link,
            operation: (sent) async {
              sent(2);
              wireBytes = 2;
            },
          );
        };
        final result = await registry.invoke(request);
        expect(result.status, ToolCallStatus.succeeded);
        expect(wireBytes, 2);
        final row = db.raw
            .select('SELECT * FROM outbound_tool_requests')
            .single;
        expect(row['grant_id'], source.id);
        expect(row['authorization_source'], 'grant');
        expect(row['review_decision_id'], outcome.reviewDecisionId);
        expect(row['payload_digest'], call.effectIntent!.payloadDigest);
        expect(row['state'], 'succeeded');
        expect(
          jsonEncode(Map<String, Object?>.from(row)),
          isNot(contains('never-persist')),
        );
        await expectLater(
          ledger.run(
            toolId: 'send',
            channel: 'mcp',
            destination: endpoint,
            payload: [9],
            authorization: transportLink,
            operation: (_) async {
              wireBytes++;
            },
          ),
          throwsA(isA<ToolPlatformException>()),
        );
        expect(wireBytes, 2);
        expect(
          db.raw.select('SELECT * FROM outbound_tool_requests'),
          hasLength(1),
        );
      },
    );
    test('review INSERT failure stops before approval and transport', () async {
      await grant();
      db.raw.execute(
        "CREATE TRIGGER refuse_review BEFORE INSERT ON assistant_review_decisions BEGIN SELECT RAISE(ABORT,'fail'); END",
      );
      await expectLater(
        service(const NoopReviewer()).review(call),
        throwsA(anything),
      );
      expect(grants.list().single.uses, 0);
      expect(db.raw.select('SELECT * FROM tool_approvals'), isEmpty);
      expect(db.raw.select('SELECT * FROM outbound_tool_requests'), isEmpty);
    });
  });
}

void channelReviewTests() {
  for (final kind in ['web', 'hub']) {
    for (final block in [true, false]) {
      test(
        'host $kind local block=$block precedes UI and records honest source',
        () async {
          final root = Directory.systemTemp.createTempSync(
            'auth-host-channel-',
          );
          final storage = StorageManager(root.path);
          final owner = await storage.open('muyon', WorkspaceRepository.schema);
          final registry = ToolRegistry(
            database: owner,
            resolveScope: (scope) async =>
                ResolvedAssistantScope(requested: scope, objects: const []),
          );
          addTearDown(() async {
            await registry.close();
            await storage.close();
            root.deleteSync(recursive: true);
          });
          final auth = HostToolAuthorization(
            registry: registry,
            reviewer: _Review(
              (_) async => block
                  ? const ReviewDecision.block('secret')
                  : const ReviewDecision.allow(),
            ),
          );
          var cards = 0, effects = 0;
          final cancellation = AiCancellation();
          late Future<void> operation;
          if (kind == 'web') {
            final authority = InquiryWebAuthority(
              registry,
              authorization: auth,
            );
            operation = authority.run(
              destination: Uri.parse('https://example.test/a?token=private'),
              sessionId: 'host-session',
              cancellation: cancellation,
              review: (_, _) async {
                cards++;
                return true;
              },
              validateSession: () {},
              operation: (guard) async {
                guard();
                effects++;
              },
            );
          } else {
            final authority = InquiryHubAuthority(
              registry,
              authorization: auth,
            );
            final request = HubRequest(
              'POST',
              Uri.parse('https://example.test/v1/publications'),
              const {'title': 'actual body'},
            );
            operation = authority.run(
              request: request,
              cancellation: cancellation,
              review: (_, _) async {
                cards++;
                return true;
              },
              validateSession: () {},
              operation: (guard) async {
                guard();
                effects++;
                request.onBodySent?.call(
                  utf8.encode(request.encodedBody!).length,
                );
              },
            );
          }
          if (block) {
            await expectLater(operation, throwsA(anything));
            expect(cards, 0);
            expect(effects, 0);
            expect(owner.raw.select('SELECT * FROM tool_approvals'), isEmpty);
            expect(
              owner.raw.select('SELECT * FROM outbound_tool_requests'),
              isEmpty,
            );
            expect(
              owner.raw.select('SELECT * FROM tool_invocation_receipts'),
              isEmpty,
            );
            expect(
              owner.raw
                  .select('SELECT decision FROM assistant_review_decisions')
                  .single['decision'],
              'block',
            );
          } else {
            await operation;
            expect(cards, 1);
            expect(effects, 1);
            final decision = owner.raw
                .select('SELECT * FROM assistant_review_decisions')
                .single;
            final receipt = owner.raw
                .select('SELECT * FROM tool_invocation_receipts')
                .single;
            final row = owner.raw
                .select('SELECT * FROM outbound_tool_requests')
                .single;
            expect(decision['task_id'], isNull);
            expect(row['task_id'], isNull);
            expect(row['grant_id'], isNull);
            expect(row['authorization_source'], 'manual');
            expect(receipt['authorization_source'], 'manual');
            expect(receipt['review_decision_id'], decision['id']);
            expect(row['review_decision_id'], decision['id']);
            expect(row['payload_digest'], decision['payload_digest']);
            expect(row['state'], 'succeeded');
          }
        },
      );
    }
  }
}
