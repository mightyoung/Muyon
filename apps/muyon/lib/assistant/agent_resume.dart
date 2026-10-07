import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../platform/foundation_repository.dart';
import '../platform/task_records.dart';
import 'agent_budget.dart';
import 'agent_context.dart';
import 'agent_dispatch.dart';
import 'agent_event_sink.dart';
import 'agent_model_turn.dart';
import 'agent_task_factory.dart';

/// Resuming a paused / interrupted / failed task from where it stopped
/// (ADR-0005 §6.5, §8.3, R10; K-4).
///
/// A resume is still a new attempt (new task id, `previousAttemptId`), but it
/// no longer starts the conversation over: it takes over what the earlier
/// attempt got to, judged from its payload, its event timeline and, above all,
/// the tool registry's receipts.
///
/// - A call with a successful receipt is never run again; its recorded result
///   is used as it is.
/// - A write / export whose receipt says the effect may have happened (the
///   call never finished, or ended `interrupted`), or that is otherwise
///   undecidable, is never replayed: the new attempt stops at
///   `waitingConfirmation` (stage [stage]) and says why. Confirming it only
///   acknowledges that the person looked; whatever is still to be done comes
///   as ordinary requests with their own confirmations and one-time approvals.
/// - Nothing here issues an approval or invokes a tool. Anything not covered
///   by a receipt goes back to the model, whose calls need their cards again.
class AgentResume {
  AgentResume(this.ctx);
  final AgentContext ctx;
  late AgentModelTurn model;
  late AgentDispatch dispatch;
  late AgentTaskFactory factory;

  /// Stage of an attempt that stopped because it could not tell what the
  /// earlier one did.
  static const stage = 'resume';

  /// Codes of the `resume` event.
  static const reused = 'reused', carried = 'carried', held = 'held';

  /// Takes over [prev], or returns null when there is nothing to take over
  /// (no tool call has happened): the caller then starts afresh as before.
  Future<PersonalTask?> attempt(PersonalTask prev) async {
    if (ctx.closing) throw StateError('Assistant is closing');
    final manual = prev.profileId == null;
    if (manual) {
      return prev.payload['toolCall'] is Map ? _manual(prev) : null;
    }
    return _model(prev);
  }

  // --- manual tool task -------------------------------------------------

  Future<PersonalTask?> _manual(PersonalTask prev) async {
    final call = Map<String, Object?>.from(prev.payload['toolCall'] as Map);
    final id = call['invocationId'] as String?;
    final receipt = id == null ? null : ctx.tools.receiptFor(id);
    final toolId = call['toolId'] as String;
    final mismatch = receipt != null && receipt.toolId != toolId;
    if (!mismatch &&
        (receipt == null || (!receipt.succeeded && !receipt.unknown))) {
      // Nothing ran, or it failed without any effect: ask again as before.
      return null;
    }
    final task = factory.toolTask(
      conversationId: prev.conversationId,
      toolId: toolId,
      previousAttemptId: prev.id,
    );
    await ctx.repository.appendMessage(
      prev.conversationId,
      'user',
      '运行工具 $toolId：${jsonEncode(call['parameters'] ?? const {})}',
    );
    final withCall = task.copy({
      'toolCall': {
        'toolId': toolId,
        'parameters': call['parameters'],
        'destination': call['destination'],
      },
    });
    if (!mismatch && receipt.succeeded) {
      final result = receipt.result!;
      final taken = withCall.copy({
        'step': {
          'assistant': null,
          'calls': [
            {
              'index': 0,
              'toolId': toolId,
              'invocationId': id,
              'disposition': 'run',
              'outcome': {'status': 'succeeded', 'result': result.toJson()},
            },
          ],
        },
        'stepFolded': true,
      });
      await ctx.repository.createTask(
        taken.withEvents([
          _resumeEvent(prev, reused, adopted: 1),
          TaskEventDraft(
            AgentEventType.toolResult,
            step: 0,
            data: {
              'toolId': toolId,
              'invocationId': id,
              'status': result.status.name,
              'reused': true,
            },
          ),
        ]),
      );
      await ctx.finish(
        taken,
        '${result.summary}\n${jsonEncode(result.data)}',
        result.objectRefs,
      );
      return ctx.repository.task(taken.id)!;
    }
    await ctx.repository.createTask(withCall);
    await _hold(
      withCall,
      prev,
      calls: [
        {'toolId': toolId, 'invocationId': id, 'receipt': 'unknown'},
      ],
      unknownTools: [toolId],
      adopted: 0,
      unknown: 1,
    );
    return ctx.repository.task(withCall.id)!;
  }

  // --- model task ---------------------------------------------------------

  /// Whether the last step's calls are not yet in `messages`.
  static bool _inflight(PersonalTask prev) {
    final step = prev.payload['step'];
    if (step is! Map || (step['calls'] as List? ?? const []).isEmpty) {
      return false;
    }
    final folded = prev.payload['stepFolded'];
    if (folded != null) return folded != true;
    // Before the flag existed: unfinished if a call has no outcome.
    return AgentContext.calls(prev).any((c) => c['outcome'] == null);
  }

  Future<PersonalTask?> _model(PersonalTask prev) async {
    final progressed =
        (prev.payload['toolLog'] as List? ?? const []).isNotEmpty ||
        prev.payload['stepFolded'] == true;
    final List<Map<String, Object?>> calls = _inflight(prev)
        ? AgentContext.calls(prev)
        : const [];
    var adopted = 0, pending = 0, unknown = 0;
    final settled = <Map<String, Object?>>[];
    final view = <Map<String, Object?>>[];
    final unknownTools = <String>[];
    final known = <String>{};
    for (final c in calls) {
      final id = c['invocationId'] as String?;
      if (id != null) known.add(id);
      final receipt = id == null ? null : ctx.tools.receiptFor(id);
      final read = c['access'] == 'read';
      if (id == null) {
        // Never prepared (over a limit): its outcome is already fixed.
        settled.add(c);
      } else if (receipt != null && receipt.toolId != c['toolId']) {
        // The id belongs to another tool: nothing can be taken from it.
        unknown++;
        unknownTools.add(c['toolId'] as String);
        settled.add({
          ...c,
          'outcome': {'status': 'unknown_before_resume'},
        });
        view.add({
          'toolId': c['toolId'],
          'invocationId': id,
          'receipt': 'unknown',
        });
      } else if (receipt != null && receipt.succeeded) {
        adopted++;
        settled.add({
          ...c,
          'outcome': {
            'status': 'succeeded',
            'result': receipt.result!.toJson(),
          },
        });
        view.add({
          'toolId': c['toolId'],
          'invocationId': id,
          'receipt': 'taken',
        });
      } else if (receipt != null && receipt.unknown && !read) {
        unknown++;
        unknownTools.add(c['toolId'] as String);
        settled.add({
          ...c,
          'outcome': {'status': 'unknown_before_resume'},
        });
        view.add({
          'toolId': c['toolId'],
          'invocationId': id,
          'receipt': 'unknown',
        });
      } else {
        // No receipt, a failure that had no effect, or an unfinished read.
        pending++;
        settled.add({
          ...c,
          'outcome': {'status': 'not_run_resume'},
        });
        view.add({
          'toolId': c['toolId'],
          'invocationId': id,
          'receipt': 'none',
        });
      }
    }
    // Receipts for calls the timeline proposed for this step but the payload
    // does not know cannot be taken over: undecidable, so a stop.
    for (final id
        in prev.payload['stepFolded'] == true
            ? const <String>[]
            : _orphans(prev, known)) {
      unknown++;
      view.add({'invocationId': id, 'receipt': 'unknown'});
    }
    final tookNothing = adopted == 0 && unknown == 0;
    if (tookNothing && !progressed) return null;

    final base = _carry(prev);
    final task = tookNothing || calls.isEmpty
        ? base
        : base.copy({
            'step': {
              ...Map<String, Object?>.from(prev.payload['step'] as Map),
              'calls': settled,
            },
          });
    if (unknown > 0) {
      await ctx.repository.createTask(task);
      await _hold(
        task,
        prev,
        calls: view,
        unknownTools: unknownTools,
        adopted: adopted,
        unknown: unknown,
      );
      return ctx.repository.task(task.id)!;
    }
    await ctx.repository.createTask(
      task.withEvents([
        _resumeEvent(prev, carried, adopted: adopted, pending: pending),
      ]),
    );
    if (!tookNothing && calls.isNotEmpty) {
      await dispatch.completeStep(task);
    } else {
      await model.advance(task);
    }
    return ctx.repository.task(task.id)!;
  }

  /// The new attempt: the earlier one's conversation so far (completed steps
  /// with their results) under a freshly built system message, nothing of its
  /// budget usage, confirmations or card.
  PersonalTask _carry(PersonalTask prev) {
    final (base, _) = factory.chatTask(
      conversationId: prev.conversationId,
      prompt: prev.prompt,
      profile: ctx.profile(prev),
      previousAttemptId: prev.id,
    );
    final messages = prev.payload['messages'] as List;
    return base.copy({
      'messages': [
        (base.payload['messages'] as List).first,
        ...messages.skip(1),
      ],
      // What the earlier attempt used still counts: repeated resumes cannot
      // get past the step, time and token limits.
      ...BudgetUsage.fromPayload(prev.payload).toPayload(),
      'references': prev.payload['references'] ?? const <Object?>[],
      'toolLog': prev.payload['toolLog'] ?? const <Object?>[],
      'compaction': ?prev.payload['compaction'],
    });
  }

  /// Invocation ids the timeline proposed for the step in progress (after the
  /// last model response) that have a receipt and are not among [known].
  List<String> _orphans(PersonalTask prev, Set<String> known) {
    final events = ctx.repository.taskEvents(prev.id);
    final lastResponse = events.lastIndexWhere(
      (e) => e.type == AgentEventType.modelResponse,
    );
    return [
      for (final e in events.skip(lastResponse + 1))
        if (e.type == AgentEventType.toolProposed &&
            e.data['invocationId'] is String &&
            !known.contains(e.data['invocationId']) &&
            ctx.tools.receiptFor(e.data['invocationId'] as String) != null)
          e.data['invocationId'] as String,
    ];
  }

  // --- the stop -------------------------------------------------------------

  TaskEventDraft _resumeEvent(
    PersonalTask prev,
    String outcome, {
    int adopted = 0,
    int pending = 0,
    int unknown = 0,
  }) => TaskEventDraft(
    AgentEventType.resume,
    step: 0,
    data: {
      'previousAttemptId': prev.id,
      'outcome': outcome,
      'adopted': adopted,
      'pending': pending,
      'unknown': unknown,
    },
  );

  /// Parks [task] (stored, queued) at `waitingConfirmation` with the reason.
  Future<void> _hold(
    PersonalTask task,
    PersonalTask prev, {
    required List<Map<String, Object?>> calls,
    required List<String> unknownTools,
    required int adopted,
    required int unknown,
  }) async {
    final reason =
        '上一次尝试中「${unknownTools.isEmpty ? '某个操作' : unknownTools.toSet().join('、')}」'
        '可能已经执行，但结果未知。为避免重复写入，已停止在此；'
        '请先核实实际结果。确认只表示您已核实，之后的操作仍会作为新的请求逐项确认。';
    final preview = {
      'resume': {
        'reason': reason,
        'previousAttemptId': prev.id,
        'calls': calls,
      },
    };
    final digest = AgentContext.digest(preview);
    final card = task.copy({
      'state': 'waitingConfirmation',
      'stage': stage,
      'waitingFor': reason,
      'preview': preview,
      'requestDigest': digest,
      'expiresAt': ctx
          .clock()
          .toUtc()
          .add(const Duration(minutes: 5))
          .toIso8601String(),
      'approvalNonce': const Uuid().v4(),
    });
    await ctx.commit(
      card,
      events: [
        (
          AgentEventType.resume,
          {
            'previousAttemptId': prev.id,
            'outcome': held,
            'adopted': adopted,
            'pending': 0,
            'unknown': unknown,
          },
        ),
        (AgentEventType.wait, {'stage': stage, 'requestDigest': digest}),
      ],
    );
  }

  /// The person confirmed the stop (the task is `running` again). Nothing is
  /// executed: a manual tool run is asked for again on a new card; a model
  /// task settles the step from what is known and goes back to the model.
  Future<void> continueHeld(PersonalTask task) async {
    if (task.profileId == null) {
      final call = task.payload['toolCall'] as Map;
      await dispatch.dispatch(task, [
        Planned(
          call['toolId'] as String,
          Map<String, Object?>.from(call['parameters'] as Map),
          destination: call['destination'] as String?,
        ),
      ]);
    } else if (task.payload['step'] is Map) {
      await dispatch.completeStep(task);
    } else {
      await model.advance(task);
    }
  }
}
