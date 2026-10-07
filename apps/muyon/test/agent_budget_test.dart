import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/agent_budget.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

/// K-3: step, active-time and token budgets (ADR-0005 §6.1) and the host's
/// summary when one runs out.
class _RecordingGateway extends OpenAiModelGateway {
  _RecordingGateway({super.ledger}) : super(LoopSecrets());
  final limits = <Duration?>[];

  @override
  Stream<ModelEvent> chatStream({
    required ModelProvider provider,
    required ModelRequest request,
    ModelCancellation? cancellation,
    Future<void> Function()? beforeSend,
    Duration? maxDuration,
  }) {
    limits.add(maxDuration);
    return super.chatStream(
      provider: provider,
      request: request,
      cancellation: cancellation,
      beforeSend: beforeSend,
      maxDuration: maxDuration,
    );
  }
}

List<String> _read() => sseCalls([('c1', 'read', '{}')]);

void main() {
  group('steps', () {
    test('the default is 4 steps; maxRounds is an alias of maxSteps', () async {
      final f = await LoopFixture.open();
      expect(f.agent().maxRounds, 4);
      expect(f.agent().budget.maxSteps, 4);
      expect(f.agent(maxRounds: 2).budget.maxSteps, 2);
      expect(f.agent(maxRounds: 2).maxRounds, 2);
      const b = Budget(maxSteps: 7);
      expect(b.maxRounds, 7);
      expect(b.maxTokens, 200000);
      expect(b.maxActive, const Duration(minutes: 10));
    });

    test('running out of steps fails the task with a summary of the '
        'receipts and sends no further request', () async {
      final f = await LoopFixture.open();
      for (var i = 0; i < 6; i++) {
        f.replies.add(LoopReply.sse(_read()));
      }
      final agent = f.agent();
      final task = await f.run(agent, await f.start(agent, f.profile()));
      expect(task.state, PersonalTaskState.failed);
      expect(task.error, contains('轮次'));
      expect(task.error, contains('4/4'));
      expect(task.error, contains('read（succeeded）actual result'));
      expect(task.error, contains('尚未得到最终答案'));
      expect(f.bodies, hasLength(4));
      expect(f.callsOf('read'), 4);
      expect(f.repo.messages(task.conversationId).map((m) => m.role), ['user']);
    });

    test('maxRounds: 1 ends after the first tool result, with the old '
        'wording', () async {
      final f = await LoopFixture.open();
      f.replies.add(LoopReply.sse(_read()));
      final agent = f.agent(maxRounds: 1);
      final task = await f.run(agent, await f.start(agent, f.profile()));
      expect(task.state, PersonalTaskState.failed);
      expect(task.error, contains('轮次'));
      expect(f.bodies, hasLength(1));
    });

    test('a corrective round counts as a step', () async {
      final f = await LoopFixture.open();
      f.replies
        ..add(LoopReply.sse([sseChunk({}, finish: 'stop'), 'data: [DONE]\n\n']))
        ..add(LoopReply.sse(_read()))
        ..add(LoopReply.sse(sseText('不应发送')));
      final agent = f.agent(maxRounds: 2);
      final task = await f.run(agent, await f.start(agent, f.profile()));
      expect(task.payload['protocolCorrections'], 1);
      expect(task.state, PersonalTaskState.failed);
      expect(task.error, contains('轮次'));
      expect(f.bodies, hasLength(2));
      expect(f.callsOf('read'), 1);
    });

    test('a second protocol violation fails with a fixed reason', () async {
      final f = await LoopFixture.open();
      final empty = [sseChunk({}, finish: 'stop'), 'data: [DONE]\n\n'];
      f.replies
        ..add(LoopReply.sse(empty))
        ..add(LoopReply.sse(empty));
      final agent = f.agent(budget: const Budget(maxSteps: 9));
      final task = await f.run(agent, await f.start(agent, f.profile()));
      expect(task.state, PersonalTaskState.failed);
      expect(task.error, contains('Invalid assistant protocol'));
      expect(f.bodies, hasLength(2));
    });
  });

  group('active time', () {
    test(
      'tool time counts; running out ends the task with a summary',
      () async {
        final f = await LoopFixture.open();
        var now = DateTime.utc(2026, 1, 1);
        f.addTool(
          'slow',
          ToolEffect.read,
          onCall: (_) async {
            now = now.add(const Duration(minutes: 6));
            return null;
          },
          summary: 'slow result',
        );
        f.replies
          ..add(LoopReply.sse(sseCalls([('c1', 'slow', '{}')])))
          ..add(LoopReply.sse(sseCalls([('c2', 'slow', '{}')])))
          ..add(LoopReply.sse(sseText('不应发送')));
        final agent = f.agent(clock: () => now);
        final task = await f.run(agent, await f.start(agent, f.profile()));
        expect(task.state, PersonalTaskState.failed);
        expect(task.error, contains('活动时长'));
        expect(task.error, contains('slow（succeeded）slow result'));
        expect(f.bodies, hasLength(2));
        expect(
          BudgetUsage.fromPayload(task.payload).active,
          const Duration(minutes: 12),
        );
      },
    );

    test('time spent waiting for confirmation is not counted', () async {
      final f = await LoopFixture.open();
      var now = DateTime.utc(2026, 1, 1);
      f.replies
        ..add(LoopReply.sse(_read()))
        ..add(LoopReply.sse(sseCalls([('c2', 'read', '{}')])))
        ..add(LoopReply.sse(sseText('成本合计 2080 元')));
      final agent = f.agent(clock: () => now);
      var task = await f.start(agent, f.profile());
      // Three cards, each waited on for 4 minutes (the card lives 5): 12
      // minutes in all, more than the 10-minute active budget.
      for (var i = 0; i < 3; i++) {
        now = now.add(const Duration(minutes: 4));
        await agent.confirm(
          task.id,
          requestDigest: task.payload['requestDigest'] as String,
        );
        task = f.repo.task(task.id)!;
      }
      expect(task.state, PersonalTaskState.succeeded);
      expect(BudgetUsage.fromPayload(task.payload).active, Duration.zero);
    });

    test('one request may take at most what is left of the active budget, '
        'and no more than 5 minutes', () async {
      final f = await LoopFixture.open();
      var now = DateTime.utc(2026, 1, 1);
      f.addTool(
        'slow',
        ToolEffect.read,
        onCall: (_) async {
          now = now.add(const Duration(seconds: 90));
          return null;
        },
      );
      f.replies
        ..add(LoopReply.sse(sseCalls([('c1', 'slow', '{}')])))
        ..add(LoopReply.sse(sseText('好')));
      final gateway = _RecordingGateway(ledger: f.ledger);
      final agent = f.agent(
        clock: () => now,
        gateway: gateway,
        budget: const Budget(maxActive: Duration(minutes: 2)),
      );
      await f.run(agent, await f.start(agent, f.profile()));
      expect(gateway.limits, [
        const Duration(minutes: 2),
        const Duration(seconds: 30),
      ]);
      final f2 = await LoopFixture.open();
      f2.replies.add(LoopReply.sse(sseText('好')));
      final agent2 = f2.agent(gateway: gateway);
      await f2.run(agent2, await f2.start(agent2, f2.profile()));
      expect(gateway.limits.last, const Duration(minutes: 5));
    });
  });

  group('tokens', () {
    test('reported usage is added up; running out ends the task', () async {
      final f = await LoopFixture.open();
      f.replies
        ..add(
          LoopReply.sse(
            sseCalls([('c1', 'read', '{}')], prompt: 600, completion: 500),
          ),
        )
        ..add(LoopReply.sse(sseText('不应发送')));
      final agent = f.agent(budget: const Budget(maxTokens: 1000));
      final task = await f.run(agent, await f.start(agent, f.profile()));
      expect(task.state, PersonalTaskState.failed);
      expect(task.error, contains('token'));
      expect(task.error, contains('1100/1000'));
      expect(task.error, isNot(contains('估算')));
      expect(f.bodies, hasLength(1));
      expect(task.payload['tokensUsed'], 1100);
      expect(task.payload['tokensEstimated'], false);
    });

    test(
      'an endpoint that reports no usage is estimated, and marked',
      () async {
        final f = await LoopFixture.open();
        f.replies
          ..add(LoopReply.sse(_read()))
          ..add(LoopReply.sse(sseText('不应发送')));
        final agent = f.agent(budget: const Budget(maxTokens: 50));
        final task = await f.run(agent, await f.start(agent, f.profile()));
        expect(task.state, PersonalTaskState.failed);
        expect(task.error, contains('含估算'));
        expect(task.payload['tokensEstimated'], true);
        expect(task.payload['tokensUsed'], greaterThan(50));
        expect(f.bodies, hasLength(1));
      },
    );

    test('with little budget left the request is limited to what is left, '
        'and the person sees that limit', () async {
      final f = await LoopFixture.open();
      f.replies
        ..add(
          LoopReply.sse(
            sseCalls([('c1', 'read', '{}')], prompt: 2000, completion: 1000),
          ),
        )
        ..add(LoopReply.sse(sseText('好')));
      final agent = f.agent(budget: const Budget(maxTokens: 10000));
      var task = await f.start(agent, f.profile());
      expect(
        (task.payload['preview'] as Map).containsKey('maxOutputTokens'),
        isFalse,
      );
      task = await f.run(agent, task);
      expect(f.bodies[0].containsKey('max_tokens'), isFalse);
      final cap = f.bodies[1]['max_tokens'] as int;
      expect(cap, lessThanOrEqualTo(7000));
      expect(cap, greaterThan(6000));
      expect(task.state, PersonalTaskState.succeeded);
      // What was sent is what was previewed.
      expect((task.payload['preview'] as Map)['maxOutputTokens'], cap);
    });
  });

  group('closing', () {
    test('closing the host during a stream interrupts the task and the ledger '
        'row is cancelled', () async {
      final f = await LoopFixture.open();
      final hold = Completer<void>();
      f.replies.add(
        LoopReply.sse(sseText('一部分', prompt: 10), hold: hold.future),
      );
      final agent = f.agent();
      final task = await f.start(agent, f.profile());
      final pending = agent
          .confirm(
            task.id,
            requestDigest: task.payload['requestDigest'] as String,
          )
          .catchError((Object _) {});
      while (f.bodies.isEmpty || f.ledger.recent().isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await agent.close();
      hold.complete();
      await pending;
      final after = f.repo.task(task.id)!;
      expect(after.state, PersonalTaskState.interrupted);
      expect(f.ledger.recent().single['status'], 'cancelled');
      expect(f.repo.messages(task.conversationId).map((m) => m.role), ['user']);
      expect(jsonEncode(after.payload), isNot(contains('一部分')));
    });
  });
}
