import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../platform/foundation_repository.dart';
import '../services/models/model_gateway.dart';
import '../services/models/model_provider.dart';
import '../services/models/token_estimate.dart';
import 'agent_budget.dart';
import 'agent_context.dart';
import 'agent_event_sink.dart';
import 'agent_model_turn.dart';
import 'context_compactor.dart';
import 'model_request_gate.dart';

/// Context compaction (ADR-0005 §6.6): clearing old results, the summary
/// request and its confirmation card, and the manual / declined paths.
class AgentCompactionFlow {
  AgentCompactionFlow(this.ctx);
  final AgentContext ctx;
  late AgentModelTurn model;

  Map<String, String> _wireNames(PersonalTask task) => {
    for (final t in task.payload['nativeTools'] as List? ?? const [])
      (t as Map)['name'] as String: t['toolId'] as String,
  };

  int _toolsTokens(PersonalTask task) => AgentContext.native(task)
      ? estimateTokens(jsonEncode(task.payload['nativeTools']))
      : 0;

  /// Tokens the next request would have under [state]: the provider's report
  /// for the same view when there is one, an estimate otherwise.
  int _tokensUnder(
    PersonalTask task,
    CompactionState state, {
    bool useReport = false,
  }) => ctx.compactor.tokensOfView(
    task.payload['messages'] as List,
    state,
    references: task.payload['references'] as List? ?? const [],
    extra: _toolsTokens(task),
    reportedPromptTokens: useReport
        ? task.payload['reportedPromptTokens'] as int?
        : null,
    reportedViewCount: useReport
        ? task.payload['reportedViewCount'] as int? ?? 0
        : 0,
  );

  static CompactionState _stateOf(PersonalTask task) =>
      CompactionState.fromJson(task.payload['compaction']);

  /// The profile that may summarize this task's conversation: the task's own,
  /// or the one the person set up for it if that exposes the data to no more
  /// than the conversation's profile does. null: none that is allowed, and
  /// nothing is sent.
  ModelProfile? _summaryProfile(ModelProfile conversation) {
    final configured = ctx.compactionProfile;
    if (configured == null) return conversation;
    return ctx.compactor.exposureAllowed(
          conversation: conversation,
          candidate: configured,
        )
        ? configured
        : null;
  }

  /// S0 (ADR-0005 §6.6). Compaction is a view over the stored messages and
  /// never changes them. Returns the task to build the next request from, or
  /// null when this call already ended it (`context_too_large`) or wrote the
  /// card that asks to send the summary request.
  Future<PersonalTask?> compactIfNeeded(
    PersonalTask task, {
    bool force = false,
  }) async {
    if (task.payload['profile'] == null) return task;
    final profile = ctx.profile(task);
    final caps = profile.capabilities;
    final threshold = ctx.compactor.compactAt(caps);
    if (threshold == null && !force) return task;
    final state = _stateOf(task);
    final messages = task.payload['messages'] as List;
    final before = _tokensUnder(task, state, useReport: true);
    if (!force && before <= threshold!) return task;
    final reported = task.payload['reportedPromptTokens'] != null;

    // A: clear old tool results, locally, if that frees enough to be worth
    // breaking the provider's prompt cache for (always, when asked for).
    var next = state;
    var strategy = '';
    final cleared = ctx.compactor.clearOldResults(
      messages,
      state,
      toolIdByWireName: _wireNames(task),
    );
    if (!identical(cleared, state)) {
      final freed = before - _tokensUnder(task, cleared);
      final window = caps.contextTokens;
      if (force ||
          (window != null && freed >= window * ctx.compactor.minFreedRatio)) {
        next = cleared;
        strategy = 'A';
      }
    }
    final afterA = _tokensUnder(task, next, useReport: identical(next, state));

    // B: one summary request, which needs the person's confirmation.
    if ((force || afterA > threshold!) && !next.summaryFailed) {
      final plan = ctx.compactor.planSummary(messages, next);
      if (plan != null) {
        final chosen = _summaryProfile(profile);
        if (chosen != null) {
          if (await _askSummary(
            task,
            next,
            plan,
            chosen,
            tokensBefore: before,
            tokenSource: reported ? 'reported' : 'estimated',
            strategyA: strategy == 'A',
          )) {
            return null;
          }
        } else {
          await ctx.event(task, AgentEventType.compactionFailed, {
            'reason': 'profile_not_allowed',
            'stage': 'B',
          });
        }
        next = next.copyWith(summaryFailed: true);
      }
    }
    // The last resort short of failing: keep one call whole and drop the
    // arguments of the older ones.
    if (!force && _tokensUnder(task, next) > threshold!) {
      final harder = ctx.compactor.clearOldResults(
        messages,
        next,
        keep: 1,
        clearArguments: true,
        toolIdByWireName: _wireNames(task),
      );
      if (!identical(harder, next)) {
        next = harder;
        strategy = 'A';
      }
    }
    return _settleCompaction(
      task,
      state,
      next,
      tokensBefore: before,
      tokenSource: reported ? 'reported' : 'estimated',
      strategy: strategy,
    );
  }

  /// Writes the compaction state of [next] and its event, and ends the task
  /// if the request still does not fit. Never sends anything.
  Future<PersonalTask?> _settleCompaction(
    PersonalTask task,
    CompactionState from,
    CompactionState next, {
    required int tokensBefore,
    required String tokenSource,
    required String strategy,
    String? summaryDigest,
  }) async {
    final changed =
        !identical(from, next) &&
        (jsonEncode(from.toJson()) != jsonEncode(next.toJson()));
    final threshold = ctx.compactor.compactAt(ctx.profile(task).capabilities);
    final hard = ctx.compactor.hardLimit(ctx.profile(task).capabilities);
    final after = _tokensUnder(task, next, useReport: !changed);
    var state = next;
    if (changed) {
      state = next.copyWith(
        overCount: ctx.compactor.overCountAfter(
          from,
          changed: true,
          tokens: after,
          threshold: threshold,
        ),
        history: [
          ...next.history,
          {
            'step': BudgetUsage.fromPayload(task.payload).steps,
            'strategy': strategy,
            'tokensBefore': tokensBefore,
            'tokensAfter': after,
            'tokenSource': tokenSource,
            'summaryDigest': ?summaryDigest,
            'previousSummaryDigest': ?from.summaryDigest,
          },
        ],
      );
    }
    final updated = changed
        ? task.copy({
            'compaction': state.toJson(),
            // The earlier report was for a different view.
            'reportedPromptTokens': null,
            'reportedViewCount': null,
          })
        : task;
    if (changed) {
      await ctx.event(updated, AgentEventType.compaction, {
        'strategy': strategy,
        'tokensBefore': tokensBefore,
        'tokensAfter': after,
        'tokenSource': tokenSource,
        'cleared': state.cleared.length,
        'replacedUpTo': state.summary?['upTo'],
        'summaryDigest': ?summaryDigest,
        'previousSummaryDigest': ?from.summaryDigest,
      });
    }
    if (ctx.compactor.tooLarge(
      tokens: after,
      hard: hard,
      overCount: state.overCount,
    )) {
      await ctx.fail(
        updated,
        '上下文超出模型窗口（context_too_large），请缩小范围或新建对话',
        code: 'context_too_large',
      );
      return null;
    }
    return updated;
  }

  /// The card for the summary request: it is a model request, so it has its
  /// own preview (the exact messages that would be sent), digest, gate
  /// decision and confirmation. Returns false when nothing was written (the
  /// gate did not ask the person, or the preview is too large) and the task
  /// goes on with clearing only.
  Future<bool> _askSummary(
    PersonalTask task,
    CompactionState withA,
    SummaryPlan plan,
    ModelProfile profile, {
    required int tokensBefore,
    required String tokenSource,
    required bool strategyA,
  }) async {
    final preview = {
      'endpoint': profile.endpoint.toString(),
      'profile': profile.toJsonWithoutCapabilities(),
      'scope': task.scope.toJson(),
      'purpose': 'context_compaction',
      'messages': plan.messages,
      'dataCategories': ['conversation', 'tool_results'],
      'summarizes': {'from': plan.from, 'to': plan.upTo},
    };
    if (utf8.encode(jsonEncode(preview)).length > 256 * 1024) {
      await ctx.event(task, AgentEventType.compactionFailed, {
        'reason': 'preview_too_large',
        'stage': 'B',
      });
      return false;
    }
    final requestDigest = AgentContext.digest(preview);
    final decision = await ctx.gate.decide(
      ModelRequestFacts(
        location: profile.location,
        endpoint: profile.endpoint.toString(),
        endpointIdentity: profile.endpointIdentity,
        scopeDigest: AgentContext.digest(task.scope.toJson()),
        requestDigest: requestDigest,
        dataCategories: const {'conversation', 'tool_results'},
        step: BudgetUsage.fromPayload(task.payload).steps,
      ),
    );
    if (decision is! GateConfirm) {
      await ctx.event(task, AgentEventType.compactionFailed, {
        'reason': 'not_allowed',
        'stage': 'B',
      });
      return false;
    }
    final card = task.copy({
      'compaction': withA.toJson(),
      'reportedPromptTokens': null,
      'reportedViewCount': null,
      'compactionPlan': {
        'upTo': plan.upTo,
        'from': plan.from,
        'tokensBefore': tokensBefore,
        'tokenSource': tokenSource,
        'strategyA': strategyA,
        'profileId': profile.id,
      },
      'state': 'waitingConfirmation',
      'stage': 'compaction',
      'waitingFor': '为节省上下文，需先把较早内容发给模型做摘要；确认发送以下内容',
      'preview': preview,
      'requestDigest': requestDigest,
      'expiresAt': ctx
          .clock()
          .toUtc()
          .add(const Duration(minutes: 5))
          .toIso8601String(),
      'approvalNonce': const Uuid().v4(),
    });
    if (!await ctx.repository.updateTask(card)) return true;
    await ctx.event(card, AgentEventType.wait, {
      'stage': 'compaction',
      'requestDigest': requestDigest,
    });
    return true;
  }

  /// After the person confirmed the summary card: the one summary request,
  /// sent exactly as previewed, with no tools. Whatever goes wrong, the task
  /// goes on with clearing only.
  Future<void> runCompaction(PersonalTask task) async {
    final token = ModelCancellation();
    ctx.modelTokens[task.id] = token;
    try {
      final preview = Map<String, Object?>.from(task.payload['preview'] as Map);
      final conversation = ctx.profile(task);
      final profile = _summaryProfile(conversation);
      if (profile == null ||
          profile.endpoint.toString() != preview['endpoint']) {
        await summaryFailed(task, 'profile_changed');
        return;
      }
      final plan = Map<String, Object?>.from(
        task.payload['compactionPlan'] as Map,
      );
      final request = ModelRequest(
        profile: profile,
        messages: [
          for (final m in preview['messages'] as List)
            ModelMessage.fromJson(m as Map),
        ],
        toolChoice: ToolChoice.none,
        maxOutputTokens: ctx.compactor.summaryTokens,
        caller: 'context_compaction',
        requestDigest: task.payload['requestDigest'] as String?,
      );
      final started = ctx.clock();
      final Reply reply;
      try {
        reply = await model.drain(task, request, token);
      } catch (_) {
        // Cancelled, closing or ended meanwhile: not a failure to recover
        // from. Anything else is.
        token.check();
        if (ctx.closing ||
            ctx.repository.task(task.id)?.state != PersonalTaskState.running) {
          return;
        }
        // What was spent still counts: the time, and the prompt that went.
        await summaryFailed(
          task.copy(
            BudgetUsage.fromPayload(task.payload)
                .plus(
                  active: ctx.clock().difference(started),
                  tokens: estimateTokens(jsonEncode(preview['messages'])),
                  estimated: true,
                )
                .toPayload(),
          ),
          'request_failed',
        );
        return;
      }
      if (ctx.closing ||
          ctx.repository.task(task.id)?.state != PersonalTaskState.running) {
        return;
      }
      final text = reply.text.toString();
      final state = _stateOf(task);
      final billed = task.copy(
        BudgetUsage.fromPayload(task.payload)
            .plus(
              active: ctx.clock().difference(started),
              tokens:
                  (reply.usage?.promptTokens ??
                      estimateTokens(jsonEncode(preview['messages']))) +
                  (reply.usage?.completionTokens ?? estimateTokens(text)),
              estimated:
                  reply.usage?.promptTokens == null ||
                  reply.usage?.completionTokens == null,
            )
            .toPayload(),
      );
      final summary =
          reply.error == null &&
              reply.calls.isEmpty &&
              reply.done?.reason == FinishReason.stop
          ? ctx.compactor.parseSummary(text)
          : null;
      if (summary == null) {
        await summaryFailed(billed, 'bad_reply');
        return;
      }
      // An endpoint that echoes the key must not leave it in the summary.
      final masked = {
        for (final e in summary.entries)
          e.key: await ctx.gateway.mask(profile, e.value),
      };
      final planned = SummaryPlan(
        messages: const [],
        upTo: plan['upTo'] as int,
        from: plan['from'] as int,
        previousDigest: state.summaryDigest,
      );
      final next = ctx.compactor.withSummary(
        state,
        planned,
        masked,
        task.payload['references'] as List? ?? const [],
      );
      final settled = await _settleCompaction(
        billed.copy({'stage': 'model', 'compactionPlan': null}),
        state,
        next,
        tokensBefore: plan['tokensBefore'] as int,
        tokenSource: plan['tokenSource'] as String,
        strategy: plan['strategyA'] == true ? 'A+B' : 'B',
        summaryDigest: next.summaryDigest,
      );
      if (settled != null) await model.advance(settled);
    } finally {
      ctx.modelTokens.remove(task.id);
    }
  }

  /// The summary could not be had (the request failed, was refused, came back
  /// in the wrong shape, or the person declined): record it, stop asking for
  /// one in this task, and carry on with clearing only.
  Future<void> summaryFailed(PersonalTask task, String reason) async {
    await ctx.event(task, AgentEventType.compactionFailed, {
      'reason': reason,
      'stage': 'B',
    });
    final state = _stateOf(task);
    final marked = state.copyWith(summaryFailed: true);
    await model.advance(
      task.copy({
        'stage': 'model',
        'compactionPlan': null,
        'compaction': marked.toJson(),
        'state': 'running',
        'waitingFor': null,
      }),
    );
  }

  /// Manual compaction (ADR-0005 §6.6-6): the same pipeline, forced. Allowed
  /// only while the next model request is waiting for confirmation, never
  /// while an approval for a tool call is pending: nothing of a pending
  /// approval or its preview is touched.
  Future<void> compactNow(String taskId) {
    if (ctx.closing || ctx.operations.containsKey(taskId)) {
      return Future.error(StateError('Task unavailable'));
    }
    final future = Future<void>(() async {
      final task = ctx.repository.task(taskId);
      if (task == null ||
          task.state != PersonalTaskState.waitingConfirmation ||
          task.stage != 'model') {
        throw StateError('compaction_unavailable');
      }
      final next = await compactIfNeeded(task, force: true);
      if (next != null) await model.waitForModel(next);
    });
    ctx.operations[taskId] = future;
    return future.whenComplete(() => ctx.operations.remove(taskId));
  }

  /// The person declines to send the summary request: clearing only.
  Future<void> declineCompaction(String taskId) {
    if (ctx.closing || ctx.operations.containsKey(taskId)) {
      return Future.error(StateError('Task unavailable'));
    }
    final future = Future<void>(() async {
      final task = ctx.repository.task(taskId);
      if (task == null ||
          task.state != PersonalTaskState.waitingConfirmation ||
          task.stage != 'compaction') {
        throw StateError('compaction_unavailable');
      }
      await summaryFailed(task, 'declined');
    });
    ctx.operations[taskId] = future;
    return future.whenComplete(() => ctx.operations.remove(taskId));
  }
}
