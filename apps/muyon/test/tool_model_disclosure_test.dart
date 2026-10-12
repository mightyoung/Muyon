import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

import 'package:muyon/assistant/model_tool_result_projection.dart';

const secret = 'FREE_TEXT_UNREGISTERED_7b7f8b';
const ref = ObjectRef(
  moduleId: 'inquiry',
  objectType: 'project_item',
  objectId: 'item-1',
);
ToolCallResult result() => ToolCallResult(
  status: ToolCallStatus.succeeded,
  summary: '读取 $secret',
  data: {
    'record': {
      'name': '合法品名',
      'qty': 4,
      'notes': secret,
      'award_note': secret,
      'requirement': secret,
      'unknown_future_field': secret,
    },
  },
  objectRefs: [ref],
);
void main() {
  test(
    'fresh real model request keeps registered scalars and not local free text',
    () async {
      final f = await LoopFixture.open();
      f.objects = [ref];
      f.addTool(
        'inquiry.object',
        ToolEffect.read,
        onCall: (_) async => result(),
      );
      f.replies
        ..add(LoopReply.sse(sseCalls([('c1', 'inquiry__object', '{}')])))
        ..add(LoopReply.sse(sseText('完成')));
      final agent = f.agent();
      final task = await f.run(agent, await f.start(agent, f.profile()));
      expect(task.state, PersonalTaskState.succeeded);
      final sent = jsonEncode(f.bodies.last['messages']);
      expect(sent, isNot(contains(secret)));
      expect(sent, contains('合法品名'));
      expect(sent, contains('qty'));
      expect(
        jsonEncode((task.payload['step'] as Map)['calls']),
        contains(secret),
        reason: 'local immutable result is preserved',
      );
    },
  );
  test(
    'folded legacy result is projected again after persisted resume',
    () async {
      final f = await LoopFixture.open();
      f.objects = [ref];
      f.addTool(
        'inquiry.object',
        ToolEffect.write,
        onCall: (_) async => result(),
      );
      f.replies.add(LoopReply.sse(sseCalls([('c1', 'inquiry__object', '{}')])));
      final agent = f.agent();
      var task = await f.run(agent, await f.start(agent, f.profile()));
      await agent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      task = f.repo.task(task.id)!;
      await agent.pause(task.id);
      final messages = [...task.payload['messages'] as List];
      final index = messages.indexWhere((m) => m is Map && m['role'] == 'tool');
      messages[index] = {
        ...messages[index] as Map,
        'content': jsonEncode({
          'trustedToolResult': result().toJson(),
          'citations': [],
        }),
      };
      await f.repo.database.write(
        (db) => db.execute(
          "UPDATE execution_records SET payload=json_set(payload,'\$.messages',json(?)) WHERE id=?",
          [jsonEncode(messages), task.id],
        ),
      );
      f.replies.add(LoopReply.sse(sseText('恢复完成')));
      final resumed = await agent.resume(task.id);
      final done = await f.run(agent, resumed);
      expect(done.state, PersonalTaskState.succeeded);
      final sent = jsonEncode(f.bodies.last['messages']);
      expect(sent, isNot(contains(secret)));
      expect(sent, contains('合法品名'));
      expect(f.callsOf('inquiry.object'), 1);
      final call =
          ((task.payload['step'] as Map)['calls'] as List).first as Map;
      expect(
        f.tools.receiptFor(call['invocationId'] as String)!.result!.summary,
        contains(secret),
      );
    },
  );
  test(
    'unknown provider and nested field state have no registered model payload',
    () {
      final raw = ToolCallResult(
        status: ToolCallStatus.succeeded,
        summary: secret,
        data: {
          'record': {
            'name': {'state': 'notDisclosed', 'value': secret},
            'qty': 4,
            'sources': [
              {'originalText': secret},
            ],
          },
          'computedEvidence': {'inputFingerprint': secret},
        },
        objectRefs: [ref],
      );
      final projected = modelToolResult(raw);
      expect(jsonEncode(projected), isNot(contains(secret)));
      expect((projected['data'] as Map)['record'], {'qty': 4});
      final unknown = ToolCallResult(
        status: ToolCallStatus.succeeded,
        summary: secret,
        data: {'value': secret, 'notes': secret},
      );
      expect(modelToolResult(unknown)['data'], isEmpty);
      expect(unknown.data['notes'], secret);
    },
  );
  test('legacy derived prose and call arguments cannot bypass projection through summary', () {
    final history = modelToolHistory([
      {'role': 'system', 'content': 'system'},
      {'role': 'user', 'content': 'user-authored-allowed'},
      {
        'role': 'tool',
        'tool_call_id': 'old',
        'content': jsonEncode({'trustedToolResult': result().toJson()}),
      },
      {
        'role': 'assistant',
        'content': secret,
        'tool_calls': [
          {
            'id': 'next',
            'type': 'function',
            'function': {
              'name': 'inquiry__object',
              'arguments': jsonEncode({'notes': secret}),
            },
          },
        ],
      },
    ]);
    expect(jsonEncode(history.messages), isNot(contains(secret)));
    expect(jsonEncode(history.messages), contains('user-authored-allowed'));
    expect(
      history.compaction({
        'summary': {'content': secret},
        'cleared': {
          '2': {'content': secret},
        },
      }),
      isNull,
    );
  });
  test(
    'manual local result remains visible but cannot reenter a later model turn',
    () async {
      final f = await LoopFixture.open();
      f.objects = [ref];
      f.addTool(
        'inquiry.object',
        ToolEffect.read,
        onCall: (_) async => result(),
      );
      final agent = f.agent();
      final conversation = await f.repo.createConversation();
      final manual = await agent.startTool(
        conversationId: conversation.id,
        toolId: 'inquiry.object',
      );
      expect(manual.state, PersonalTaskState.succeeded);
      expect(f.repo.messages(conversation.id).last.content, contains(secret));
      f.replies.add(LoopReply.sse(sseText('完成')));
      final chat = await f.run(
        agent,
        await f.start(agent, f.profile(), conversationId: conversation.id),
      );
      expect(chat.state, PersonalTaskState.succeeded);
      expect(jsonEncode(f.bodies.single['messages']), isNot(contains(secret)));
      expect(
        f.repo
            .messages(conversation.id)
            .where((m) => m.content.contains(secret)),
        isNotEmpty,
      );
      expect(f.callsOf('inquiry.object'), 1);
    },
  );
  test('explicit user JSON is not misidentified as a host tool result', () {
    final user = {
      'role': 'user',
      'content': jsonEncode({'trustedToolResult': result().toJson()}),
    };
    expect(
      modelToolHistory([
        {'role': 'system', 'content': 'system'},
        user,
      ]).messages.last,
      user,
    );
  });
  test(
    'actual compaction request never summarizes legacy raw tool content',
    () async {
      final f = await LoopFixture.open();
      final agent = f.agent();
      final task = await f.start(agent, f.profile());
      final messages = [
        (task.payload['messages'] as List).first,
        {
          'role': 'tool',
          'tool_call_id': 'old',
          'content': jsonEncode({'trustedToolResult': result().toJson()}),
        },
        {'role': 'assistant', 'content': secret},
        for (var i = 0; i < 12; i++)
          {
            'role': i.isEven ? 'user' : 'assistant',
            'content': 'legitimate-$i-${'abcd' * 600}',
          },
      ];
      await f.repo.database.write(
        (db) => db.execute(
          "UPDATE execution_records SET payload=json_set(payload,'\$.messages',json(?)) WHERE id=?",
          [jsonEncode(messages), task.id],
        ),
      );
      await agent.compactNow(task.id);
      final card = f.repo.task(task.id)!;
      expect(card.stage, 'compaction');
      expect(jsonEncode(card.payload['preview']), isNot(contains(secret)));
      f.replies.add(
        LoopReply.sse(
          sseText(
            '{"goal":"g","decisions":"d","pending":"p","preferences":"x"}',
          ),
        ),
      );
      await agent.confirm(
        card.id,
        requestDigest: card.payload['requestDigest'] as String,
      );
      expect(f.bodies, hasLength(1));
      expect(jsonEncode(f.bodies.single), isNot(contains(secret)));
      expect(
        jsonEncode(f.repo.task(task.id)!.payload['messages']),
        contains(secret),
      );
    },
  );
  test(
    'unknown legacy tool formats and malformed persisted envelopes fail closed',
    () {
      for (final body in [
        secret,
        jsonEncode({'payload': secret}),
        jsonEncode({
          'trustedToolResult': {'summary': secret},
        }),
      ]) {
        final history = modelToolHistory([
          {'role': 'system', 'content': 'system'},
          {'role': 'tool', 'content': body},
        ]);
        expect(jsonEncode(history.messages), isNot(contains(secret)));
        expect(history.hadLegacyResult, isTrue);
      }
    },
  );
  test(
    'old unversioned summary approvals do not send a pre-policy preview',
    () async {
      final f = await LoopFixture.open();
      final agent = f.agent();
      final task = await f.start(agent, f.profile());
      final messages = [
        (task.payload['messages'] as List).first,
        for (var i = 0; i < 12; i++)
          {
            'role': i.isEven ? 'user' : 'assistant',
            'content': 'turn-$i-${'abcd' * 600}',
          },
      ];
      await f.repo.database.write(
        (db) => db.execute(
          "UPDATE execution_records SET payload=json_set(payload,'\$.messages',json(?)) WHERE id=?",
          [jsonEncode(messages), task.id],
        ),
      );
      await agent.compactNow(task.id);
      final card = f.repo.task(task.id)!;
      expect(card.stage, 'compaction');
      await f.repo.database.write(
        (db) => db.execute(
          "UPDATE execution_records SET payload=json_remove(payload,'\$.compactionPlan.modelDisclosurePolicy') WHERE id=?",
          [task.id],
        ),
      );
      await agent.confirm(
        card.id,
        requestDigest: card.payload['requestDigest'] as String,
      );
      expect(f.bodies, isEmpty);
      expect(f.ledger.recent(), isEmpty);
      expect(
        f.repo
            .taskEvents(task.id)
            .where((e) => e.type == 'compaction_failed')
            .map((e) => e.data['reason']),
        contains('disclosure_policy_changed'),
      );
    },
  );
}
