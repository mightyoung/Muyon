import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/assistant/agent_budget.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/grant_store.dart';
import 'package:muyon/platform/grants/host_authorization_policy.dart';
import 'package:muyon/platform/grants/host_model_authorization.dart';
import 'package:muyon/platform/grants/outbound_content_reviewer.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';
import 'support/confirm_model_reviewer.dart';

/// GB-6 characterization for model-turn gaps G11–G14 / §4 items 12–18.
/// Each test documents the lib/ mutation it should catch.
class _BlockModelReviewer implements OutboundContentReviewer {
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async =>
      const ReviewDecision.block('fixture blocks model content');
}

class _HoldThenAllowReviewer implements OutboundContentReviewer {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return const ReviewDecision.allow(reviewed: false);
  }
}

List<Map> _events(LoopFixture f, String taskId) => [
  for (final e in f.repo.taskEvents(taskId)) e.toJson(),
];

Map<String, Object?>? _toolLogEntry(PersonalTask task) {
  final log = task.payload['toolLog'] as List?;
  if (log == null || log.isEmpty) return null;
  return Map<String, Object?>.from(log.last as Map);
}

void main() {
  test('wire_review_required_leaves_model_card_without_send', () async {
    // Mutation: HostModelWireReviewRequired / non-automatic review is treated
    // as automatic and runModel is called immediately (bodies non-empty).
    // Production ConfirmModelReviewer forces a waiting model card with no send.
    final root = Directory.systemTemp.createTempSync('gb6-wire-review-');
    final loop = await LoopFixture.open();
    final host = await MuyonHost.open(
      root.path,
      localModelReviewer: const ConfirmModelReviewer(),
    );
    addTearDown(() async {
      await host.close();
      root.deleteSync(recursive: true);
    });
    loop.replies.add(LoopReply.sse(sseText('should-not-send')));
    final conversation = await host.foundation.createConversation();
    final task = await host.personalAgent.start(
      conversationId: conversation.id,
      prompt: 'answer',
      profile: loop.profile(),
    );
    expect(task.state, PersonalTaskState.waitingConfirmation);
    expect(task.stage, 'model');
    expect(loop.bodies, isEmpty);
  });

  test('model_content_block_fails_with_fixed_reason', () async {
    // Mutation: ReviewAction.block still proceeds to runModel / send.
    final f = await LoopFixture.open();
    final policy = HostAuthorizationPolicy(f.repo.database);
    final profile = f.profile();
    final authority = HostModelAuthorization(
      repository: f.repo,
      policy: policy,
      grants: GrantStore(f.repo.database),
      reviewer: _BlockModelReviewer(),
      configuredProfiles: () => [profile],
    );
    final agent = PersonalAgent(
      repository: f.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      tools: f.tools,
      modelAuthorization: authority,
    );
    addTearDown(agent.close);
    f.replies.add(LoopReply.sse(sseText('blocked')));
    final task = await f.start(agent, profile);
    expect(task.state, PersonalTaskState.failed);
    expect(task.error, contains('模型内容审查阻止发送'));
    expect(f.bodies, isEmpty);
  });

  test('planning_session_expired_before_send', () async {
    // Mutation: _beforeSend drops the uiPlanningInternal / uiModelChecks guard.
    final f = await LoopFixture.open();
    f.replies.add(LoopReply.sse(sseText('nope')));
    final agent = f.agent();
    var task = await f.start(agent, f.profile());
    expect(task.state, PersonalTaskState.waitingConfirmation);
    expect(task.stage, 'model');
    // Simulate a planning child whose session check was cleared.
    expect(
      await f.repo.updateTask(task.copy({'uiPlanningInternal': true})),
      isTrue,
    );
    task = f.repo.task(task.id)!;
    await agent.confirm(
      task.id,
      requestDigest: task.payload['requestDigest'] as String,
    );
    task = f.repo.task(task.id)!;
    expect(task.state, PersonalTaskState.failed);
    expect(task.error, contains('planning_session_expired'));
    expect(f.bodies, isEmpty);
  });

  test('check_permission_task_detects_profile_change_mid_prepare', () async {
    // Mutation: checkPermissionTask stops comparing payload profile digests.
    final f = await LoopFixture.open();
    final policy = HostAuthorizationPolicy(f.repo.database);
    final profile = f.profile();
    final holder = _HoldThenAllowReviewer();
    final authority = HostModelAuthorization(
      repository: f.repo,
      policy: policy,
      grants: GrantStore(f.repo.database),
      reviewer: holder,
      configuredProfiles: () => [profile],
    );
    final agent = PersonalAgent(
      repository: f.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      tools: f.tools,
      modelAuthorization: authority,
    );
    addTearDown(() async {
      if (!holder.release.isCompleted) holder.release.complete();
      await agent.close();
    });
    f.replies.add(LoopReply.sse(sseText('nope')));
    final pending = f.start(agent, profile);
    await holder.entered.future.timeout(const Duration(seconds: 10));
    final current = f.repo.tasks().single;
    final mutatedProfile = Map<String, Object?>.from(
      current.payload['profile'] as Map,
    )..['modelId'] = 'mutated-mid-prepare';
    expect(
      await f.repo.updateTask(current.copy({'profile': mutatedProfile})),
      isTrue,
    );
    holder.release.complete();
    final task = await pending;
    expect(task.state, PersonalTaskState.failed);
    expect(f.bodies, isEmpty);
    expect(
      task.error,
      anyOf(contains('model_source_changed'), contains('执行失败')),
    );
  });

  test('nonstreaming_compat_preview_omits_max_output_tokens', () async {
    // Mutation: _outputCap drops the early return for non-stream non-native,
    // so preview.maxOutputTokens appears on a compat non-stream card.
    final f = await LoopFixture.open();
    final longPrompt = '请分析以下内容并给出结论。' * 40;
    // Streaming+native control: with little budget left, cap is present.
    f.replies
      ..add(
        LoopReply.sse(
          sseCalls([('c1', 'read', '{}')], prompt: 2000, completion: 1000),
        ),
      )
      ..add(LoopReply.sse(sseText('好')));
    final streamAgent = f.agent(budget: const Budget(maxTokens: 10000));
    var streamTask = await f.start(
      streamAgent,
      f.profile(),
      prompt: longPrompt,
    );
    expect(
      (streamTask.payload['preview'] as Map).containsKey('maxOutputTokens'),
      isFalse,
    );
    streamTask = await f.run(streamAgent, streamTask, confirmTools: true);
    expect(
      (streamTask.payload['preview'] as Map)['maxOutputTokens'],
      isNotNull,
    );

    // Non-stream, non-native: even with little remaining budget, no cap key.
    final g = await LoopFixture.open();
    g.replies.add(
      LoopReply.sse(
        sseText(
          jsonEncode({
            'type': 'answer',
            'answer': 'ok',
            'citationIds': <String>[],
          }),
        ),
      ),
    );
    // Force low remaining tokens by starting with a large prior usage via a
    // tiny budget relative to the long prompt estimate.
    final compat = g.agent(budget: const Budget(maxTokens: 500));
    final compatTask = await g.start(
      compat,
      g.profile(
        capabilities: const ModelCapabilities(
          streaming: false,
          nativeTools: false,
          source: CapabilitySource.userDeclared,
        ),
      ),
      prompt: longPrompt,
    );
    expect(compatTask.state, PersonalTaskState.waitingConfirmation);
    expect(
      (compatTask.payload['preview'] as Map).containsKey('maxOutputTokens'),
      isFalse,
      reason: 'compat non-stream must omit maxOutputTokens in preview',
    );
  });

  test('drain_announces_model_request_only_after_first_stream_event', () async {
    // Mutation: drain writes modelRequest before the first stream event
    // (before the ledger row exists) — e.g. moving the announce ahead of
    // `await for` / into beforeSend.
    final f = await LoopFixture.open();
    final hold = Completer<void>();
    f.replies.add(
      LoopReply.sse(
        sseText('hello', prompt: 10, completion: 2),
        hold: hold.future,
      ),
    );
    final agent = f.agent();
    final task = await f.start(agent, f.profile());
    expect(
      _events(f, task.id).map((e) => e['type']),
      isNot(contains('model_request')),
      reason: 'waiting model card must not announce a send',
    );
    final pending = agent.confirm(
      task.id,
      requestDigest: task.payload['requestDigest'] as String,
    );
    // Fixture writes the first SSE part then awaits [hold]. Poll until drain
    // has observed that first event (and announced) while the stream is still
    // open — proving announce is tied to the first event, not to beforeSend.
    for (var i = 0; i < 200; i++) {
      if (_events(f, task.id).any((e) => e['type'] == 'model_request')) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(
      _events(f, task.id).map((e) => e['type']),
      contains('model_request'),
      reason: 'first stream event must announce model_request while held',
    );
    expect(
      _events(f, task.id).where((e) => e['type'] == 'model_request'),
      hasLength(1),
    );
    hold.complete();
    await pending;
    expect(
      _events(f, task.id).where((e) => e['type'] == 'model_request'),
      hasLength(1),
    );
  });

  test('native_bad_citation_strips_but_compat_bad_citation_fails', () async {
    // Mutation: swap native strip-and-succeed vs compat fail-on-bad-citation.
    final native = await LoopFixture.open();
    native.replies.add(LoopReply.sse(sseText('答案 [r99]')));
    final nativeAgent = native.agent();
    final nativeTask = await native.run(
      nativeAgent,
      await native.start(
        nativeAgent,
        native.profile(
          capabilities: const ModelCapabilities(
            streaming: true,
            nativeTools: true,
            source: CapabilitySource.userDeclared,
          ),
        ),
      ),
    );
    expect(nativeTask.state, PersonalTaskState.succeeded);
    expect(nativeTask.summary, contains('引用未通过校验'));
    expect(nativeTask.summary, isNot(contains('[r99]')));

    final compat = await LoopFixture.open();
    compat.replies.add(
      LoopReply.sse(
        sseText(
          jsonEncode({
            'type': 'answer',
            'answer': '42',
            'citationIds': ['r99'],
          }),
        ),
      ),
    );
    final compatAgent = compat.agent();
    final compatTask = await compat.run(
      compatAgent,
      await compat.start(
        compatAgent,
        compat.profile(
          capabilities: const ModelCapabilities(
            streaming: true,
            nativeTools: false,
            source: CapabilitySource.userDeclared,
          ),
        ),
      ),
    );
    expect(compatTask.state, PersonalTaskState.failed);
    expect(compatTask.summary, isNull);
  });

  test('log_entry_summary_truncated_and_not_run_texts', () async {
    // Mutation: _logEntry stops truncating at 120, or _notRunText keys /
    // Chinese strings change for not_approved / not_run_prior_failed /
    // not_run_resume / unknown_before_resume.
    final f = await LoopFixture.open();
    final long = '字' * 200;
    f.addTool('longwrite', ToolEffect.write, summary: long);
    f.addTool('after', ToolEffect.write);
    f.replies
      ..add(
        LoopReply.sse(
          sseCalls([('c1', 'longwrite', '{}'), ('c2', 'after', '{}')]),
        ),
      )
      ..add(LoopReply.sse(sseText('好')));
    final agent = f.agent();
    var task = await f.run(agent, await f.start(agent, f.profile()));
    final ids = [
      for (final c in (task.payload['toolCalls'] as List).cast<Map>())
        c['invocationId'] as String,
    ];
    // Only first selected → after is not_approved; also exercise digest.
    await agent.confirm(
      task.id,
      requestDigest: task.payload['requestDigest'] as String,
      selectedInvocationIds: [ids.first],
    );
    task = await f.run(agent, f.repo.task(task.id)!);
    expect(task.state, PersonalTaskState.succeeded);
    final entry = _toolLogEntry(task)!;
    expect(entry['toolId'], 'longwrite');
    expect(entry['status'], 'succeeded');
    final summary = entry['summary'] as String;
    expect(summary.length, 121); // 120 chars + ellipsis
    expect(summary.endsWith('…'), isTrue);
    expect(summary.substring(0, 120), '字' * 120);

    final messages = (task.payload['messages'] as List).cast<Map>();
    final toolMsgs = messages.where((m) => m['role'] == 'tool').toList();
    expect(toolMsgs, hasLength(2));
    final notApproved = jsonDecode(toolMsgs[1]['content'] as String) as Map;
    expect(notApproved['notExecuted'], '用户未批准此调用');

    // prior_failed path
    final g = await LoopFixture.open();
    g.addTool(
      'bad',
      ToolEffect.write,
      onCall: (_) async =>
          ToolCallResult(status: ToolCallStatus.failed, summary: 'disk full'),
    );
    g.addTool('later', ToolEffect.write);
    g.replies.add(
      LoopReply.sse(sseCalls([('c1', 'bad', '{}'), ('c2', 'later', '{}')])),
    );
    final agent2 = g.agent();
    final failedCard = await g.run(agent2, await g.start(agent2, g.profile()));
    await agent2.confirm(
      failedCard.id,
      requestDigest: failedCard.payload['requestDigest'] as String,
    );
    final afterFail = g.repo.task(failedCard.id)!;
    expect(afterFail.state, PersonalTaskState.failed);
    final stepCalls = ((afterFail.payload['step'] as Map)['calls'] as List)
        .cast<Map>();
    expect(stepCalls[1]['outcome'], {'status': 'not_run_prior_failed'});

    // Resume keys: unfinished step with one successful receipt and one pending
    // folds not_run_resume into carried messages (GB-4 G14 / agent_resume).
    final h = await LoopFixture.open();
    h.addTool('w1', ToolEffect.write);
    h.addTool('w2', ToolEffect.write);
    h.replies
      ..add(LoopReply.sse(sseCalls([('c1', 'w1', '{}'), ('c2', 'w2', '{}')])))
      ..add(LoopReply.sse(sseText('续')));
    final agent3 = h.agent();
    final card = await h.run(agent3, await h.start(agent3, h.profile()));
    final cardCalls = (card.payload['toolCalls'] as List).cast<Map>();
    await agent3.cancel(card.id);
    final first = cardCalls.first;
    final request = ToolCallRequest(
      invocationId: first['invocationId'] as String,
      toolId: first['toolId'] as String,
      scope: card.scope,
      parameters: Map<String, Object?>.from(first['parameters'] as Map),
    );
    final prepared = await h.tools.prepare(request);
    final approval = await h.tools.approve(prepared);
    final result = await h.tools.invoke(request.withApproval(approval));
    expect(result.status, ToolCallStatus.succeeded);
    await h.repo.database.write(
      (db) => db.execute(
        "UPDATE execution_records SET state=?1,payload=json_set(payload,"
        "'\$.state',?1,'\$.stage',?1) WHERE id=?2",
        ['interrupted', card.id],
      ),
    );
    final next = await agent3.resume(card.id);
    final toolContents = (next.payload['messages'] as List)
        .whereType<Map>()
        .where((m) => m['role'] == 'tool')
        .map((m) => m['content'] as String)
        .toList();
    expect(
      toolContents.any((c) => c.contains('未执行：任务在此之前中断，如仍需要请重新提出')),
      isTrue,
      reason: 'not_run_resume Chinese text must stay fixed',
    );
  });
}
