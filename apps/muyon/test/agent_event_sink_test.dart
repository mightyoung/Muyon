import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/agent_event_sink.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

/// K-3: the loop reports through [AgentEventSink] (ADR-0005 §6.5); K-4's
/// implementation keeps the events in the `task_events` table.
class _CollectingSink implements AgentEventSink {
  final events = <(String, AgentEvent)>[];
  @override
  Future<void> append(String taskId, AgentEvent event) async =>
      events.add((taskId, event));
}

class _BrokenSink implements AgentEventSink {
  @override
  Future<void> append(String taskId, AgentEvent event) async =>
      throw StateError('disk full');
}

/// The timeline from the event table (K-4), in the shape events always had.
List<Map> _events(LoopFixture f, PersonalTask task) => [
  for (final e in f.repo.taskEvents(task.id)) e.toJson(),
];

void main() {
  test(
    'a read task leaves its timeline in the event table: in order, numbered, '
    'with digests and counts and none of the text',
    () async {
      final f = await LoopFixture.open();
      f.replies
        ..add(
          LoopReply.sse(
            sseCalls([('c1', 'read', '{}')], prompt: 400, completion: 20),
          ),
        )
        ..add(
          LoopReply.sse(
            sseText('MODEL-ANSWER-TEXT [r1]', prompt: 600, completion: 30),
          ),
        );
      final agent = f.agent();
      final task = await f.run(agent, await f.start(agent, f.profile()));
      expect(task.state, PersonalTaskState.succeeded);
      final events = _events(f, task);
      expect(events.map((e) => e['type']), [
        'wait',
        'approval',
        'model_request',
        'model_response',
        'tool_proposed',
        'tool_result',
        'wait',
        'approval',
        'model_request',
        'model_response',
        'done',
      ]);
      expect(events.map((e) => e['seq']), [for (var i = 1; i <= 11; i++) i]);
      expect(events.map((e) => e['step']), [
        0,
        0,
        0,
        0,
        1,
        1,
        1,
        1,
        1,
        1,
        2,
      ], reason: 'steps used when it happened');
      final first = events.first['data'] as Map;
      expect(first['stage'], 'model');
      expect(first['requestDigest'], hasLength(64));
      expect(
        (events[1]['data'] as Map)['requestDigest'],
        first['requestDigest'],
      );
      expect((events[2]['data'] as Map)['mode'], 'native');
      expect(events[3]['data'], containsPair('promptTokens', 400));
      expect(events[3]['data'], containsPair('finish', 'toolCalls'));
      expect(events[4]['data'], containsPair('toolId', 'read'));
      expect(events[5]['data'], containsPair('status', 'succeeded'));
      final text = jsonEncode(events);
      expect(text, isNot(contains('MODEL-ANSWER-TEXT')));
      expect(text, isNot(contains(loopKey)));
      expect(text, isNot(contains('actual result')));
    },
  );

  test('a batch leaves one approval and one result per call', () async {
    final f = await LoopFixture.open();
    f.addTool('w1', ToolEffect.write);
    f.addTool('w2', ToolEffect.write);
    f.replies.add(
      LoopReply.sse(sseCalls([('c1', 'w1', '{}'), ('c2', 'w2', '{}')])),
    );
    final agent = f.agent();
    var task = await f.run(agent, await f.start(agent, f.profile()));
    await agent.confirm(
      task.id,
      requestDigest: task.payload['requestDigest'] as String,
    );
    task = f.repo.task(task.id)!;
    final types = _events(f, task).map((e) => e['type']).toList();
    expect(types.where((t) => t == 'tool_proposed'), hasLength(2));
    expect(
      types.where((t) => t == 'approval'),
      hasLength(3),
      reason: 'model + 2 calls',
    );
    expect(types.where((t) => t == 'tool_result'), hasLength(2));
    expect(types.indexOf('wait'), 0);
  });

  test('failures and cancels are events too', () async {
    final f = await LoopFixture.open();
    f.replies.add(LoopReply.sse(sseText('x')));
    final agent = f.agent(maxRounds: 1);
    var task = await f.start(agent, f.profile());
    await agent.cancel(task.id);
    task = f.repo.task(task.id)!;
    expect(_events(f, task).last['type'], 'cancel');

    final g = await LoopFixture.open();
    g.replies.add(LoopReply.sse(sseCalls([('c1', 'read', '{}')])));
    final agent2 = g.agent(maxRounds: 1);
    task = await g.run(agent2, await g.start(agent2, g.profile()));
    expect(task.state, PersonalTaskState.failed);
    final last = _events(g, task).last;
    expect(last['type'], 'error');
    expect((last['data'] as Map)['code'], 'budget_steps');
  });

  test('a snapshot taken before an event cannot drop it', () async {
    final f = await LoopFixture.open();
    final agent = f.agent();
    final task = await f.start(agent, f.profile());
    final stale = f.repo.task(task.id)!;
    await f.repo.appendTaskEvent(task.id, {'type': 'wait'});
    await f.repo.appendTaskEvent(task.id, {'type': 'done'});
    expect(await f.repo.updateTask(stale.copy({'summary': 'later'})), isTrue);
    final after = f.repo.task(task.id)!;
    expect(after.summary, 'later');
    expect(_events(f, after).last['type'], 'done');
    final seqs = _events(f, after).map((e) => e['seq'] as int).toList();
    expect(seqs, [for (var i = 1; i <= seqs.length; i++) i]);
  });

  test('any sink can take the events, and one that cannot write does not '
      'change what the task does', () async {
    final f = await LoopFixture.open();
    f.replies.add(LoopReply.sse(sseText('好')));
    final sink = _CollectingSink();
    final agent = PersonalAgent(
      repository: f.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      tools: f.tools,
      events: sink,
    );
    addTearDown(agent.close);
    var task = await f.run(agent, await f.start(agent, f.profile()));
    expect(task.state, PersonalTaskState.succeeded);
    expect(sink.events.map((e) => e.$2.type), [
      'wait',
      'approval',
      'model_request',
      'model_response',
      'done',
    ]);
    expect(sink.events.every((e) => e.$1 == task.id), isTrue);
    expect(
      task.payload.containsKey('events'),
      isFalse,
      reason: 'not the payload sink',
    );

    final g = await LoopFixture.open();
    g.replies.add(LoopReply.sse(sseText('好')));
    final broken = PersonalAgent(
      repository: g.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: g.ledger),
      tools: g.tools,
      events: _BrokenSink(),
    );
    addTearDown(broken.close);
    task = await g.run(broken, await g.start(broken, g.profile()));
    expect(task.state, PersonalTaskState.succeeded);
  });
}
