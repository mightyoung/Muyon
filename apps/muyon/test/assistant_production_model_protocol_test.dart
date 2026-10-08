import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon/platform/grants/outbound_content_reviewer.dart';

import 'support/agent_loop_fixture.dart';

final class VariantReviewer implements OutboundContentReviewer {
  VariantReviewer(this.action);
  final ReviewAction action;
  int calls = 0;
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async {
    calls++;
    if (calls == 1) return const ReviewDecision.allow();
    return switch (action) {
      ReviewAction.allow => const ReviewDecision.allow(),
      ReviewAction.confirm => const ReviewDecision.confirm('confirm variant'),
      ReviewAction.block => const ReviewDecision.block('block variant'),
    };
  }
}

void main() {
  for (final action in ReviewAction.values) {
    test('actual host nonstream compatibility retry / $action', () async {
      final root = Directory.systemTemp.createTempSync('auth-model-retry-');
      final reviewer = VariantReviewer(action);
      final host = await MuyonHost.open(
        root.path,
        localModelReviewer: reviewer,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bodies = <dynamic>[];
      addTearDown(() async {
        await host.close();
        await server.close(force: true);
        root.deleteSync(recursive: true);
      });
      server.listen((request) async {
        bodies.add(jsonDecode(await utf8.decoder.bind(request).join()));
        request.response.statusCode = bodies.length == 1 ? 400 : 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'type': 'answer',
                    'answer': 'compatible done',
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
        id: 'actual-compat',
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1'),
        location: ModelLocation.local,
        modelId: 'm',
        endpointIdentity: 'compat-fixture',
      );
      final c = await host.foundation.createConversation();
      var task = await host.personalAgent.start(
        conversationId: c.id,
        prompt: 'compatible response',
        profile: profile,
      );
      expect(reviewer.calls, 2);
      if (action == ReviewAction.block) {
        expect(task.state, PersonalTaskState.failed);
        expect(bodies, hasLength(1));
        expect(host.outbound.recent(), hasLength(1));
        expect(
          host.foundation.database.raw.select(
            "SELECT * FROM assistant_review_decisions WHERE decision='block'",
          ),
          hasLength(1),
        );
        return;
      }
      if (action == ReviewAction.confirm) {
        expect(task.state, PersonalTaskState.waitingConfirmation);
        expect(bodies, hasLength(1));
        expect(host.outbound.recent(), hasLength(1));
        await host.personalAgent.confirm(
          task.id,
          requestDigest: task.payload['requestDigest'] as String,
        );
        task = host.foundation.task(task.id)!;
      }
      expect(task.state, PersonalTaskState.succeeded, reason: task.error);
      expect(bodies, hasLength(2));
      expect(bodies[0], contains('response_format'));
      expect(bodies[1], isNot(contains('response_format')));
      final rows = host.outbound.recent();
      expect(rows, hasLength(2));
      expect(rows.map((r) => r['status']), ['succeeded', 'failed']);
      expect(rows.map((r) => r['authorization_source']), [
        action == ReviewAction.confirm ? 'manual' : 'mode_auto',
        'mode_auto',
      ]);
      expect(rows.map((r) => r['grant_id']), everyElement(isNull));
      expect(rows[0]['payload_sha256'], isNot(rows[1]['payload_sha256']));
      for (final row in rows) {
        final review = host.foundation.database.raw.select(
          'SELECT * FROM assistant_review_decisions WHERE id=?',
          [row['review_decision_id']],
        ).single;
        expect(review['payload_digest'], row['payload_sha256']);
        expect(review['reviewed'], 0);
      }
    });
  }
  test('actual host same-endpoint summary uses model mode_auto and preserves taint', () async {
    final loop = await LoopFixture.open();
    final root = Directory.systemTemp.createTempSync('auth-model-summary-');
    final host = await MuyonHost.open(root.path);
    addTearDown(() async {
      await host.close();
      root.deleteSync(recursive: true);
    });
    final c = await host.foundation.createConversation();
    for (var i = 0; i < 8; i++) {
      await host.foundation.appendMessage(
        c.id,
        i.isEven ? 'user' : 'assistant',
        'history-$i-${'abcd' * 600}',
      );
    }
    loop.replies.addAll([
      LoopReply.sse(
        sseText(
          '{"goal":"fixture","decisions":"keep","pending":"none","preferences":"concise"}',
        ),
      ),
      LoopReply.sse(sseText('summary then actual answer')),
    ]);
    final task = await host.personalAgent.start(
      conversationId: c.id,
      prompt: 'answer after summary',
      profile: loop.profile(
        capabilities: const ModelCapabilities(
          streaming: true,
          nativeTools: true,
          contextTokens: 12000,
          maxOutputTokens: 512,
          source: CapabilitySource.userDeclared,
        ),
      ),
    );
    expect(
      task.state,
      PersonalTaskState.succeeded,
      reason: jsonEncode({
        'error': task.error,
        'compaction': task.payload['compaction'],
      }),
    );
    expect(loop.bodies, hasLength(2));
    expect(host.outbound.recent().map((r) => r['authorization_source']), [
      'mode_auto',
      'mode_auto',
    ]);
    expect(host.outbound.recent().map((r) => r['caller']), [
      'assistant',
      'context_compaction',
    ]);
    expect(task.payload['compaction'], isNotNull);
    expect(
      host.foundation.authorizationFacts.readTask(task.id).requiresConfirmation,
      isTrue,
      reason: 'unproven old history is not cleared by a host summary',
    );
  });
}
