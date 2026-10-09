import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/assistant_subconversations.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/platform/outbound_ledger.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

Future<(LoopFixture, AssistantSubconversations, PersonalTask)> setup() async {
  final f = await LoopFixture.open();
  final c = await f.repo.createConversation();
  final t = await f.agent().start(conversationId: c.id, prompt: '父任务');
  return (f, AssistantSubconversations(f.repo), t);
}

void main() {
  test(
    'open_atomic_same_creation_token_creates_one_child; one_level_only',
    () async {
      final (f, s, t) = await setup();
      final refs = await Future.wait([
        s.openSubconversation(t.id, '子目标', creationToken: 'gesture'),
        s.openSubconversation(t.id, '子目标', creationToken: 'gesture'),
      ]);
      expect(refs[0].childConversationId, refs[1].childConversationId);
      expect(f.repo.conversations(), hasLength(2));
      expect(f.repo.messages(refs[0].childConversationId), isEmpty);
      final child = await f.agent().start(
        conversationId: refs[0].childConversationId,
        prompt: '子任务',
      );
      await expectLater(
        s.openSubconversation(child.id, '孙任务'),
        throwsStateError,
      );
    },
  );
  test('workspace_cas_and_reopen_keep_draft; scope_change_keeps_readable_old_draft', () async {
    final (f, s, t) = await setup();
    final ref = await s.openSubconversation(t.id, '初始问题');
    const state = SubconversationWorkspace(
      draftText: '待发问题',
      scrollOffset: 120,
      selectedProfileId: 'local',
      openState: false,
      revision: 1,
    );
    expect(await s.saveWorkspace(ref, state, expectedRevision: 0), isTrue);
    expect(await s.saveWorkspace(ref, state, expectedRevision: 0), isFalse);
    final storage = StorageManager(f.root.path);
    final db = await storage.open('muyon', WorkspaceRepository.schema);
    final reopened = AssistantSubconversations(FoundationRepository(db));
    expect(reopened.loadWorkspace(ref).draftText, '待发问题');
    expect(reopened.loadWorkspace(ref).scrollOffset, 120);
    await storage.close();
    await f.repo.database.write(
      (db) => db.execute('UPDATE conversations SET scope_json=? WHERE id=?', [
        jsonEncode(AssistantScope.workspace('changed').toJson()),
        t.conversationId,
      ]),
    );
    expect(s.loadWorkspace(ref).draftText, '待发问题');
    expect(
      () => s.validateConversation(ref.childConversationId),
      throwsStateError,
    );
    await expectLater(
      s.saveWorkspace(
        ref,
        const SubconversationWorkspace(revision: 2),
        expectedRevision: 1,
      ),
      throwsStateError,
    );
  });
  test('parent_reads_latest_only_when_requested; historical reads retain versions and no authority', () async {
    final (f, s, t) = await setup();
    final before = jsonEncode(f.repo.task(t.id)!.payload);
    final ref = await s.openSubconversation(t.id, '研究');
    const object = ObjectRef(
      moduleId: 'test',
      objectType: 'budget',
      objectId: 'b1',
      revisionRef: 'v1',
      contentDigest: 'digest-v1',
    );
    await f.repo.appendMessage(
      ref.childConversationId,
      'assistant',
      '结果 v1',
      references: [object],
    );
    expect(s.reads(ref), isEmpty);
    expect(jsonEncode(f.repo.task(t.id)!.payload), before);
    final v1 = await s.readLatestSubconversation(ref);
    await f.repo.appendMessage(ref.childConversationId, 'assistant', '结果 v2');
    expect(s.reads(ref).single.summary, '结果 v1');
    final v2 = await s.readLatestSubconversation(ref);
    expect(v1.digest, isNot(v2.digest));
    expect(v2.summary, '结果 v2');
    final reopened = AssistantSubconversations(
      FoundationRepository(f.repo.database),
    );
    expect(reopened.reads(ref).map((r) => r.summary), ['结果 v1', '结果 v2']);
    expect(jsonEncode(v1.value), contains('digest-v1'));
    expect(v1.value['authority'], 'display_only');
    expect(
      f.repo.messages(t.conversationId).where((m) => m.content.contains('结果')),
      isEmpty,
    );
    expect(jsonEncode(f.repo.task(t.id)!.payload), before);
  });
  test('child readonly is enforced by factory for manual write and native candidates', () async {
    final (f, s, t) = await setup();
    final ref = await s.openSubconversation(t.id, '查询');
    final agent = f.agent();
    await expectLater(
      agent.startTool(
        conversationId: ref.childConversationId,
        toolId: 'write',
        parameters: {},
      ),
      throwsStateError,
    );
    expect(f.callsOf('write'), 0);
    final child = await f.start(
      agent,
      f.profile(),
      conversationId: ref.childConversationId,
    );
    expect(child.payload['candidateIds'] as List, isNot(contains('write')));
    expect(child.payload['candidateIds'] as List, contains('read'));
  });
  test('child model-proposed writes are refused and parent still requires its own card', () async {
    final (f, s, t) = await setup();
    final ref = await s.openSubconversation(t.id, '查询');
    final agent = f.agent();
    f.replies.add(LoopReply.sse(sseCalls([('c1', 'write', '{}')])));
    final child = await f.start(
      agent,
      f.profile(),
      conversationId: ref.childConversationId,
    );
    final settled = await f.run(agent, child, confirmTools: true);
    expect(settled.state, PersonalTaskState.failed);
    expect(f.callsOf('read'), 0);
    expect(f.callsOf('write'), 0);
    final parentWrite = await agent.startTool(
      conversationId: t.conversationId,
      toolId: 'write',
      parameters: {},
    );
    expect(parentWrite.state, PersonalTaskState.waitingConfirmation);
  });
  test('missing or malformed child relationship fails closed; stale child resume never widens scope', () async {
    final (f, s, t) = await setup();
    final ref = await s.openSubconversation(t.id, '查询');
    await f.repo.database.write(
      (db) => db.execute('DELETE FROM settings WHERE key=?', [
        'subconversation:${ref.childConversationId}',
      ]),
    );
    await expectLater(
      f.agent().start(
        conversationId: ref.childConversationId,
        prompt: '不能恢复成主对话',
      ),
      throwsStateError,
    );
  });
  test('child resume after real database and agent restart stays read-only and needs fresh confirmation', () async {
    final f = await LoopFixture.open();
    final oldAgent = PersonalAgent(
      repository: f.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      tools: f.tools,
    );
    var oldClosed = false;
    addTearDown(() async {
      if (!oldClosed) await oldAgent.close();
    });
    final c = await f.repo.createConversation();
    final parent = await oldAgent.start(conversationId: c.id, prompt: '父任务');
    final ref = await AssistantSubconversations(f.repo)
        .openSubconversation(parent.id, '只读子任务');
    final child = await f.start(
      oldAgent,
      f.profile(),
      conversationId: ref.childConversationId,
    );
    await oldAgent.pause(child.id);
    await oldAgent.close();
    oldClosed = true;
    await f.storage.close();
    final storage = StorageManager(f.root.path);
    final db = await storage.open('muyon', WorkspaceRepository.schema);
    addTearDown(storage.close);
    final repo = FoundationRepository(db);
    final tools = ToolRegistry(
      database: db,
      resolveScope: (scope) async =>
          ResolvedAssistantScope(requested: scope, objects: [f.ref]),
    );
    for (final info in f.tools.list()) {
      tools.register(
        providerId: info.providerId,
        descriptor: info.descriptor,
        handler: (_) async =>
            throw StateError('Must not invoke before a fresh confirmation'),
      );
    }
    final nextAgent = PersonalAgent(
      repository: repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: OutboundLedger(db)),
      tools: tools,
    );
    addTearDown(nextAgent.close);
    final resumed = await nextAgent.resume(child.id);
    expect(resumed.previousAttemptId, child.id);
    expect(resumed.state, PersonalTaskState.waitingConfirmation);
    expect(resumed.payload['candidateIds'] as List, contains('read'));
    expect(resumed.payload['candidateIds'] as List, isNot(contains('write')));
    expect(
      resumed.payload['requestDigest'],
      isNot(child.payload['requestDigest']),
    );
    expect(f.bodies, isEmpty);
    await expectLater(
      nextAgent.startTool(
        conversationId: ref.childConversationId,
        toolId: 'write',
        parameters: {},
      ),
      throwsStateError,
    );
  });
}
