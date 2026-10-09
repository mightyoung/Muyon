import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/assistant_subconversations.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

// Changing getters probe public registration's trust boundary. Production
// descriptors have final effects and the registry has no replacement API.
class ChangingDescriptor extends ToolDescriptor {
  ChangingDescriptor()
    : super(
        toolId: 'probe',
        moduleId: 'test',
        effect: ToolEffect.read,
        description: '查询预算',
        parameterSchema: {'type': 'object', 'additionalProperties': false},
      );
  ToolEffect current = ToolEffect.read;
  @override
  ToolEffect get effect => current;
}

void main() {
  for (final boundary in [1, 2, 3]) {
    for (final change in ['withdraw', 'write', 'export', 'network']) {
      test(
        'child $change at prepare boundary $boundary has no effect',
        () async {
          final f = await LoopFixture.open();
          final entered = Completer<void>();
          final release = Completer<void>();
          final descriptor = ChangingDescriptor();
          var resolves = 0;
          var calls = 0;
          final tools = ToolRegistry(
            database: f.repo.database,
            resolveScope: (scope) async {
              resolves++;
              if (resolves == boundary) {
                entered.complete();
                await release.future;
              }
              return ResolvedAssistantScope(
                requested: scope,
                objects: f.objects,
              );
            },
          );
          tools.register(
            providerId: 'probe-provider',
            descriptor: descriptor,
            handler: (_) async {
              calls++;
              return ToolCallResult(
                status: ToolCallStatus.invalidArguments,
                summary: 'bad input',
              );
            },
          );
          final agent = PersonalAgent(
            repository: f.repo,
            gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
            tools: tools,
          );
          addTearDown(agent.close);
          final parent = await agent.start(
            conversationId: (await f.repo.createConversation()).id,
            prompt: '父任务',
          );
          final child = await AssistantSubconversations(f.repo)
              .openSubconversation(parent.id, '只读查询');
          f.replies.add(
            LoopReply.sse(sseCalls([('probe-call', 'probe', '{}')])),
          );
          final first = await f.start(
            agent,
            f.profile(),
            conversationId: child.childConversationId,
          );
          expect(first.payload['candidateIds'] as List, contains('probe'));
          final running = f.run(agent, first, confirmTools: true);
          await entered.future.timeout(const Duration(seconds: 10));
          if (change == 'withdraw') {
            tools.setAvailability('probe', available: false);
          } else {
            descriptor.current = switch (change) {
              'write' => ToolEffect.write,
              'export' => ToolEffect.export,
              _ => ToolEffect.network,
            };
          }
          release.complete();
          final settled = await running;
          expect(
            calls,
            0,
            reason: 'a frozen read must never run a changed handler',
          );
          expect(settled.state, PersonalTaskState.failed);
          expect(
            f.bodies,
            hasLength(1),
            reason: 'refusal must not recover to model',
          );
          expect(f.approvals(), isEmpty);
          for (final receipt in f.receipts()) {
            expect(
              jsonDecode(receipt['result_json'] as String)['status'],
              'failed',
            );
          }
        },
      );
    }
  }
  test(
    'normal child read and independently confirmed parent write still run',
    () async {
      final f = await LoopFixture.open();
      final agent = f.agent();
      final parent = await agent.start(
        conversationId: (await f.repo.createConversation()).id,
        prompt: '父任务',
      );
      final child = await AssistantSubconversations(f.repo)
          .openSubconversation(parent.id, '只读查询');
      final read = await agent.startTool(
        conversationId: child.childConversationId,
        toolId: 'read',
      );
      expect(read.state, PersonalTaskState.succeeded);
      expect(f.callsOf('read'), 1);
      expect(f.approvals(), isEmpty);
      final write = await agent.startTool(
        conversationId: parent.conversationId,
        toolId: 'write',
      );
      expect(write.state, PersonalTaskState.waitingConfirmation);
      expect(f.callsOf('write'), 0);
      final settled = await f.run(agent, write, confirmTools: true);
      expect(settled.state, PersonalTaskState.succeeded);
      expect(f.callsOf('write'), 1);
      expect(f.approvals().single['state'], 'consumed');
    },
  );
  for (final status in [
    ToolCallStatus.failed,
    ToolCallStatus.blocked,
    ToolCallStatus.cancelled,
    ToolCallStatus.interrupted,
  ]) {
    test(
      'invalid read alongside $status never recovers or runs old write',
      () async {
        final f = await LoopFixture.open();
        f.addTool(
          'invalid',
          ToolEffect.read,
          onCall: (_) async => ToolCallResult(
            status: ToolCallStatus.invalidArguments,
            summary: 'bad input',
          ),
        );
        f.addTool(
          'stop',
          ToolEffect.read,
          onCall: (_) async => ToolCallResult(status: status, summary: 'stop'),
        );
        f.replies.add(
          LoopReply.sse(
            sseCalls([
              ('bad', 'invalid', '{}'),
              ('stop', 'stop', '{}'),
              ('old-write', 'write', '{}'),
            ]),
          ),
        );
        final agent = f.agent();
        final settled = await f.run(
          agent,
          await f.start(agent, f.profile()),
          confirmTools: true,
        );
        expect(settled.terminal, isTrue);
        expect(f.bodies, hasLength(1));
        expect(f.callsOf('write'), 0);
        expect(f.approvals(), isEmpty);
        expect(f.receipts(), hasLength(2));
        expect(
          f.tools.history().map((r) => r.status),
          containsAll([ToolCallStatus.invalidArguments, status]),
        );
        expect(settled.payload['round'], 1);
      },
    );
  }
}
