import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/host_effect_intent.dart';
import 'package:muyon/platform/grants/outbound_content_reviewer.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/tool_names.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

void main() {
  for (final recreateAgent in [false, true]) {
    for (final manualStart in [false, true]) {
      test(
        'native complete destination snapshots remain private (recreate Agent: $recreateAgent, manual start: $manualStart)',
        () async {
          final f = await LoopFixture.open();
          final endpoint = Uri.parse(
            'https://trusted.invalid/rpc?credential=unique-private-query',
          );
          final a = PersonalAgent(
            repository: f.repo,
            tools: f.tools,
            gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
            toolReviewer: const NoopReviewer(),
          );
          addTearDown(a.close);
          var effects = 0;
          f.tools.register(
            providerId: 'host.test',
            descriptor: ToolDescriptor(
              toolId: 'send',
              moduleId: 'test',
              effect: ToolEffect.network,
              parameterSchema: const {
                'type': 'object',
                'properties': {
                  'destination': {'type': 'string'},
                },
                'additionalProperties': false,
              },
            ),
            effectIntent: (request, scope) => HostEffectIntent.transport(
              toolId: request.toolId,
              invocationId: request.invocationId,
              endpoint: endpoint,
              endpointIdentity: 'trusted',
              content: utf8.encode('private'),
            ),
            handler: (context) async {
              expect(context.request.destination, endpoint.toString());
              expect(
                context.request.parameters['destination'],
                endpoint.toString(),
              );
              effects++;
              return ToolCallResult(
                status: ToolCallStatus.succeeded,
                summary: 'sent',
              );
            },
          );
          final conv = await f.repo.createConversation();
          f.replies.add(
            LoopReply.sse(
              sseCalls([
                (
                  's',
                  encodeToolName('send'),
                  jsonEncode({'destination': endpoint.toString()}),
                ),
              ]),
            ),
          );
          final task = manualStart
              ? await a.startTool(
                  conversationId: conv.id,
                  toolId: 'send',
                  destination: endpoint.toString(),
                  parameters: {'destination': endpoint.toString()},
                )
              : await a.start(
                  conversationId: conv.id,
                  prompt: '执行已注册工具',
                  profile: f.profile(),
                );
          if (!manualStart) {
            await a.confirm(
              task.id,
              requestDigest: task.payload['requestDigest'] as String,
            );
          }
          final current = f.repo.task(task.id)!;
          expect(
            current.state,
            PersonalTaskState.waitingConfirmation,
            reason: jsonEncode(current.payload),
          );
          expect(effects, 0);
          expect(
            (current.payload['toolCall'] as Map)['destination'],
            'https://trusted.invalid/rpc',
          );
          expect(
            jsonEncode(current.payload),
            isNot(contains('unique-private-query')),
            reason: 'native argument destination must not bypass masked snapshots through parameters or assistant arguments',
          );
          var actor = a;
          if (recreateAgent) {
            await a.close();
            actor = PersonalAgent(
              repository: f.repo,
              tools: f.tools,
              gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
              toolReviewer: const NoopReviewer(),
            );
            addTearDown(actor.close);
          }
          await actor.confirm(
            task.id,
            requestDigest: current.payload['requestDigest'] as String,
          );
          expect(effects, recreateAgent ? 0 : 1);
          if (recreateAgent) {
            expect(f.repo.task(task.id)!.state, PersonalTaskState.failed);
            expect(f.approvals(), isEmpty);
          }
          expect(
            jsonEncode(f.repo.task(task.id)!.payload),
            isNot(contains('unique-private-query')),
          );
          expect(
            jsonEncode(f.repo.messages(conv.id).map((m) => m.content).toList()),
            isNot(contains('unique-private-query')),
          );
          if (!recreateAgent) {
            final approval = f.approvals().single;
            expect(approval['authorization_source'], 'manual');
            expect(approval['grant_id'], isNull);
            expect(approval['review_decision_id'], isNotNull);
          }
        },
      );
    }
  }
}
