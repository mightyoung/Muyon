import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/host_effect_intent.dart';
import 'package:muyon/platform/grants/outbound_content_reviewer.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/tool_names.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

class BarrierReview implements OutboundContentReviewer {
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async {
    entered.complete();
    await release.future;
    return const ReviewDecision.allow();
  }
}

void main() {
  for (final failReviewPersist in [false, true]) {
    test(
      'cancel during post-read local review must not publish a card (persist failure: $failReviewPersist)',
      () async {
        final f = await LoopFixture.open();
        final review = BarrierReview();
        if (failReviewPersist) {
          f.repo.database.raw.execute(
            "CREATE TRIGGER fail_review BEFORE INSERT ON assistant_review_decisions BEGIN SELECT RAISE(ABORT, 'fixture review persistence failure'); END",
          );
        }
        final a = PersonalAgent(
          repository: f.repo,
          tools: f.tools,
          gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
          toolReviewer: review,
        );
        addTearDown(a.close);
        final endpoint = Uri.parse('https://trusted.invalid/rpc');
        var effects = 0;
        f.tools.register(
          providerId: 'host.test',
          descriptor: ToolDescriptor(
            toolId: 'send',
            moduleId: 'test',
            effect: ToolEffect.network,
            parameterSchema: const {
              'type': 'object',
              'properties': {
                'destination': {'type': 'string'},
              },
              'additionalProperties': false,
            },
          ),
          effectIntent: (request, scope) => HostEffectIntent.transport(
            toolId: request.toolId,
            invocationId: request.invocationId,
            endpoint: endpoint,
            endpointIdentity: 'trusted',
            content: utf8.encode('private'),
          ),
          handler: (context) async {
            effects++;
            return ToolCallResult(
              status: ToolCallStatus.succeeded,
              summary: 'sent',
            );
          },
        );
        final conv = await f.repo.createConversation();
        f.replies.add(
          LoopReply.sse(
            sseCalls([
              ('r', encodeToolName('read'), '{}'),
              (
                's',
                encodeToolName('send'),
                jsonEncode({'destination': endpoint.toString()}),
              ),
            ]),
          ),
        );
        final task = await a.start(
          conversationId: conv.id,
          prompt: '执行已注册工具',
          profile: f.profile(),
        );
        final running = a.confirm(
          task.id,
          requestDigest: task.payload['requestDigest'] as String,
        );
        await Future.any([
          review.entered.future,
          running.then(
            (_) => throw StateError(
              'ended before reviewer: ${f.repo.task(task.id)!.state}',
            ),
          ),
        ]).timeout(const Duration(seconds: 5));
        expect(f.repo.task(task.id)!.state, PersonalTaskState.running);
        await a.cancel(task.id);
        expect(
          f.repo.task(task.id)!.stage,
          'cancelling',
          reason: 'public cancel must take its active-tool signal branch',
        );
        review.release.complete();
        await running;
        expect(effects, 0);
        expect(f.approvals(), isEmpty);
        expect(
          f.repo.task(task.id)!.state,
          PersonalTaskState.cancelled,
          reason: 'cancel after read while review awaits must remain terminal',
        );
      },
    );
  }
}
