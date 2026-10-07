import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

/// K-3: several calls in one reply and the batch confirmation card
/// (ADR-0005 §6.3). One click on the card never becomes one approval for
/// several executions (ADR-0002 §3).
List<String> _calls(List<String> names, {String? text}) => sseCalls([
  for (var i = 0; i < names.length; i++) ('c${i + 1}', names[i], '{}'),
], text: text);

Future<LoopFixture> _open({int writes = 3}) async {
  final f = await LoopFixture.open();
  for (var i = 1; i <= writes; i++) {
    f.addTool('w$i', ToolEffect.write, summary: 'wrote $i');
  }
  return f;
}

/// The tool messages the second request carried, by `tool_call_id`.
Map<String, Map> _toolMessages(LoopFixture f, [int request = 1]) => {
  for (final m in f.bodies[request]['messages'] as List)
    if ((m as Map)['role'] == 'tool') m['tool_call_id'] as String: m,
};

Map<String, Object?> _text(Map m) =>
    jsonDecode(m['content'] as String) as Map<String, Object?>;

void main() {
  group('several calls in one reply', () {
    test('reads run in parallel and each call id gets exactly one tool '
        'message, in order', () async {
      final f = await LoopFixture.open();
      final a = Completer<void>(), b = Completer<void>();
      // Each read waits for the other to have started: only parallel
      // execution can finish.
      f.addTool(
        'ra',
        ToolEffect.read,
        onCall: (_) async {
          a.complete();
          await b.future.timeout(const Duration(seconds: 5));
          return null;
        },
        summary: 'A done',
      );
      f.addTool(
        'rb',
        ToolEffect.read,
        onCall: (_) async {
          b.complete();
          await a.future.timeout(const Duration(seconds: 5));
          return null;
        },
        summary: 'B done',
      );
      f.replies
        ..add(LoopReply.sse(_calls(['ra', 'rb'], text: '先查两项')))
        ..add(LoopReply.sse(sseText('成本合计 2080 元 [r1]')));
      final agent = f.agent();
      final task = await f.run(agent, await f.start(agent, f.profile()));
      expect(task.state, PersonalTaskState.succeeded);
      expect(f.callsOf('ra') + f.callsOf('rb'), 2);
      final messages = f.bodies[1]['messages'] as List;
      final assistant =
          messages.firstWhere((m) => (m as Map)['tool_calls'] != null) as Map;
      expect(assistant['content'], '先查两项');
      expect((assistant['tool_calls'] as List).map((c) => c['id']), [
        'c1',
        'c2',
      ]);
      final tools = _toolMessages(f);
      expect(tools.keys, ['c1', 'c2']);
      expect(
        _text(tools['c1']!)['trustedToolResult'],
        containsPair('summary', 'A done'),
      );
      expect(
        _text(tools['c2']!)['trustedToolResult'],
        containsPair('summary', 'B done'),
      );
      // The same reference is one citation.
      expect(task.payload['references'], hasLength(1));
      expect(f.ledger.recent(), hasLength(2));
    });

    test('a read and a write in one reply: the read runs, the write waits on '
        'the card, and the card is the write', () async {
      final f = await _open(writes: 1);
      f.replies
        ..add(LoopReply.sse(_calls(['read', 'w1'])))
        ..add(LoopReply.sse(sseText('好')));
      final agent = f.agent();
      var task = await f.run(agent, await f.start(agent, f.profile()));
      expect(task.state, PersonalTaskState.waitingConfirmation);
      expect(task.stage, 'tool');
      expect(f.callsOf('read'), 1);
      expect(f.callsOf('w1'), 0);
      expect((task.payload['toolCall'] as Map)['toolId'], 'w1');
      expect(task.payload['toolCalls'], hasLength(1));
      await agent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      task = await f.run(agent, f.repo.task(task.id)!);
      expect(task.state, PersonalTaskState.succeeded);
      expect(_toolMessages(f).keys, ['c1', 'c2']);
    });

    test('one bad call spoils the reply: nothing runs, the reply is not '
        'saved and the correction is sent once', () async {
      final f = await _open(writes: 1);
      f.replies
        ..add(LoopReply.sse(_calls(['read', 'nope'])))
        ..add(LoopReply.sse(_calls(['read'])))
        ..add(LoopReply.sse(sseText('好')));
      final agent = f.agent();
      final task = await f.run(agent, await f.start(agent, f.profile()));
      expect(task.state, PersonalTaskState.succeeded);
      expect(task.payload['protocolCorrections'], 1);
      expect(f.callsOf('read'), 1, reason: 'only the second, valid reply ran');
      expect(jsonEncode(f.bodies[1]['messages']), isNot(contains('nope')));
    });

    test(
      'a call that cannot be prepared ends the task before anything runs',
      () async {
        final f = await _open(writes: 1);
        f.replies.add(
          LoopReply.sse(
            sseCalls([('c1', 'read', '{}'), ('c2', 'read', '{"note":5}')]),
          ),
        );
        final agent = f.agent();
        final task = await f.run(agent, await f.start(agent, f.profile()));
        expect(task.state, PersonalTaskState.failed);
        expect(task.error, contains('校验未通过'));
        expect(f.callsOf('read'), 0);
      },
    );

    test('calls past the per-step limit and the card limit come back as not '
        'run, and every call id is still answered', () async {
      final f = await _open(writes: 7);
      f.replies
        ..add(LoopReply.sse(_calls(['w1', 'w2', 'w3', 'w4', 'w5', 'w6', 'w7'])))
        ..add(LoopReply.sse(sseText('好')))
        ..add(LoopReply.sse(_calls([for (var i = 0; i < 10; i++) 'read'])))
        ..add(LoopReply.sse(sseText('好')));
      final agent = f.agent(maxRounds: 6);
      var task = await f.run(agent, await f.start(agent, f.profile()));
      expect(
        task.payload['toolCalls'],
        hasLength(5),
        reason: 'at most 5 on a card',
      );
      await agent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      task = await f.run(agent, f.repo.task(task.id)!);
      expect(task.state, PersonalTaskState.succeeded);
      expect(f.order, ['w1', 'w2', 'w3', 'w4', 'w5']);
      final tools = _toolMessages(f);
      expect(tools.keys, ['c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7']);
      expect(_text(tools['c6']!)['notExecuted'], contains('确认卡'));
      expect(_text(tools['c7']!)['notExecuted'], contains('确认卡'));

      // A second task: ten reads, eight looked at.
      final f2 = await _open(writes: 0);
      f2.replies
        ..add(LoopReply.sse(_calls([for (var i = 0; i < 10; i++) 'read'])))
        ..add(LoopReply.sse(sseText('好')));
      final agent2 = f2.agent();
      final t2 = await f2.run(agent2, await f2.start(agent2, f2.profile()));
      expect(t2.state, PersonalTaskState.succeeded);
      expect(f2.callsOf('read'), 8);
      final tools2 = _toolMessages(f2);
      expect(tools2, hasLength(10));
      expect(_text(tools2['c9']!)['notExecuted'], contains('单步'));
    });
  });

  group('batch confirmation card', () {
    test('every call has its own fields; several calls digest as a list, one '
        'call as its identityDigest', () async {
      final f = await _open();
      f.replies
        ..add(LoopReply.sse(_calls(['w1', 'w2', 'w3'])))
        ..add(LoopReply.sse(_calls(['w1'])));
      final agent = f.agent();
      var task = await f.run(agent, await f.start(agent, f.profile()));
      expect(task.state, PersonalTaskState.waitingConfirmation);
      final calls = (task.payload['toolCalls'] as List).cast<Map>();
      expect(calls.map((c) => c['toolId']), ['w1', 'w2', 'w3']);
      for (final c in calls) {
        expect(c['effect'], 'write');
        expect(c['identityDigest'], isNotEmpty);
        expect(c['scope'], isNotNull);
        expect(c['invocationId'], isNotEmpty);
      }
      expect(
        calls.map((c) => c['invocationId']).toSet(),
        hasLength(3),
        reason: 'host-made, one per call',
      );
      expect(
        task.payload['toolSelection'],
        calls.map((c) => c['invocationId']),
      );
      expect(
        task.payload['requestDigest'],
        PersonalAgent.digest({
          'calls': [for (final c in calls) c['identityDigest']],
        }),
      );
      expect(task.payload['toolIdentityDigest'], calls.first['identityDigest']);
      expect(
        (task.payload['toolCall'] as Map)['invocationId'],
        calls.first['invocationId'],
      );
      expect((task.payload['preview'] as Map)['calls'], hasLength(3));

      // One call: the digest is that call's identityDigest.
      await agent.cancel(task.id);
      final g = await _open(writes: 1);
      g.replies.add(LoopReply.sse(_calls(['w1'])));
      final agent2 = g.agent();
      task = await g.run(agent2, await g.start(agent2, g.profile()));
      expect(task.payload['requestDigest'], task.payload['toolIdentityDigest']);
      expect(task.payload['toolCalls'], hasLength(1));
      expect(task.payload['toolSelection'], hasLength(1));
    });

    test('every selected call has its own one-use approval and receipt, run '
        'one after the other in the model\'s order', () async {
      final f = await _open();
      f.replies
        ..add(LoopReply.sse(_calls(['w1', 'w2', 'w3'])))
        ..add(LoopReply.sse(sseText('已写入')));
      final agent = f.agent();
      var task = await f.run(agent, await f.start(agent, f.profile()));
      final calls = (task.payload['toolCalls'] as List).cast<Map>();
      expect(f.approvals(), isEmpty, reason: 'nothing before the person');
      expect(f.receipts(), isEmpty);
      await agent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      expect(f.order, ['w1', 'w2', 'w3']);
      final approvals = f.approvals();
      expect(approvals, hasLength(3));
      expect(approvals.map((a) => a['state']), everyElement('consumed'));
      expect(
        approvals.map((a) => a['identity_digest']),
        calls.map((c) => c['identityDigest']),
      );
      final receipts = f.receipts();
      expect(receipts, hasLength(3));
      expect(receipts.map((r) => r['state']), everyElement('succeeded'));
      expect(
        receipts.map((r) => r['invocation_id']),
        calls.map((c) => c['invocationId']),
      );
      // Back to the model: under AlwaysConfirmGate every step waits.
      task = f.repo.task(task.id)!;
      expect(task.state, PersonalTaskState.waitingConfirmation);
      expect(task.stage, 'model');
      task = await f.run(agent, task);
      expect(task.state, PersonalTaskState.succeeded);
      expect(_toolMessages(f).keys, ['c1', 'c2', 'c3']);
      // The approval of a card cannot be used a second time.
      await expectLater(
        agent.confirm(
          task.id,
          requestDigest: calls.first['identityDigest'] as String,
        ),
        throwsStateError,
      );
      expect(f.receipts(), hasLength(3));
    });

    test('unticked calls do not run, say so to the model, and a wrong id or '
        'digest changes nothing', () async {
      final f = await _open();
      f.replies
        ..add(LoopReply.sse(_calls(['w1', 'w2', 'w3'])))
        ..add(LoopReply.sse(sseText('好')));
      final agent = f.agent();
      var task = await f.run(agent, await f.start(agent, f.profile()));
      final ids = (task.payload['toolCalls'] as List)
          .map((c) => (c as Map)['invocationId'] as String)
          .toList();
      final digest = task.payload['requestDigest'] as String;
      await expectLater(
        agent.confirm(
          task.id,
          requestDigest: digest,
          selectedInvocationIds: [ids[0], 'not-on-the-card'],
        ),
        throwsArgumentError,
      );
      await expectLater(
        agent.confirm(
          task.id,
          requestDigest: digest,
          selectedInvocationIds: [ids[0], ids[0]],
        ),
        throwsArgumentError,
      );
      await expectLater(
        agent.confirm(
          task.id,
          requestDigest: '0' * 64,
          selectedInvocationIds: ids,
        ),
        throwsStateError,
      );
      expect(
        f.repo.task(task.id)!.state,
        PersonalTaskState.waitingConfirmation,
      );
      expect(f.order, isEmpty);
      await agent.confirm(
        task.id,
        requestDigest: digest,
        selectedInvocationIds: [ids[0], ids[2]],
      );
      expect(f.order, ['w1', 'w3']);
      expect(f.approvals(), hasLength(2));
      task = await f.run(agent, f.repo.task(task.id)!);
      expect(task.state, PersonalTaskState.succeeded);
      final tools = _toolMessages(f);
      expect(tools.keys, ['c1', 'c2', 'c3']);
      expect(_text(tools['c2']!)['notExecuted'], '用户未批准此调用');
      expect(_text(tools['c3']!)['trustedToolResult'], isNotNull);
    });

    test('a selection only means something on a tool card', () async {
      final f = await _open();
      f.replies.add(LoopReply.sse(sseText('好')));
      final agent = f.agent();
      final task = await f.start(agent, f.profile());
      expect(task.stage, 'model');
      await expectLater(
        agent.confirm(
          task.id,
          requestDigest: task.payload['requestDigest'] as String,
          selectedInvocationIds: const ['x'],
        ),
        throwsArgumentError,
      );
      expect(f.bodies, isEmpty);
      expect(
        f.repo.task(task.id)!.state,
        PersonalTaskState.waitingConfirmation,
      );
    });

    test('ticking nothing refuses the whole card', () async {
      final f = await _open();
      f.replies.add(LoopReply.sse(_calls(['w1', 'w2'])));
      final agent = f.agent();
      final task = await f.run(agent, await f.start(agent, f.profile()));
      await agent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
        selectedInvocationIds: const [],
      );
      expect(f.repo.task(task.id)!.state, PersonalTaskState.cancelled);
      expect(f.order, isEmpty);
      expect(f.approvals(), isEmpty);
    });

    test('unticking a call unticks the ones after it, and each can be '
        'ticked again', () {
      const order = ['a', 'b', 'c', 'd'];
      expect(PersonalAgent.toggleSelection(order, order, 'b'), ['a']);
      expect(PersonalAgent.toggleSelection(order, ['a'], 'c'), ['a', 'c']);
      expect(PersonalAgent.toggleSelection(order, ['a', 'c'], 'a'), isEmpty);
      expect(PersonalAgent.toggleSelection(order, order, 'd'), ['a', 'b', 'c']);
      expect(
        () => PersonalAgent.toggleSelection(order, order, 'x'),
        throwsArgumentError,
      );
    });

    test('a call that fails stops the ones after it', () async {
      final f = await _open(writes: 1);
      f.addTool(
        'bad',
        ToolEffect.write,
        onCall: (_) async =>
            ToolCallResult(status: ToolCallStatus.failed, summary: 'disk full'),
      );
      f.addTool('w3', ToolEffect.write);
      f.replies.add(LoopReply.sse(_calls(['w1', 'bad', 'w3'])));
      final agent = f.agent();
      final task = await f.run(agent, await f.start(agent, f.profile()));
      await agent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      final after = f.repo.task(task.id)!;
      expect(after.state, PersonalTaskState.failed);
      expect(after.error, 'disk full');
      expect(f.order, ['w1', 'bad']);
      expect(f.callsOf('w3'), 0);
      expect(
        f.approvals(),
        hasLength(2),
        reason: 'no approval for a call that did not start',
      );
      expect(f.receipts(), hasLength(2));
      expect(f.bodies, hasLength(1), reason: 'no further model request');
    });

    test('an interrupted call ends the task interrupted and starts nothing '
        'after it', () async {
      final f = await _open(writes: 1);
      f.addTool(
        'maybe',
        ToolEffect.write,
        onCall: (c) async {
          c.checkBeforeEffect();
          throw StateError('connection dropped after sending');
        },
      );
      f.addTool('w3', ToolEffect.write);
      f.replies.add(LoopReply.sse(_calls(['w1', 'maybe', 'w3'])));
      final agent = f.agent();
      final task = await f.run(agent, await f.start(agent, f.profile()));
      await agent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      final after = f.repo.task(task.id)!;
      expect(after.state, PersonalTaskState.interrupted);
      expect(after.error, contains('结果未知'));
      expect(f.callsOf('w3'), 0);
      expect(f.receipts().map((r) => r['state']), ['succeeded', 'interrupted']);
    });

    test('a write that changes the scope of the next one makes it fail with '
        'stale_scope and stops the batch', () async {
      final f = await _open(writes: 0);
      f.addTool(
        'first',
        ToolEffect.write,
        onCall: (_) async {
          f.objects = [
            f.ref,
            const ObjectRef(
              moduleId: 'test',
              objectType: 'budget',
              objectId: 'b2',
            ),
          ];
          return null;
        },
      );
      f.addTool('second', ToolEffect.write);
      f.addTool('third', ToolEffect.write);
      f.replies.add(LoopReply.sse(_calls(['first', 'second', 'third'])));
      final agent = f.agent();
      final task = await f.run(agent, await f.start(agent, f.profile()));
      await agent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      final after = f.repo.task(task.id)!;
      expect(after.state, PersonalTaskState.failed);
      expect(after.error, contains('stale_scope'));
      expect(f.order, ['first']);
      expect(
        f.approvals(),
        hasLength(1),
        reason: 'the stale call was never approved',
      );
      expect(f.receipts(), hasLength(1));
    });

    test('an expired card runs nothing, for every call on it', () async {
      final f = await _open();
      var now = DateTime.utc(2026, 1, 1);
      f.replies.add(LoopReply.sse(_calls(['w1', 'w2'])));
      final agent = f.agent(clock: () => now);
      final task = await f.run(agent, await f.start(agent, f.profile()));
      now = now.add(const Duration(minutes: 6));
      await expectLater(
        agent.confirm(
          task.id,
          requestDigest: task.payload['requestDigest'] as String,
        ),
        throwsStateError,
      );
      expect(f.order, isEmpty);
      expect(f.approvals(), isEmpty);
    });

    test('cancelling the task cancels the whole card', () async {
      final f = await _open();
      f.replies.add(LoopReply.sse(_calls(['w1', 'w2'])));
      final agent = f.agent();
      final task = await f.run(agent, await f.start(agent, f.profile()));
      await agent.cancel(task.id);
      expect(f.repo.task(task.id)!.state, PersonalTaskState.cancelled);
      await expectLater(
        agent.confirm(
          task.id,
          requestDigest: task.payload['requestDigest'] as String,
        ),
        throwsStateError,
      );
      expect(f.order, isEmpty);
    });

    test('cancelling while parallel reads run discards their results and '
        'cancels the task', () async {
      final f = await LoopFixture.open();
      final entered = [Completer<void>(), Completer<void>()];
      final release = Completer<void>();
      for (var i = 0; i < 2; i++) {
        f.addTool(
          'slow$i',
          ToolEffect.read,
          onCall: (_) async {
            entered[i].complete();
            await release.future;
            return null;
          },
        );
      }
      f.replies
        ..add(LoopReply.sse(_calls(['slow0', 'slow1'])))
        ..add(LoopReply.sse(sseText('不应发送')));
      final agent = f.agent();
      final task = await f.start(agent, f.profile());
      final running = agent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      await Future.wait(entered.map((e) => e.future));
      await agent.cancel(task.id);
      release.complete();
      await running;
      expect(f.repo.task(task.id)!.state, PersonalTaskState.cancelled);
      expect(f.bodies, hasLength(1));
      expect(f.repo.messages(task.conversationId).map((m) => m.role), ['user']);
    });

    for (final afterEffect in [false, true]) {
      test(
        'a cancel during a card stops the calls not yet started '
        '(${afterEffect ? 'after the effect: interrupted' : 'before it: cancelled'})',
        () async {
          final f = await _open(writes: 0);
          final entered = Completer<void>(), release = Completer<void>();
          f.addTool(
            'first',
            ToolEffect.write,
            onCall: (c) async {
              if (afterEffect) c.checkBeforeEffect();
              entered.complete();
              await release.future;
              return null;
            },
          );
          f.addTool('second', ToolEffect.write);
          f.replies.add(LoopReply.sse(_calls(['first', 'second'])));
          final agent = f.agent();
          final task = await f.run(agent, await f.start(agent, f.profile()));
          final running = agent.confirm(
            task.id,
            requestDigest: task.payload['requestDigest'] as String,
          );
          await entered.future;
          await agent.cancel(task.id);
          release.complete();
          await running;
          final after = f.repo.task(task.id)!;
          expect(
            after.state,
            afterEffect
                ? PersonalTaskState.interrupted
                : PersonalTaskState.cancelled,
          );
          expect(f.order, ['first']);
          expect(f.callsOf('second'), 0);
          expect(f.receipts(), hasLength(1));
          expect(
            f.bodies,
            hasLength(1),
            reason: 'no model request after a cancel',
          );
        },
      );
    }
  });
}
