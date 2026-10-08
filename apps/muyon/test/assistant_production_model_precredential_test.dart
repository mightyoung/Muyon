import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/host_ui_grant_authority.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/grants.dart';
import 'package:muyon/platform/grants/host_model_authorization.dart';
import 'package:muyon/platform/grants/tool_grant_context.dart';
import 'package:muyon/services/models/model_gateway.dart';

import 'support/agent_loop_fixture.dart';

class _BarrierReviewer implements OutboundContentReviewer {
  bool hold = false;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async {
    if (hold) {
      entered.complete();
      await release.future;
    }
    return const ReviewDecision.allow();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  for (final revoked in [true, false]) {
    test(
      'actual model grant unavailable during review stops before credentials / revoked=$revoked',
      () async {
        const channel = MethodChannel('com.mightyoung.muyon/secrets');
        final reviewer = _BarrierReviewer();
        final root = Directory.systemTemp.createTempSync(
          'model-review-revoke-',
        );
        final host = await MuyonHost.open(
          root.path,
          localModelReviewer: reviewer,
        );
        final loop = await LoopFixture.open();
        var held = false, newCredentialReads = 0;
        final credentialEntered = Completer<void>();
        final credentialRelease = Completer<String>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async {
              if (!held) {
                return loopKey;
              }
              newCredentialReads++;
              if (!credentialEntered.isCompleted) credentialEntered.complete();
              return credentialRelease.future;
            });
        addTearDown(() async {
          if (!reviewer.release.isCompleted) reviewer.release.complete();
          if (!credentialRelease.isCompleted) {
            credentialRelease.complete(loopKey);
          }
          await host.close();
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
          root.deleteSync(recursive: true);
        });
        final profile = ModelProfile(
          id: 'review-revoke',
          endpoint: loop.profile().endpoint,
          location: ModelLocation.local,
          modelId: 'fixture',
          endpointIdentity: 'actual-review-revoke',
          cloudProxy: true,
          credentialRef: 'key',
          capabilities: loop.profile().capabilities,
        );
        final c = await host.foundation.createConversation();
        loop.replies.add(
          LoopReply.sse(sseText('explicit endpoint authorization')),
        );
        final initial = await host.personalAgent.start(
          conversationId: c.id,
          prompt: 'first request',
          profile: profile,
        );
        expect(initial.state, PersonalTaskState.waitingConfirmation);
        await host.personalAgent.confirm(
          initial.id,
          requestDigest: initial.payload['requestDigest'] as String,
        );
        expect(
          host.foundation.task(initial.id)!.state,
          PersonalTaskState.succeeded,
        );
        final grant = await withConfirmedHostUiGrant(
          (token) => host.assistantGrants.create(
            token: token,
            now: DateTime.now().toUtc(),
            draft: GrantDraft(
              category: 'model',
              toolId: 'assistant.model',
              scopeDigest: toolGrantScopeDigest(c.scope, {
                for (final t in host.tools.list())
                  ...host.tools.authorityModules(t.descriptor.toolId),
              }),
              destination: modelEndpointIdentity(profile),
              duration: GrantDuration.once,
            ),
          ),
        );
        reviewer.hold = true;
        held = true;
        final pending = host.personalAgent.start(
          conversationId: c.id,
          prompt: 'revocation at review boundary',
          profile: profile,
        );
        await reviewer.entered.future;
        if (revoked) {
          await GrantStore(host.foundation.database)
              .revoke(grant.id, now: DateTime.now().toUtc());
        } else {
          final current = host.foundation.tasks().singleWhere(
            (t) => t.prompt == 'revocation at review boundary',
          );
          final consumed = await GrantStore(host.foundation.database).recordUse(
            grant.id,
            GrantRequest(
              category: 'model',
              toolId: 'assistant.model',
              scopeDigest: grant.scopeDigest,
              destination: modelEndpointIdentity(profile),
              taskId: current.id,
              taskTainted: host.foundation.authorizationFacts
                  .readTask(current.id)
                  .requiresConfirmation,
              conversationId: c.id,
              now: DateTime.now().toUtc(),
            ),
          );
          expect(consumed, isNotNull);
        }
        reviewer.release.complete();
        final finished = pending.then((_) => 'settled');
        final boundary = await Future.any([
          finished,
          credentialEntered.future.then((_) => 'credential'),
        ]);
        if (!credentialRelease.isCompleted) credentialRelease.complete(loopKey);
        final ended = await pending;
        expect(
          boundary,
          'settled',
          reason: 'unavailable grant must fail before beginning another credential RPC',
        );
        expect(newCredentialReads, 0);
        expect(ended.state, PersonalTaskState.failed);
        expect(loop.bodies, hasLength(1));
        expect(host.outbound.recent(), hasLength(1));
        expect(host.assistantGrants.list().single.uses, revoked ? 0 : 1);
      },
    );
  }
  test(
    'actual shared-owner late subscriber sees persisted revocation',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'model-revoke-subscribe-',
      );
      final host = await MuyonHost.open(root.path);
      addTearDown(() async {
        await host.close();
        root.deleteSync(recursive: true);
      });
      final conversation = await host.foundation.createConversation();
      final grant = await withConfirmedHostUiGrant(
        (token) => host.assistantGrants.create(
          token: token,
          now: DateTime.now().toUtc(),
          draft: GrantDraft(
            category: 'model',
            toolId: 'assistant.model',
            scopeDigest: toolGrantScopeDigest(conversation.scope, {
              for (final t in host.tools.list())
                ...host.tools.authorityModules(t.descriptor.toolId),
            }),
            destination: 'actual-revocation-subscription',
            duration: GrantDuration.once,
          ),
        ),
      );
      await GrantStore(host.foundation.database)
          .revoke(grant.id, now: DateTime.now().toUtc());
      expect(host.assistantGrants.list().single.revokedAt, isNotNull);
      var notifications = 0;
      final unsubscribe = GrantStore(host.foundation.database)
          .onRevocation(grant.id, () => notifications++);
      addTearDown(unsubscribe);
      expect(notifications, 1);
    },
  );
}
