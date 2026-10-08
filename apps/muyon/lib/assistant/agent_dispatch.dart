import 'dart:async';
import 'dart:convert';

import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:uuid/uuid.dart';

import '../platform/foundation_repository.dart';
import '../platform/tool_registry.dart';
import '../platform/grants/host_authorization_facts.dart';
import '../platform/grants/outbound_content_reviewer.dart';
import '../services/models/credential_redaction.dart';
import 'agent_budget.dart';
import 'agent_context.dart';
import 'agent_event_sink.dart';
import 'agent_model_turn.dart';

/// Tool-call stage of a task (S4-S5): preparing the calls of a step, running
/// reads, the confirmation card, executing its writes and completing the step.
class AgentDispatch {
  AgentDispatch(this.ctx);
  final AgentContext ctx;
  late AgentModelTurn model;

  ToolCallRequest _requestOf(PersonalTask task, Map call) =>
      ctx.invocationRequests[call['invocationId']] ??
      ToolCallRequest(
        invocationId: call['invocationId'] as String,
        toolId: call['toolId'] as String,
        scope: task.scope,
        parameters: Map<String, Object?>.from(call['parameters'] as Map),
        destination: call['destination'] as String?,
      );

  // Keep full credential-bearing destination only in the live host binding.
  // A restart cannot reconstruct a missing query from a masked card.
  static String? _displayDestination(String? destination) {
    if (destination == null) return null;
    final uri = Uri.tryParse(destination);
    return uri == null
        ? '[invalid destination]'
        : Uri(
            scheme: uri.scheme,
            host: uri.host,
            port: uri.hasPort ? uri.port : null,
            path: uri.path,
          ).toString();
  }

  /// Fixed texts for a call that did not run; the model's own words are never
  /// used.
  static const _notRunText = {
    'not_approved': '用户未批准此调用',
    'not_run_prior_failed': '未执行：前一个操作失败',
    'not_run_cancelled': '未执行：已请求取消',
    'over_limit': '未执行：超出单步调用上限',
    'over_card_limit': '未执行：超出一张确认卡的调用上限',
    'not_run_resume': '未执行：任务在此之前中断，如仍需要请重新提出',
    'unknown_before_resume': '未执行：上一次尝试中该操作的结果未知，需先核实',
  };

  Map<String, Object?> _planned(
    int index,
    Planned p, {
    required String disposition,
    PreparedToolCall? prepared,
    String? note,
  }) => {
    'index': index,
    'callId': p.callId,
    'toolId': p.toolId,
    'parameters': p.parameters,
    'destination':
        prepared?.effectIntent?.displayDestination ??
        _displayDestination(p.destination),
    'disposition': disposition,
    if (prepared != null) ...{
      'invocationId': prepared.request.invocationId,
      'access': prepared.info.accessLevel.name,
      'effect': prepared.info.descriptor.effect.name,
      'identityDigest': prepared.identityDigest,
      'scope': prepared.resolvedScope.toJson(),
    },
    if (note != null) 'outcome': {'status': note},
  };

  /// What the person sees of one call on the card.
  static Map<String, Object?> _cardView(Map<String, Object?> call) => {
    'invocationId': call['invocationId'],
    'toolId': call['toolId'],
    'parameters': call['parameters'],
    'destination': call['destination'],
    'scope': call['scope'],
    'effect': call['effect'],
    'identityDigest': call['identityDigest'],
  };

  /// S4 (ADR-0005 §6.2, §6.3). Every call of the reply is prepared first: one
  /// that cannot be prepared ends the task before anything has run. Reads then
  /// run in parallel; writes and exports wait on one card (at most
  /// `maxCardCalls`), and each of them is prepared again, approved, invoked and
  /// receipted by itself.
  Future<void> dispatch(
    PersonalTask task,
    List<Planned> planned, {
    Map<String, Object?>? assistantMessage,
  }) async {
    final List<Map<String, Object?>> calls;
    try {
      final candidates = task.payload['candidateIds'] as List?;
      if (candidates == null ||
          planned.any((p) => !candidates.contains(p.toolId))) {
        throw StateError('Tool is outside frozen candidates');
      }
      calls = [];
      var cards = 0;
      for (var i = 0; i < planned.length; i++) {
        final p = planned[i];
        if (i >= ctx.budget.maxCallsPerStep) {
          calls.add(_planned(i, p, disposition: 'none', note: 'over_limit'));
          continue;
        }
        final request = ToolCallRequest(
          invocationId: const Uuid().v4(),
          toolId: p.toolId,
          scope: task.scope,
          parameters: p.parameters,
          destination: p.destination,
        );
        if (ctx.closing) throw StateError('Assistant is closing');
        ctx.invocationTasks[request.invocationId] = task.id;
        ctx.invocationRequests[request.invocationId] = request;
        final prepared = await ctx.tools.prepare(request);
        if (ctx.closing) throw StateError('Assistant is closing');
        final read = prepared.info.accessLevel == ToolAccessLevel.read;
        if (!read && cards >= ctx.budget.maxCardCalls) {
          calls.add(
            _planned(i, p, disposition: 'none', note: 'over_card_limit'),
          );
          continue;
        }
        if (!read) cards++;
        calls.add(
          _planned(
            i,
            p,
            disposition: read ? 'run' : 'card',
            prepared: prepared,
          ),
        );
      }
    } catch (_) {
      // Only the checks of the calls themselves are reported this way.
      await ctx.fail(task, '工具参数、可用性或范围校验未通过');
      return;
    }
    try {
      var next = task.copy({
        'stage': 'tool',
        'step': {'assistant': assistantMessage, 'calls': calls},
        // Set by [_complete] once the step's calls and results are in
        // `messages`: until then a resume has to settle the step itself.
        'stepFolded': false,
      });
      for (final c in calls) {
        if (c['disposition'] == 'none') continue;
        await ctx.event(next, AgentEventType.toolProposed, {
          'toolId': c['toolId'],
          'invocationId': c['invocationId'],
          'effect': c['effect'],
          'identityDigest': c['identityDigest'],
        });
      }
      final reads = [
        for (final c in calls)
          if (c['disposition'] == 'run') c,
      ];
      if (reads.isNotEmpty) {
        next = next.copy(_stage(reads, state: 'running'));
        if (!await ctx.repository.updateTask(next)) return;
        await _runReads(next);
      } else {
        await _openCard(next);
      }
    } catch (error) {
      // A later stage failed (a tool, the store, the next request): say so
      // with its cause, redacted, not as a check of the call.
      final cause = redactCredentials(error).replaceAll(RegExp(r'\s+'), ' ');
      await ctx.fail(
        task,
        '执行失败（${cause.length > 160 ? '${cause.substring(0, 160)}…' : cause}）；'
        '请检查端点、模型名称、工具权限或资料范围后新建尝试',
      );
    }
  }

  /// The payload keys that describe the calls the task is on: `toolCall` (the
  /// one waiting or running now, the first on a card), its `toolIdentityDigest`,
  /// `toolCalls` (all [shown]) and, for a task that waits, `toolSelection`.
  /// The digest of one call is its `identityDigest`; of several, the digest of
  /// the list of them in order. A single call has the keys it always had.
  Map<String, Object?> _stage(
    List<Map<String, Object?>> shown, {
    required String state,
  }) {
    final single = shown.length == 1;
    final identity = single
        ? shown.single['identityDigest'] as String
        : AgentContext.digest({
            'calls': [for (final c in shown) c['identityDigest']],
          });
    final first = shown.first;
    return {
      'state': state,
      'toolCall': {
        'invocationId': first['invocationId'],
        'toolId': first['toolId'],
        'parameters': first['parameters'],
        'destination': first['destination'],
        'callId': ?first['callId'],
      },
      'toolIdentityDigest': first['identityDigest'],
      'toolCalls': [for (final c in shown) _cardView(c)],
      if (state == 'waitingConfirmation')
        'toolSelection': [for (final c in shown) c['invocationId']],
      'requestDigest': identity,
      'preview': single
          ? {
              'toolId': first['toolId'],
              'parameters': first['parameters'],
              'destination': first['destination'],
              'scope': first['scope'],
              'effect': first['effect'],
            }
          : {
              'order': '按顺序执行；某项失败则其后各项不再执行',
              'calls': [for (final c in shown) _cardView(c)],
            },
      'waitingFor': state == 'waitingConfirmation' ? '确认工具操作' : null,
      'expiresAt': ctx
          .clock()
          .toUtc()
          .add(const Duration(minutes: 5))
          .toIso8601String(),
      'approvalNonce': const Uuid().v4(),
    };
  }

  /// The confirmation card for the writes / exports of the step. Which of
  /// them the person selects is not part of its digest.
  bool _cardAllowed(PersonalTask task) =>
      !ctx.closing &&
      !ctx.cancelRequested.contains(task.id) &&
      ctx.toolTokens[task.id]?.isCancelled != true &&
      ctx.repository.task(task.id)?.terminal == false;

  Future<bool> _stopBeforeCard(PersonalTask task) async {
    final current = ctx.repository.task(task.id);
    if (ctx.closing || current == null || current.terminal) return true;
    if (ctx.cancelRequested.contains(task.id) ||
        ctx.toolTokens[task.id]?.isCancelled == true) {
      await ctx.settle(task, PersonalTaskState.cancelled, null);
      return true;
    }
    return false;
  }

  Future<void> _openCard(PersonalTask task) async {
    if (await _stopBeforeCard(task)) return;
    final card = AgentContext.cardCalls(task);
    if (card.isEmpty) {
      await _complete(task);
      return;
    }
    final authorization = ctx.toolAuthorization;
    if (authorization != null) {
      try {
        // Persist the entire pending external union before reviewing any call.
        for (final call in card) {
          await _markExternal(task, _requestOf(task, call));
          if (await _stopBeforeCard(task)) return;
        }
        for (final call in card) {
          final request = _requestOf(task, call);
          ctx.invocationTasks[request.invocationId] = task.id;
          final prepared = await ctx.tools.prepare(request);
          if (prepared.identityDigest != call['identityDigest']) {
            throw StateError('stale_scope');
          }
          if (prepared.effectIntent == null) continue;
          final reviewed = await authorization.review(prepared);
          if (await _stopBeforeCard(task)) return;
          if (reviewed.action == ReviewAction.block) {
            await ctx.fail(task, '本地内容审查阻止了该操作', code: 'review_block');
            return;
          }
          ctx.toolReviews[request.invocationId] = reviewed;
        }
      } catch (_) {
        if (await _stopBeforeCard(task)) return;
        await ctx.fail(task, '操作来源或审查记录已变化，该操作未执行', code: 'review_stale');
        return;
      }
    }
    final next = task.copy(_stage(card, state: 'waitingConfirmation'));
    if (await _stopBeforeCard(task)) return;
    final saved = await ctx.commit(
      next,
      canCommit: () => _cardAllowed(task),
      events: [
        (
          AgentEventType.wait,
          {
            'stage': 'tool',
            'requestDigest': next.payload['requestDigest'],
            'calls': card.length,
          },
        ),
      ],
    );
    if (!saved) await _stopBeforeCard(task);
  }

  /// What a card selection looks like after the person toggles [id]: turning
  /// a call off turns off every later one too (a later write may depend on
  /// it); turning one on adds just that call back. Order is the card's.
  static List<String> toggleSelection(
    List<String> cardOrder,
    List<String> selected,
    String id,
  ) {
    final at = cardOrder.indexOf(id);
    if (at < 0) throw ArgumentError('unknown_invocation');
    final on = selected.toSet();
    if (on.contains(id)) {
      on.removeAll(cardOrder.skip(at));
    } else {
      on.add(id);
    }
    return [
      for (final c in cardOrder)
        if (on.contains(c)) c,
    ];
  }

  /// Calls of the step in the order the model gave them, with [outcome] set
  /// for the one at [index].
  PersonalTask _record(
    PersonalTask task,
    int index,
    String status, {
    ToolCallResult? result,
  }) {
    final step = Map<String, Object?>.from(task.payload['step'] as Map);
    step['calls'] = [
      for (final c in AgentContext.calls(task))
        if (c['index'] == index)
          {
            ...c,
            'outcome': {
              'status': status,
              if (result != null) 'result': result.toJson(),
            },
          }
        else
          c,
    ];
    return task.copy({'step': step});
  }

  /// The outcomes just recorded on [task] and their `tool_result` events in
  /// one transaction, so a receipt the task has taken is never missing from
  /// its timeline or the other way round. If the task is no longer running
  /// the events are still kept: the receipts exist.
  Future<void> _recordResults(
    PersonalTask task,
    List<(String, Map<String, Object?>)> events,
  ) async {
    if (await ctx.commit(
      task,
      events: events,
      expected: {PersonalTaskState.running},
      keepStage: true,
    )) {
      return;
    }
    for (final e in events) {
      await ctx.event(task, e.$1, e.$2);
    }
  }

  PersonalTask _chargeActive(PersonalTask task, Duration spent) => task.copy(
    BudgetUsage.fromPayload(task.payload).plus(active: spent).toPayload(),
  );

  /// Invokes one prepared call and reads off what the registry says; nothing
  /// is settled here. [abandoned]: the task ended or the host is closing.
  /// [cancelled]: stopped before dispatch, so nothing ran.
  final _premarked = <String>{};
  bool _external(ToolCallRequest request) {
    final info = ctx.tools.inspect(request.toolId);
    return info != null &&
        (info.accessLevel == ToolAccessLevel.external ||
            info.providerId.startsWith('mcp:') ||
            info.descriptor.moduleId == 'inquiry' ||
            info.descriptor.moduleId == 'knowledge' ||
            info.descriptor.moduleId == 'research');
  }

  Future<void> _markExternal(PersonalTask task, ToolCallRequest request) async {
    if (!_external(request) || _premarked.contains(request.invocationId)) {
      return;
    }
    final info = ctx.tools.inspect(request.toolId)!;
    await ctx.repository.authorizationFacts.markExternal(
      task.id,
      HostSourceFact.object(
        ObjectRef(
          moduleId: info.descriptor.moduleId,
          objectType: 'tool_invocation',
          objectId: request.invocationId,
        ),
      ),
    );
    _premarked.add(request.invocationId);
  }

  Future<Run> _invokeOne(
    PersonalTask task,
    ToolCallRequest request,
    ToolCancellationToken token,
  ) async {
    if (ctx.closing ||
        ctx.repository.task(task.id)?.state != PersonalTaskState.running) {
      return const Run.abandoned();
    }
    try {
      final external = _external(request);
      if (external) {
        await _markExternal(task, request);
        token.throwIfCancelled();
        if (ctx.closing ||
            ctx.repository.task(task.id)?.state != PersonalTaskState.running) {
          return const Run.abandoned();
        }
      }
      final result = await ctx.tools.invoke(request, cancellation: token);
      if (external) {
        // Persist stable returned sources before content acceptance. The
        // premarker remains durable on failure after the real invocation.
        for (final ref in result.objectRefs) {
          await ctx.repository.authorizationFacts.markExternal(
            task.id,
            HostSourceFact.object(ref),
          );
        }
      }
      return Run.ran(result);
    } on ToolCancelled {
      return const Run.cancelled();
    } catch (_) {
      // Refusal, receipt/persistence failure, or failed content acceptance.
      // A real registry receipt remains authoritative after dispatch.
      if (ctx.cancelRequested.contains(task.id)) return const Run.cancelled();
      rethrow;
    }
  }

  /// Reads of a step, in parallel. A cancel request discards their results
  /// (a read has no external effect); otherwise the first call that did not
  /// succeed decides how the task ends, as a single call always did.
  Future<void> _runReads(PersonalTask task) async {
    final token = ToolCancellationToken();
    ctx.toolTokens[task.id] = token;
    try {
      if (ctx.closing ||
          ctx.repository.task(task.id)?.state != PersonalTaskState.running) {
        return;
      }
      ctx.toolActive.add(task.id);
      final reads = [
        for (final c in AgentContext.calls(task))
          if (c['disposition'] == 'run') c,
      ];
      final started = ctx.clock();
      final runs = await Future.wait([
        for (final c in reads) _invokeOne(task, _requestOf(task, c), token),
      ]);
      final spent = ctx.clock().difference(started);
      final cancelRequested =
          ctx.cancelRequested.remove(task.id) || token.isCancelled;
      if (runs.any((r) => r.kind == RunKind.cancelled)) {
        await ctx.settle(task, PersonalTaskState.cancelled, null);
        return;
      }
      if (ctx.closing ||
          runs.any((r) => r.kind == RunKind.abandoned) ||
          ctx.repository.task(task.id)?.state != PersonalTaskState.running) {
        return;
      }
      if (cancelRequested) {
        await ctx.settle(task, PersonalTaskState.cancelled, null);
        return;
      }
      var current = _chargeActive(task, spent);
      final recorded = <(String, Map<String, Object?>)>[];
      for (var i = 0; i < reads.length; i++) {
        final result = runs[i].result!;
        current = _record(
          current,
          reads[i]['index'] as int,
          result.status.name,
          result: result,
        );
        recorded.add((
          AgentEventType.toolResult,
          {
            'toolId': reads[i]['toolId'],
            'invocationId': reads[i]['invocationId'],
            'status': result.status.name,
          },
        ));
      }
      await _recordResults(current, recorded);
      for (final run in runs) {
        final result = run.result!;
        if (result.status == ToolCallStatus.cancelled) {
          await ctx.settle(current, PersonalTaskState.cancelled, null);
          return;
        }
        if (result.status == ToolCallStatus.interrupted) {
          await ctx.settle(
            current,
            PersonalTaskState.interrupted,
            '操作结果未知，重试前请先核实。${result.summary}',
          );
          return;
        }
      }
      // A read that failed ends the task before any card is shown.
      final failed = runs.any(
        (r) => r.result!.status != ToolCallStatus.succeeded,
      );
      if (failed) {
        await _complete(current);
      } else {
        await _openCard(current);
      }
    } finally {
      // Held until the outcome is written: a cancel in between must only
      // signal, never take the "not started" path and write `cancelled`.
      ctx.toolActive.remove(task.id);
      ctx.cancelRequested.remove(task.id);
      ctx.toolTokens.remove(task.id);
    }
  }

  /// After the person confirmed the card: the selected writes / exports, one
  /// at a time in the model's order. Each is prepared again, its
  /// `identityDigest` compared with the card's, approved (one use) and
  /// invoked, and has its own receipt. A call that does not succeed stops the
  /// rest; so does a change of scope (`stale_scope`).
  Future<void> executeCard(PersonalTask task, Set<String> selected) async {
    final token = ToolCancellationToken();
    ctx.toolTokens[task.id] = token;
    ctx.toolActive.add(task.id);
    try {
      var current = task.copy({
        'toolSelection': [
          for (final c in AgentContext.cardCalls(task))
            if (selected.contains(c['invocationId'])) c['invocationId'],
        ],
      });
      var stopped = false, cancelled = false;
      var ran = 0;
      for (final c in AgentContext.cardCalls(task)) {
        final id = c['invocationId'] as String;
        final index = c['index'] as int;
        if (ctx.closing ||
            ctx.repository.task(task.id)?.state != PersonalTaskState.running) {
          return;
        }
        if (stopped) {
          current = _record(current, index, 'not_run_prior_failed');
          continue;
        }
        if (!selected.contains(id)) {
          current = _record(current, index, 'not_approved');
          continue;
        }
        if (token.isCancelled || ctx.cancelRequested.contains(task.id)) {
          cancelled = stopped = true;
          current = _record(current, index, 'not_run_cancelled');
          continue;
        }
        // The task is on this call now.
        current = current.copy({
          'stage': ctx.repository.task(task.id)!.stage,
          'toolCall': (_stage([c], state: 'running'))['toolCall'],
          'toolIdentityDigest': c['identityDigest'],
        });
        if (!await ctx.repository.updateTask(
          current,
          expected: {PersonalTaskState.running},
        )) {
          return;
        }
        final request = _requestOf(task, c);
        ToolCallResult failed(String reason) =>
            ToolCallResult(status: ToolCallStatus.failed, summary: reason);
        ToolCallResult? stale;
        PreparedToolCall? prepared;
        try {
          prepared = await ctx.tools.prepare(request);
          // The scope may have moved under an earlier write of this card.
          if (prepared.identityDigest != c['identityDigest']) {
            stale = failed('stale_scope: 资料范围已变化，该操作未执行');
          }
        } catch (error) {
          stale = failed(
            '${error is ToolPlatformException ? error.code : 'prepare_failed'}: 该操作未执行',
          );
        }
        String? approval;
        if (stale == null) {
          try {
            // One approval for this one call, used up by its invoke.
            final authorization = ctx.toolAuthorization;
            if (authorization != null && prepared!.effectIntent != null) {
              ctx.invocationTasks[request.invocationId] = task.id;
              final reviewed =
                  ctx.toolReviews[id] ?? await authorization.review(prepared);
              approval = await authorization.confirm(reviewed);
              if (approval == null) throw StateError('review_block');
            } else {
              approval = await ctx.tools.approve(prepared!);
            }
            await ctx.event(current, AgentEventType.approval, {
              'toolId': c['toolId'],
              'invocationId': id,
              'identityDigest': c['identityDigest'],
            });
          } catch (error) {
            stale = failed(
              '${error is ToolPlatformException ? error.code : 'approve_failed'}: 该操作未执行',
            );
          }
        }
        if (stale != null) {
          stopped = true;
          current = _record(current, index, 'failed', result: stale);
          await _recordResults(current, [
            (
              AgentEventType.toolResult,
              {
                'toolId': c['toolId'],
                'invocationId': id,
                'status': 'failed',
                'executed': false,
              },
            ),
          ]);
          continue;
        }
        final started = ctx.clock();
        final run = await _invokeOne(
          task,
          request.withApproval(approval!),
          token,
        );
        if (run.kind == RunKind.abandoned) return;
        if (run.kind == RunKind.cancelled) {
          await ctx.settle(
            current,
            PersonalTaskState.cancelled,
            ran == 0 ? null : '已取消；此前已执行 $ran 个操作，见回执',
          );
          return;
        }
        ran++;
        final result = run.result!;
        final cancelRequested =
            ctx.cancelRequested.contains(task.id) || token.isCancelled;
        current = _chargeActive(current, ctx.clock().difference(started));
        if (ctx.closing ||
            ctx.repository.task(task.id)?.state != PersonalTaskState.running) {
          return;
        }
        current = _record(current, index, result.status.name, result: result);
        await _recordResults(current, [
          (
            AgentEventType.toolResult,
            {
              'toolId': c['toolId'],
              'invocationId': id,
              'status': result.status.name,
            },
          ),
        ]);
        if (result.status == ToolCallStatus.cancelled) {
          await ctx.settle(
            current,
            PersonalTaskState.cancelled,
            ran == 1 ? null : '已取消；此前已执行 ${ran - 1} 个操作，见回执',
          );
          return;
        }
        if (result.status == ToolCallStatus.interrupted) {
          // The effect may have happened; the receipt is the truth, not
          // "cancelled". The calls after it do not start.
          await ctx.settle(
            current,
            PersonalTaskState.interrupted,
            cancelRequested
                ? '已请求取消，但操作可能已生效，重试前请先核实。${result.summary}'
                : '操作结果未知，重试前请先核实。${result.summary}',
          );
          return;
        }
        if (result.status != ToolCallStatus.succeeded) stopped = true;
        if (cancelRequested) cancelled = stopped = true;
      }
      if (cancelled && ran == 0) {
        await ctx.settle(current, PersonalTaskState.cancelled, null);
        return;
      }
      await _complete(current, lateCancel: cancelled);
    } finally {
      ctx.toolActive.remove(task.id);
      ctx.cancelRequested.remove(task.id);
      ctx.toolTokens.remove(task.id);
    }
  }

  /// S5 (ADR-0005 §6.2): every call of the step has an outcome. A failure
  /// ends the task as a failed call always did. Otherwise the model's calls
  /// and exactly one result for each `callId` (a real result, or a fixed text
  /// for a call that did not run) go into the conversation together, and the
  /// next step starts.
  /// A resumed attempt settling the step it took over from receipts.
  Future<void> completeStep(PersonalTask task) => _complete(task);

  Future<void> _complete(PersonalTask task, {bool lateCancel = false}) async {
    final calls = AgentContext.calls(task);
    final log = [...task.payload['toolLog'] as List? ?? const []];
    var refs = ctx.references(task);
    final results = <ToolCallResult>[];
    final added = <Map<String, Object?>>[];
    for (final c in calls) {
      final outcome = c['outcome'] as Map?;
      final result = outcome?['result'] == null
          ? null
          : ToolCallResult.fromJson(
              Map<String, Object?>.from(outcome!['result'] as Map),
            );
      if (result != null) {
        log.add(_logEntry(c['toolId'] as String, result));
        if (result.status == ToolCallStatus.succeeded) {
          results.add(result);
          refs = <ObjectRef>{...refs, ...result.objectRefs}.toList();
        }
      }
      final String content;
      if (result != null && result.status == ToolCallStatus.succeeded) {
        content = jsonEncode({
          'trustedToolResult': result.toJson(),
          'citations': [
            for (var i = 0; i < refs.length; i++)
              {'citationId': 'r${i + 1}', 'reference': refs[i].toJson()},
          ],
        });
      } else {
        content = jsonEncode({
          'notExecuted': _notRunText[outcome?['status']] ?? '未执行',
        });
      }
      if ((task.payload['step'] as Map)['assistant'] == null) {
        added.add({'role': 'user', 'content': content});
      } else {
        added.add({
          'role': 'tool',
          'tool_call_id': c['callId'],
          'content': content,
        });
      }
    }
    final failure = [
      for (final c in calls)
        if ((c['outcome'] as Map?)?['result'] != null &&
            ToolCallResult.fromJson(
                  Map<String, Object?>.from(
                    (c['outcome'] as Map)['result'] as Map,
                  ),
                ).status !=
                ToolCallStatus.succeeded)
          ToolCallResult.fromJson(
            Map<String, Object?>.from((c['outcome'] as Map)['result'] as Map),
          ),
    ];
    final logged = task.copy({'toolLog': log});
    if (failure.isNotEmpty) {
      await ctx.fail(logged, failure.first.summary);
      return;
    }
    final assistant = (task.payload['step'] as Map)['assistant'];
    final late = lateCancel ? '（取消请求晚于完成）' : '';
    final updated = logged.copy({
      'stepFolded': true,
      'references': refs.map((r) => r.toJson()).toList(),
      'summary': '${results.map((r) => r.summary).join('；')}$late',
      'messages': [
        ...task.payload['messages'] as List,
        if (assistant is Map) assistant,
        ...added,
      ],
    });
    if (task.profileId == null || lateCancel) {
      // A cancel request that arrived after the tool finished must not
      // discard its real result, and it ends the task here: no further
      // model request after the person cancelled. The state guard still
      // lets only one of cancel and completion land.
      await ctx.finish(
        updated,
        results
            .map((r) => '${r.summary}$late\n${jsonEncode(r.data)}')
            .join('\n\n'),
        refs,
      );
    } else {
      await model.advance(updated);
    }
  }

  /// What the budget summary says about one finished call.
  static Map<String, Object?> _logEntry(String toolId, ToolCallResult result) =>
      {
        'toolId': toolId,
        'status': result.status.name,
        'summary': result.summary.length > 120
            ? '${result.summary.substring(0, 120)}…'
            : result.summary,
      };
}
