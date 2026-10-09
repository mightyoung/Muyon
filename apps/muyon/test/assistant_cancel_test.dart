import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

/// What a task says after "cancel": only what the tool receipt supports.
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

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('assistant-cancel');
    storage = StorageManager(dir.path);
    repo = FoundationRepository(
      await storage.open('muyon', WorkspaceRepository.schema),
    );
    tools = ToolRegistry(
      database: repo.database,
      resolveScope: (scope) async =>
          ResolvedAssistantScope(requested: scope, objects: [ref]),
    );
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

  void register(
    String id,
    ToolEffect effect,
    Future<ToolCallResult> Function(ToolCallContext) handler, {
    bool supportsCancel = true,
  }) => tools.register(
    providerId: 'test',
    descriptor: ToolDescriptor(
      toolId: id,
      moduleId: 'test',
      effect: effect,
      supportsCancel: supportsCancel,
      parameterSchema: {
        'type': 'object',
        'properties': <String, Object?>{},
        'additionalProperties': false,
      },
    ),
    handler: handler,
  );

  ToolCallResult ok() => ToolCallResult(
    status: ToolCallStatus.succeeded,
    summary: 'actual result',
    data: {'value': 42},
    objectRefs: [ref],
  );

  Future<void> confirm(PersonalTask task) => agent.confirm(
    task.id,
    requestDigest: task.payload['requestDigest'] as String,
  );

  Future<void> until(bool Function() ready, String label) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!ready()) {
      if (DateTime.now().isAfter(deadline)) fail(label);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  int answers(String conversationId) =>
      repo.messages(conversationId).where((m) => m.role == 'assistant').length;

  test(
    'cancel while waiting for confirmation is cancelled and never runs',
    () async {
      var calls = 0;
      register('w', ToolEffect.write, (c) async {
        calls++;
        return ok();
      });
      final c = await repo.createConversation();
      final task = await agent.startTool(conversationId: c.id, toolId: 'w');
      expect(task.state, PersonalTaskState.waitingConfirmation);
      await agent.cancel(task.id);
      expect(repo.task(task.id)!.state, PersonalTaskState.cancelled);
      await expectLater(confirm(task), throwsStateError);
      expect(calls, 0);
    },
  );

  test(
    'cancel before the effect point is cancelled and the effect never happens',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      var effect = 0;
      register('w', ToolEffect.write, (c) async {
        entered.complete();
        await release.future;
        c.checkBeforeEffect(); // cancelled here: nothing happens
        effect++;
        return ok();
      });
      final c = await repo.createConversation();
      final task = await agent.startTool(conversationId: c.id, toolId: 'w');
      final running = confirm(task);
      await entered.future;
      await agent.cancel(task.id);
      expect(repo.task(task.id)!.stage, 'cancelling');
      expect(
        repo.task(task.id)!.state,
        PersonalTaskState.running,
        reason: 'the receipt has not decided yet',
      );
      release.complete();
      await running;
      expect(repo.task(task.id)!.state, PersonalTaskState.cancelled);
      expect(effect, 0);
      expect(tools.history().single.status, ToolCallStatus.cancelled);
      expect(answers(c.id), 0);
    },
  );

  for (final supportsCancel in [true, false]) {
    test('cancel after the effect point is interrupted, not cancelled '
        '(supportsCancel=$supportsCancel)', () async {
      final past = Completer<void>(), release = Completer<void>();
      var effect = 0;
      register('w', ToolEffect.write, (c) async {
        c.checkBeforeEffect();
        effect++; // the write happened
        past.complete();
        await release.future;
        return ok();
      }, supportsCancel: supportsCancel);
      final c = await repo.createConversation();
      final task = await agent.startTool(conversationId: c.id, toolId: 'w');
      final running = confirm(task);
      await past.future;
      await agent.cancel(task.id);
      release.complete();
      await running;
      final after = repo.task(task.id)!;
      expect(effect, 1);
      expect(after.state, PersonalTaskState.interrupted);
      expect(after.payload['error'], contains('已请求取消，但操作可能已生效，重试前请先核实'));
      expect(
        tools.history().single.status,
        ToolCallStatus.interrupted,
        reason: 'the task agrees with the receipt',
      );
      expect(answers(c.id), 0);
      expect(repo.notifications().any((n) => n.title == '助手任务结果未知'), isTrue);
    });
  }

  test('a read tool cancelled mid-run is cancelled (no external effect) and its result discarded', () async {
    final entered = Completer<void>(), release = Completer<void>();
    register('r', ToolEffect.read, (c) async {
      entered.complete();
      await release.future;
      return ok();
    });
    final c = await repo.createConversation();
    final start = agent.startTool(conversationId: c.id, toolId: 'r');
    await entered.future;
    final id = repo.tasks().single.id;
    await agent.cancel(id);
    release.complete();
    await start;
    expect(repo.task(id)!.state, PersonalTaskState.cancelled);
    expect(answers(c.id), 0);
  });

  test(
    'an interrupted receipt without any cancel is interrupted, not failed',
    () async {
      register('w', ToolEffect.write, (c) async {
        c.checkBeforeEffect();
        throw StateError('connection dropped after sending');
      });
      final c = await repo.createConversation();
      final task = await agent.startTool(conversationId: c.id, toolId: 'w');
      await confirm(task);
      final after = repo.task(task.id)!;
      expect(after.state, PersonalTaskState.interrupted);
      expect(after.payload['error'], contains('结果未知'));
    },
  );

  test(
    'cancel racing a finishing tool leaves exactly one consistent outcome',
    () async {
      for (var round = 0; round < 25; round++) {
        final id = 'w$round';
        final release = Completer<void>(), past = Completer<void>();
        register(id, ToolEffect.write, (c) async {
          c.checkBeforeEffect();
          past.complete();
          await release.future;
          return ok();
        });
        final c = await repo.createConversation();
        final task = await agent.startTool(conversationId: c.id, toolId: id);
        final running = confirm(task);
        await past.future;
        // Release and cancel in the same turn, in alternating order.
        if (round.isEven) {
          release.complete();
          unawaited(agent.cancel(task.id));
        } else {
          unawaited(agent.cancel(task.id));
          release.complete();
        }
        await running;
        await until(
          () => repo.task(task.id)!.terminal,
          'task settled ($round)',
        );
        final state = repo.task(task.id)!.state;
        expect([
          PersonalTaskState.succeeded,
          PersonalTaskState.interrupted,
          PersonalTaskState.cancelled,
        ], contains(state));
        final receipt = tools.history().first.status;
        switch (state) {
          case PersonalTaskState.succeeded:
            expect(receipt, ToolCallStatus.succeeded);
            expect(answers(c.id), 1);
            expect(repo.messages(c.id).singleWhere((m) => m.role == 'assistant').content, contains('value：42'));
            expect(tools.history().first.data, {'value': 42});
          case PersonalTaskState.interrupted:
            expect(receipt, ToolCallStatus.interrupted);
            expect(answers(c.id), 0);
          default:
            fail('effect had happened, so cancelled is untrue: $state');
        }
      }
    },
  );
}
