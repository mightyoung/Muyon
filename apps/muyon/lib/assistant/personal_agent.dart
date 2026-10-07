import 'dart:async';
import 'dart:convert';

import 'package:muyon_module_api/muyon_module_api.dart';

import '../platform/foundation_repository.dart';
import '../services/models/credential_redaction.dart';
import '../services/models/model_gateway.dart';
import '../services/models/model_provider.dart';
import '../services/models/openai_compat_provider.dart';
import '../platform/tool_registry.dart';
import 'agent_budget.dart';
import 'agent_event_sink.dart';
import 'context_compactor.dart';
import 'model_request_gate.dart';
import 'tool_selection.dart';
import 'agent_compaction_flow.dart';
import 'agent_context.dart';
import 'agent_dispatch.dart';
import 'agent_model_turn.dart';
import 'agent_task_factory.dart';

/// Host lifetime service. Views only create requests and approve displayed
/// snapshots; disposing a view never disposes or cancels its executor.
///
/// A facade: the stages live in collaborators that share one [AgentContext]
/// ([AgentTaskFactory], [AgentDispatch], [AgentModelTurn],
/// [AgentCompactionFlow]); this class keeps the public API, the entry points
/// and the task state table (confirm, cancel, pause, resume, close).
class PersonalAgent {
  PersonalAgent({
    required this.repository,
    required this.gateway,
    required this.tools,
    this.executionDeviceId = 'this-device',
    int? maxRounds,
    Budget budget = const Budget(),
    AgentEventSink? events,
    this.selectionStrategy = const RuleAndModelToolSelection(),
    this.gate = const AlwaysConfirmGate(),
    this.provider = const OpenAiCompatProvider(),
    this.compactor = const ContextCompactor(),
    this.compactionProfile,
    DateTime Function()? clock,
  }) : budget = maxRounds == null
           ? budget
           : Budget(
               maxSteps: maxRounds,
               maxActive: budget.maxActive,
               maxTokens: budget.maxTokens,
               maxCallsPerStep: budget.maxCallsPerStep,
               maxCardCalls: budget.maxCardCalls,
               requestCap: budget.requestCap,
             ),
       events = events ?? TaskEventTableSink(repository),
       _clock = clock ?? DateTime.now {
    _dispatch.model = _model;
    _model
      ..dispatch = _dispatch
      ..compaction = _compaction;
    _compaction.model = _model;
  }
  final FoundationRepository repository;
  final OpenAiModelGateway gateway;
  final ToolRegistry tools;
  final String executionDeviceId;
  final Budget budget;

  /// Old name of `budget.maxSteps`.
  int get maxRounds => budget.maxSteps;
  final AgentEventSink events;
  final DateTime Function() _clock;
  final ToolSelectionStrategy selectionStrategy;
  final ModelRequestGate gate;

  /// Used for tasks whose frozen capabilities say streaming or native tools;
  /// a non-streaming compatibility task still goes through `gateway.chat`.
  final ModelProvider provider;

  /// Context compaction (ADR-0005 §6.6); only profiles that declare
  /// `contextTokens` are compacted automatically.
  final ContextCompactor compactor;

  /// A profile the person set up to write the summaries, in place of the
  /// conversation's own. It is used only if it exposes the data to no more
  /// than the conversation's profile does; otherwise nothing is summarized.
  final ModelProfile? compactionProfile;
  late final AgentContext _ctx = AgentContext(
    repository: repository,
    gateway: gateway,
    tools: tools,
    executionDeviceId: executionDeviceId,
    budget: budget,
    events: events,
    selectionStrategy: selectionStrategy,
    gate: gate,
    provider: provider,
    compactor: compactor,
    compactionProfile: compactionProfile,
    clock: _clock,
  );
  late final AgentTaskFactory _factory = AgentTaskFactory(_ctx);
  late final AgentDispatch _dispatch = AgentDispatch(_ctx);
  late final AgentModelTurn _model = AgentModelTurn(_ctx);
  late final AgentCompactionFlow _compaction = AgentCompactionFlow(_ctx);

  Future<PersonalTask> _trackStart(Future<PersonalTask> Function() run) {
    if (_ctx.closing) return Future.error(StateError("Assistant is closing"));
    final future = run();
    _ctx.activeStarts.add(future);
    return future.whenComplete(() => _ctx.activeStarts.remove(future));
  }

  static String digest(Object? value) => AgentContext.digest(value);

  Future<PersonalTask> start({
    required String conversationId,
    required String prompt,
    ModelProfile? profile,
    AssistantScope? scope,
    String? previousAttemptId,
  }) => _trackStart(() async {
    if (_ctx.closing) throw StateError('Assistant is closing');
    final (task, selection) = _factory.chatTask(
      conversationId: conversationId,
      prompt: prompt,
      profile: profile,
      scope: scope,
      previousAttemptId: previousAttemptId,
    );
    await repository.createTask(task);
    await repository.appendMessage(conversationId, 'user', prompt.trim());
    if (profile == null) {
      if (selection.ruleToolId == null) {
        await _ctx.finish(task, '当前使用离线模式。请选择下方已注册工具进行真实查询或计算，或选择模型开始对话。', []);
      } else {
        await _dispatch.dispatch(task, [
          Planned(selection.ruleToolId!, selection.ruleParameters),
        ]);
      }
    } else {
      await _model.advance(task);
    }
    return repository.task(task.id)!;
  });

  Future<PersonalTask> startTool({
    required String conversationId,
    required String toolId,
    Map<String, Object?> parameters = const {},
    String? destination,
    String? previousAttemptId,
  }) => _trackStart(() async {
    if (_ctx.closing) throw StateError('Assistant is closing');
    final task = _factory.toolTask(
      conversationId: conversationId,
      toolId: toolId,
      previousAttemptId: previousAttemptId,
    );
    await repository.createTask(task);
    await repository.appendMessage(
      conversationId,
      'user',
      '运行工具 $toolId：${jsonEncode(parameters)}',
    );
    await _dispatch.dispatch(task, [
      Planned(toolId, parameters, destination: destination),
    ]);
    return repository.task(task.id)!;
  });

  /// What a card selection looks like after the person toggles [id]: turning
  /// a call off turns off every later one too (a later write may depend on
  /// it); turning one on adds just that call back. Order is the card's.
  static List<String> toggleSelection(
    List<String> cardOrder,
    List<String> selected,
    String id,
  ) => AgentDispatch.toggleSelection(cardOrder, selected, id);

  /// Manual compaction (ADR-0005 §6.6-6): the same pipeline, forced. Allowed
  /// only while the next model request is waiting for confirmation, never
  /// while an approval for a tool call is pending: nothing of a pending
  /// approval or its preview is touched.
  Future<void> compactNow(String taskId) => _compaction.compactNow(taskId);

  /// The person declines to send the summary request: clearing only.
  Future<void> declineCompaction(String taskId) =>
      _compaction.declineCompaction(taskId);

  /// Trusted host UI only: display preview before supplying its exact digest.
  ///
  /// On a tool card [selectedInvocationIds] names the calls the person left
  /// ticked (null: all of them; none: the card is refused and the task
  /// cancelled). It must name only calls listed on the card. One confirmation
  /// is one click on the card, never one approval for several executions:
  /// each selected call is approved and invoked by itself.
  Future<void> confirm(
    String taskId, {
    required String requestDigest,
    List<String>? selectedInvocationIds,
  }) {
    if (_ctx.closing || _ctx.operations.containsKey(taskId)) {
      return Future.error(StateError('Task unavailable'));
    }
    final future = Future<void>(() async {
      var task = repository.task(taskId);
      if (task == null ||
          task.state != PersonalTaskState.waitingConfirmation ||
          task.payload['requestDigest'] != requestDigest ||
          !_clock().toUtc().isBefore(
            DateTime.parse(task.payload['expiresAt'] as String),
          )) {
        throw StateError('stale_confirmation');
      }
      final c = repository.conversation(task.conversationId);
      if (c == null ||
          AgentContext.digest(c.scope.toJson()) !=
              AgentContext.digest(task.scope.toJson())) {
        throw StateError('scope_mismatch');
      }
      final cardIds = [
        for (final call in AgentContext.cardCalls(task))
          call['invocationId'] as String,
      ];
      final chosen = selectedInvocationIds;
      if (chosen != null &&
          (task.stage != 'tool' ||
              chosen.toSet().length != chosen.length ||
              chosen.any((id) => !cardIds.contains(id)))) {
        // Only calls on the card, each once.
        throw ArgumentError('unknown_invocation');
      }
      if (chosen != null && chosen.isEmpty) {
        // Nothing ticked is a refusal of the whole card.
        await cancel(taskId);
        return;
      }
      // The approval of a model / summary request is
      // written with the state change that consumes the confirmation.
      final approves = ['model', 'compaction'].contains(task.stage);
      final previewOk =
          AgentContext.digest(task.payload['preview']) == requestDigest;
      if (!await _ctx.commit(
        task.copy({'state': 'running', 'waitingFor': null}),
        events: [
          if (approves && previewOk)
            (
              AgentEventType.approval,
              {'stage': task.stage, 'requestDigest': requestDigest},
            ),
        ],
        expected: {PersonalTaskState.waitingConfirmation},
      )) {
        throw StateError('confirmation_consumed');
      }
      task = repository.task(taskId)!;
      try {
        if (task.stage == 'model') {
          if (!previewOk) throw StateError('preview_changed');
          await _model.runModel(task);
        } else if (task.stage == 'compaction') {
          if (!previewOk) throw StateError('preview_changed');
          await _compaction.runCompaction(task);
        } else {
          await _dispatch.executeCard(task, {...(chosen ?? cardIds)});
        }
      } on FixedFailure catch (error) {
        await _ctx.fail(task, error.message);
      } catch (error) {
        // Name the cause (e.g. model_http_404) so a wrong endpoint or model
        // name can be fixed. The text is stored on the task, shown and sent
        // as a notification, so anything that may quote a key is withheld.
        final cause = redactCredentials(error).replaceAll(RegExp(r'\s+'), ' ');
        await _ctx.fail(
          task,
          '执行失败（${cause.length > 160 ? '${cause.substring(0, 160)}…' : cause}）；'
          '请检查端点、模型名称、工具权限或资料范围后新建尝试',
        );
      }
    });
    _ctx.operations[taskId] = future;
    return future.whenComplete(() => _ctx.operations.remove(taskId));
  }

  /// Corrective rounds allowed per task when a reply breaks the protocol.
  static const maxProtocolCorrections = AgentModelTurn.maxProtocolCorrections;

  /// Before a tool call is under way (waiting for confirmation, queued, model
  /// phase) this ends the task as `cancelled`. Once the tool call started it
  /// only sends the signal: the registry's receipt decides whether the task
  /// ends `cancelled` (stopped before the effect), `interrupted` (the effect
  /// may have happened) or with the real result.
  Future<void> cancel(String id) async {
    var task = repository.task(id);
    if (task == null || task.terminal) return;
    if (_ctx.toolActive.contains(id)) {
      _ctx.cancelRequested.add(id);
      _ctx.toolTokens[id]?.cancel();
      final marked = await repository.updateTask(
        task.copy({'stage': 'cancelling'}),
        expected: {PersonalTaskState.running},
      );
      if (marked) return;
      // The tool outcome was written first (for example the task now waits
      // for the next model turn): cancel what follows like any other task.
      task = repository.task(id);
      if (task == null || task.terminal) return;
    }
    _ctx.modelTokens[id]?.cancel();
    _ctx.toolTokens[id]?.cancel();
    await _ctx.commit(
      task.copy({
        'state': 'cancelled',
        'stage': 'cancelled',
        'waitingFor': null,
      }),
      events: [(AgentEventType.cancel, <String, Object?>{})],
    );
  }

  Future<void> pause(String id) async {
    final task = repository.task(id);
    if (task == null || task.state != PersonalTaskState.waitingConfirmation) {
      throw StateError('只能在等待确认的安全边界暂停');
    }
    await repository.updateTask(
      task.copy({'state': 'paused', 'stage': 'paused', 'waitingFor': null}),
    );
  }

  Future<PersonalTask> resume(String id) async {
    final task = repository.task(id);
    if (task == null ||
        ![
          PersonalTaskState.paused,
          PersonalTaskState.interrupted,
          PersonalTaskState.failed,
        ].contains(task.state)) {
      throw StateError('Task is not resumable');
    }
    if (task.profileId == null && task.payload["toolCall"] is Map) {
      final call = task.payload["toolCall"] as Map;
      return startTool(
        conversationId: task.conversationId,
        toolId: call["toolId"] as String,
        parameters: Map<String, Object?>.from(call["parameters"] as Map),
        destination: call["destination"] as String?,
        previousAttemptId: id,
      );
    }
    return start(
      conversationId: task.conversationId,
      prompt: task.prompt,
      profile: task.profileId == null ? null : _ctx.profile(task),
      previousAttemptId: id,
    );
  }

  Future<void> close() async {
    _ctx.closing = true;
    for (final t in _ctx.modelTokens.values) {
      t.cancel();
    }
    for (final t in _ctx.toolTokens.values) {
      t.cancel();
    }
    for (final t in repository.tasks()) {
      if (t.payload['owner'] == 'platform') {
        continue;
      }
      if (t.state == PersonalTaskState.running ||
          t.state == PersonalTaskState.queued) {
        await repository.updateTask(
          t.copy({
            'state': 'interrupted',
            'stage': 'interrupted',
            'error': '宿主关闭，继续将重新确认',
          }),
        );
      }
    }
    await Future.wait(
      _ctx.activeStarts.toList().map(
        (f) => f.then<void>((_) {}, onError: (Object _) {}),
      ),
    );
    await Future.wait(
      _ctx.operations.values.toList().map((f) => f.catchError((Object _) {})),
    );
  }
}
