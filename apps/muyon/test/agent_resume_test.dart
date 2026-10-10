import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/agent_budget.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

/// K-4: resuming from the last checkpoint never runs again what a receipt
/// shows ran, never replays what may have run, and never skips an approval.
Future<void> _crash(LoopFixture f, String id, String state) =>
    f.repo.database.write(
      (db) => db.execute(
        "UPDATE execution_records SET state=?1,payload=json_set(payload,"
        "'\$.state',?1,'\$.stage',?1) WHERE id=?2",
        [state, id],
      ),
    );

/// A receipt row as the registry leaves it: [result] null = mid-call.
void _receipt(
  LoopFixture f,
  Map call,
  String state, {
  ToolCallResult? result,
  String? identityDigest,
}) => f.repo.database.raw.execute(
  'INSERT INTO tool_invocation_receipts(replay_key,invocation_id,identity_digest,tool_id,state,result_json) VALUES(?,?,?,?,?,?)',
  [
    call['invocationId'],
    call['invocationId'],
    identityDigest ?? call['identityDigest'] ?? 'digest',
    call['toolId'],
    state,
    result == null ? null : jsonEncode(result.toJson()),
  ],
);

/// Runs a call as the loop would have, so the registry holds its receipt.
Future<ToolCallResult> _execute(
  LoopFixture f,
  PersonalTask task,
  Map call,
) async {
  final request = ToolCallRequest(
    invocationId: call['invocationId'] as String,
    toolId: call['toolId'] as String,
    scope: task.scope,
    parameters: Map<String, Object?>.from(call['parameters'] as Map),
    destination: call['destination'] as String?,
  );
  final approval = await f.tools.approve(await f.tools.prepare(request));
  return f.tools.invoke(request.withApproval(approval));
}

Future<(LoopFixture, PersonalAgent, PersonalTask)> _twoWrites() async {
  final f = await LoopFixture.open();
  f.addTool('w1', ToolEffect.write);
  f.addTool('w2', ToolEffect.write);
  f.replies.add(
    LoopReply.sse(sseCalls([('c1', 'w1', '{}'), ('c2', 'w2', '{}')])),
  );
  final agent = f.agent();
  final task = await f.run(agent, await f.start(agent, f.profile()));
  expect(task.stage, 'tool');
  return (f, agent, task);
}

List<String> _types(LoopFixture f, String id) => [
  for (final e in f.repo.taskEvents(id)) e.type,
];

void main() {
  group('historical invocation identity', () {

    for (final manual in [true, false]) {
      for (final field in ['invocationId', 'toolId']) {
        test('${manual ? 'manual' : 'model'} rejects invalid $field clearly',
            () async {
          final f = await LoopFixture.open();
          final agent = f.agent();
          final conversation = await f.repo.createConversation();
          final PersonalTask task;
          if (manual) {
            task = await agent.startTool(
              conversationId: conversation.id, toolId: 'write',
            );
          } else {
            f.replies.add(LoopReply.sse(sseCalls([('c1', 'write', '{}')])));
            task = await f.run(agent, await f.start(agent, f.profile()));
          }
          await agent.cancel(task.id);
          await _crash(f, task.id, 'interrupted');
          await f.repo.database.write((db) => db.execute(
            "UPDATE execution_records SET payload=json_set(payload,?,17) "
            "WHERE id=?",
            [manual ? '\$.toolCall.$field' : '\$.step.calls[0].$field', task.id],
          ));
          await expectLater(agent.resume(task.id), throwsA(isA<StateError>()
              .having((e) => e.message, 'message',
                  contains('resume_invalid_call_identity'))));
          expect(f.callsOf('write'), 0);
          expect(f.approvals(), isEmpty);
        });
      }
    }

    for (final manual in [true, false]) {
      for (final changed in ['parameters', 'scope', 'destination']) {
        test('${manual ? 'manual' : 'model'} rejects a same-tool receipt '
            'for different $changed', () async {
          final f = await LoopFixture.open();
          final agent = f.agent();
          final conversation = await f.repo.createConversation();
          final PersonalTask task;
          if (manual) {
            task = await agent.startTool(
              conversationId: conversation.id,
              toolId: 'write',
            );
          } else {
            f.replies.add(LoopReply.sse(sseCalls([('c1', 'write', '{}')])));
            task = await f.run(agent, await f.start(agent, f.profile()));
          }
          final call = manual
              ? task.payload['toolCall'] as Map
              : ((task.payload['step'] as Map)['calls'] as List).first as Map;
          final original = await f.tools.prepare(ToolCallRequest(
            invocationId: call['invocationId'] as String,
            toolId: 'write',
            scope: task.scope,
            parameters: const {},
          ));
          if (changed == 'scope') f.objects = [];
          final foreign = await f.tools.prepare(ToolCallRequest(
            invocationId: call['invocationId'] as String,
            toolId: 'write',
            scope: task.scope,
            parameters: changed == 'parameters' ? {'note': 'other'} : const {},
            destination: changed == 'destination' ? 'https://other.test' : null,
          ));
          expect(foreign.identityDigest, isNot(original.identityDigest));
          _receipt(f, {...call, 'identityDigest': foreign.identityDigest},
            'succeeded', result: ToolCallResult(
              status: ToolCallStatus.succeeded,
              summary: 'foreign result must not be adopted',
            ));
          await agent.cancel(task.id);
          await _crash(f, task.id, 'interrupted');
          final approvals = f.approvals().length;
          final held = await agent.resume(task.id);
          expect(held.stage, 'resume');
          expect(held.state, PersonalTaskState.waitingConfirmation);
          expect(held.waitingFor, contains('身份'));
          expect(f.repo.taskEvents(held.id).first.data['adopted'], 0);
          expect(jsonEncode(held.payload['messages']),
              isNot(contains('foreign result must not be adopted')));
          expect(f.callsOf('write'), 0);
          expect(f.approvals(), hasLength(approvals));
        });
      }

      for (final digest in [null, '', 'not-a-digest', 17]) {
        test('${manual ? 'manual' : 'model'} holds missing or malformed '
            'historical digest $digest', () async {
          final f = await LoopFixture.open();
          final agent = f.agent();
          final conversation = await f.repo.createConversation();
          final PersonalTask task;
          if (manual) {
            task = await agent.startTool(
              conversationId: conversation.id,
              toolId: 'write',
            );
          } else {
            f.replies.add(LoopReply.sse(sseCalls([('c1', 'write', '{}')])));
            task = await f.run(agent, await f.start(agent, f.profile()));
          }
          final call = manual
              ? task.payload['toolCall'] as Map
              : ((task.payload['step'] as Map)['calls'] as List).first as Map;
          final prepared = await f.tools.prepare(ToolCallRequest(
            invocationId: call['invocationId'] as String,
            toolId: 'write',
            scope: task.scope,
          ));
          _receipt(f, {...call, 'identityDigest': prepared.identityDigest},
            'succeeded', result: ToolCallResult(
              status: ToolCallStatus.succeeded, summary: 'unverified result',
            ));
          await agent.cancel(task.id);
          await _crash(f, task.id, 'interrupted');
          await f.repo.database.write((db) => db.execute(
            "UPDATE execution_records SET payload=json_set(payload,?,?) "
            "WHERE id=?",
            [manual ? '\$.toolIdentityDigest' : '\$.step.calls[0].identityDigest',
              digest, task.id],
          ));
          final held = await agent.resume(task.id);
          expect(held.stage, 'resume');
          expect(held.waitingFor, contains('身份'));
          expect(f.repo.taskEvents(held.id).first.data['adopted'], 0);
          expect(f.callsOf('write'), 0);
        });
      }
    }
  });

  for (final effect in [ToolEffect.export, ToolEffect.network]) {
    test('unknown ${effect.name} with missing identity never replays', () async {
      final f = await LoopFixture.open();
      f.addTool('external', effect);
      final agent = f.agent();
      final conversation = await f.repo.createConversation();
      final task = await agent.startTool(
        conversationId: conversation.id, toolId: 'external',
        destination: 'https://example.test/receive',
      );
      _receipt(f, task.payload['toolCall'] as Map, 'running',
          identityDigest: task.payload['toolIdentityDigest'] as String);
      await agent.cancel(task.id);
      await _crash(f, task.id, 'interrupted');
      await f.repo.database.write((db) => db.execute(
        "UPDATE execution_records SET payload=json_remove(payload,"
        "'\$.toolIdentityDigest') WHERE id=?", [task.id],
      ));
      var held = await agent.resume(task.id);
      expect(held.stage, 'resume');
      expect(held.waitingFor, contains('身份'));
      expect(f.callsOf('external'), 0);
      expect(f.approvals(), isEmpty);
      await agent.confirm(held.id,
          requestDigest: held.payload['requestDigest'] as String);
      held = f.repo.task(held.id)!;
      expect(held.stage, 'tool');
      expect(held.state, PersonalTaskState.waitingConfirmation);
      expect(f.callsOf('external'), 0);
      expect(f.approvals(), isEmpty);
    });
  }

  group('a manual tool run', () {
    test('with a successful receipt is taken over, not run again, and asks '
        'for no approval', () async {
      final f = await LoopFixture.open();
      final agent = f.agent();
      final conversation = await f.repo.createConversation();
      var task = await agent.startTool(
        conversationId: conversation.id,
        toolId: 'write',
      );
      await agent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      expect(f.callsOf('write'), 1);
      final approvals = f.approvals().length;
      // The process died after the receipt, before the task said so.
      await _crash(f, task.id, 'interrupted');
      final next = await agent.resume(task.id);
      expect(f.callsOf('write'), 1, reason: 'not executed again');
      expect(f.approvals(), hasLength(approvals), reason: 'no new approval');
      expect(next.id, isNot(task.id));
      expect(next.previousAttemptId, task.id);
      expect(next.state, PersonalTaskState.succeeded);
      final events = f.repo.taskEvents(next.id);
      expect(events.map((e) => e.type), ['resume', 'tool_result', 'done']);
      expect(events.first.data['outcome'], 'reused');
      expect(events[1].data['reused'], true);
      expect(f.repo.taskObjects(next.id), isNotEmpty);
    });

    test('whose receipt says it may have run stops at a confirmation with the '
        'reason; only a person moves it on, and then by a new card', () async {
      final f = await LoopFixture.open();
      final agent = f.agent();
      final conversation = await f.repo.createConversation();
      final task = await agent.startTool(
        conversationId: conversation.id,
        toolId: 'write',
      );
      // A receipt that never got its outcome.
      _receipt(f, task.payload['toolCall'] as Map, 'running',
        identityDigest: task.payload['toolIdentityDigest'] as String);
      await agent.cancel(task.id);
      await _crash(f, task.id, 'interrupted');
      final approvals = f.approvals().length;

      var held = await agent.resume(task.id);
      expect(held.state, PersonalTaskState.waitingConfirmation);
      expect(held.stage, 'resume');
      expect(held.waitingFor, contains('write'));
      expect(held.waitingFor, contains('结果未知'));
      expect(f.callsOf('write'), 0);
      expect(f.approvals(), hasLength(approvals));
      expect(_types(f, held.id), ['resume', 'wait']);

      // It moves only on a person's confirmation, of this exact stop.
      await expectLater(
        agent.confirm(held.id, requestDigest: 'wrong'),
        throwsStateError,
      );
      await agent.confirm(
        held.id,
        requestDigest: held.payload['requestDigest'] as String,
      );
      held = f.repo.task(held.id)!;
      expect(held.state, PersonalTaskState.waitingConfirmation);
      expect(held.stage, 'tool', reason: 'a new card, new approval');
      expect(f.callsOf('write'), 0, reason: 'still not run');
      expect(f.approvals(), hasLength(approvals));
      expect(
        (held.payload['toolCall'] as Map)['invocationId'],
        isNot((task.payload['toolCall'] as Map)['invocationId']),
      );
      await agent.confirm(
        held.id,
        requestDigest: held.payload['requestDigest'] as String,
      );
      expect(f.callsOf('write'), 1);
      expect(f.approvals(), hasLength(approvals + 1));
    });

    test(
      'whose receipt belongs to another tool is not taken over: a stop',
      () async {
        final f = await LoopFixture.open();
        final agent = f.agent();
        final conversation = await f.repo.createConversation();
        final task = await agent.startTool(
          conversationId: conversation.id,
          toolId: 'write',
        );
        _receipt(
          f,
          {...(task.payload['toolCall'] as Map), 'toolId': 'read'},
          'succeeded',
          result: ToolCallResult(
            status: ToolCallStatus.succeeded,
            summary: 's',
          ),
        );
        await agent.cancel(task.id);
        await _crash(f, task.id, 'interrupted');
        final held = await agent.resume(task.id);
        expect(held.state, PersonalTaskState.waitingConfirmation);
        expect(held.stage, 'resume');
        expect(f.callsOf('write'), 0);
        expect(f.callsOf('read'), 0);
      },
    );

    test('with no receipt, or one that failed without effect, starts again as '
        'before', () async {
      final f = await LoopFixture.open();
      final agent = f.agent();
      final conversation = await f.repo.createConversation();
      final task = await agent.startTool(
        conversationId: conversation.id,
        toolId: 'write',
      );
      await agent.pause(task.id);
      var next = await agent.resume(task.id);
      expect(next.state, PersonalTaskState.waitingConfirmation);
      expect(next.stage, 'tool');
      await agent.pause(next.id);
      _receipt(
        f,
        task.payload['toolCall'] as Map,
        'failed',
        result: ToolCallResult(
          status: ToolCallStatus.failed,
          summary: 'stale_scope',
        ),
      );
      next = await agent.resume(next.id);
      expect(next.stage, 'tool');
      expect(f.callsOf('write'), 0);
    });
  });

  group('a model task', () {

    test('an unverified read receipt is held rather than adopted', () async {
      final f = await LoopFixture.open();
      f.replies.add(LoopReply.sse(
          sseCalls([('c1', 'read', '{}'), ('c2', 'write', '{}')])));
      final agent = f.agent();
      final task = await f.run(agent, await f.start(agent, f.profile()));
      final call = ((task.payload['step'] as Map)['calls'] as List)
          .cast<Map>().first;
      await f.repo.database.write((db) => db.execute(
        "UPDATE tool_invocation_receipts SET identity_digest='' "
        "WHERE invocation_id=?", [call['invocationId']],
      ));
      await agent.cancel(task.id);
      await _crash(f, task.id, 'interrupted');
      final held = await agent.resume(task.id);
      expect(held.stage, 'resume');
      expect(held.waitingFor, contains('身份'));
      expect(f.repo.taskEvents(held.id).first.data['adopted'], 0);
      expect(f.callsOf('read'), 1);
      expect(f.callsOf('write'), 0);
      expect(f.bodies, hasLength(1));
    });

    test('successful historical receipts survive current scope and registry '
        'changes', () async {
      final (f, agent, task) = await _twoWrites();
      final calls = (task.payload['toolCalls'] as List).cast<Map>();
      await agent.cancel(task.id);
      await _execute(f, task, calls[0]);
      f.objects = [];
      f.tools.setAvailability('w1', available: false);
      await _crash(f, task.id, 'interrupted');
      final next = await agent.resume(task.id);
      expect(next.stage, 'model');
      expect(f.repo.taskEvents(next.id).first.data['adopted'], 1);
      expect(f.callsOf('w1'), 1);
      expect(f.callsOf('w2'), 0);
    });

    for (final failedReceipt in [false, true]) {
      test('prepared calls preserve spent budget with '
          '${failedReceipt ? 'a failed' : 'no'} receipt', () async {
        final f = await LoopFixture.open();
        f.replies.add(LoopReply.sse(sseCalls([('c1', 'write', '{}')],
            prompt: 100, completion: 50)));
        final agent = f.agent(maxRounds: 1);
        final task = await f.run(agent, await f.start(agent, f.profile()));
        final call = ((task.payload['step'] as Map)['calls'] as List).first as Map;
        if (failedReceipt) {
          _receipt(f, call, 'failed', result: ToolCallResult(
            status: ToolCallStatus.failed, summary: 'failed before effect',
          ));
        }
        await agent.cancel(task.id);
        await _crash(f, task.id, 'interrupted');
        final usage = BudgetUsage.fromPayload(task.payload).toPayload();
        var next = await agent.resume(task.id);
        expect(next.state, PersonalTaskState.failed);
        expect(next.error, contains('轮次'));
        expect(BudgetUsage.fromPayload(next.payload).toPayload(), usage);
        expect(jsonEncode(next.payload['messages']), contains('notExecuted'));
        expect(f.repo.taskEvents(next.id).first.data['pending'], 1);
        next = await agent.resume(next.id);
        expect(next.state, PersonalTaskState.failed);
        expect(BudgetUsage.fromPayload(next.payload).toPayload(), usage);
        expect(f.callsOf('write'), 0);
        expect(f.approvals(), isEmpty);
        expect(f.bodies, hasLength(1));
      });
    }

    test('steps, time and tokens accumulate across repeated resumes', () async {
      final f = await LoopFixture.open();
      var now = DateTime.utc(2026, 10, 10);
      f.addTool('timed', ToolEffect.write, onCall: (_) async {
        now = now.add(const Duration(seconds: 20));
        return null;
      });
      f.replies
        ..add(LoopReply.sse(sseCalls([('c1', 'timed', '{}')],
            prompt: 100, completion: 50)))
        ..add(LoopReply.sse(sseCalls([('c2', 'timed', '{}')],
            prompt: 100, completion: 50)));
      final agent = f.agent(clock: () => now);
      var task = await f.run(agent, await f.start(agent, f.profile()));
      await agent.confirm(task.id,
          requestDigest: task.payload['requestDigest'] as String);
      task = f.repo.task(task.id)!;
      expect(BudgetUsage.fromPayload(task.payload).toPayload(), {
        'round': 1, 'activeMs': 20000, 'tokensUsed': 150,
        'tokensEstimated': false,
      });
      await agent.pause(task.id);
      task = await agent.resume(task.id);
      task = await f.run(agent, task);
      await agent.confirm(task.id,
          requestDigest: task.payload['requestDigest'] as String);
      task = f.repo.task(task.id)!;
      final usage = BudgetUsage.fromPayload(task.payload).toPayload();
      expect(usage, {
        'round': 2, 'activeMs': 40000, 'tokensUsed': 300,
        'tokensEstimated': false,
      });
      for (var i = 0; i < 2; i++) {
        await agent.pause(task.id);
        task = await agent.resume(task.id);
        expect(BudgetUsage.fromPayload(task.payload).toPayload(), usage);
      }
      expect(f.bodies, hasLength(2));
      expect(f.callsOf('timed'), 2);
    });

    test('after a finished step goes on from its messages: the write is in '
        'them, not asked for again', () async {
      final f = await LoopFixture.open();
      f.replies
        ..add(LoopReply.sse(sseCalls([('c1', 'write', '{}')])))
        ..add(LoopReply.sse(sseText('已写入')));
      final agent = f.agent();
      var task = await f.run(agent, await f.start(agent, f.profile()));
      await agent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      task = f.repo.task(task.id)!;
      expect(task.stage, 'model');
      expect(f.callsOf('write'), 1);
      await agent.pause(task.id);

      var next = await agent.resume(task.id);
      expect(next.id, isNot(task.id));
      expect(next.previousAttemptId, task.id);
      expect(next.state, PersonalTaskState.waitingConfirmation);
      expect(next.stage, 'model');
      expect(
        next.payload['round'],
        task.payload['round'],
        reason: 'what the earlier attempt used still counts',
      );
      final text = jsonEncode(next.payload['messages']);
      expect(text, contains('trustedToolResult'));
      expect(text, contains('c1'));
      expect(_types(f, next.id), ['resume', 'wait']);
      expect(f.repo.taskEvents(next.id).first.data['outcome'], 'carried');

      next = await f.run(agent, next);
      expect(next.state, PersonalTaskState.succeeded);
      expect(f.callsOf('write'), 1, reason: 'the write ran once in all');
      // The request that was sent had the earlier result in it.
      expect(
        jsonEncode(f.bodies.last['messages']),
        contains('trustedToolResult'),
      );
    });

    test('with a step that has receipts but was never recorded: successful '
        'ones are used, the rest are not run, and it goes back to the model '
        'for a new card', () async {
      final (f, agent, task) = await _twoWrites();
      final calls = (task.payload['toolCalls'] as List).cast<Map>();
      await agent.cancel(task.id); // the card is gone; the receipt below is
      // not: w1 ran under an approval the person gave before the crash.
      final ran = await _execute(f, task, calls[0]);
      expect(ran.status, ToolCallStatus.succeeded);
      expect(f.callsOf('w1'), 1);
      await _crash(f, task.id, 'interrupted');
      final approvals = f.approvals().length;

      f.replies.add(LoopReply.sse(sseText('好')));
      final next = await agent.resume(task.id);
      expect(f.callsOf('w1'), 1, reason: 'w1 not run again');
      expect(f.callsOf('w2'), 0, reason: 'w2 was never approved');
      expect(f.approvals(), hasLength(approvals), reason: 'no approval issued');
      expect(next.state, PersonalTaskState.waitingConfirmation);
      expect(next.stage, 'model');
      final messages = (next.payload['messages'] as List).cast<Map>();
      final tools = messages.where((m) => m['role'] == 'tool').toList();
      expect(tools.map((m) => m['tool_call_id']), ['c1', 'c2']);
      expect(tools[0]['content'], contains('trustedToolResult'));
      expect(tools[1]['content'], contains('notExecuted'));
      final event = f.repo.taskEvents(next.id).first;
      expect(event.type, 'resume');
      expect(event.data['adopted'], 1);
      expect(event.data['pending'], 1);
      expect(
        f.repo.taskObjects(next.id).map((l) => l.role),
        contains('tool_result'),
      );
    });

    test('with a call whose receipt shows it may have run stops, says so, '
        'and does not run it; a person moves it on to the model', () async {
      final (f, agent, task) = await _twoWrites();
      final calls = (task.payload['toolCalls'] as List).cast<Map>();
      await agent.cancel(task.id);
      expect(
        (await _execute(f, task, calls[0])).status,
        ToolCallStatus.succeeded,
      );
      _receipt(f, calls[1], 'running'); // w2 was mid-call at the crash
      await _crash(f, task.id, 'interrupted');
      final approvals = f.approvals().length;

      var held = await agent.resume(task.id);
      expect(held.state, PersonalTaskState.waitingConfirmation);
      expect(held.stage, 'resume');
      expect(held.waitingFor, contains('w2'));
      expect(f.callsOf('w2'), 0);
      expect(f.callsOf('w1'), 1);
      expect(f.repo.taskEvents(held.id).first.data['outcome'], 'held');
      expect(f.approvals(), hasLength(approvals));

      f.replies.add(LoopReply.sse(sseText('核实后继续')));
      await agent.confirm(
        held.id,
        requestDigest: held.payload['requestDigest'] as String,
      );
      held = f.repo.task(held.id)!;
      expect(held.stage, 'model');
      expect(held.state, PersonalTaskState.waitingConfirmation);
      final tools = (held.payload['messages'] as List)
          .cast<Map>()
          .where((m) => m['role'] == 'tool')
          .toList();
      expect(tools[1]['content'], contains('结果未知'));
      expect(f.callsOf('w2'), 0);
      expect(f.callsOf('w1'), 1);
      expect(f.approvals(), hasLength(approvals));
    });

    test('a read whose receipt has no outcome is just a read: not an unknown, '
        'and with nothing taken over it starts afresh', () async {
      final f = await LoopFixture.open();
      f.addTool('w1', ToolEffect.write);
      f.replies.add(
        LoopReply.sse(sseCalls([('c1', 'read', '{}'), ('c2', 'w1', '{}')])),
      );
      final agent = f.agent();
      final task = await f.run(agent, await f.start(agent, f.profile()));
      expect(task.stage, 'tool', reason: 'the read ran, the write waits');
      final read = ((task.payload['step'] as Map)['calls'] as List)
          .cast<Map>()
          .firstWhere((c) => c['toolId'] == 'read');
      final id = read['invocationId'];
      await f.repo.database.write(
        (db) => db.execute(
          "UPDATE tool_invocation_receipts SET state='running',result_json=NULL WHERE invocation_id=?",
          [id],
        ),
      );
      await _crash(f, task.id, 'interrupted');
      final next = await agent.resume(task.id);
      expect(next.stage, 'model');
      expect(next.state, PersonalTaskState.waitingConfirmation);
      expect(f.callsOf('w1'), 0);
    });

    test('repeated resumes cannot get past the step limit', () async {
      final f = await LoopFixture.open();
      f.replies.add(LoopReply.sse(sseCalls([('c1', 'write', '{}')])));
      final agent = f.agent(maxRounds: 1);
      var task = await f.run(agent, await f.start(agent, f.profile()));
      await agent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      task = f.repo.task(task.id)!;
      expect(task.state, PersonalTaskState.failed, reason: 'one step only');
      for (var i = 0; i < 2; i++) {
        final next = await agent.resume(task.id);
        expect(next.state, PersonalTaskState.failed);
        expect(next.payload['round'], 1);
        expect(f.bodies, hasLength(1), reason: 'no further request');
        task = next;
      }
      expect(f.callsOf('write'), 1);
    });

    test('a receipt of another tool is not taken over: a stop', () async {
      final (f, agent, task) = await _twoWrites();
      final calls = (task.payload['toolCalls'] as List).cast<Map>();
      await agent.cancel(task.id);
      _receipt(
        f,
        {...calls[0], 'toolId': 'w2'},
        'succeeded',
        result: ToolCallResult(status: ToolCallStatus.succeeded, summary: 's'),
      );
      await _crash(f, task.id, 'interrupted');
      final held = await agent.resume(task.id);
      expect(held.stage, 'resume');
      expect(f.callsOf('w1'), 0);
    });

    test('before any tool call it starts afresh, as it always did', () async {
      final f = await LoopFixture.open();
      final agent = f.agent();
      final task = await f.start(agent, f.profile());
      await agent.pause(task.id);
      final next = await agent.resume(task.id);
      expect(next.state, PersonalTaskState.waitingConfirmation);
      expect(next.previousAttemptId, task.id);
      expect(_types(f, next.id), ['wait']);
    });
  });
}
