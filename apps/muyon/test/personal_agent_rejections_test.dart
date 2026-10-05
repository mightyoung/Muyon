import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/tool_selection.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

/// Rejection paths of the personal assistant: invalid starts, frozen
/// candidates, confirmation guards, cancelled/failed model requests that must
/// never persist an answer, and closing with a request in flight.
void main() {
  late ManagedConnection db;
  late FoundationRepository repo;
  late ToolRegistry tools;
  late PersonalAgent agent;
  var calls = 0;
  const ref = ObjectRef(
    moduleId: 'test',
    objectType: 'item',
    objectId: '1',
    revisionRef: 'v1',
  );
  final profile = ModelProfile(
    id: 'local',
    endpoint: Uri.parse('http://127.0.0.1:9/v1/chat/completions'),
    location: ModelLocation.local,
    modelId: 'test',
    endpointIdentity: 'test-local',
  );

  ManagedConnection database() {
    final value = ManagedConnection(sqlite3.openInMemory());
    for (final migration in WorkspaceRepository.schema.migrations) {
      migration.migrate(value.raw);
    }
    return value;
  }

  void registerTools(ToolRegistry registry) {
    for (final effect in [ToolEffect.read, ToolEffect.write]) {
      registry.register(
        providerId: 'test',
        descriptor: ToolDescriptor(
          toolId: effect.name,
          moduleId: 'test',
          effect: effect,
          description: '读取测试对象',
          parameterSchema: {
            'type': 'object',
            'properties': <String, Object?>{},
            'additionalProperties': false,
          },
        ),
        handler: (context) async {
          calls++;
          return ToolCallResult(
            status: ToolCallStatus.succeeded,
            summary: 'actual result',
            data: {'value': 42},
            objectRefs: [ref],
          );
        },
      );
    }
    registry.register(
      providerId: 'test',
      descriptor: ToolDescriptor(
        toolId: 'broken',
        moduleId: 'test',
        effect: ToolEffect.read,
        parameterSchema: {
          'type': 'object',
          'properties': <String, Object?>{},
          'additionalProperties': false,
        },
      ),
      handler: (context) async => ToolCallResult(
        status: ToolCallStatus.failed,
        summary: '工具执行失败：远端错误',
      ),
    );
  }

  setUp(() {
    db = database();
    repo = FoundationRepository(db);
    tools = ToolRegistry(
      database: db,
      resolveScope: (scope) async =>
          ResolvedAssistantScope(requested: scope, objects: [ref]),
    );
    registerTools(tools);
    calls = 0;
    agent = PersonalAgent(
      repository: repo,
      gateway: _ScriptedGateway(
        () async => '{"type":"answer","answer":"ok"}',
      ),
      tools: tools,
    );
  });
  tearDown(() async {
    await agent.close();
    await db.close();
  });

  Future<void> confirm(PersonalTask task) => agent.confirm(
    task.id,
    requestDigest: task.payload['requestDigest'] as String,
  );

  test('rejects a non-chat profile and missing conversation or prompt', () async {
    final c = await repo.createConversation();
    final embedding = ModelProfile(
      id: 'embed',
      endpoint: Uri.parse('http://127.0.0.1:9/v1/embeddings'),
      location: ModelLocation.local,
      modelId: 'embed',
      endpointIdentity: 'local-embed',
      purpose: ModelPurpose.embedding,
    );
    await expectLater(
      agent.start(conversationId: c.id, prompt: 'x', profile: embedding),
      throwsArgumentError,
    );
    await expectLater(
      agent.start(conversationId: 'missing', prompt: 'x'),
      throwsArgumentError,
    );
    await expectLater(
      agent.start(conversationId: c.id, prompt: '   '),
      throwsArgumentError,
    );
    await expectLater(
      agent.startTool(conversationId: 'missing', toolId: 'read'),
      throwsStateError,
    );
  });

  test('a selection outside the registered candidates is rejected', () async {
    final bad = PersonalAgent(
      repository: repo,
      gateway: _ScriptedGateway(
        () async => '{"type":"answer","answer":"ok"}',
      ),
      tools: tools,
      selectionStrategy: _GhostStrategy(),
    );
    addTearDown(bad.close);
    final c = await repo.createConversation();
    await expectLater(
      bad.start(conversationId: c.id, prompt: 'x'),
      throwsStateError,
    );
  });

  test('pause and resume only work at the confirmation boundary', () async {
    final c = await repo.createConversation();
    final task = await agent.startTool(conversationId: c.id, toolId: 'write');
    await expectLater(agent.resume(task.id), throwsStateError);
    await agent.pause(task.id);
    expect(repo.task(task.id)!.state, PersonalTaskState.paused);
    await expectLater(agent.pause(task.id), throwsStateError);
    await expectLater(agent.resume('missing'), throwsStateError);
  });

  test('concurrent confirmation of the same task is refused', () async {
    final gateway = _BlockingGateway();
    agent = PersonalAgent(repository: repo, gateway: gateway, tools: tools);
    final c = await repo.createConversation();
    final task = await agent.start(
      conversationId: c.id,
      prompt: 'x',
      profile: profile,
    );
    final first = confirm(task);
    await gateway.started.future;
    await expectLater(confirm(task), throwsStateError);
    gateway.release.complete();
    await first;
    expect(repo.task(task.id)!.state, PersonalTaskState.succeeded);
  });

  test('a changed conversation scope is refused before any send', () async {
    var sent = 0;
    agent = PersonalAgent(
      repository: repo,
      gateway: _ScriptedGateway(() async {
        sent++;
        return '{"type":"answer","answer":"ok"}';
      }),
      tools: tools,
    );
    final c = await repo.createConversation(
      scope: AssistantScope.workspace('one'),
    );
    final task = await agent.start(
      conversationId: c.id,
      prompt: 'x',
      profile: profile,
    );
    await repo.database.write(
      (value) => value.execute(
        'UPDATE conversations SET scope_json=? WHERE id=?',
        [jsonEncode(AssistantScope.workspace('two').toJson()), c.id],
      ),
    );
    await expectLater(confirm(task), throwsStateError);
    expect(sent, 0);
  });

  test('a changed preview is refused before any send', () async {
    var sent = 0;
    agent = PersonalAgent(
      repository: repo,
      gateway: _ScriptedGateway(() async {
        sent++;
        return '{"type":"answer","answer":"ok"}';
      }),
      tools: tools,
    );
    final c = await repo.createConversation();
    final task = await agent.start(
      conversationId: c.id,
      prompt: 'x',
      profile: profile,
    );
    await repo.updateTask(task.copy({'preview': {'changed': true}}));
    await confirm(task);
    expect(repo.task(task.id)!.state, PersonalTaskState.failed);
    expect(sent, 0);
  });

  test('a tool registry change is refused before any call', () async {
    final c = await repo.createConversation();
    final task = await agent.startTool(conversationId: c.id, toolId: 'write');
    tools.setAvailability('write', available: true);
    await confirm(task);
    expect(repo.task(task.id)!.state, PersonalTaskState.failed);
    expect(calls, 0);
  });

  test('a confirmation that cannot be consumed is refused', () async {
    final localDb = database();
    addTearDown(localDb.close);
    final localRepo = _NoCommitRepository(localDb);
    final localTools = ToolRegistry(
      database: localDb,
      resolveScope: (scope) async =>
          ResolvedAssistantScope(requested: scope, objects: [ref]),
    );
    registerTools(localTools);
    final localAgent = PersonalAgent(
      repository: localRepo,
      gateway: _ScriptedGateway(
        () async => '{"type":"answer","answer":"ok"}',
      ),
      tools: localTools,
    );
    addTearDown(localAgent.close);
    final c = await localRepo.createConversation();
    final task = await localAgent.startTool(
      conversationId: c.id,
      toolId: 'write',
    );
    localRepo.block = true;
    await expectLater(
      localAgent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      ),
      throwsStateError,
    );
  });

  test('citations outside the frozen evidence fail without an answer', () async {
    agent = PersonalAgent(
      repository: repo,
      gateway: _ScriptedGateway(
        () async =>
            '{"type":"answer","answer":"42","citationIds":["r1"]}',
      ),
      tools: tools,
    );
    final c = await repo.createConversation();
    final task = await agent.start(
      conversationId: c.id,
      prompt: 'x',
      profile: profile,
    );
    await confirm(task);
    expect(repo.task(task.id)!.state, PersonalTaskState.failed);
    expect(repo.messages(c.id).where((m) => m.role == 'assistant'), isEmpty);
  });

  test('a failed tool result fails the task without an answer', () async {
    final c = await repo.createConversation();
    final task = await agent.startTool(conversationId: c.id, toolId: 'broken');
    expect(repo.task(task.id)!.state, PersonalTaskState.failed);
    expect(repo.task(task.id)!.error, contains('工具执行失败'));
    expect(repo.messages(c.id).where((m) => m.role == 'assistant'), isEmpty);
  });

  test('a cancelled model request fails the task without an answer', () async {
    var taskId = '';
    agent = PersonalAgent(
      repository: repo,
      gateway: _ScriptedGateway(
        () async => '{"type":"answer","answer":"late"}',
        onBeforeSend: () async {
          final task = repo.task(taskId)!;
          await repo.updateTask(
            task.copy({'state': 'cancelled', 'stage': 'cancelled'}),
          );
        },
      ),
      tools: tools,
    );
    final c = await repo.createConversation();
    final task = await agent.start(
      conversationId: c.id,
      prompt: 'x',
      profile: profile,
    );
    taskId = task.id;
    await confirm(task);
    expect(repo.task(task.id)!.state, PersonalTaskState.cancelled);
    expect(repo.messages(c.id).where((m) => m.role == 'assistant'), isEmpty);
  });

  test('a scope change during send is refused without an answer', () async {
    var conversationId = '';
    agent = PersonalAgent(
      repository: repo,
      gateway: _ScriptedGateway(
        () async => '{"type":"answer","answer":"late"}',
        onBeforeSend: () async {
          await repo.database.write(
            (value) => value.execute(
              'UPDATE conversations SET scope_json=? WHERE id=?',
              [jsonEncode(AssistantScope.workspace('two').toJson()), conversationId],
            ),
          );
        },
      ),
      tools: tools,
    );
    final c = await repo.createConversation(
      scope: AssistantScope.workspace('one'),
    );
    conversationId = c.id;
    final task = await agent.start(
      conversationId: c.id,
      prompt: 'x',
      profile: profile,
    );
    await confirm(task);
    expect(repo.task(task.id)!.state, PersonalTaskState.failed);
    expect(repo.messages(c.id).where((m) => m.role == 'assistant'), isEmpty);
  });

  test('the tool loop stops at the round limit', () async {
    agent = PersonalAgent(
      repository: repo,
      gateway: _ScriptedGateway(
        () async => '{"type":"tool","toolId":"read","parameters":{}}',
      ),
      tools: tools,
      maxRounds: 1,
    );
    final c = await repo.createConversation();
    final task = await agent.start(
      conversationId: c.id,
      prompt: 'x',
      profile: profile,
    );
    await confirm(task);
    final after = repo.task(task.id)!;
    expect(after.state, PersonalTaskState.failed);
    expect(after.error, contains('轮次'));
  });

  test('an oversized model context is refused before any send', () async {
    var sent = 0;
    agent = PersonalAgent(
      repository: repo,
      gateway: _ScriptedGateway(() async {
        sent++;
        return '{"type":"answer","answer":"ok"}';
      }),
      tools: tools,
    );
    final c = await repo.createConversation();
    for (var i = 0; i < 16; i++) {
      await repo.appendMessage(c.id, 'user', 'x' * 20000);
    }
    final task = await agent.start(
      conversationId: c.id,
      prompt: 'x',
      profile: profile,
    );
    final after = repo.task(task.id)!;
    expect(after.state, PersonalTaskState.failed);
    expect(after.error, contains('上下文过大'));
    expect(sent, 0);
  });

  test('closing cancels an in-flight model request', () async {
    final gateway = _BlockingGateway();
    agent = PersonalAgent(repository: repo, gateway: gateway, tools: tools);
    final c = await repo.createConversation();
    final task = await agent.start(
      conversationId: c.id,
      prompt: 'x',
      profile: profile,
    );
    final running = confirm(task);
    await gateway.started.future;
    await agent.close();
    await running;
    expect(repo.task(task.id)!.state, isNot(PersonalTaskState.succeeded));
    expect(repo.messages(c.id).where((m) => m.role == 'assistant'), isEmpty);
  });
}

class _GhostStrategy implements ToolSelectionStrategy {
  @override
  String get id => 'ghost';
  @override
  ToolSelection select({
    required String prompt,
    required AssistantScope scope,
    required List<RegisteredToolInfo> availableTools,
    required bool modelAvailable,
  }) => ToolSelection(candidateIds: const ['ghost']);
}

class _NoCommitRepository extends FoundationRepository {
  _NoCommitRepository(super.database);
  bool block = false;
  @override
  Future<bool> updateTask(
    PersonalTask next, {
    Set<PersonalTaskState>? expected,
    bool Function()? canCommit,
    String? assistantAnswer,
    List<ObjectRef> references = const [],
  }) {
    if (block) return Future.value(false);
    return super.updateTask(
      next,
      expected: expected,
      canCommit: canCommit,
      assistantAnswer: assistantAnswer,
      references: references,
    );
  }
}

class _ScriptedGateway extends OpenAiModelGateway {
  _ScriptedGateway(this.script, {this.onBeforeSend})
    : super(UnavailableSecretStore());
  final Future<String> Function() script;
  final Future<void> Function()? onBeforeSend;
  @override
  Future<String> chat({
    required ModelProfile profile,
    required List<Map<String, String>> messages,
    ModelCancellation? cancellation,
    Future<void> Function()? beforeSend,
    String caller = 'chat',
  }) async {
    if (onBeforeSend != null) await onBeforeSend!();
    if (beforeSend != null) await beforeSend();
    return script();
  }
}

class _BlockingGateway extends OpenAiModelGateway {
  _BlockingGateway() : super(UnavailableSecretStore());
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<String> chat({
    required ModelProfile profile,
    required List<Map<String, String>> messages,
    ModelCancellation? cancellation,
    Future<void> Function()? beforeSend,
    String caller = 'chat',
  }) async {
    if (beforeSend != null) await beforeSend();
    started.complete();
    final cancelled = Completer<void>();
    cancellation?.add(() => cancelled.complete());
    await Future.any([release.future, cancelled.future]);
    cancellation?.check();
    return '{"type":"answer","answer":"ok"}';
  }
}
