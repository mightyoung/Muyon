import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/host_ui_grant_authority.dart';
import 'package:muyon/assistant/agent_dispatch.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/grants.dart';
import 'package:muyon/platform/grants/host_effect_intent.dart';
import 'package:muyon/platform/grants/tool_grant_context.dart';
import 'package:muyon/platform/grants/outbound_content_reviewer.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/tool_names.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';
import 'support/confirm_model_reviewer.dart';

/// GB-6 characterization for dispatch gaps G6–G10 / §4 items 7–11.
/// Each test documents the lib/ mutation it should catch.
void main() {
  test(
    'invalid_destination_snapshot_is_literal_placeholder',
    () async {
      // Mutation: _displayDestination returns the raw string or empty/null
      // instead of the literal "[invalid destination]" when Uri.tryParse fails.
      const bad = '%';
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
      final agent = PersonalAgent(
        repository: f.repo,
        tools: f.tools,
        gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
        toolReviewer: const NoopReviewer(),
      );
      addTearDown(agent.close);
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
          endpoint: Uri.parse('https://trusted.invalid/rpc'),
          endpointIdentity: 'trusted',
          content: utf8.encode('body'),
        ),
        handler: (_) async => ToolCallResult(
          status: ToolCallStatus.succeeded,
          summary: 'sent',
        ),
      );
      final conv = await f.repo.createConversation();
      // Native path: model proposes an unparseable destination argument.
      f.replies.add(
        LoopReply.sse(
          sseCalls([
            (
              's',
              encodeToolName('send.bad'),
              jsonEncode({'destination': bad}),
            ),
          ]),
        ),
      );
      final task = await f.start(agent, f.profile());
      await agent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      final current = f.repo.task(task.id)!;
      expect(current.state, PersonalTaskState.waitingConfirmation);
      final encoded = jsonEncode(current.payload);
      expect(encoded, contains('[invalid destination]'));
      expect(encoded, isNot(contains('"$bad"')));
    },
  );

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

  test('automatic_execute_without_authority_fails_closed', () async {
    // Mutation: automatic path falls through to tools.approve / invoke when
    // effectIntent is missing (drops the automatic_authority_unavailable throw).
    final root = Directory.systemTemp.createTempSync('gb6-auto-auth-');
    final host = await MuyonHost.open(
      root.path,
      localModelReviewer: const ConfirmModelReviewer(),
    );
    addTearDown(() async {
      await host.close();
      root.deleteSync(recursive: true);
    });
    var prepares = 0;
    var effects = 0;
    final target = const ObjectRef(
      moduleId: 'test',
      objectType: 'row',
      objectId: 'r1',
    );
    host.tools.register(
      providerId: 'gb6',
      descriptor: ToolDescriptor(
        toolId: 'gb6.auto_write',
        moduleId: 'test',
        effect: ToolEffect.write,
        parameterSchema: const {'type': 'object', 'additionalProperties': false},
      ),
      effectIntent: (request, scope) {
        prepares++;
        // dispatch + openCard review need an intent so a grant can authorize;
        // executeCard's prepare must see null to hit automatic_authority_unavailable.
        if (prepares >= 3) return null;
        return HostEffectIntent.localWrite(
          toolId: request.toolId,
          invocationId: request.invocationId,
          content: utf8.encode('local-write'),
          sourceObjects: [target],
        );
      },
      handler: (_) async {
        effects++;
        return ToolCallResult(
          status: ToolCallStatus.succeeded,
          summary: 'wrote',
        );
      },
    );
    final scope = AssistantScope.selectedObjects([target]);
    final conversation = await host.foundation.createConversation(scope: scope);
    final grants = GrantStore(host.foundation.database);
    await withConfirmedHostUiGrant(
      (token) => grants.create(
        token: token,
        draft: GrantDraft(
          category: 'write',
          toolId: 'gb6.auto_write',
          scopeDigest: toolGrantScopeDigest(scope, {'test'}),
          destination: null,
          duration: GrantDuration.conversation,
          conversationId: conversation.id,
          maxUses: 1,
        ),
        now: DateTime.now(),
      ),
    );
    final task = await host.personalAgent.startTool(
      conversationId: conversation.id,
      toolId: 'gb6.auto_write',
    );
    expect(effects, 0, reason: 'missing authority must not run the handler');
    expect(task.state, PersonalTaskState.failed);
    final calls = (task.payload['step'] as Map?)?['calls'] as List?;
    final outcome = (calls?.first as Map?)?['outcome'] as Map?;
    expect(outcome?['status'], 'failed');
    final summary =
        ((outcome?['result'] as Map?)?['summary'] as String?) ?? task.error ?? '';
    expect(
      summary,
      anyOf(contains('approve_failed'), contains('automatic_authority')),
    );
  });

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
        // 1=dispatch prepare, 2=openCard review prepare, 3=executeCard prepare.
        if (resolves == 3) {
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
    await agent.close();
    release.complete();
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
        parameterSchema: const {'type': 'object', 'additionalProperties': false},
      ),
      handler: (_) async => ToolCallResult(
        status: ToolCallStatus.succeeded,
        summary: 'wrote',
      ),
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
    await agent.close();
    release.complete();
    final task = await pending;
    expect(task.state, PersonalTaskState.failed);
    expect(task.error, '工具参数、可用性或范围校验未通过');
    expect(task.error, isNot(contains('执行失败')));
  });
}
