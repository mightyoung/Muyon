import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/agent_event_sink.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/host_effect_intent.dart';
import 'package:muyon/platform/grants/outbound_content_reviewer.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

/// GB-4 high-risk gaps for `AgentDispatch` (see
/// docs/reviews/2026-10-11-dispatch-turn-characterization.md §4.1 items 1-4).
void main() {
  void register(
    LoopFixture f,
    String id, {
    required String moduleId,
    required ToolEffect effect,
    HostEffectIntent? Function(ToolCallRequest request, ResolvedAssistantScope)?
    intent,
    Future<ToolCallResult?> Function(ToolCallContext context)? onCall,
  }) {
    f.tools.register(
      providerId: 'test',
      descriptor: ToolDescriptor(
        toolId: id,
        moduleId: moduleId,
        effect: effect,
        description: '测试工具 $id',
        parameterSchema: const {
          'type': 'object',
          'properties': {
            'note': {'type': 'string'},
            'destination': {'type': 'string'},
          },
          'additionalProperties': false,
        },
      ),
      effectIntent: intent,
      handler: (context) async {
        f.calls[id] = (f.calls[id] ?? 0) + 1;
        f.order.add(id);
        return await onCall?.call(context) ??
            ToolCallResult(
              status: ToolCallStatus.succeeded,
              summary: 'ran $id',
              data: const {'value': 1},
              objectRefs: [f.ref],
            );
      },
    );
  }

  // A transport intent must match the call's `destination` argument.
  const externalDestination = 'https://example.test/v1';
  HostEffectIntent externalIntent(ToolCallRequest request) =>
      HostEffectIntent.transport(
        toolId: request.toolId,
        invocationId: request.invocationId,
        endpoint: Uri.parse(externalDestination),
        endpointIdentity: 'fixture-external',
        content: utf8.encode('payload'),
      );

  PersonalAgent agentWith(LoopFixture f, {OutboundContentReviewer? reviewer}) {
    final agent = PersonalAgent(
      repository: f.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      tools: f.tools,
      toolReviewer: reviewer,
    );
    addTearDown(agent.close);
    return agent;
  }

  test('tool_result_events_kept_when_task_commit_loses_race', () async {
    final f = await LoopFixture.open();
    late String taskId;
    var armed = false;
    // Move the task out of `running` between the stage check and the commit:
    // scope resolution during the card's prepare throws after the move.
    f.onResolve = (_) {
      if (!armed) return;
      armed = false;
      // The repository reads the task from its payload, so move the payload.
      f.repo.database.raw.execute(
        "UPDATE execution_records SET state='cancelled',"
        "payload=json_set(payload,'\$.state','cancelled') WHERE id=?",
        [taskId],
      );
      throw StateError('scope_moved');
    };
    register(f, 'race_write', moduleId: 'test', effect: ToolEffect.write);
    final agent = agentWith(f);
    f.replies.add(
      LoopReply.sse(sseCalls([('c1', 'race_write', '{"note":"a"}')])),
    );
    final task = await f.start(agent, f.profile());
    taskId = task.id;
    final card = await f.run(agent, task);
    expect(card.payload['error'], isNull);
    expect(card.stage, 'tool');

    armed = true;
    await agent.confirm(
      card.id,
      requestDigest: card.payload['requestDigest'] as String,
    );

    expect(f.callsOf('race_write'), 0, reason: 'the stale call must not run');
    final events = f.repo.database.raw.select(
      'SELECT payload_json FROM task_events WHERE task_id=? AND type=?',
      [taskId, AgentEventType.toolResult],
    );
    expect(events, hasLength(1), reason: 'event survives the lost commit');
    expect(
      (jsonDecode(events.single['payload_json'] as String) as Map)['data'],
      containsPair('status', 'failed'),
    );
  });

  test(
    'external_premark_skips_pure_local_write_but_marks_research_module',
    () async {
      final f = await LoopFixture.open();
      final reviewer = _RecordingReviewer(f.repo);
      register(
        f,
        'research_local',
        moduleId: 'research',
        effect: ToolEffect.write,
        intent: (request, _) => HostEffectIntent.localWrite(
          toolId: request.toolId,
          invocationId: request.invocationId,
          content: const [123, 125],
          sourceObjects: [f.ref],
        ),
      );
      register(
        f,
        'research_external',
        moduleId: 'research',
        effect: ToolEffect.write,
        intent: (request, _) => externalIntent(request),
      );
      final agent = agentWith(f, reviewer: reviewer);
      f.replies.add(
        LoopReply.sse(
          sseCalls([
            ('c1', 'research_local', '{"note":"a"}'),
            (
              'c2',
              'research_external',
              '{"note":"b","destination":"$externalDestination"}',
            ),
          ]),
        ),
      );
      final task = await f.start(agent, f.profile());
      reviewer.taskId = task.id;

      final card = await f.run(agent, task);

      expect(card.payload['error'], isNull);
      expect(card.stage, 'tool');
      expect(
        f.repo.authorizationFacts.readTask(task.id).sourceDigests,
        hasLength(1),
        reason: 'only the non-pure research call is pre-marked',
      );
    },
  );

  test('card_marks_entire_pending_external_union_before_any_review', () async {
    final f = await LoopFixture.open();
    final reviewer = _RecordingReviewer(f.repo);
    for (final id in ['external_a', 'external_b']) {
      register(
        f,
        id,
        moduleId: 'research',
        effect: ToolEffect.write,
        intent: (request, _) => externalIntent(request),
      );
    }
    final agent = agentWith(f, reviewer: reviewer);
    f.replies.add(
      LoopReply.sse(
        sseCalls([
          (
            'c1',
            'external_a',
            '{"note":"a","destination":"$externalDestination"}',
          ),
          (
            'c2',
            'external_b',
            '{"note":"b","destination":"$externalDestination"}',
          ),
        ]),
      ),
    );
    final task = await f.start(agent, f.profile());
    reviewer.taskId = task.id;

    final card = await f.run(agent, task);

    expect(card.payload['error'], isNull);
    expect(card.stage, 'tool');
    expect(reviewer.seen, [
      2,
      2,
    ], reason: 'both calls are marked before the first review');
  });
}

/// Records how many external sources were already persisted at each review.
final class _RecordingReviewer implements OutboundContentReviewer {
  _RecordingReviewer(this.repo);
  final FoundationRepository repo;
  String? taskId;
  final seen = <int>[];

  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async {
    seen.add(repo.authorizationFacts.readTask(taskId!).sourceDigests.length);
    return const ReviewDecision.allow(reviewed: false);
  }
}
