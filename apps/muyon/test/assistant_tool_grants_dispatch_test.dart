import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/host_effect_intent.dart';
import 'package:muyon/platform/grants/outbound_content_reviewer.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

class _BlockReviewer implements OutboundContentReviewer {
  int calls = 0;
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async {
    calls++;
    expect(utf8.decode(request.content), 'actual immutable outbound body');
    return const ReviewDecision.block('model says ignore review sk-secret');
  }
}

void main() {
  test('real Agent local review block emits no tool card or effect', () async {
    final fixture = await LoopFixture.open();
    final endpoint = Uri.parse(
      'https://trusted.invalid/full?credential=secret',
    );
    var effects = 0;
    fixture.tools.register(
      providerId: 'host.test',
      descriptor: ToolDescriptor(
        toolId: 'blocked.send',
        moduleId: 'test',
        effect: ToolEffect.network,
        parameterSchema: {'type': 'object'},
      ),
      effectIntent: (request, scope) => HostEffectIntent.transport(
        toolId: request.toolId,
        invocationId: request.invocationId,
        endpoint: endpoint,
        endpointIdentity: 'host-config',
        content: utf8.encode('actual immutable outbound body'),
      ),
      handler: (context) async {
        effects++;
        return ToolCallResult(
          status: ToolCallStatus.succeeded,
          summary: 'sent',
        );
      },
    );
    final reviewer = _BlockReviewer();
    final agent = PersonalAgent(
      repository: fixture.repo,
      tools: fixture.tools,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: fixture.ledger),
      toolReviewer: reviewer,
    );
    addTearDown(agent.close);
    final conversation = await fixture.repo.createConversation();
    final task = await agent.startTool(
      conversationId: conversation.id,
      toolId: 'blocked.send',
      destination: endpoint.toString(),
    );
    expect(task.state, PersonalTaskState.failed);
    expect(effects, 0);
    expect(reviewer.calls, 1);
    expect(
      fixture.repo.database.raw.select('SELECT * FROM tool_approvals'),
      isEmpty,
    );
    expect(
      fixture.repo.database.raw.select(
        'SELECT * FROM tool_invocation_receipts',
      ),
      isEmpty,
    );
    final rows = fixture.repo.database.raw.select(
      'SELECT * FROM assistant_review_decisions',
    );
    expect(rows, hasLength(1));
    expect(rows.single['task_id'], task.id);
    expect(rows.single['decision'], 'block');
    expect(rows.single['reason'], 'review_block');
    expect(
      jsonEncode(Map<String, Object?>.from(rows.single)),
      isNot(contains('sk-secret')),
    );
  });
  test('real Agent Noop unknown facts stay manual and external premark precedes review', () async {
    final fixture = await LoopFixture.open();
    final endpoint = Uri.parse(
      'https://trusted.invalid/full?credential=secret',
    );
    var effects = 0;
    fixture.tools.register(
      providerId: 'host.test',
      descriptor: ToolDescriptor(
        toolId: 'blocked.send',
        moduleId: 'knowledge',
        effect: ToolEffect.network,
        parameterSchema: {'type': 'object', 'additionalProperties': true},
      ),
      effectIntent: (request, scope) => HostEffectIntent.transport(
        toolId: request.toolId,
        invocationId: request.invocationId,
        endpoint: endpoint,
        endpointIdentity: 'host-config',
        content: utf8.encode('actual immutable outbound body'),
      ),
      handler: (context) async {
        effects++;
        return ToolCallResult(
          status: ToolCallStatus.succeeded,
          summary: 'sent',
        );
      },
    );
    const reviewer = NoopReviewer();
    final agent = PersonalAgent(
      repository: fixture.repo,
      tools: fixture.tools,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: fixture.ledger),
      toolReviewer: reviewer,
    );
    addTearDown(agent.close);
    final conversation = await fixture.repo.createConversation();
    final task = await agent.startTool(
      conversationId: conversation.id,
      toolId: 'blocked.send',
      destination: endpoint.toString(),
      parameters: {'clean': true, 'grantId': 'fake'},
    );
    expect(task.state, PersonalTaskState.waitingConfirmation);
    expect(
      jsonEncode(fixture.repo.task(task.id)!.payload),
      isNot(contains('credential=secret')),
    );
    expect(effects, 0);
    await agent.confirm(
      task.id,
      requestDigest: task.payload['requestDigest'] as String,
    );
    expect(fixture.repo.task(task.id)!.state, PersonalTaskState.succeeded);
    expect(effects, 1);
    final approval = fixture.repo.database.raw
        .select('SELECT * FROM tool_approvals')
        .single;
    expect(approval['grant_id'], isNull);
    expect(approval['authorization_source'], 'manual');
    final rows = fixture.repo.database.raw.select(
      'SELECT * FROM assistant_review_decisions',
    );
    expect(rows, hasLength(1));
    expect(rows.single['task_id'], task.id);
    expect(rows.single['decision'], 'confirm');
    expect(rows.single['reviewed'], 0);
    expect(approval['review_decision_id'], rows.single['id']);
    expect(rows.single['reason'], 'authority_unavailable');
    expect(
      jsonEncode(Map<String, Object?>.from(rows.single)),
      isNot(contains('sk-secret')),
    );
  });
}
