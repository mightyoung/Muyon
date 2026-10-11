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

/// GB-6 characterization for model-turn gaps G11–G14 (CR-9 review revisions).
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

/// First review allows (mode_auto send); variant review can confirm/block.
final class _VariantWireReviewer implements OutboundContentReviewer {
  _VariantWireReviewer(this.action);
  final ReviewAction action;
  int calls = 0;
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async {
    calls++;
    if (calls == 1) return const ReviewDecision.allow();
    return switch (action) {
      ReviewAction.allow => const ReviewDecision.allow(),
      ReviewAction.confirm => const ReviewDecision.confirm('confirm variant'),
      ReviewAction.block => const ReviewDecision.block('block variant'),
    };
  }
}

List<Map> _events(LoopFixture f, String taskId) => [
  for (final e in f.repo.taskEvents(taskId)) e.toJson(),
];

void main() {
  test('manual_model_confirm_leaves_card_without_send', () async {
    // Renamed from wire_review: ConfirmModelReviewer is ordinary manual
    // confirm, not HostModelWireReviewRequired.
    // Mutation: non-automatic review is treated as automatic runModel.
    final root = Directory.systemTemp.createTempSync('gb6-manual-confirm-');
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

  test('wire_review_required_holds_variant_without_second_send', () async {
    // Mutation: HostModelWireReviewRequired handler (≈182-195) treated as
    // automatic — second request is sent without waiting.
    // Real path: local non-stream compat gets 400, variant needs confirm.
    final root = Directory.systemTemp.createTempSync('gb6-wire-real-');
    final reviewer = _VariantWireReviewer(ReviewAction.confirm);
    final host = await MuyonHost.open(root.path, localModelReviewer: reviewer);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final bodies = <dynamic>[];
    addTearDown(() async {
      await host.close();
      await server.close(force: true);
      root.deleteSync(recursive: true);
    });
    server.listen((request) async {
      bodies.add(jsonDecode(await utf8.decoder.bind(request).join()));
      request.response.statusCode = bodies.length == 1 ? 400 : 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'type': 'answer',
                  'answer': 'compatible done',
                  'citationIds': [],
                }),
              },
              'finish_reason': 'stop',
            },
          ],
        }),
      );
      await request.response.close();
    });
    final profile = ModelProfile(
      id: 'gb6-compat-wire',
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1'),
      location: ModelLocation.local,
      modelId: 'm',
      endpointIdentity: 'compat-wire-fixture',
    );
    final c = await host.foundation.createConversation();
    var task = await host.personalAgent.start(
      conversationId: c.id,
      prompt: 'compatible response',
      profile: profile,
    );
    expect(reviewer.calls, 2);
    expect(task.state, PersonalTaskState.waitingConfirmation);
    expect(
      bodies,
      hasLength(1),
      reason: 'variant awaiting confirm must not send again',
    );
    expect(host.outbound.recent(), hasLength(1));
    await host.personalAgent.confirm(
      task.id,
      requestDigest: task.payload['requestDigest'] as String,
    );
    task = host.foundation.task(task.id)!;
    expect(task.state, PersonalTaskState.succeeded);
    expect(bodies, hasLength(2));
  });

  test('model_content_block_fails_with_fixed_reason', () async {
    // Mutation: delete initial block handling (≈167-170).
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
    expect(task.error, '模型内容审查阻止发送');
    expect(f.bodies, isEmpty);
  });

  test('planning_session_expired_before_send', () async {
    // Mutation: delete planning_session_expired check (≈223-226).
    final f = await LoopFixture.open();
    f.replies.add(LoopReply.sse(sseText('nope')));
    final agent = f.agent();
    var task = await f.start(agent, f.profile());
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
    // Mutation: delete profile digest compare (≈259-260).
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
    expect(task.error, contains('model_source_changed'));
  });

  test('nonstreaming_compat_preview_omits_max_output_tokens', () async {
    // Mutation: drop capability early return in _outputCap (≈581-583), or
    // change && to || (≈581).
    // Premise: 0 < remaining − promptEstimate < maxOutputTokens (default 8192).
    // Short prompt + mid-size budget keeps room in that window for stream paths
    // while compat still omits the key solely due to the capability guard.
    const prompt = '短提示';
    const budget = Budget(maxTokens: 4000);

    // Streaming+native: cap must appear (proves room > 0 and room < 8192).
    final f = await LoopFixture.open();
    f.replies.add(LoopReply.sse(sseText('hello')));
    final streamAgent = f.agent(budget: budget);
    final streamTask = await f.start(streamAgent, f.profile(), prompt: prompt);
    expect(streamTask.state, PersonalTaskState.waitingConfirmation);
    final streamCap =
        (streamTask.payload['preview'] as Map)['maxOutputTokens'] as int?;
    expect(
      streamCap,
      isNotNull,
      reason: 'stream+native must expose cap when 0 < room < 8192',
    );
    expect(streamCap, greaterThan(0));
    expect(streamCap, lessThan(8192));

    // Non-stream non-native: same budget premise, cap key must be absent.
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
    final compat = g.agent(budget: budget);
    final compatTask = await g.start(
      compat,
      g.profile(
        capabilities: const ModelCapabilities(
          streaming: false,
          nativeTools: false,
          source: CapabilitySource.userDeclared,
        ),
      ),
      prompt: prompt,
    );
    expect(compatTask.state, PersonalTaskState.waitingConfirmation);
    expect(
      (compatTask.payload['preview'] as Map).containsKey('maxOutputTokens'),
      isFalse,
      reason: 'compat non-stream omits cap only via capability early return',
    );

    // streaming-only (native false): still has cap (&& not ||).
    final h = await LoopFixture.open();
    h.replies.add(LoopReply.sse(sseText('hello')));
    final streamOnly = h.agent(budget: budget);
    final streamOnlyTask = await h.start(
      streamOnly,
      h.profile(
        capabilities: const ModelCapabilities(
          streaming: true,
          nativeTools: false,
          source: CapabilitySource.userDeclared,
        ),
      ),
      prompt: prompt,
    );
    expect(
      (streamOnlyTask.payload['preview'] as Map).containsKey('maxOutputTokens'),
      isTrue,
      reason: 'streaming alone must still apply _outputCap',
    );

    // native-only (streaming false): still has cap (&& not ||).
    final i = await LoopFixture.open();
    i.replies.add(LoopReply.sse(sseText('hello')));
    final nativeOnly = i.agent(budget: budget);
    final nativeOnlyTask = await i.start(
      nativeOnly,
      i.profile(
        capabilities: const ModelCapabilities(
          streaming: false,
          nativeTools: true,
          source: CapabilitySource.userDeclared,
        ),
      ),
      prompt: prompt,
    );
    expect(
      (nativeOnlyTask.payload['preview'] as Map).containsKey('maxOutputTokens'),
      isTrue,
      reason: 'nativeTools alone must still apply _outputCap',
    );
  });

  test('drain_announces_model_request_only_after_first_stream_event', () async {
    // Mutation: announce before await-for / before first ModelEvent (≈508-516).
    // Custom server holds BEFORE writing any SSE so we can assert no announce
    // after confirm but before the first event.
    final f = await LoopFixture.open();
    final releaseFirst = Completer<void>();
    final accepted = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      if (!releaseFirst.isCompleted) releaseFirst.complete();
      await server.close(force: true);
    });
    server.listen((request) async {
      f.bodies.add(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>,
      );
      if (!accepted.isCompleted) accepted.complete();
      await releaseFirst.future;
      request.response.statusCode = 200;
      request.response.bufferOutput = false;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      for (final part in sseText('hello', prompt: 10, completion: 2)) {
        request.response.write(part);
        await request.response.flush();
      }
      await request.response.close();
    });
    final agent = f.agent();
    final profile = f.profile(port: server.port);
    final task = await f.start(agent, profile);
    expect(
      _events(f, task.id).where((e) => e['type'] == 'model_request'),
      isEmpty,
    );
    final pending = agent.confirm(
      task.id,
      requestDigest: task.payload['requestDigest'] as String,
    );
    await accepted.future.timeout(const Duration(seconds: 10));
    expect(
      _events(f, task.id).where((e) => e['type'] == 'model_request'),
      isEmpty,
      reason: 'confirmed but first ModelEvent not yet delivered',
    );
    releaseFirst.complete();
    await pending;
    expect(
      _events(f, task.id).where((e) => e['type'] == 'model_request'),
      hasLength(1),
    );
  });

  test('native_bad_citation_strips_but_compat_bad_citation_fails', () async {
    // Mutation: native keeps bad [rN]; compat fails for a reason other than
    // Invalid citations (≈394 / ≈811).
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
    expect(nativeTask.summary, contains('答案'));
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
    expect(compatTask.error, contains('Invalid citations'));
    expect(compatTask.summary, isNull);
  });

  test('log_entry_truncates_above_120_chars', () async {
    // Mutation: _logEntry (≈937) returns full summary; or >120 becomes >=120.
    final f = await LoopFixture.open();
    f.addTool('longwrite', ToolEffect.write, summary: '字' * 121);
    f.replies
      ..add(LoopReply.sse(sseCalls([('c1', 'longwrite', '{}')])))
      ..add(LoopReply.sse(sseText('好')));
    final agent = f.agent();
    var task = await f.run(agent, await f.start(agent, f.profile()));
    await agent.confirm(
      task.id,
      requestDigest: task.payload['requestDigest'] as String,
    );
    task = await f.run(agent, f.repo.task(task.id)!);
    expect(task.state, PersonalTaskState.succeeded);
    final entry = Map<String, Object?>.from(
      (task.payload['toolLog'] as List).single as Map,
    );
    expect(entry['summary'], '${'字' * 120}…');

    final exact = await LoopFixture.open();
    exact.addTool('exact', ToolEffect.write, summary: '字' * 120);
    exact.replies
      ..add(LoopReply.sse(sseCalls([('c1', 'exact', '{}')])))
      ..add(LoopReply.sse(sseText('好')));
    final a2 = exact.agent();
    var t2 = await exact.run(a2, await exact.start(a2, exact.profile()));
    await a2.confirm(
      t2.id,
      requestDigest: t2.payload['requestDigest'] as String,
    );
    t2 = await exact.run(a2, exact.repo.task(t2.id)!);
    final e2 = Map<String, Object?>.from(
      (t2.payload['toolLog'] as List).single as Map,
    );
    expect(e2['summary'], '字' * 120, reason: 'exactly 120 must not truncate');
  });

  test('not_approved_not_run_text_is_fixed', () async {
    // Mutation: change not_approved Chinese string (≈65).
    final f = await LoopFixture.open();
    f.addTool('w1', ToolEffect.write);
    f.addTool('w2', ToolEffect.write);
    f.replies
      ..add(LoopReply.sse(sseCalls([('c1', 'w1', '{}'), ('c2', 'w2', '{}')])))
      ..add(LoopReply.sse(sseText('好')));
    final agent = f.agent();
    var task = await f.run(agent, await f.start(agent, f.profile()));
    final ids = [
      for (final c in (task.payload['toolCalls'] as List).cast<Map>())
        c['invocationId'] as String,
    ];
    await agent.confirm(
      task.id,
      requestDigest: task.payload['requestDigest'] as String,
      selectedInvocationIds: [ids.first],
    );
    task = await f.run(agent, f.repo.task(task.id)!);
    final toolMsgs = (task.payload['messages'] as List)
        .whereType<Map>()
        .where((m) => m['role'] == 'tool')
        .toList();
    expect(
      jsonDecode(toolMsgs[1]['content'] as String)['notExecuted'],
      '用户未批准此调用',
    );
  });

  test('not_run_prior_failed_status_key_is_fixed', () async {
    // Mutation: status key not_run_prior_failed (≈654) becomes not_approved.
    // Note: _complete fails before folding notExecuted messages for this path.
    final f = await LoopFixture.open();
    f.addTool(
      'bad',
      ToolEffect.write,
      onCall: (_) async =>
          ToolCallResult(status: ToolCallStatus.failed, summary: 'disk full'),
    );
    f.addTool('later', ToolEffect.write);
    f.replies.add(
      LoopReply.sse(sseCalls([('c1', 'bad', '{}'), ('c2', 'later', '{}')])),
    );
    final agent = f.agent();
    final card = await f.run(agent, await f.start(agent, f.profile()));
    await agent.confirm(
      card.id,
      requestDigest: card.payload['requestDigest'] as String,
    );
    final after = f.repo.task(card.id)!;
    expect(after.state, PersonalTaskState.failed);
    final stepCalls = ((after.payload['step'] as Map)['calls'] as List)
        .cast<Map>();
    expect(stepCalls[1]['outcome'], {'status': 'not_run_prior_failed'});
  });

  test('not_run_resume_text_is_fixed', () async {
    // Mutation: change not_run_resume Chinese (≈71).
    // unknown_before_resume wording deferred per CR-9 (hold prompt conflict).
    final f = await LoopFixture.open();
    f.addTool('w1', ToolEffect.write);
    f.addTool('w2', ToolEffect.write);
    f.replies
      ..add(LoopReply.sse(sseCalls([('c1', 'w1', '{}'), ('c2', 'w2', '{}')])))
      ..add(LoopReply.sse(sseText('续')));
    final agent = f.agent();
    final card = await f.run(agent, await f.start(agent, f.profile()));
    final cardCalls = (card.payload['toolCalls'] as List).cast<Map>();
    await agent.cancel(card.id);
    final first = cardCalls.first;
    final request = ToolCallRequest(
      invocationId: first['invocationId'] as String,
      toolId: first['toolId'] as String,
      scope: card.scope,
      parameters: Map<String, Object?>.from(first['parameters'] as Map),
    );
    final prepared = await f.tools.prepare(request);
    final approval = await f.tools.approve(prepared);
    expect(
      (await f.tools.invoke(request.withApproval(approval))).status,
      ToolCallStatus.succeeded,
    );
    await f.repo.database.write(
      (db) => db.execute(
        "UPDATE execution_records SET state=?1,payload=json_set(payload,"
        "'\$.state',?1,'\$.stage',?1) WHERE id=?2",
        ['interrupted', card.id],
      ),
    );
    final next = await agent.resume(card.id);
    final toolContents = (next.payload['messages'] as List)
        .whereType<Map>()
        .where((m) => m['role'] == 'tool')
        .map((m) => m['content'] as String)
        .toList();
    expect(
      toolContents.any((c) => c.contains('未执行：任务在此之前中断，如仍需要请重新提出')),
      isTrue,
    );
  });
}
