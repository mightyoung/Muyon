import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../platform/foundation_repository.dart';
import '../services/models/model_gateway.dart';
import '../services/models/model_provider.dart';
import '../services/models/token_estimate.dart';
import 'agent_budget.dart';
import 'agent_context.dart';
import 'agent_drafts.dart';
import 'agent_event_sink.dart';
import 'agent_compaction_flow.dart';
import 'agent_dispatch.dart';
import 'model_request_gate.dart';
import 'request_view.dart';

/// Model turn of a task (S0 budget check, the confirmation of the request,
/// the request itself in compatibility and native mode, billing and the
/// protocol corrections).
class AgentModelTurn {
  AgentModelTurn(this.ctx);
  final AgentContext ctx;
  late AgentDispatch dispatch;
  late AgentCompactionFlow compaction;

  /// S0 (ADR-0005 §6.2): what the task may still use is checked before
  /// anything is built; a spent budget ends it with a summary, no request.
  Future<void> advance(PersonalTask task) async {
    final usage = BudgetUsage.fromPayload(task.payload);
    final kind = ctx.budget.exhausted(usage);
    if (kind != null) {
      await _exhausted(task, kind, usage);
      return;
    }
    final ready = await compaction.compactIfNeeded(task);
    if (ready != null) await waitForModel(ready);
  }

  /// The task ends `failed` with what the receipts show was done and what was
  /// not; the host writes it, not the model, and nothing more is sent. The
  /// step case keeps the old "轮次" wording.
  Future<void> _exhausted(
    PersonalTask task,
    BudgetKind kind,
    BudgetUsage usage,
  ) async {
    final reason = switch (kind) {
      BudgetKind.steps => '工具轮次达到上限（${usage.steps}/${ctx.budget.maxSteps} 步）',
      BudgetKind.activeTime =>
        '活动时长达到上限（${usage.active.inSeconds}/${ctx.budget.maxActive.inSeconds} 秒）',
      BudgetKind.tokens =>
        'token 预算耗尽（${usage.tokens}/${ctx.budget.maxTokens}${usage.estimated ? '，含估算' : ''}）',
    };
    final log = [
      for (final e in task.payload['toolLog'] as List? ?? const [])
        '${(e as Map)['toolId']}（${e['status']}）${e['summary']}',
    ];
    await ctx.fail(
      task,
      '$reason。${log.isEmpty ? '没有已完成的工具调用。' : '已完成：${log.join('；')}。'}'
      '尚未得到最终答案；可点“继续”新建尝试，预算重新计算。',
      code: 'budget_${kind.name}',
    );
  }

  Future<void> waitForModel(PersonalTask task) async {
    final preview = {
      'endpoint': ctx.profile(task).endpoint.toString(),
      'profile': ctx.previewProfile(task),
      'scope': task.scope.toJson(),
      'messages': ctx.view(task),
      'dataCategories': ['conversation', 'memories', 'tool_results'],
      // Native mode sends more than the messages; the person confirms that
      // too, so the tools and the mode are part of the digest.
      if (AgentContext.native(task)) ...{
        'mode': 'native',
        'tools': task.payload['nativeTools'],
      },
      // The person is told when earlier content was compacted.
      'compacted': ?_compacted(task),
      // Only when the token budget is nearly spent: the request is then
      // limited to what is left, and the person sees the limit too.
      'maxOutputTokens': ?_outputCap(task),
    };
    if (utf8.encode(jsonEncode(preview)).length > 256 * 1024) {
      await ctx.fail(task, '上下文过大，请缩小范围');
      return;
    }
    final decision = await ctx.gate.decide(
      ModelRequestFacts(
        location: ctx.profile(task).location,
        endpoint: ctx.profile(task).endpoint.toString(),
        endpointIdentity: ctx.profile(task).endpointIdentity,
        scopeDigest: AgentContext.digest(task.scope.toJson()),
        requestDigest: AgentContext.digest(preview),
        dataCategories: const {'conversation', 'memories', 'tool_results'},
        step: task.payload['round'] as int,
      ),
    );
    // Only the confirmation card exists until AUTH-1 (K-3's loop): any other
    // answer stops here rather than sending without the person.
    if (decision is! GateConfirm) {
      await ctx.fail(task, '模型请求未获放行');
      return;
    }
    final card = task.copy({
      'state': 'waitingConfirmation',
      'stage': 'model',
      'waitingFor': '确认向所选端点发送以下内容',
      'preview': preview,
      'requestDigest': AgentContext.digest(preview),
      'expiresAt': ctx
          .clock()
          .toUtc()
          .add(const Duration(minutes: 5))
          .toIso8601String(),
      'approvalNonce': const Uuid().v4(),
    });
    if (!await ctx.repository.updateTask(card)) return;
    await ctx.event(card, AgentEventType.wait, {
      'stage': 'model',
      'requestDigest': card.payload['requestDigest'],
    });
  }

  /// Same checks before every send, whichever path sends.
  Future<void> _beforeSend(PersonalTask task) async {
    if (ctx.closing ||
        ctx.repository.task(task.id)?.state != PersonalTaskState.running) {
      throw StateError('cancelled');
    }
    if (!ctx.clock().toUtc().isBefore(
          DateTime.parse(task.payload['expiresAt'] as String),
        ) ||
        task.payload['memoryDigest'] !=
            AgentContext.digest(ctx.memories(task.scope))) {
      throw StateError('stale_confirmation');
    }
    final current = ctx.repository.conversation(task.conversationId);
    if (current == null ||
        AgentContext.digest(current.scope.toJson()) !=
            AgentContext.digest(task.scope.toJson())) {
      throw StateError('scope_mismatch');
    }
  }

  Future<void> runModel(PersonalTask task) async {
    final token = ModelCancellation();
    ctx.modelTokens[task.id] = token;
    try {
      // Frozen when the task started: editing the profile later does not
      // change this task's protocol.
      final profile = ctx.profile(task);
      if (profile.capabilities.nativeTools) {
        await _runNative(task, token, profile);
        return;
      }
      final started = ctx.clock();
      final String text;
      Usage? usage;
      Reply? streamed;
      if (profile.capabilities.streaming) {
        streamed = await _streamCompat(task, token, profile);
        text = streamed.text.toString();
        usage = streamed.usage;
      } else {
        text = await ctx.gateway.chat(
          profile: profile,
          messages: [
            for (final m in ctx.view(task)) Map<String, String>.from(m as Map),
          ],
          caller: 'assistant',
          cancellation: token,
          beforeSend: () => _beforeSend(task),
        );
      }
      token.check();
      if (ctx.closing ||
          ctx.repository.task(task.id)?.state != PersonalTaskState.running) {
        return;
      }
      if (!profile.capabilities.streaming) {
        await ctx.event(task, AgentEventType.modelRequest, {
          'caller': 'assistant',
          'requestDigest': task.payload['requestDigest'],
          'mode': 'compat',
          'streamed': false,
        });
      }
      // What this response used is charged whatever it turns out to be.
      final billed = _bill(task, started, replyText: text, usage: usage);
      await _responded(billed, usage, null, streamed?.draft);
      final response = _protocolReply(text);
      if (response == null) {
        // The draft was only ever a view of this text: dropped with it.
        ctx.drafts.discard(task.id);
        // Prose, native tool-call markup or a wrong shape is never acted on.
        // At most one corrective round, confirmed like any other; then a
        // fixed reason that does not quote the model (it may echo a key).
        await _correctOrFail(billed, notJson: _notJson(text));
        return;
      }
      final advanced = billed.copy({
        'round': (task.payload['round'] as int) + 1,
        'messages': [
          ...task.payload['messages'] as List,
          {'role': 'assistant', 'content': text},
        ],
      });
      if (response['type'] == 'tool') {
        ctx.drafts.commit(task.id);
        await dispatch.dispatch(advanced, [
          Planned(
            response['toolId'] as String,
            Map<String, Object?>.from(response['parameters'] as Map),
            destination: response['destination'] as String?,
          ),
        ]);
      } else if (response['type'] == 'answer' && response['answer'] is String) {
        final all = ctx.references(task);
        final ids = response['citationIds'] as List? ?? const [];
        if (ids.any(
          (id) =>
              id is! String ||
              !RegExp(r'^r[1-9][0-9]*$').hasMatch(id) ||
              int.parse(id.substring(1)) > all.length,
        )) {
          ctx.drafts.discard(task.id);
          throw StateError('Invalid citations');
        }
        ctx.drafts.commit(task.id);
        await ctx.finish(advanced, response['answer'] as String, [
          for (final id in ids.toSet())
            all[int.parse((id as String).substring(1)) - 1],
        ], canCommit: () => !token.isCancelled);
      } else {
        ctx.drafts.discard(task.id);
        throw const FormatException('Invalid assistant protocol');
      }
    } finally {
      ctx.modelTokens.remove(task.id);
      // Whatever ended the request without a usable reply (cancel, cut
      // stream, timeout, truncation, a rejected request): the draft stays on
      // screen, marked as not saved. A no-op once it was committed or
      // discarded.
      ctx.drafts.interrupt(task.id);
    }
  }

  /// Fixed correction for native mode; like [_correction] it quotes nothing.
  static const _nativeCorrection =
      'Your previous reply did not follow the protocol and was discarded. '
      'Call the provided functions with valid JSON arguments, '
      'or answer in plain text. No other markup.';

  ModelRequest _modelRequest(PersonalTask task, ModelProfile profile) {
    final native = profile.capabilities.nativeTools;
    return ModelRequest(
      profile: profile,
      messages: [
        for (final m in ctx.view(task)) ModelMessage.fromJson(m as Map),
      ],
      tools: native
          ? [
              for (final t in task.payload['nativeTools'] as List)
                ModelToolSpec(
                  name: (t as Map)['name'] as String,
                  description: t['description'] as String,
                  parameters: Map<String, Object?>.from(t['parameters'] as Map),
                ),
            ]
          : const [],
      maxOutputTokens:
          (task.payload['preview'] as Map?)?['maxOutputTokens'] as int?,
      // Compatibility mode asks for one JSON object per reply (P0-3d).
      jsonObject: !native,
      caller: 'assistant',
      requestDigest: task.payload['requestDigest'] as String?,
    );
  }

  /// Reads one response to its end. Nothing is acted on here: the caller
  /// sees the whole reply only after [Done], and a partial one never.
  Future<Reply> _collect(
    PersonalTask task,
    ModelCancellation token,
    ModelProfile profile,
  ) async {
    try {
      return await drain(
        task,
        _modelRequest(task, profile),
        token,
        showDraft: true,
      );
    } on HttpException catch (error) {
      // The endpoint refused what was asked: a fixed failure, never another
      // protocol, model or endpoint (ADR-0005 §4.3), and no resend.
      if (error.message == 'model_http_400' ||
          error.message == 'model_http_422') {
        throw profile.capabilities.nativeTools
            ? const FixedFailure(
                'native_tools_rejected',
                '端点以 400/422 拒绝（可能是流式、工具或其他参数）（native_tools_rejected）：请把该模型改为兼容模式，或关闭流式',
              )
            : const FixedFailure(
                'stream_rejected',
                '端点以 400/422 拒绝（可能是流式、工具或其他参数）（stream_rejected）：请关闭该模型的流式，或运行测试连接',
              );
      }
      rethrow;
    }
  }

  /// Sends [request] through the gateway and gathers its events. Nothing is
  /// acted on here.
  ///
  /// With [showDraft] the text (compatibility mode: only the `answer` text)
  /// is also offered to the screen as a draft, in memory only; the task event
  /// gets its length and digest, never its text.
  Future<Reply> drain(
    PersonalTask task,
    ModelRequest request,
    ModelCancellation token, {
    bool showDraft = false,
  }) async {
    final reply = Reply();
    final feed = showDraft
        ? DraftFeed(ctx.drafts, task.id, native: request.tools.isNotEmpty)
        : null;
    try {
      var announced = false;
      await for (final event in ctx.gateway.chatStream(
        provider: ctx.provider,
        request: request,
        cancellation: token,
        beforeSend: () => _beforeSend(task),
        // The smaller of what is left of the active budget and 5 minutes.
        maxDuration: ctx.budget.requestLimit(
          BudgetUsage.fromPayload(task.payload),
        ),
      )) {
        if (!announced) {
          // The first event means the ledger row exists and the request went.
          announced = true;
          await ctx.event(task, AgentEventType.modelRequest, {
            'caller': request.caller,
            'requestDigest': request.requestDigest,
            'mode': request.tools.isNotEmpty ? 'native' : 'compat',
            'streamed': request.profile.capabilities.streaming,
          });
        }
        switch (event) {
          case TextDelta():
            reply.text.write(event.text);
            feed?.text(event.text);
          case ToolCallComplete():
            reply.calls.add(event);
          case ToolCallDelta():
            // Display only: "preparing a tool call"; never acted on.
            feed?.toolCall();
          case Usage():
            reply.usage = event;
          case Done():
            reply.done = event;
          case ModelError():
            reply.error = event;
        }
      }
    } finally {
      feed?.flush();
    }
    if (feed != null) {
      reply.draft = (
        length: feed.length,
        digest: AgentContext.digest(feed.shown),
      );
    }
    return reply;
  }

  /// Compatibility mode over a stream: the same JSON protocol, only the
  /// transport changes. The text is accumulated and judged after [Done] by
  /// the same strict parse as a non-streaming reply.
  Future<Reply> _streamCompat(
    PersonalTask task,
    ModelCancellation token,
    ModelProfile profile,
  ) async {
    final reply = await _collect(task, token, profile);
    _throwIfFailed(reply, profile);
    // No tools are offered here, so a tool call is not protocol: the reply is
    // discarded and corrected like any other non-JSON reply.
    if (reply.calls.isNotEmpty) {
      reply.text.clear();
    }
    return reply;
  }

  /// Before / after sizes of the last compaction, if the task had one.
  static Map<String, Object?>? _compacted(PersonalTask task) {
    final history = (task.payload['compaction'] as Map?)?['history'];
    if (history is! List || history.isEmpty) return null;
    final last = history.last as Map;
    return {
      'tokensBefore': last['tokensBefore'],
      'tokensAfter': last['tokensAfter'],
    };
  }

  /// What is left of the token budget after the prompt, when that is less than
  /// the reply could take; null otherwise. Only requests that go through the
  /// provider carry it (`ctx.gateway.chat` has no such parameter).
  int? _outputCap(PersonalTask task) {
    final profile = ctx.profile(task);
    if (!profile.capabilities.streaming && !profile.capabilities.nativeTools) {
      return null;
    }
    final prompt =
        estimateMessageTokens(ctx.view(task)) +
        (AgentContext.native(task)
            ? estimateTokens(jsonEncode(task.payload['nativeTools']))
            : 0);
    final room =
        ctx.budget.remainingTokens(BudgetUsage.fromPayload(task.payload)) -
        prompt;
    return room > 0 && room < (profile.capabilities.maxOutputTokens ?? 8192)
        ? room
        : null;
  }

  /// Charges one model response to the task's budgets: the time it ran
  /// (never time spent waiting for the person) and its tokens, as the endpoint
  /// reported them or, where it did not, a conservative estimate.
  PersonalTask _bill(
    PersonalTask task,
    DateTime started, {
    required String replyText,
    Usage? usage,
  }) {
    final promptEstimate =
        estimateMessageTokens(ctx.view(task)) +
        (AgentContext.native(task)
            ? estimateTokens(jsonEncode(task.payload['nativeTools']))
            : 0);
    final prompt = usage?.promptTokens;
    final completion = usage?.completionTokens;
    final next = BudgetUsage.fromPayload(task.payload).plus(
      active: ctx.clock().difference(started),
      tokens:
          (prompt ?? promptEstimate) +
          (completion ?? estimateTokens(replyText)),
      estimated: prompt == null || completion == null,
    );
    return task.copy({
      ...next.toPayload(),
      'round': task.payload['round'],
      // Known size of the prompt just sent, to correct the next estimate.
      if (prompt != null) ...{
        'reportedPromptTokens': prompt,
        'reportedViewCount': ctx.view(task).length,
      },
    });
  }

  /// What one response cost, as an event: sizes and a finish reason, never
  /// the text.
  Future<void> _responded(
    PersonalTask billed,
    Usage? usage,
    Done? done, [
    ({int length, String digest})? draft,
  ]) => ctx.event(billed, AgentEventType.modelResponse, {
    'promptTokens': usage?.promptTokens,
    'completionTokens': usage?.completionTokens,
    'tokensUsed': billed.payload['tokensUsed'],
    'estimated': billed.payload['tokensEstimated'],
    'finish': ?done?.reason.name,
    // The draft the person was shown: its size and digest only (Q4).
    if (draft != null) ...{
      'draftLength': draft.length,
      'draftDigest': draft.digest,
    },
  });

  static Never _failure(FixedFailure f) => throw f;

  /// Failures that end the task with a fixed reason (never the model's text).
  static void _throwIfFailed(Reply reply, ModelProfile profile) {
    final error = reply.error;
    if (error != null) {
      const shape = {
        'empty_choices',
        'choice_without_message',
        'tool_calls_not_list',
        'response_not_object',
        'response_not_json',
      };
      if (profile.capabilities.nativeTools && shape.contains(error.code)) {
        _failure(
          const FixedFailure(
            'native_tools_rejected',
            '端点的响应不符合原生工具调用格式（native_tools_rejected）：请把该模型改为兼容模式',
          ),
        );
      }
      if (error.code == 'stream_truncated') {
        _failure(
          const FixedFailure(
            'stream_truncated',
            '模型响应中断（stream_truncated），部分内容未保存',
          ),
        );
      }
      _failure(
        const FixedFailure('model_stream_error', '模型返回错误（model_stream_error）'),
      );
    }
    final reason = reply.done?.reason;
    if (reason == FinishReason.length) {
      _failure(
        const FixedFailure(
          'model_output_truncated',
          '模型输出被截断（model_output_truncated）',
        ),
      );
    }
    if (reason == FinishReason.contentFilter || reason == FinishReason.other) {
      _failure(
        const FixedFailure(
          'model_reply_unusable',
          '模型回复无法使用（model_reply_unusable）',
        ),
      );
    }
  }

  /// Native tool calling. A reply that breaks the protocol (an unknown or
  /// repeated call, arguments that are not a JSON object, the legacy
  /// `function_call`, an empty reply) is discarded whole: it is not saved and
  /// not sent back; only the fixed correction is added, at most once. Several
  /// calls in one reply are fine: each goes through the frozen candidates and
  /// `ToolRegistry.prepare`, and writes through the person's confirmation.
  Future<void> _runNative(
    PersonalTask task,
    ModelCancellation token,
    ModelProfile profile,
  ) async {
    final started = ctx.clock();
    final reply = await _collect(task, token, profile);
    token.check();
    if (ctx.closing ||
        ctx.repository.task(task.id)?.state != PersonalTaskState.running) {
      return;
    }
    _throwIfFailed(reply, profile);
    final text = reply.text.toString();
    final billed = _bill(
      task,
      started,
      replyText:
          text +
          [for (final c in reply.calls) '${c.name}${jsonEncode(c.arguments)}']
              .join(),
      usage: reply.usage,
    );
    await _responded(billed, reply.usage, reply.done, reply.draft);
    Future<void> discard() {
      ctx.drafts.discard(task.id);
      return _correctOrFail(
        billed,
        notJson: false,
        correction: _nativeCorrection,
      );
    }

    if (reply.calls.isEmpty) {
      if (text.trim().isEmpty) return discard();
      await _answerNative(billed, token, text);
      return;
    }
    final toolIds = {
      for (final t in task.payload['nativeTools'] as List)
        (t as Map)['name'] as String: t['toolId'] as String,
    };
    // One bad call spoils the reply: it is discarded whole, so no saved call
    // is ever left without its result.
    if (reply.calls.any((c) => !c.valid || toolIds[c.name] == null)) {
      return discard();
    }
    final advanced = billed.copy({'round': (task.payload['round'] as int) + 1});
    // The text before the calls is saved with the step's assistant message.
    ctx.drafts.commit(task.id);
    await dispatch.dispatch(
      advanced,
      [
        for (final c in reply.calls)
          Planned(toolIds[c.name]!, c.arguments!, callId: c.callId),
      ],
      assistantMessage: {
        'role': 'assistant',
        'content': text,
        'tool_calls': [
          for (final c in reply.calls)
            ModelToolCall(
              id: c.callId,
              name: c.name,
              arguments: jsonEncode(c.arguments),
            ).toJson(),
        ],
      },
    );
  }

  /// Plain-text answer in native mode. `[r1]` marks a citation; one that does
  /// not name an actual tool result is removed and the answer says so, rather
  /// than failing (compatibility mode still fails on a bad citation).
  Future<void> _answerNative(
    PersonalTask task,
    ModelCancellation token,
    String text,
  ) async {
    final all = ctx.references(task);
    final cited = <int>{};
    var invalid = false;
    final cleaned = text.replaceAllMapped(RegExp(r'\[r([0-9]+)\]'), (m) {
      final n = int.parse(m[1]!);
      if (n >= 1 && n <= all.length) {
        cited.add(n);
        return m[0]!;
      }
      invalid = true;
      return '';
    });
    final answer = invalid ? '$cleaned\n\n（引用未通过校验，已移除无效引用）' : cleaned;
    final advanced = task.copy({
      'round': (task.payload['round'] as int) + 1,
      'messages': [
        ...task.payload['messages'] as List,
        {'role': 'assistant', 'content': text},
      ],
    });
    ctx.drafts.commit(task.id);
    await ctx.finish(advanced, answer, [
      for (final n in cited.toList()..sort()) all[n - 1],
    ], canCommit: () => !token.isCancelled);
  }

  /// Corrective rounds allowed per task when a reply breaks the protocol.
  static const maxProtocolCorrections = 1;

  static const _correction =
      'Your previous reply did not follow the protocol and was discarded. '
      'Reply with exactly one JSON object: {"type":"tool","toolId":"registered '
      'ID","parameters":{}} OR {"type":"answer","answer":"text",'
      '"citationIds":["r1"]}. No other text, no markup.';

  /// The reply as a protocol object, or null. Strict: the whole text must be
  /// one JSON object of a known shape. No fence stripping, no extraction of
  /// JSON or native tool-call markup from prose.
  static Map<String, dynamic>? _protocolReply(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    return switch (decoded['type']) {
      'tool'
          when decoded['toolId'] is String &&
              decoded['parameters'] is Map &&
              (decoded['destination'] == null ||
                  decoded['destination'] is String) =>
        decoded,
      'answer' when decoded['answer'] is String => decoded,
      _ => null,
    };
  }

  static bool _notJson(String text) {
    try {
      jsonDecode(text);
      return false;
    } on FormatException {
      return true;
    }
  }

  Future<void> _correctOrFail(
    PersonalTask task, {
    required bool notJson,
    String correction = _correction,
  }) async {
    final used = task.payload['protocolCorrections'] as int? ?? 0;
    if (used >= maxProtocolCorrections) {
      throw FormatException(
        notJson ? 'model_reply_not_json' : 'Invalid assistant protocol',
      );
    }
    // The discarded reply is not kept; only the correction is added. The new
    // round counts against the step budget and waits for confirmation as usual.
    await advance(
      task.copy({
        'round': (task.payload['round'] as int) + 1,
        'protocolCorrections': used + 1,
        'messages': [
          ...task.payload['messages'] as List,
          {'role': 'user', 'content': correction},
        ],
      }),
    );
  }
}
