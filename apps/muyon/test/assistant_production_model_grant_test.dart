import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/host_ui_grant_authority.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/grant.dart';
import 'package:muyon/platform/grants/grant_store.dart';
import 'package:muyon/platform/grants/host_authorization_policy.dart';
import 'package:muyon/platform/grants/host_model_authorization.dart';
import 'package:muyon/platform/grants/tool_grant_context.dart';
import 'package:muyon/platform/grants/outbound_content_reviewer.dart';
import 'package:muyon/services/models/model_gateway.dart';

import 'support/agent_loop_fixture.dart';

String scopeFor(MuyonHost host, AssistantConversation conversation) =>
    toolGrantScopeDigest(conversation.scope, {
      for (final t in host.tools.list())
        ...host.tools.authorityModules(t.descriptor.toolId),
    });
ModelProfile proxyProfile(LoopFixture loop) => ModelProfile(
  id: 'fixture-proxy',
  endpoint: loop.profile().endpoint,
  location: ModelLocation.local,
  modelId: 'm',
  endpointIdentity: 'actual-proxy-fixture',
  cloudProxy: true,
  capabilities: loop.profile().capabilities,
);
Future<void> authorizeEndpoint(
  MuyonHost host,
  LoopFixture loop,
  AssistantConversation c,
  ModelProfile profile,
) async {
  loop.replies.add(LoopReply.sse(sseText('first explicit request done')));
  final first = await host.personalAgent.start(
    conversationId: c.id,
    prompt: 'first explicit request',
    profile: profile,
  );
  expect(first.state, PersonalTaskState.waitingConfirmation);
  expect(loop.bodies, isEmpty);
  await host.personalAgent.confirm(
    first.id,
    requestDigest: first.payload['requestDigest'] as String,
  );
  expect(host.foundation.task(first.id)!.state, PersonalTaskState.succeeded);
  expect(host.outbound.recent().single['authorization_source'], 'manual');
}

Future<AssistantGrant> once(
  MuyonHost host,
  AssistantConversation c,
  ModelProfile profile,
) => withConfirmedHostUiGrant(
  (token) => host.assistantGrants.create(
    token: token,
    now: DateTime.now().toUtc(),
    draft: GrantDraft(
      category: 'model',
      toolId: 'assistant.model',
      scopeDigest: scopeFor(host, c),
      destination: modelEndpointIdentity(profile),
      duration: GrantDuration.once,
    ),
  ),
);

final class LastUseReviewer implements OutboundContentReviewer {
  bool concurrent = false;
  int arrivals = 0;
  final release = Completer<void>();
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async {
    if (concurrent) {
      if (++arrivals == 2) release.complete();
      await release.future;
    }
    return const ReviewDecision.allow();
  }
}

void main() {
  test(
    'actual compatibility retry consumes its one-use model grant only once',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'auth-model-grant-retry-',
      );
      final host = await MuyonHost.open(root.path);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bodies = <dynamic>[];
      addTearDown(() async {
        await host.close();
        await server.close(force: true);
        root.deleteSync(recursive: true);
      });
      server.listen((request) async {
        bodies.add(jsonDecode(await utf8.decoder.bind(request).join()));
        request.response.statusCode = bodies.length == 2 ? 400 : 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'type': 'answer',
                    'answer': 'actual compatibility result',
                    'citationIds': [],
                  }),
                },
                'finish_reason': 'stop',
              },
            ],
          }),
        );
        await request.response.close();
      });
      final profile = ModelProfile(
        id: 'grant-retry',
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1'),
        location: ModelLocation.local,
        modelId: 'm',
        endpointIdentity: 'actual-grant-retry',
        cloudProxy: true,
      );
      final c = await host.foundation.createConversation();
      final first = await host.personalAgent.start(
        conversationId: c.id,
        prompt: 'first explicit endpoint request',
        profile: profile,
      );
      expect(first.state, PersonalTaskState.waitingConfirmation);
      await host.personalAgent.confirm(
        first.id,
        requestDigest: first.payload['requestDigest'] as String,
      );
      expect(
        host.foundation.task(first.id)!.state,
        PersonalTaskState.succeeded,
      );
      final grant = await once(host, c, profile);
      final retried = await host.personalAgent.start(
        conversationId: c.id,
        prompt: 'retry JSON response format at actual known endpoint',
        profile: profile,
      );
      expect(retried.state, PersonalTaskState.succeeded, reason: retried.error);
      expect(bodies, hasLength(3));
      expect(bodies[1], contains('response_format'));
      expect(bodies[2], isNot(contains('response_format')));
      final rows = host.outbound
          .recent()
          .where((r) => r['grant_id'] == grant.id)
          .toList();
      expect(rows, hasLength(2));
      expect(rows.map((r) => r['status']), ['succeeded', 'failed']);
      expect(rows.map((r) => r['authorization_source']), ['grant', 'grant']);
      expect(rows.map((r) => r['review_decision_id']).toSet(), hasLength(2));
      expect(host.assistantGrants.list().single.uses, 1);
      expect(
        host.assistantGrants
            .audit(grant.id)
            .where((r) => r['action'] == 'used'),
        hasLength(1),
      );
    },
  );
  test('actual model ledger composition permits exactly one concurrent final grant use', () async {
    final loop = await LoopFixture.open();
    final root = Directory.systemTemp.createTempSync('auth-model-last-use-');
    final reviewer = LastUseReviewer();
    final host = await MuyonHost.open(root.path, localModelReviewer: reviewer);
    addTearDown(() async {
      await host.close();
      root.deleteSync(recursive: true);
    });
    final c = await host.foundation.createConversation();
    final profile = proxyProfile(loop);
    await authorizeEndpoint(host, loop, c, profile);
    final grant = await once(host, c, profile);
    reviewer.concurrent = true;
    loop.replies.add(LoopReply.sse(sseText('one actual final use')));
    final results = await Future.wait([
      host.personalAgent.start(
        conversationId: c.id,
        prompt: 'concurrent first',
        profile: profile,
      ),
      host.personalAgent.start(
        conversationId: c.id,
        prompt: 'concurrent second',
        profile: profile,
      ),
    ]);
    expect(
      results.map((r) => r.state),
      unorderedEquals([PersonalTaskState.succeeded, PersonalTaskState.failed]),
    );
    expect(host.assistantGrants.list().single.uses, 1);
    expect(
      host.assistantGrants.audit(grant.id).where((a) => a['action'] == 'used'),
      hasLength(1),
    );
    expect(loop.bodies, hasLength(2));
    expect(host.outbound.recent(), hasLength(2));
    expect(
      host.outbound.recent().where((r) => r['grant_id'] == grant.id),
      hasLength(1),
    );
  });
  for (final mode in ['normal', 'insert-failure', 'other-profile']) {
    final triggerFailure = mode == 'insert-failure';
    test(
      'actual host known endpoint one-use model grant / mode=$mode',
      () async {
        final loop = await LoopFixture.open();
        final root = Directory.systemTemp.createTempSync('auth-model-grant-');
        final host = await MuyonHost.open(root.path);
        addTearDown(() async {
          await host.close();
          root.deleteSync(recursive: true);
        });
        final c = await host.foundation.createConversation();
        final profile = proxyProfile(loop);
        await authorizeEndpoint(host, loop, c, profile);
        final grant = await once(host, c, profile);
        if (mode == 'other-profile') {
          loop.replies.add(
            LoopReply.sse(sseText('new profile fixture response')),
          );
          final other = ModelProfile(
            id: 'distinct-actual-profile',
            endpoint: profile.endpoint,
            location: profile.location,
            modelId: profile.modelId,
            endpointIdentity: profile.endpointIdentity,
            cloudProxy: true,
            capabilities: profile.capabilities,
          );
          final fresh = await host.personalAgent.start(
            conversationId: c.id,
            prompt: 'first request at a distinct complete profile identity',
            profile: other,
          );
          expect(fresh.state, PersonalTaskState.waitingConfirmation);
          expect(host.assistantGrants.list().single.uses, 0);
          expect(loop.bodies, hasLength(1));
          return;
        }
        if (triggerFailure) {
          await host.foundation.database.write(
            (db) => db.execute(
              "CREATE TRIGGER auth_model_insert_fail BEFORE INSERT ON outbound_requests BEGIN SELECT RAISE(ABORT,'fixture outbound insert rejected'); END",
            ),
          );
        }
        loop.replies.add(LoopReply.sse(sseText('second actual request done')));
        final second = await host.personalAgent.start(
          conversationId: c.id,
          prompt: 'repeat at known full endpoint',
          profile: profile,
        );
        expect(
          second.state,
          triggerFailure
              ? PersonalTaskState.failed
              : PersonalTaskState.succeeded,
        );
        final stored = host.assistantGrants.list().single;
        expect(stored.id, grant.id);
        expect(stored.uses, triggerFailure ? 0 : 1);
        expect(
          host.assistantGrants
              .audit(grant.id)
              .where((a) => a['action'] == 'used'),
          hasLength(triggerFailure ? 0 : 1),
        );
        expect(loop.bodies, hasLength(triggerFailure ? 1 : 2));
        expect(host.outbound.recent(), hasLength(triggerFailure ? 1 : 2));
        if (!triggerFailure) {
          final row = host.outbound.recent().first;
          expect(row['authorization_source'], 'grant');
          expect(row['grant_id'], grant.id);
          expect(row['review_decision_id'], isNotNull);
          final third = await host.personalAgent.start(
            conversationId: c.id,
            prompt: 'spent grant cannot replay',
            profile: profile,
          );
          expect(third.state, PersonalTaskState.waitingConfirmation);
          expect(loop.bodies, hasLength(2));
          expect(host.assistantGrants.list().single.uses, 1);
        }
      },
    );
  }
  for (final revokeGrant in [true, false]) {
    test(
      'actual host stops held HTTP stream on shared-owner revocation / grant=$revokeGrant',
      () async {
        final loop = await LoopFixture.open();
        final root = Directory.systemTemp.createTempSync('auth-model-revoke-');
        final host = await MuyonHost.open(root.path);
        final release = Completer<void>();
        addTearDown(() async {
          if (!release.isCompleted) release.complete();
          await host.close();
          root.deleteSync(recursive: true);
        });
        final c = await host.foundation.createConversation();
        final profile = revokeGrant ? proxyProfile(loop) : loop.profile();
        AssistantGrant? grant;
        if (revokeGrant) {
          await authorizeEndpoint(host, loop, c, profile);
          grant = await once(host, c, profile);
        }
        loop.replies.add(
          LoopReply.sse(
            sseText('in-flight fixture response'),
            hold: release.future,
          ),
        );
        final receiving = host.personalAgent.drafts.firstWhere(
          (d) => d.text.contains('in-flight'),
        );
        final pending = host.personalAgent.start(
          conversationId: c.id,
          prompt: 'request to cancel in-flight',
          profile: profile,
        );
        await receiving.timeout(const Duration(seconds: 5));
        final taskId = host.foundation.tasks(conversationId: c.id).first.id;
        if (revokeGrant) {
          await GrantStore(host.foundation.database)
              .revoke(grant!.id, now: DateTime.now().toUtc());
        } else {
          await withConfirmedHostUiGrant(
            (token) => HostAuthorizationPolicy(host.foundation.database).update(
              token: token,
              mode: AssistantAuthorizationMode.standard,
              enabled: Set.of(AssistantAuthorizationCategory.values)
                ..remove(AssistantAuthorizationCategory.model),
            ),
          );
        }
        // Deadlock protection: the endpoint intentionally never sends another
        // chunk until teardown, so cancellation must settle without that chunk.
        final result = await pending.timeout(
          const Duration(seconds: 2),
          onTimeout: () => host.foundation.task(taskId)!,
        );
        expect(result.state, PersonalTaskState.failed);
        expect(host.outbound.recent().first['status'], 'cancelled');
        expect(loop.bodies, hasLength(revokeGrant ? 2 : 1));
        if (revokeGrant) expect(host.assistantGrants.list().single.uses, 1);
        expect(
          host.foundation
              .messages(c.id)
              .where((m) => m.content.contains('in-flight fixture response')),
          isEmpty,
        );
      },
    );
  }
}
