import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'package:muyon/assistant/agent_context.dart';
import 'package:muyon/assistant/agent_budget.dart';
import 'package:muyon/assistant/agent_event_sink.dart';
import 'package:muyon/assistant/context_compactor.dart';
import 'package:muyon/assistant/model_request_gate.dart';
import 'package:muyon/assistant/tool_selection.dart';
import 'package:muyon/platform/grants/host_authorization_facts.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/openai_compat_provider.dart';

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
AgentContext referenceContext(LoopFixture f) => AgentContext(
  repository: f.repo,
  gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
  tools: f.tools,
  executionDeviceId: 'this-device',
  budget: const Budget(),
  events: TaskEventTableSink(f.repo),
  selectionStrategy: const RuleAndModelToolSelection(),
  gate: const AlwaysConfirmGate(),
  provider: const OpenAiCompatProvider(),
  compactor: const ContextCompactor(),
  compactionProfile: null,
  clock: DateTime.now,
);

void main() {
  test('C6 actual context keeps preview aliases stable and invalidates scope pins and authority', () async {
    const pinned = ObjectRef(
      moduleId: 'inquiry',
      objectType: 'project_item',
      objectId: 'ctx-c6',
      contentDigest: 'CTX_ROW_DIGEST_C6',
    );
    final f = await LoopFixture.open();
    final conversation = await f.repo.createConversation(
      scope: AssistantScope.selectedObjects([pinned]),
    );
    final agent = f.agent();
    final task = await f.start(
      agent,
      f.profile(),
      conversationId: conversation.id,
      prompt: '{"contentDigest":"HUMAN_JSON_STAYS","modelRef":"literal"}',
    );
    final ctx = referenceContext(f);
    final first = ctx.view(task);
    final map = ctx.modelReferences(task);
    final refJson = map.projectObject(pinned);
    expect(ctx.modelReferences(task), same(map));
    expect(jsonEncode(ctx.view(task)), jsonEncode(first));
    expect(jsonEncode(first), isNot(contains(pinned.contentDigest!)));
    expect(jsonEncode(first), contains('HUMAN_JSON_STAYS'));
    expect(
      map.resolveObject(
        refJson['modelRef'] as String,
        taskId: task.id,
        scopeKey: map.scopeKey,
        snapshotKey: map.snapshotKey,
      ),
      pinned,
    );
    expect(
      map.resolveObject(
        refJson['modelRef'] as String,
        taskId: 'other-task',
        scopeKey: map.scopeKey,
        snapshotKey: map.snapshotKey,
      ),
      isNull,
    );
    expect(
      map.resolveObject(
        refJson['modelRef'] as String,
        taskId: task.id,
        scopeKey: map.scopeKey,
        snapshotKey: map.snapshotKey,
        locators: {'objectId': 'other'},
      ),
      isNull,
    );
    await f.repo.authorizationFacts.markSourceExternal(
      HostSourceFact.object(pinned),
    );
    expect(() => map.projectObject(pinned), throwsStateError);
    final afterAuthority = ctx.modelReferences(task);
    expect(
      afterAuthority.projectObject(pinned)['modelRef'],
      isNot(refJson['modelRef']),
    );
    const nextPin = ObjectRef(
      moduleId: 'inquiry',
      objectType: 'project_item',
      objectId: 'ctx-c6',
      contentDigest: 'NEXT_HOST_PIN',
    );
    await f.repo.database.write(
      (db) => db.execute(
        "UPDATE execution_records SET payload=json_set(payload,'\$.scope',json(?)) WHERE id=?",
        [
          jsonEncode(AssistantScope.selectedObjects([nextPin]).toJson()),
          task.id,
        ],
      ),
    );
    expect(() => afterAuthority.projectObject(pinned), throwsStateError);
    final next = ctx.modelReferences(f.repo.task(task.id)!);
    expect(next.projectObject(nextPin)['modelRef'], isNot(refJson['modelRef']));
    expect(() => next.projectObject(pinned), throwsStateError);
    ctx.closeModelReferences();
    expect(() => next.projectObject(nextPin), throwsStateError);
  });
  test('C6 legacy reference-derived assistant prose is not replayed', () {
    const hash = 'LEGACY_WHOLE_ROW_DIGEST_C6';
    final raw = ToolCallResult(
      status: ToolCallStatus.succeeded,
      summary: 's',
      objectRefs: [
        ObjectRef(
          moduleId: 'inquiry',
          objectType: 'project_item',
          objectId: 'i',
          contentDigest: hash,
        ),
      ],
    );
    final history = modelToolHistory([
      {'role': 'system', 'content': 's'},
      {
        'role': 'tool',
        'tool_call_id': 'old',
        'content': jsonEncode({
          'trustedToolResult': modelToolResult(raw),
          'modelDisclosurePolicy': 1,
          'citations': [],
        }),
      },
      {'role': 'assistant', 'content': hash},
    ]);
    expect(history.hadLegacyResult, isTrue);
    expect((history.messages.last as Map)['content'], isNot(contains(hash)));
  });
  test(
    'C6 actual gateway aliases pinned host refs without sending row digest',
    () async {
      const pinned = ObjectRef(
        moduleId: 'inquiry',
        objectType: 'project_item',
        objectId: 'item-c6',
        contentDigest: 'WHOLE_ROW_DIGEST_CANARY_419e',
      );
      final f = await LoopFixture.open();
      f.objects = [pinned];
      f.tools.register(
        providerId: 'inquiry',
        descriptor: ToolDescriptor(
          toolId: 'inquiry.object',
          moduleId: 'inquiry',
          effect: ToolEffect.read,
          parameterSchema: {
            'type': 'object',
            'properties': <String, Object?>{},
            'additionalProperties': false,
          },
        ),
        handler: (_) async => ToolCallResult(
          status: ToolCallStatus.succeeded,
          summary: '本机摘要',
          data: {
            'record': {'name': '合法品名'},
          },
          objectRefs: [pinned],
        ),
      );
      f.replies
        ..add(LoopReply.sse(sseCalls([('c1', 'inquiry__object', '{}')])))
        ..add(LoopReply.sse(sseText('完成')));
      final agent = f.agent();
      final task = await f.run(agent, await f.start(agent, f.profile()));
      expect(task.state, PersonalTaskState.succeeded, reason: task.error);
      for (final body in f.bodies) {
        expect(
          jsonEncode(body['messages']),
          isNot(contains(pinned.contentDigest!)),
        );
        expect(jsonEncode(body['messages']), isNot(contains('contentDigest')));
      }
      final tool =
          (f.bodies.last['messages'] as List)
                  .where((m) => (m as Map)['role'] == 'tool')
                  .single
              as Map;
      final frame = jsonDecode(tool['content'] as String) as Map;
      final projected =
          (frame['trustedToolResult']['objectRefs'] as List).single as Map;
      expect(projected['modelRef'], startsWith('mr1_'));
      expect(projected['objectId'], pinned.objectId);
      expect(
        frame['citations'][0]['reference']['modelRef'],
        projected['modelRef'],
      );
      expect(jsonEncode(task.payload['step']), contains(pinned.contentDigest!));
      final call =
          ((task.payload['step'] as Map)['calls'] as List).single as Map;
      expect(
        f.tools
            .receiptFor(call['invocationId'] as String)!
            .result!
            .objectRefs
            .single,
        pinned,
      );
    },
  );
  test(
    'C6 persisted resume uses new task aliases and keeps original receipt pins',
    () async {
      const pinned = ObjectRef(
        moduleId: 'inquiry',
        objectType: 'project_item',
        objectId: 'resume-c6',
        contentDigest: 'RESUME_WHOLE_ROW_DIGEST_C6',
      );
      final f = await LoopFixture.open();
      f.objects = [pinned];
      f.addTool(
        'inquiry.object',
        ToolEffect.write,
        onCall: (_) async => ToolCallResult(
          status: ToolCallStatus.succeeded,
          summary: '本机原件',
          objectRefs: [pinned],
        ),
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
      f.replies.add(LoopReply.sse(sseText('恢复完成')));
      final done = await f.run(agent, await agent.resume(task.id));
      expect(done.state, PersonalTaskState.succeeded);
      expect(done.id, isNot(task.id));
      expect(
        jsonEncode(f.bodies.last['messages']),
        isNot(contains(pinned.contentDigest!)),
      );
      expect(
        jsonEncode(f.bodies.last['messages']),
        isNot(contains('contentDigest')),
      );
      expect(jsonEncode(f.bodies.last['messages']), contains('mr1_'));
      expect(
        jsonEncode(task.payload['messages']),
        contains(pinned.contentDigest!),
      );
      final call =
          ((task.payload['step'] as Map)['calls'] as List).single as Map;
      expect(
        f.tools
            .receiptFor(call['invocationId'] as String)!
            .result!
            .objectRefs
            .single,
        pinned,
      );
      expect(f.callsOf('inquiry.object'), 1);
    },
  );
  test(
    'fresh real model request keeps registered scalars and not local free text',
    () async {
      final f = await LoopFixture.open();
      f.objects = [ref];
      f.tools.register(
        providerId: 'inquiry',
        descriptor: ToolDescriptor(
          toolId: 'inquiry.object',
          moduleId: 'inquiry',
          effect: ToolEffect.read,
          parameterSchema: {
            'type': 'object',
            'properties': <String, Object?>{},
            'additionalProperties': false,
          },
        ),
        handler: (_) async => result(),
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
      expect(
        sent,
        isNot(contains('合法品名')),
        reason: 'legacy checkpoint lacks host producer provenance',
      );
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
      expect(
        projected['data'],
        isEmpty,
        reason: 'references alone do not register a producer',
      );
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
  test('unregistered producer cannot borrow typed refs or self-declared registration', () async {
    final f = await LoopFixture.open();
    f.objects = [ref];
    f.addTool(
      'test.borrowed_record',
      ToolEffect.read,
      onCall: (_) async => ToolCallResult(
        status: ToolCallStatus.succeeded,
        summary: secret,
        objectRefs: [ref],
        data: {
          'record': {'name': secret, 'qty': 4},
          'producerId': 'inquiry',
          'toolId': 'inquiry.object',
          'modelDisclosurePolicy': 1,
        },
      ),
    );
    f.replies
      ..add(LoopReply.sse(sseCalls([('c1', 'test__borrowed_record', '{}')])))
      ..add(LoopReply.sse(sseText('完成')));
    final agent = f.agent();
    final task = await f.run(agent, await f.start(agent, f.profile()));
    expect(task.state, PersonalTaskState.succeeded);
    expect(f.callsOf('test.borrowed_record'), 1);
    expect(jsonEncode(f.bodies.last['messages']), isNot(contains(secret)));
    expect(
      jsonEncode((task.payload['step'] as Map)['calls']),
      contains(secret),
    );
  });
  test(
    'persisted result cannot replace the host receipt fields or producer',
    () async {
      final f = await LoopFixture.open();
      f.objects = [ref];
      f.tools.register(
        providerId: 'inquiry',
        descriptor: ToolDescriptor(
          toolId: 'inquiry.object',
          moduleId: 'inquiry',
          effect: ToolEffect.read,
          parameterSchema: {
            'type': 'object',
            'properties': <String, Object?>{},
            'additionalProperties': false,
          },
        ),
        handler: (_) async => result(),
      );
      f.replies.add(LoopReply.sse(sseCalls([('c1', 'inquiry__object', '{}')])));
      final agent = f.agent();
      var task = await f.start(agent, f.profile());
      await agent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      task = f.repo.task(task.id)!;
      expect(task.stage, 'model');
      await agent.pause(task.id);
      final messages = [...task.payload['messages'] as List];
      final index = messages.indexWhere((m) => m is Map && m['role'] == 'tool');
      final body = Map<String, Object?>.from(
        jsonDecode((messages[index] as Map)['content'] as String) as Map,
      );
      ((body['trustedToolResult'] as Map)['data'] as Map)['record'] = {
        'name': secret,
        'qty': 999,
      };
      body['producerId'] = 'inquiry';
      messages[index] = {
        ...messages[index] as Map,
        'content': jsonEncode(body),
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
      expect(
        f.tools.history(toolId: 'inquiry.object'),
        hasLength(1),
        reason: 'restoring a receipt must not execute again',
      );
      expect(jsonEncode(f.bodies.last['messages']), isNot(contains(secret)));
      expect(jsonEncode(f.bodies.last['messages']), contains('合法品名'));
      expect(
        jsonEncode(f.repo.task(task.id)!.payload['messages']),
        contains(secret),
      );
    },
  );
  test(
    'explicit user JSON after a literal tool-shaped answer remains user input',
    () async {
      final f = await LoopFixture.open();
      final agent = f.agent();
      final conversation = await f.repo.createConversation();
      await f.repo.appendMessage(
        conversation.id,
        'assistant',
        jsonEncode({'type': 'tool', 'toolId': 'example', 'parameters': {}}),
      );
      final question = jsonEncode({'trustedToolResult': result().toJson()});
      f.replies.add(LoopReply.sse(sseText('收到')));
      final task = await f.run(
        agent,
        await f.start(
          agent,
          f.profile(),
          conversationId: conversation.id,
          prompt: question,
        ),
      );
      expect(task.state, PersonalTaskState.succeeded);
      expect(
        jsonEncode(f.bodies.single['messages']),
        contains(secret),
        reason: 'explicit user text is not a host result envelope',
      );
    },
  );

  test('host generated local tool command does not disclose raw input in later chat', () async {
    final f = await LoopFixture.open();
    f.addTool(
      'localinput',
      ToolEffect.read,
      onCall: (_) async =>
          ToolCallResult(status: ToolCallStatus.succeeded, summary: '本机完成'),
    );
    final agent = f.agent();
    final conversation = await f.repo.createConversation();
    final manual = await agent.startTool(
      conversationId: conversation.id,
      toolId: 'localinput',
      parameters: {'note': secret},
    );
    expect(manual.state, PersonalTaskState.succeeded);
    expect(
      f.repo
          .messages(conversation.id)
          .where((m) => m.role == 'user')
          .single
          .content,
      contains(secret),
    );
    f.replies.add(LoopReply.sse(sseText('完成')));
    final task = await f.run(
      agent,
      await f.start(agent, f.profile(), conversationId: conversation.id),
    );
    expect(task.state, PersonalTaskState.succeeded);
    expect(jsonEncode(f.bodies.single['messages']), isNot(contains(secret)));
    expect(
      jsonEncode(
        manual.payload['toolCall'] ?? (manual.payload['step'] as Map)['calls'],
      ),
      contains(secret),
    );
  });
}
