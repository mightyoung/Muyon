import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/execution_store.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/tool_selection.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/screens/assistant_page.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/profile_repository.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

class _SelectedReadStrategy implements ToolSelectionStrategy {
  @override
  String get id => 'test-read-selection';
  final candidates = <String>['read'];
  @override
  ToolSelection select({
    required String prompt,
    required AssistantScope scope,
    required List<RegisteredToolInfo> availableTools,
    required bool modelAvailable,
  }) => ToolSelection(
    candidateIds: candidates,
    ruleToolId: modelAvailable ? null : 'read',
  );
}

void main() {
  late Directory dir;
  late StorageManager storage;
  late FoundationRepository repo;
  late PersonalAgent agent;
  late ToolRegistry tools;
  const ref = ObjectRef(
    moduleId: 'test',
    objectType: 'item',
    objectId: '1',
    revisionRef: 'v1',
  );
  late int calls;
  setUp(() async {
    HttpOverrides.global = null;
    dir = Directory.systemTemp.createTempSync('personal-agent');
    storage = StorageManager(dir.path);
    repo = FoundationRepository(
      await storage.open('muyon', WorkspaceRepository.schema),
    );
    tools = ToolRegistry(
      database: repo.database,
      resolveScope: (scope) async =>
          ResolvedAssistantScope(requested: scope, objects: [ref]),
    );
    calls = 0;
    for (final effect in [ToolEffect.read, ToolEffect.write]) {
      tools.register(
        providerId: 'test',
        descriptor: ToolDescriptor(
          toolId: effect.name,
          moduleId: 'test',
          effect: effect,
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
    agent = PersonalAgent(
      repository: repo,
      gateway: OpenAiModelGateway(UnavailableSecretStore()),
      tools: tools,
    );
  });
  tearDown(() async {
    await agent.close();
    await storage.close();
    dir.deleteSync(recursive: true);
  });

  Future<void> confirm(PersonalTask task) => agent.confirm(
    task.id,
    requestDigest: task.payload['requestDigest'] as String,
  );
  Future<(HttpServer, ModelProfile)> server(
    Future<String> Function(int) respond,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var count = 0;
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      final content = await respond(++count);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {'content': content},
            },
          ],
        }),
      );
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    return (
      server,
      ModelProfile(
        id: 'local',
        endpoint: Uri.parse(
          'http://127.0.0.1:${server.port}/v1/chat/completions',
        ),
        location: ModelLocation.local,
        modelId: 'test',
        endpointIdentity: 'test-local',
      ),
    );
  }

  test(
    'real model tool loop requires each send consent and keeps real citations',
    () async {
      var sent = 0;
      final fixture = await server((count) async {
        sent++;
        return jsonEncode(
          count == 1
              ? {'type': 'tool', 'toolId': 'read', 'parameters': {}}
              : {
                  'type': 'answer',
                  'answer': '42',
                  'citationIds': ['r1'],
                },
        );
      });
      final c = await repo.createConversation();
      var task = await agent.start(
        conversationId: c.id,
        prompt: 'calculate',
        profile: fixture.$2,
      );
      expect(sent, 0);
      expect(calls, 0);
      await confirm(task);
      task = repo.task(task.id)!;
      expect(task.state, PersonalTaskState.waitingConfirmation);
      expect(sent, 1);
      expect(calls, 1);
      await confirm(task);
      expect(repo.task(task.id)!.state, PersonalTaskState.succeeded);
      expect(repo.messages(c.id).last.references, [ref]);
      expect(sent, 2);
      await expectLater(confirm(task), throwsStateError);
      expect(sent, 2);
      expect(ExecutionStore(repo.database).all(), isEmpty);
    },
  );

  test(
    'write requires one host confirmation; pause resume gets new attempt',
    () async {
      final c = await repo.createConversation();
      final task = await agent.startTool(conversationId: c.id, toolId: 'write');
      expect(calls, 0);
      await agent.pause(task.id);
      final resumed = await agent.resume(task.id);
      expect(resumed.id, isNot(task.id));
      expect(resumed.previousAttemptId, task.id);
      expect(calls, 0);
      await confirm(resumed);
      expect(calls, 1);
      await expectLater(confirm(resumed), throwsStateError);
      expect(calls, 1);
    },
  );

  test(
    'scope mismatch and changed memory prevent network transmission',
    () async {
      var sent = 0;
      final fixture = await server((_) async {
        sent++;
        return '{"type":"answer","answer":"no"}';
      });
      final c = await repo.createConversation(
        scope: AssistantScope.workspace('one'),
      );
      await expectLater(
        agent.start(
          conversationId: c.id,
          prompt: 'x',
          scope: AssistantScope.workspace('two'),
        ),
        throwsStateError,
      );
      final memory = await repo.saveMemory(
        content: 'secret',
        source: 'user-confirmed',
      );
      final task = await agent.start(
        conversationId: c.id,
        prompt: 'x',
        profile: fixture.$2,
      );
      await repo.deleteMemory(memory);
      await confirm(task);
      expect(sent, 0);
      expect(repo.task(task.id)!.state, PersonalTaskState.failed);
      expect(repo.messages(c.id).where((m) => m.role == 'assistant'), isEmpty);
    },
  );

  test('cancel while model running never persists a late answer', () async {
    final arrived = Completer<void>(), release = Completer<void>();
    final fixture = await server((_) async {
      arrived.complete();
      await release.future;
      return '{"type":"answer","answer":"late"}';
    });
    final c = await repo.createConversation();
    final task = await agent.start(
      conversationId: c.id,
      prompt: 'x',
      profile: fixture.$2,
    );
    final run = confirm(task);
    await arrived.future;
    await agent.cancel(task.id);
    release.complete();
    await run;
    expect(repo.task(task.id)!.state, PersonalTaskState.cancelled);
    expect(repo.messages(c.id).where((m) => m.role == 'assistant'), isEmpty);
  });

  test(
    'persistent memory scope revision expiry and notifications survive restart',
    () async {
      final c = await repo.createConversation();
      final m = await repo.saveMemory(
        content: 'a',
        source: 'manual',
        scope: AssistantScope.workspace('one'),
        sourceRef: ref,
      );
      await repo.saveMemory(
        id: m,
        content: 'b',
        source: 'manual',
        scope: AssistantScope.workspace('one'),
        sourceRef: ref,
      );
      expect(repo.memories().single.revision, 2);
      await repo.saveMemory(
        content: 'expired',
        source: 'manual',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      await repo.notify(title: 'hello', body: 'world');
      await agent.startTool(conversationId: c.id, toolId: 'write');
      await agent.close();
      await storage.close();
      storage = StorageManager(dir.path);
      repo = FoundationRepository(
        await storage.open('muyon', WorkspaceRepository.schema),
      );
      agent = PersonalAgent(
        repository: repo,
        gateway: OpenAiModelGateway(UnavailableSecretStore()),
        tools: tools,
      );
      await repo.recoverInterrupted();
      expect(repo.tasks().single.state, PersonalTaskState.waitingConfirmation);
      expect(repo.memories().single.content, 'b');
      expect(repo.memories().single.sourceRef, ref);
      expect(repo.memories(includeExpired: true).length, 2);
      await repo.markNotificationRead(repo.notifications().single.id);
      expect(repo.notifications(unreadOnly: true), isEmpty);
    },
  );

  test(
    'recovery interrupts active tasks; contextual memory never leaks globally',
    () async {
      final fixture = await server(
        (_) async => '{"type":"answer","answer":"ok"}',
      );
      final c = await repo.createConversation();
      await repo.saveMemory(
        content: 'project secret',
        source: 'manual',
        scope: AssistantScope.workspace('other'),
      );
      await repo.saveMemory(
        content: 'unverified secret',
        source: 'suggestion',
        verified: false,
      );
      final task = await agent.start(
        conversationId: c.id,
        prompt: 'hello',
        profile: fixture.$2,
      );
      expect(
        jsonEncode(task.payload['messages']),
        isNot(contains('project secret')),
      );
      expect(
        jsonEncode(task.payload['messages']),
        isNot(contains('unverified secret')),
      );
      await repo.updateTask(task.copy({'state': 'running'}));
      await repo.recoverInterrupted();
      expect(repo.task(task.id)!.state, PersonalTaskState.interrupted);
      final next = await agent.resume(task.id);
      expect(next.state, PersonalTaskState.waitingConfirmation);
      expect(next.previousAttemptId, task.id);
    },
  );

  test(
    'host close drains a running offline tool and blocks late results',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      tools.register(
        providerId: 'test',
        descriptor: ToolDescriptor(
          toolId: 'slow',
          parameterSchema: {
            'type': 'object',
            'properties': <String, Object?>{},
            'additionalProperties': false,
          },
          moduleId: 'test',
          effect: ToolEffect.read,
        ),
        handler: (context) async {
          entered.complete();
          await release.future;
          return ToolCallResult(
            status: ToolCallStatus.succeeded,
            summary: 'late',
          );
        },
      );
      final c = await repo.createConversation();
      final start = agent.startTool(conversationId: c.id, toolId: 'slow');
      await entered.future;
      var closed = false;
      final close = agent.close().then((_) {
        closed = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(closed, false);
      release.complete();
      await start;
      await close;
      expect(repo.tasks().single.state, PersonalTaskState.interrupted);
      expect(repo.messages(c.id).where((m) => m.role == 'assistant'), isEmpty);
    },
  );

  test('injected selection replaces offline routing and persists evaluation identity', () async {
    agent = PersonalAgent(
      repository: repo,
      gateway: OpenAiModelGateway(UnavailableSecretStore()),
      tools: tools,
      selectionStrategy: _SelectedReadStrategy(),
    );
    final c = await repo.createConversation();
    final task = await agent.start(
      conversationId: c.id,
      prompt: 'please inspect local records',
    );
    expect(task.state, PersonalTaskState.succeeded);
    expect(calls, 1);
    expect(task.payload['strategyId'], 'test-read-selection');
    expect(task.payload['candidateIds'], ['read']);
  });

  test('model cannot propose outside frozen candidates even if strategy later changes', () async {
    final strategy = _SelectedReadStrategy();
    agent = PersonalAgent(
      repository: repo,
      gateway: OpenAiModelGateway(UnavailableSecretStore()),
      tools: tools,
      selectionStrategy: strategy,
    );
    final fixture = await server(
      (_) async => '{"type":"tool","toolId":"write","parameters":{}}',
    );
    final c = await repo.createConversation();
    final task = await agent.start(
      conversationId: c.id,
      prompt: 'inspect',
      profile: fixture.$2,
    );
    final system = jsonDecode(
      (task.payload['messages'] as List).first['content'] as String,
    ) as Map;
    expect((system['tools'] as List).map((t) => t['toolId']), ['read']);
    strategy.candidates.add('write');
    await confirm(task);
    expect(repo.task(task.id)!.state, PersonalTaskState.failed);
    expect(repo.task(task.id)!.payload['candidateIds'], ['read']);
    expect(calls, 0);
    expect(repo.messages(c.id).where((m) => m.role == 'assistant'), isEmpty);
    final manual = await agent.startTool(conversationId: c.id, toolId: 'write');
    expect(manual.state, PersonalTaskState.waitingConfirmation);
    expect(calls, 0);
    await confirm(manual);
    expect(calls, 1);
  });

  test(
    'default missing-model fallback preserves explicit local rule',
    () async {
      final c = await repo.createConversation();
      final task = await agent.start(conversationId: c.id, prompt: 'read');
      expect(task.state, PersonalTaskState.succeeded);
      expect(task.payload['strategyId'], 'registered-rule-model-v1');
      expect(task.payload['candidateIds'], ['read']);
      expect(calls, 1);
    },
  );

  testWidgets('page disposal leaves host task active', (tester) async {
    final c = (await tester.runAsync(() => repo.createConversation()))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistantPage(
            repo: repo,
            agent: agent,
            profiles: ProfileRepository(WorkspaceRepository(repo.database)),
            conversationId: c.id,
          ),
        ),
      ),
    );
    final task = (await tester.runAsync(
      () => agent.startTool(conversationId: c.id, toolId: 'write'),
    ))!;
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => confirm(task));
    expect(repo.task(task.id)!.state, PersonalTaskState.succeeded);
    expect(repo.messages(c.id).last.content, contains('actual result'));
    expect(tester.takeException(), isNull);
  });
}
