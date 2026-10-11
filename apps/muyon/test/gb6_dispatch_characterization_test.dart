import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/agent_dispatch.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/host_effect_intent.dart';
import 'package:muyon/platform/grants/outbound_content_reviewer.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

/// GB-6 characterization for dispatch gaps G6–G10 / §4 items 7–11.
/// Each test documents the lib/ mutation it should catch.
void main() {
  test('invalid_destination_snapshot_is_literal_placeholder', () async {
    // Mutation: _displayDestination returns the raw string or empty/null
    // instead of the literal "[invalid destination]" when Uri.tryParse fails.
    const bad = ':::';
    expect(Uri.tryParse(bad), isNull, reason: 'fixture assumes tryParse fails');
    expect(
      AgentDispatch.displayParameters({'destination': bad})['destination'],
      '[invalid destination]',
    );
    expect(
      AgentDispatch.displayParameters({
        'destination': 'https://trusted.invalid/rpc?credential=secret',
      })['destination'],
      'https://trusted.invalid/rpc',
    );

    final f = await LoopFixture.open();
    final endpoint = Uri.parse('https://trusted.invalid/rpc');
    f.tools.register(
      providerId: 'host.test',
      descriptor: ToolDescriptor(
        toolId: 'send.bad',
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
        content: utf8.encode('body'),
      ),
      handler: (_) async =>
          ToolCallResult(status: ToolCallStatus.succeeded, summary: 'sent'),
    );
    final agent = PersonalAgent(
      repository: f.repo,
      tools: f.tools,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      toolReviewer: const NoopReviewer(),
    );
    addTearDown(agent.close);
    final conv = await f.repo.createConversation();
    // Message is appended with displayParameters before dispatch runs.
    await agent.startTool(
      conversationId: conv.id,
      toolId: 'send.bad',
      destination: bad,
      parameters: {'destination': bad},
    );
    final contents = [for (final m in f.repo.messages(conv.id)) m.content];
    expect(jsonEncode(contents), contains('[invalid destination]'));
    expect(
      jsonEncode(contents),
      isNot(contains(':::')),
      reason: 'raw invalid destination must not persist in messages',
    );
  });

  test('selection_change_does_not_change_tool_card_digest', () async {
    // Mutation: _stage folds toolSelection into requestDigest so toggling
    // selection invalidates the digest and confirm fails.
    final f = await LoopFixture.open();
    f.addTool('w1', ToolEffect.write);
    f.addTool('w2', ToolEffect.write);
    f.addTool('w3', ToolEffect.write);
    f.replies
      ..add(
        LoopReply.sse(
          sseCalls([
            ('c1', 'w1', '{}'),
            ('c2', 'w2', '{}'),
            ('c3', 'w3', '{}'),
          ]),
        ),
      )
      ..add(LoopReply.sse(sseText('好')));
    final agent = f.agent();
    var task = await f.run(agent, await f.start(agent, f.profile()));
    expect(task.state, PersonalTaskState.waitingConfirmation);
    final digest = task.payload['requestDigest'] as String;
    final ids = [
      for (final c in (task.payload['toolCalls'] as List).cast<Map>())
        c['invocationId'] as String,
    ];
    expect(ids, hasLength(3));
    expect(
      digest,
      PersonalAgent.digest({
        'calls': [
          for (final c in (task.payload['toolCalls'] as List).cast<Map>())
            c['identityDigest'],
        ],
      }),
    );

    final toggled = PersonalAgent.toggleSelection(ids, ids, ids[1]);
    expect(toggled, [ids[0]]);
    // Persist a narrower selection the way a UI might; digest must stay.
    expect(
      await f.repo.updateTask(task.copy({'toolSelection': toggled})),
      isTrue,
    );
    task = f.repo.task(task.id)!;
    expect(task.payload['requestDigest'], digest);
    expect(task.payload['toolSelection'], toggled);

    await agent.confirm(
      task.id,
      requestDigest: digest,
      selectedInvocationIds: [ids[0], ids[2]],
    );
    expect(f.order, ['w1', 'w3']);
    task = await f.run(agent, f.repo.task(task.id)!);
    expect(task.state, PersonalTaskState.succeeded);
  });

  test(
    'automatic_execute_without_authority_fails_closed',
    () async {
      // GB-4 G9 / §4.9: automatic_authority_unavailable when automatic execute
      // sees null effectIntent (or null authorization).
      // Observed (2026-10-11): MuyonHost + synthetic moduleId=test ObjectRef fails
      // prepare with "工具参数、可用性或范围校验未通过" before effectIntent runs
      // (prepares stays 0) — host scope resolver will not resolve non-module
      // objects. Wiring GrantStore onto LoopFixture still cannot enter
      // executeCard(automatic:true) without a matching HostToolAuthorization
      // grantId on review (needs live hostGrantContext stamps).
      // Skipping rather than weakening the assertion to a different path.
      // Mutation it would catch: dropping the `if (automatic) throw
      // StateError('automatic_authority_unavailable')` branch so invoke runs
      // without approval.
      expect(true, isTrue, reason: 'G9 skipped — see comment');
    },
    skip: 'G9: automatic_authority_unavailable not constructible without host module scope; prepares=0 on synthetic refs',
  );

  test('invoke_abandoned_when_closing_after_external_premark', () async {
    // Mutation: abandoned / closing after external premark is recorded as a
    // failed receipt and folded into model.advance instead of returning quietly.
    final f = await LoopFixture.open();
    final entered = Completer<void>();
    final release = Completer<void>();
    var resolves = 0;
    var effects = 0;
    final endpoint = Uri.parse('https://trusted.invalid/rpc');
    final tools = ToolRegistry(
      database: f.repo.database,
      resolveScope: (scope) async {
        resolves++;
        // After the card is open, the next prepare is executeCard's.
        if (resolves >= 3 && !entered.isCompleted) {
          entered.complete();
          await release.future;
        }
        return ResolvedAssistantScope(requested: scope, objects: f.objects);
      },
    );
    tools.register(
      providerId: 'host.test',
      descriptor: ToolDescriptor(
        toolId: 'ext.send',
        moduleId: 'research',
        effect: ToolEffect.network,
        parameterSchema: const {
          'type': 'object',
          'additionalProperties': false,
        },
      ),
      effectIntent: (request, scope) => HostEffectIntent.transport(
        toolId: request.toolId,
        invocationId: request.invocationId,
        endpoint: endpoint,
        endpointIdentity: 'trusted',
        content: utf8.encode('body'),
      ),
      handler: (_) async {
        effects++;
        return ToolCallResult(
          status: ToolCallStatus.succeeded,
          summary: 'sent',
        );
      },
    );
    final agent = PersonalAgent(
      repository: f.repo,
      tools: tools,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      toolReviewer: const NoopReviewer(),
    );
    addTearDown(agent.close);
    final conv = await f.repo.createConversation();
    final task = await agent.startTool(
      conversationId: conv.id,
      toolId: 'ext.send',
      destination: endpoint.toString(),
    );
    expect(task.state, PersonalTaskState.waitingConfirmation);
    final factsBefore = f.repo.authorizationFacts.readTask(task.id);
    expect(
      factsBefore.sourceDigests,
      isNotEmpty,
      reason: 'research module must be externally premarked before confirm',
    );

    final running = agent.confirm(
      task.id,
      requestDigest: task.payload['requestDigest'] as String,
    );
    await entered.future.timeout(const Duration(seconds: 10));
    // Unblock prepare before close awaits operations (confirm), else deadlock.
    release.complete();
    await agent.close();
    await running;
    expect(effects, 0, reason: 'close after premark must not run the handler');
    final after = f.repo.task(task.id)!;
    expect(after.state, isNot(PersonalTaskState.succeeded));
    for (final receipt in f.receipts()) {
      final raw = receipt['result_json'];
      if (raw is! String) continue;
      final status = jsonDecode(raw)['status'];
      expect(status, isNot('succeeded'));
    }
    expect(f.bodies, isEmpty, reason: 'must not advance the model');
  });

  test('closing_during_prepare_uses_check_failure_message', () async {
    // Mutation: merge the two catch blocks in dispatch so a prepare-time
    // closing error is reported with the execution-period "执行失败（…）" template.
    final f = await LoopFixture.open();
    final entered = Completer<void>();
    final release = Completer<void>();
    var resolves = 0;
    final tools = ToolRegistry(
      database: f.repo.database,
      resolveScope: (scope) async {
        resolves++;
        if (resolves == 1) {
          entered.complete();
          await release.future;
        }
        return ResolvedAssistantScope(requested: scope, objects: f.objects);
      },
    );
    tools.register(
      providerId: 'test',
      descriptor: ToolDescriptor(
        toolId: 'write',
        moduleId: 'test',
        effect: ToolEffect.write,
        parameterSchema: const {
          'type': 'object',
          'additionalProperties': false,
        },
      ),
      handler: (_) async =>
          ToolCallResult(status: ToolCallStatus.succeeded, summary: 'wrote'),
    );
    final agent = PersonalAgent(
      repository: f.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      tools: tools,
    );
    addTearDown(agent.close);
    final conv = await f.repo.createConversation();
    final pending = agent.startTool(conversationId: conv.id, toolId: 'write');
    await entered.future.timeout(const Duration(seconds: 10));
    // close() sets closing=true synchronously before its first await; release
    // next so prepare observes closing and takes the first catch. close() may
    // also mark the queued task interrupted — both terminal outcomes are real.
    final closing = agent.close();
    release.complete();
    await closing;
    final task = await pending;
    expect(task.terminal, isTrue);
    expect(
      task.state,
      anyOf(PersonalTaskState.failed, PersonalTaskState.interrupted),
    );
    if (task.state == PersonalTaskState.failed) {
      expect(task.error, '工具参数、可用性或范围校验未通过');
    } else {
      expect(task.error, contains('宿主关闭'));
    }
    // Must not be the second catch's execution-period template.
    expect(task.error, isNot(contains('执行失败（')));
  });
}
