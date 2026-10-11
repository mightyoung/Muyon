import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon/app/host_ui_grant_authority.dart';
import 'package:muyon/assistant/agent_dispatch.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/grants/grants.dart';
import 'package:muyon/platform/grants/host_effect_intent.dart';
import 'package:muyon/platform/grants/tool_grant_context.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';
import 'support/confirm_model_reviewer.dart';

/// GB-6 characterization for dispatch gaps G6–G10 (CR-9 review revisions).
/// Each test documents the lib/ mutation it should catch.

class _HoldAllowToolReviewer implements OutboundContentReviewer {
  _HoldAllowToolReviewer(this.entered, this.release);
  final Completer<void> entered;
  final Completer<void> release;
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return const ReviewDecision.allow();
  }
}

void main() {
  test('prepare_exception_uses_check_failure_message', () async {
    // Mutation: agent_dispatch.dart first-catch message (≈177) becomes the
    // execution-period「执行失败（…）」template.
    final f = await LoopFixture.open();
    final tools = ToolRegistry(
      database: f.repo.database,
      resolveScope: (scope) async {
        throw StateError('fixture prepare refused');
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
    final task = await agent.startTool(
      conversationId: conv.id,
      toolId: 'write',
    );
    expect(task.state, PersonalTaskState.failed);
    expect(task.error, '工具参数、可用性或范围校验未通过');
    expect(task.error, isNot(contains('执行失败')));
  });

  test('closing_during_prepare_keeps_interrupted_terminal', () async {
    // Mutation: close-during-prepare is rewritten as failed, or failed is
    // allowed to overwrite interrupted (personal_agent close vs dispatch catch).
    final f = await LoopFixture.open();
    final entered = Completer<void>();
    final release = Completer<void>();
    final tools = ToolRegistry(
      database: f.repo.database,
      resolveScope: (scope) async {
        if (!entered.isCompleted) {
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
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await agent.close();
    });
    final conv = await f.repo.createConversation();
    final pending = agent.startTool(conversationId: conv.id, toolId: 'write');
    await entered.future.timeout(const Duration(seconds: 10));
    // Start close first (sets closing / may settle interrupted), then release
    // the prepare wait — never await close before releasing.
    final closing = agent.close();
    release.complete();
    await closing;
    final task = await pending;
    expect(task.state, PersonalTaskState.interrupted);
    expect(task.error, contains('宿主关闭'));
    expect(task.error, isNot(contains('执行失败（')));
  });

  test('invalid_destination_formatter_and_legal_prepare_snapshot', () async {
    // Mutation: _displayDestination (≈42) returns raw / empty instead of
    // "[invalid destination]"; or card destination keeps credential query.
    const bad = ':::';
    expect(Uri.tryParse(bad), isNull);
    expect(
      AgentDispatch.displayParameters({'destination': bad})['destination'],
      '[invalid destination]',
    );
    const secret = 'https://trusted.invalid/rpc?credential=secret';
    expect(
      AgentDispatch.displayParameters({'destination': secret})['destination'],
      'https://trusted.invalid/rpc',
    );

    // Legal prepare: request destination matches transport endpoint exactly.
    final f = await LoopFixture.open();
    final endpoint = Uri.parse(secret);
    f.tools.register(
      providerId: 'host.test',
      descriptor: ToolDescriptor(
        toolId: 'send.ok',
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
    final task = await agent.startTool(
      conversationId: conv.id,
      toolId: 'send.ok',
      destination: secret,
      parameters: {'destination': secret},
    );
    expect(task.state, PersonalTaskState.waitingConfirmation);
    final toolCall = Map<String, Object?>.from(task.payload['toolCall'] as Map);
    expect(toolCall['destination'], 'https://trusted.invalid/rpc');
    final parameters = Map<String, Object?>.from(toolCall['parameters'] as Map);
    expect(parameters['destination'], 'https://trusted.invalid/rpc');
    expect(jsonEncode(toolCall), isNot(contains('credential=secret')));
    final userMsg = f.repo
        .messages(conv.id)
        .firstWhere((m) => m.role == 'user');
    final msgJson = jsonDecode(
      userMsg.content.substring(userMsg.content.indexOf('{')),
    ) as Map;
    expect(msgJson['destination'], 'https://trusted.invalid/rpc');
  });

  test('selection_change_does_not_change_tool_card_digest', () async {
    // Mutation: _stage digest (≈232-234) includes selection IDs.
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
      ..add(LoopReply.sse(sseCalls([('c1', 'w1', '{}')])))
      ..add(LoopReply.sse(sseText('好')));
    final agent = f.agent();
    var task = await f.run(agent, await f.start(agent, f.profile()));
    expect(task.state, PersonalTaskState.waitingConfirmation);
    final digest = task.payload['requestDigest'] as String;
    final calls = (task.payload['toolCalls'] as List).cast<Map>();
    final ids = [for (final c in calls) c['invocationId'] as String];
    expect(
      digest,
      PersonalAgent.digest({
        'calls': [for (final c in calls) c['identityDigest']],
      }),
    );
    final preview = Map<String, Object?>.from(task.payload['preview'] as Map);
    expect(preview['order'], contains('按顺序执行'));
    expect(preview['calls'], hasLength(3));
    expect(task.payload['toolSelection'], ids);
    expect(task.payload.containsKey('expiresAt'), isTrue);

    final toggled = PersonalAgent.toggleSelection(ids, ids, ids[1]);
    expect(
      await f.repo.updateTask(task.copy({'toolSelection': toggled})),
      isTrue,
    );
    task = f.repo.task(task.id)!;
    expect(task.payload['requestDigest'], digest);

    await agent.confirm(
      task.id,
      requestDigest: digest,
      selectedInvocationIds: [ids[0], ids[2]],
    );
    expect(f.order, ['w1', 'w3']);

    // Single-call card: digest equals that call's identityDigest; preview shape.
    task = await f.run(agent, f.repo.task(task.id)!);
    expect(task.state, PersonalTaskState.waitingConfirmation);
    expect(task.stage, 'tool');
    expect(task.payload['requestDigest'], task.payload['toolIdentityDigest']);
    expect(task.payload['toolCalls'], hasLength(1));
    final singlePreview = Map<String, Object?>.from(
      task.payload['preview'] as Map,
    );
    expect(singlePreview.containsKey('calls'), isFalse);
    expect(singlePreview['toolId'], 'w1');
    expect(task.payload['toolSelection'], hasLength(1));
  });

  test('automatic_grant_write_consumes_grant', () async {
    // Mutation: authorization.sign replaced by confirm (≈705), or grant not
    // consumed / source not 'grant'.
    final root = Directory.systemTemp.createTempSync('gb6-auto-grant-');
    final host = await MuyonHost.open(
      root.path,
      localModelReviewer: const ConfirmModelReviewer(),
    );
    addTearDown(() async {
      await host.close();
      root.deleteSync(recursive: true);
    });
    await host.activateInquiry();
    final store = host.inquiry!.runtime.state.store;
    final projectId = store.save('project', {
      'code': 'GB6',
      'name': 'gb6 project',
      'status': 'active',
      'type': 'market',
      'level': 'A',
      'customer': null,
      'contract_no': null,
      'contract_amount': null,
      'department': null,
      'leader': null,
      'start_date': null,
      'end_date': null,
      'currency': 'CNY',
      'tax_mode': 'included',
      'markup_rate': '0',
      'notes': null,
    });
    final itemId = store.save('project_item', {
      'project_id': projectId,
      'category': 'material',
      'product_id': null,
      'name': 'gb6 item',
      'qty': '10',
      'unit': '米',
      'quotation_id': null,
      'unit_cost': '0',
      'unit_price': null,
      'notes': null,
    });
    final resolved = await resolveAssistantScope(
      host,
      const AssistantScope.global(),
    );
    final scope = AssistantScope.selectedObjects([
      for (final ref in resolved.objects)
        if (ref.objectId == itemId) ref,
    ]);
    expect(scope.objects, hasLength(1));
    final c = await host.foundation.createConversation(scope: scope);
    final grants = GrantStore(host.foundation.database);
    final grant = await withConfirmedHostUiGrant(
      (token) => grants.create(
        token: token,
        draft: GrantDraft(
          category: 'write',
          toolId: 'inquiry.set_item_qty',
          scopeDigest: toolGrantScopeDigest(scope, {'inquiry'}),
          destination: null,
          duration: GrantDuration.conversation,
          conversationId: c.id,
          maxUses: 1,
        ),
        now: DateTime.now(),
      ),
    );
    final task = await host.personalAgent.startTool(
      conversationId: c.id,
      toolId: 'inquiry.set_item_qty',
      parameters: {'item_id': itemId, 'from_qty': '10', 'to_qty': '12'},
    );
    expect(task.state, PersonalTaskState.succeeded, reason: '${task.error}');
    expect(store.get('project_item', itemId)!.data['qty'], '12');
    final approval = host.foundation.database.raw
        .select('SELECT * FROM tool_approvals')
        .single;
    expect(approval['authorization_source'], 'grant');
    expect(approval['grant_id'], grant.id);
    expect(
      host.foundation.database.raw.select(
        'SELECT uses FROM assistant_grants WHERE grant_id=?',
        [grant.id],
      ).single['uses'],
      1,
    );
  });

  test('automatic_sign_null_after_revoke_fails_closed', () async {
    // Mutation: automatic path ignores null from sign and still invokes
    // (≈707 `if (approval == null) throw`). Related defense to ≈709-711:
    // automatic must not run without usable authority. Stage signal: tool
    // reviewer pauses after allow; grant is revoked before review returns.
    final root = Directory.systemTemp.createTempSync('gb6-auto-revoke-');
    final reviewed = Completer<void>();
    final releaseReview = Completer<void>();
    final host = await MuyonHost.open(
      root.path,
      localModelReviewer: const ConfirmModelReviewer(),
      localToolReviewer: _HoldAllowToolReviewer(reviewed, releaseReview),
    );
    addTearDown(() async {
      if (!releaseReview.isCompleted) releaseReview.complete();
      await host.close();
      root.deleteSync(recursive: true);
    });
    await host.activateInquiry();
    final store = host.inquiry!.runtime.state.store;
    final projectId = store.save('project', {
      'code': 'GB6B',
      'name': 'gb6 b',
      'status': 'active',
      'type': 'market',
      'level': 'A',
      'customer': null,
      'contract_no': null,
      'contract_amount': null,
      'department': null,
      'leader': null,
      'start_date': null,
      'end_date': null,
      'currency': 'CNY',
      'tax_mode': 'included',
      'markup_rate': '0',
      'notes': null,
    });
    final itemId = store.save('project_item', {
      'project_id': projectId,
      'category': 'material',
      'product_id': null,
      'name': 'item',
      'qty': '10',
      'unit': '米',
      'quotation_id': null,
      'unit_cost': '0',
      'unit_price': null,
      'notes': null,
    });
    final resolved = await resolveAssistantScope(
      host,
      const AssistantScope.global(),
    );
    final scope = AssistantScope.selectedObjects([
      for (final ref in resolved.objects)
        if (ref.objectId == itemId) ref,
    ]);
    final c = await host.foundation.createConversation(scope: scope);
    final grants = GrantStore(host.foundation.database);
    final grant = await withConfirmedHostUiGrant(
      (token) => grants.create(
        token: token,
        draft: GrantDraft(
          category: 'write',
          toolId: 'inquiry.set_item_qty',
          scopeDigest: toolGrantScopeDigest(scope, {'inquiry'}),
          destination: null,
          duration: GrantDuration.conversation,
          conversationId: c.id,
          maxUses: 1,
        ),
        now: DateTime.now(),
      ),
    );
    final taskFuture = host.personalAgent.startTool(
      conversationId: c.id,
      toolId: 'inquiry.set_item_qty',
      parameters: {'item_id': itemId, 'from_qty': '10', 'to_qty': '12'},
    );
    await reviewed.future.timeout(const Duration(seconds: 10));
    await host.assistantGrants.revoke(grant.id, now: DateTime.now());
    releaseReview.complete();
    final task = await taskFuture;
    expect(store.get('project_item', itemId)!.data['qty'], '10');
    expect(task.state, isNot(PersonalTaskState.succeeded));
  });

  test('invoke_abandoned_after_external_mark_without_receipt', () async {
    // Mutation: delete post-mark closing/running check (≈495-498) so invoke
    // continues and writes a receipt/outcome.
    // NoopReviewer premarks in openCard; _invokeOne still awaits the async
    // _markExternal early-return, leaving a microtask gap after the entry
    // check. Arm a mutation on the approval-event commit so the gap sees a
    // non-running task without cancelling the tool token (close() would hit
    // throwIfCancelled first).
    final f = await LoopFixture.open();
    var effects = 0;
    final endpoint = Uri.parse('https://trusted.invalid/rpc');
    f.tools.register(
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
      tools: f.tools,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      toolReviewer: const NoopReviewer(),
    );
    final db = f.repo.database as ManagedConnection;
    final previousOnCommit = db.onCommit;
    var armHold = false;
    var mutated = false;
    String? armedTaskId;
    db.onCommit = () {
      previousOnCommit?.call();
      if (!armHold || mutated || armedTaskId == null) return;
      final current = f.repo.task(armedTaskId);
      if (current == null || current.state != PersonalTaskState.running) {
        return;
      }
      if (!f.repo.taskEvents(current.id).any((e) => e.type == 'approval')) {
        return;
      }
      mutated = true;
      scheduleMicrotask(() {
        db.raw.execute(
          "UPDATE execution_records SET state='interrupted',"
          "payload=json_set(payload,'\$.state','interrupted','\$.stage','interrupted',"
          "'\$.error','fixture interrupted during mark') WHERE id=?",
          [armedTaskId],
        );
      });
    };
    addTearDown(() async {
      db.onCommit = previousOnCommit;
      await agent.close();
    });
    final conv = await f.repo.createConversation();
    final task = await agent.startTool(
      conversationId: conv.id,
      toolId: 'ext.send',
      destination: endpoint.toString(),
    );
    expect(task.state, PersonalTaskState.waitingConfirmation);
    expect(
      f.repo.authorizationFacts.readTask(task.id).sourceDigests,
      isNotEmpty,
      reason: 'NoopReviewer openCard must premark research/network',
    );
    final receiptsBefore = f.receipts().length;
    final eventsBefore = f.repo.taskEvents(task.id).length;
    armedTaskId = task.id;
    armHold = true;
    await agent.confirm(
      task.id,
      requestDigest: task.payload['requestDigest'] as String,
    );
    expect(mutated, isTrue, reason: 'approval commit must arm the microtask');
    expect(effects, 0);
    expect(f.receipts(), hasLength(receiptsBefore));
    final newEvents = f.repo.taskEvents(task.id).skip(eventsBefore);
    expect(
      newEvents.any((e) => e.type == 'tool_result'),
      isFalse,
      reason: 'abandoned after mark must not append tool_result',
    );
    final after = f.repo.task(task.id)!;
    expect(after.state, isNot(PersonalTaskState.succeeded));
    final step = after.payload['step'] as Map?;
    if (step != null) {
      for (final c in (step['calls'] as List?) ?? const []) {
        final outcome = (c as Map)['outcome'] as Map?;
        expect(outcome?['status'], isNot('failed'));
        expect(outcome?['status'], isNot('succeeded'));
      }
    }
  });
}
