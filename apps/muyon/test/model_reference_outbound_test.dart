import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/agent_context.dart';
import 'package:muyon/assistant/model_reference_map.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/services/models/model_gateway.dart';
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
///   agent_resume replay ............ NOT TESTED (needs an interrupted run);
///                                    it shares view()/projectMessages with
///                                    the paths above
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
      expect(map.resolve(ref['modelRef'] as String, current: binding), row);
      // the host-side record keeps the full digest for CAS and receipts
      final stored = jsonEncode(f.repo.task(task.id)!.payload['messages']);
      expect(stored, contains(raw));
    });

    test('a handle of one task does not resolve in another', () async {
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
    test('handles minted under an old pin no longer resolve', () async {
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
      expect(map.resolve(sentHandle, current: old), row);
      pin = 'pin-2';
      expect(
        () => map.resolve(
          sentHandle,
          current: ModelReferenceBinding(
            taskId: task.id,
            scopeKey: _scopeKey(task),
            pin: pin,
          ),
        ),
        throwsA(
          isA<ModelReferenceRejected>().having(
            (e) => e.code,
            'code',
            'expired',
          ),
        ),
      );
    });
  });
}

String _scopeKey(PersonalTask task) => AgentContext.digest(task.scope.toJson());
