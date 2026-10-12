import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/agent_context.dart';
import 'package:muyon/assistant/model_reference_map.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

/// C6-REDO: every production path that builds a model request, with a real
/// agent, repository, registry and loopback endpoint (no real model).
///
/// Path matrix (positive = handle present and resolvable, negative = the raw
/// row digest is absent from every byte sent):
///   prompt assembly / scope ........ tested here
///   tool result history ............ tested here
///   confirmation card (preview) .... tested here (card == bytes sent)
///   revoked / moved authority ...... tested here (pin change retires handles)
///   manual startTool body .......... tested here (no model request at all)
///   UI planning request ............ tested in ui_disclosure_independent_test
///   compaction summary request ..... NOT TESTED (needs a full compaction run)
///   agent_resume replay ............ tested here (resume a failed run)
void main() {
  const raw =
      'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
  const row = ObjectRef(
    moduleId: 'test',
    objectType: 'budget',
    objectId: 'b1',
    nativeProjectId: 'p1',
    revisionRef: '4',
    contentDigest: raw,
  );

  late LoopFixture f;
  late ModelReferenceMap map;
  var pin = 'pin-1';
  late PersonalAgent agent;

  setUp(() async {
    f = await LoopFixture.open();
    map = ModelReferenceMap(List.filled(32, 5));
    pin = 'pin-1';
    f.objects = [row];
    f.addTool(
      'rich',
      ToolEffect.read,
      onCall: (_) async => ToolCallResult(
        status: ToolCallStatus.succeeded,
        summary: 'rich result',
        data: {'value': 42},
        objectRefs: [row],
      ),
    );
    agent = PersonalAgent(
      repository: f.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      tools: f.tools,
      modelReferences: map,
      modelReferencePin: (_) => pin,
    );
    addTearDown(agent.close);
  });

  Future<String> selectedConversation() async =>
      (await f.repo.createConversation(
        scope: AssistantScope.selectedObjects([row]),
      )).id;

  Iterable<String> bodies() => f.bodies.map(jsonEncode);

  group('prompt assembly', () {
    test(
      'the selected scope reaches the model as a handle, not the digest',
      () async {
        f.replies.add(LoopReply.sse(sseText('好的')));
        final task = await f.start(
          agent,
          f.profile(),
          conversationId: await selectedConversation(),
        );
        final done = await f.run(agent, task);
        expect(done.state, PersonalTaskState.succeeded);
        for (final body in bodies()) {
          expect(body, isNot(contains(raw)));
          expect(body, contains('modelRef'));
          expect(body, contains('mr1_'));
          expect(body, contains('objectId'), reason: 'locating fields kept');
          expect(body, contains('b1'));
        }
      },
    );

    test(
      'the same bytes are shown on the confirmation card and sent',
      () async {
        f.replies.add(LoopReply.sse(sseText('好的')));
        final task = await f.start(
          agent,
          f.profile(),
          conversationId: await selectedConversation(),
        );
        final preview = task.payload['preview'] as Map;
        expect(jsonEncode(preview), isNot(contains(raw)));
        expect(jsonEncode(preview), contains('mr1_'));
        await f.run(agent, task);
        final sent = (f.bodies.single['messages'] as List).cast<Map>();
        final shown = (preview['messages'] as List).cast<Map>();
        expect(
          [for (final m in sent) m['content']],
          [for (final m in shown) m['content']],
          reason: 'what the person confirmed is what left',
        );
      },
    );
  });

  group('tool result history', () {
    test('a read result is replayed to the model with handles only', () async {
      f.replies
        ..add(LoopReply.sse(sseCalls([('c1', 'rich', '{}')])))
        ..add(LoopReply.sse(sseText('已读取 [r1]')));
      final task = await f.run(
        agent,
        await f.start(
          agent,
          f.profile(),
          conversationId: await selectedConversation(),
        ),
      );
      expect(task.state, PersonalTaskState.succeeded);
      expect(f.callsOf('rich'), 1);
      expect(f.bodies, hasLength(2));
      for (final body in bodies()) {
        expect(body, isNot(contains(raw)));
      }
      final second = (f.bodies[1]['messages'] as List).cast<Map>();
      final toolMessage = second.singleWhere((m) => m['tool_call_id'] == 'c1');
      final trusted =
          jsonDecode(toolMessage['content'] as String)['trustedToolResult']
              as Map;
      final ref = (trusted['objectRefs'] as List).single as Map;
      expect(ref.containsKey('contentDigest'), isFalse);
      // the handle names exactly the object that was read, in this task only
      final binding = ModelReferenceBinding(
        taskId: task.id,
        scopeKey: _scopeKey(task),
        pin: pin,
      );
      expect(ref['modelRef'], map.handleFor(row, binding: binding));
      // the host-side record keeps the full digest for CAS and receipts
      final stored = jsonEncode(f.repo.task(task.id)!.payload['messages']);
      expect(stored, contains(raw));
    });

    test('map unit only: a handle of one task is refused in another', () async {
      f.replies
        ..add(LoopReply.sse(sseCalls([('c1', 'rich', '{}')])))
        ..add(LoopReply.sse(sseText('完成')));
      final task = await f.run(
        agent,
        await f.start(
          agent,
          f.profile(),
          conversationId: await selectedConversation(),
        ),
      );
      final second = (f.bodies[1]['messages'] as List).cast<Map>();
      final trusted =
          jsonDecode(
                second.singleWhere((m) => m['tool_call_id'] == 'c1')['content']
                    as String,
              )['trustedToolResult']
              as Map;
      final handle =
          ((trusted['objectRefs'] as List).single as Map)['modelRef'] as String;
      expect(
        () => map.resolve(
          handle,
          current: ModelReferenceBinding(
            taskId: 'another-task',
            scopeKey: _scopeKey(task),
            pin: pin,
          ),
        ),
        throwsA(isA<ModelReferenceRejected>()),
      );
    });
  });

  group('agent_resume', () {
    test(
      'a resumed attempt replays the stored result with its own handles',
      () async {
        f.replies
          ..add(LoopReply.sse(sseCalls([('c1', 'rich', '{}')])))
          ..add(const LoopReply.status(500))
          ..add(LoopReply.sse(sseText('恢复后的回答')));
        final first = await f.run(
          agent,
          await f.start(
            agent,
            f.profile(),
            conversationId: await selectedConversation(),
          ),
        );
        expect(first.state, PersonalTaskState.failed);
        expect(
          jsonEncode(f.repo.task(first.id)!.payload['messages']),
          contains(raw),
          reason: 'the host-side record keeps the full digest',
        );
        final resumed = await agent.resume(first.id);
        expect(resumed.id, isNot(first.id));
        final done = await f.run(agent, resumed);
        expect(done.state, PersonalTaskState.succeeded);
        expect(f.bodies, hasLength(3));
        for (final body in bodies()) {
          expect(body, isNot(contains(raw)));
        }
        final replay = (f.bodies[2]['messages'] as List).cast<Map>();
        final carried = replay.singleWhere((m) => m['tool_call_id'] == 'c1');
        final ref =
            ((jsonDecode(carried['content'] as String)['trustedToolResult']
                            as Map)['objectRefs']
                        as List)
                    .single
                as Map;
        // minted for the resumed attempt, not for the one that failed
        expect(
          ref['modelRef'],
          map.handleFor(
            row,
            binding: ModelReferenceBinding(
              taskId: resumed.id,
              scopeKey: _scopeKey(resumed),
              pin: pin,
            ),
          ),
          reason: 'minted for the resumed attempt',
        );
        expect(
          ref['modelRef'],
          isNot(
            map.handleFor(
              row,
              binding: ModelReferenceBinding(
                taskId: first.id,
                scopeKey: _scopeKey(first),
                pin: pin,
              ),
            ),
          ),
        );
      },
    );
  });

  group('manual tool run', () {
    test(
      'startTool sends nothing to a model and a later chat sends no digest',
      () async {
        final conversation = await selectedConversation();
        final manual = await agent.startTool(
          conversationId: conversation,
          toolId: 'rich',
        );
        expect(manual.state, PersonalTaskState.succeeded);
        expect(f.callsOf('rich'), 1);
        expect(
          f.bodies,
          isEmpty,
          reason: 'a manual tool body is not a model request',
        );
        f.replies.add(LoopReply.sse(sseText('继续')));
        await f.run(
          agent,
          await f.start(agent, f.profile(), conversationId: conversation),
        );
        for (final body in bodies()) {
          expect(body, isNot(contains(raw)));
        }
      },
    );
  });

  group('authority moves', () {
    test(
      'handles minted under an old pin are not the new pin\'s handles',
      () async {
        f.replies.add(LoopReply.sse(sseText('好的')));
        final task = await f.start(
          agent,
          f.profile(),
          conversationId: await selectedConversation(),
        );
        final sentHandle = RegExp(r'mr1_[A-Za-z0-9_-]+')
            .firstMatch(jsonEncode(task.payload['preview']))!
            .group(0)!;
        final old = ModelReferenceBinding(
          taskId: task.id,
          scopeKey: _scopeKey(task),
          pin: pin,
        );
        expect(map.handleFor(row, binding: old), sentHandle);
        pin = 'pin-2';
        expect(
          map.handleFor(
            row,
            binding: ModelReferenceBinding(
              taskId: task.id,
              scopeKey: _scopeKey(task),
              pin: pin,
            ),
          ),
          isNot(sentHandle),
          reason: 'a new pin mints new handles',
        );
      },
    );
  });

  group('summary request projection (C6-FIX-1 I-1)', () {
    test('a second summary quotes the first one only with handles', () async {
      f.replies
        ..add(LoopReply.sse(sseCalls([('c1', 'rich', '{}')])))
        ..add(LoopReply.sse(sseText(_summaryJson)))
        ..add(LoopReply.sse(sseCalls([('c2', 'rich', '{}')])))
        ..add(LoopReply.sse(sseText(_summaryJson)))
        ..add(LoopReply.sse(sseText('完成')));
      final conversation = await selectedConversation();
      await _seedHistory(f, conversation);
      var task = await f.start(
        agent,
        f.profile(),
        conversationId: conversation,
      );
      // read, then summary, read again, then summary: the second summary
      // starts from the first one, which holds the full digest host-side.
      Future<void> step() async {
        task = f.repo.task(task.id)!;
        await agent.confirm(
          task.id,
          requestDigest: task.payload['requestDigest'] as String,
        );
      }

      await step();
      await agent.compactNow(task.id);
      await step();
      await step();
      await agent.compactNow(task.id);
      await step();
      task = await f.run(agent, f.repo.task(task.id)!);
      expect(task.state, PersonalTaskState.succeeded);
      final summaries = [
        for (final body in bodies())
          if (body.contains('You write a summary')) body,
      ];
      expect(summaries, hasLength(2));
      expect(
        summaries.last,
        contains('previousSummary'),
        reason: 'the previous summary is part of the request',
      );
      expect(summaries.last, isNot(contains(raw)));
      expect(summaries.last, contains('mr1_'));
    });
  });

  group('confirmation after a restart (C6-FIX-1 I-3)', () {
    test(
      'an old card is not sent under a new pin and the task fails',
      () async {
        f.replies.add(LoopReply.sse(sseText('好的')));
        final task = await f.start(
          agent,
          f.profile(),
          conversationId: await selectedConversation(),
        );
        expect(task.state, PersonalTaskState.waitingConfirmation);
        final restarted = PersonalAgent(
          repository: f.repo,
          gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
          tools: f.tools,
          modelReferences: ModelReferenceMap(List.filled(32, 5)),
          modelReferencePin: (_) => 'pin-2',
        );
        addTearDown(restarted.close);
        await restarted.confirm(
          task.id,
          requestDigest: task.payload['requestDigest'] as String,
        );
        expect(f.bodies, isEmpty, reason: 'nothing left the host');
        expect(f.repo.task(task.id)!.state, PersonalTaskState.failed);
      },
    );

    test('a summary card under a new pin is not sent either', () async {
      final conversation = await selectedConversation();
      await _seedHistory(f, conversation);
      f.replies.add(LoopReply.sse(sseText('好的')));
      final task = await f.start(
        agent,
        f.profile(),
        conversationId: conversation,
      );
      await agent.compactNow(task.id);
      final card = f.repo.task(task.id)!;
      expect(card.stage, 'compaction');
      final restarted = PersonalAgent(
        repository: f.repo,
        gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
        tools: f.tools,
        modelReferences: ModelReferenceMap(List.filled(32, 5)),
        modelReferencePin: (_) => 'pin-2',
      );
      addTearDown(restarted.close);
      await restarted.confirm(
        task.id,
        requestDigest: card.payload['requestDigest'] as String,
      );
      expect(f.bodies, isEmpty, reason: 'no summary request left the host');
      expect(f.repo.task(task.id)!.state, PersonalTaskState.failed);
    });

    test('the same card under the same pin is still sent', () async {
      f.replies.add(LoopReply.sse(sseText('好的')));
      final task = await f.start(
        agent,
        f.profile(),
        conversationId: await selectedConversation(),
      );
      final restarted = PersonalAgent(
        repository: f.repo,
        gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
        tools: f.tools,
        modelReferences: ModelReferenceMap(List.filled(32, 5)),
        modelReferencePin: (_) => pin,
      );
      addTearDown(restarted.close);
      final done = await f.run(restarted, task);
      expect(done.state, PersonalTaskState.succeeded);
      expect(f.bodies, hasLength(1));
    });
  });

  group('model cannot hand a handle back (C6-FIX-1 I-5)', () {
    test(
      'a native tool call carrying a handle is refused and never runs',
      () async {
        final task = await f.start(
          agent,
          f.profile(),
          conversationId: await selectedConversation(),
        );
        final handle = map.handleFor(
          row,
          binding: ModelReferenceBinding(
            taskId: task.id,
            scopeKey: _scopeKey(task),
            pin: pin,
          ),
        );
        f.replies
          ..add(
            LoopReply.sse(
              sseCalls([
                ('c1', 'rich', jsonEncode({'note': handle})),
              ]),
            ),
          )
          ..add(LoopReply.sse(sseText('已拒绝')));
        await f.run(agent, task);
        expect(f.callsOf('rich'), 0, reason: 'the handle did not run the tool');
      },
    );

    test('a compatibility tool reply carrying a handle is refused', () async {
      final task = await f.start(
        agent,
        f.profile(
          capabilities: const ModelCapabilities(
            streaming: true,
            nativeTools: false,
            source: CapabilitySource.userDeclared,
          ),
        ),
        conversationId: await selectedConversation(),
      );
      final handle = map.handleFor(
        row,
        binding: ModelReferenceBinding(
          taskId: task.id,
          scopeKey: _scopeKey(task),
          pin: pin,
        ),
      );
      f.replies
        ..add(
          LoopReply.sse(
            sseText(
              jsonEncode({
                'type': 'tool',
                'toolId': 'rich',
                'parameters': {'note': handle},
              }),
            ),
          ),
        )
        ..add(
          LoopReply.sse(
            sseText(
              jsonEncode({
                'type': 'answer',
                'answer': '已拒绝',
                'citationIds': [],
              }),
            ),
          ),
        );
      await f.run(agent, task);
      expect(f.callsOf('rich'), 0, reason: 'the handle did not run the tool');
    });
  });

  group('cancel revokes the task (C6-FIX-1 I-5)', () {
    test('after cancel the task mints no further handles', () async {
      f.replies.add(LoopReply.sse(sseText('好的')));
      final task = await f.start(
        agent,
        f.profile(),
        conversationId: await selectedConversation(),
      );
      final binding = ModelReferenceBinding(
        taskId: task.id,
        scopeKey: _scopeKey(task),
        pin: pin,
      );
      await agent.cancel(task.id);
      expect(
        () => map.handleFor(row, binding: binding),
        throwsA(
          isA<ModelReferenceRejected>().having(
            (e) => e.code,
            'code',
            'revoked',
          ),
        ),
      );
    });
  });
}

/// Older history for a summary to fold in (as context_compaction_test does).
Future<void> _seedHistory(LoopFixture f, String conversation) async {
  for (var i = 0; i < 8; i++) {
    await f.repo.appendMessage(
      conversation,
      i.isEven ? 'user' : 'assistant',
      '历史$i' * 200,
    );
  }
}

const _summaryJson =
    '{"goal":"弄清项目成本","decisions":"先查预算","pending":"写入报价","preferences":"简短回答"}';

String _scopeKey(PersonalTask task) => AgentContext.digest(task.scope.toJson());
