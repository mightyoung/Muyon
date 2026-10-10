import 'dart:async';
import 'dart:convert';

import 'package:muyon_module_api/muyon_module_api.dart';

import '../platform/foundation_repository.dart';
import '../services/models/credential_redaction.dart';
import '../services/models/model_gateway.dart';
import '../services/models/model_provider.dart';
import '../services/models/openai_compat_provider.dart';
import '../platform/tool_registry.dart';
import '../platform/grants/outbound_content_reviewer.dart';
import '../platform/grants/host_model_authorization.dart';
import '../platform/grants/tool_grant_context.dart';
import '../platform/grants/host_scope_authority.dart';
import 'agent_budget.dart';
import 'agent_event_sink.dart';
import 'context_compactor.dart';
import 'model_request_gate.dart';
import 'tool_selection.dart';
import 'agent_compaction_flow.dart';
import 'agent_context.dart';
import 'agent_drafts.dart';
import 'agent_dispatch.dart';
import 'agent_model_turn.dart';
import 'agent_resume.dart';
import 'agent_task_factory.dart';
import 'ui_planning.dart';
import 'ui_planning_preference.dart';
import 'ui_presentation_preference.dart';
import 'stream_ui_planning.dart';
import '../platform/ui_planning_tool.dart';

import 'package:muyon_module_api/ui_contract.dart';

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
    this.toolReviewer,
    this.modelAuthorization,
    int? maxRounds,
    Budget budget = const Budget(),
    AgentEventSink? events,
    this.selectionStrategy = const RuleAndModelToolSelection(),
    this.gate = const AlwaysConfirmGate(),
    this.provider = const OpenAiCompatProvider(),
    this.compactor = const ContextCompactor(),
    this.compactionProfile,
    this.uiPlanningSource,
    this.presentationPreference,
    this.uiPlanningProviders = const {},
    this.uiPlanningMode = UiPlanningMode.intelligent,
    bool uiPlanningEnabled = true,
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
    if (uiPlanningSource != null) {
      _ctx.uiPlanning = UiPlanningHarness(
        repository: repository,
        source: uiPlanningSource!,
        providers: {
          UiPlanningMode.motivation: presentationPreference == null
            ? MotivationUiPlanningProvider(_requestUiModel)
            : StreamMotivationUiPlanningProvider(
                (request, prompt, receive) async {
                  await _requestUiModel(request, prompt, receive: receive);
                }, onProgress: (value) => _ctx.uiPlanning?.publishStream(value)),
          ...uiPlanningProviders,
        },
        mode: uiPlanningMode,
        requestView: _ctx.view,
        enabled: presentationPreference == null ? uiPlanningEnabled : true,
        allowsPresentation: presentationPreference == null ? null : _allowsPresentation,
        presentationIdentity: presentationPreference == null ? null : (id) => _presentationRequests[id],
        cancelTimedOutRequest: (request) async {
          await _uiPlanningCancellations[request]?.call();
        },
      );
      tools.register(
        providerId: 'host-ui-planning',
        descriptor: uiPlanningToolDescriptor,
        handler: (context) async {
          final request = context.request;
          final taskId = _ctx.invocationTasks[request.invocationId];
          if (taskId == null) throw StateError('planning_invocation_unowned');
          return runUiPlanningTool(_ctx.uiPlanning!, taskId, request);
        },
      );
    }
    _dispatch.model = _model;
    _model
      ..dispatch = _dispatch
      ..compaction = _compaction;
    _compaction.model = _model;
    _resume
      ..model = _model
      ..dispatch = _dispatch
      ..factory = _factory;
  }
  final UiPresentationPreference? presentationPreference;
  final _presentationRequests = <String, UiPresentationRequest>{};
  final _presentationPolicies = <String, UiPresentationPolicy>{};
  UiPresentationMode get presentationMode => presentationPreference?.mode ??
    (uiPlanningEnabled ? UiPresentationMode.automatic : UiPresentationMode.textOnly);
  bool _allowsPresentation(String id) {
    final request = _presentationRequests[id], policy = _presentationPolicies[id];
    return request != null && policy?.allowsContentFor(request) == true;
  }
  void _freezePresentation(String id, UiPresentationRequest request) {
    _presentationRequests[id] = request;
    final policy = presentationPreference?.freezeFor(request);
    if (policy != null) _presentationPolicies[id] = policy;
  }
  Future<void> savePresentationMode(UiPresentationMode mode) async {
    final preference = presentationPreference;
    if (preference == null || _ctx.closing) throw StateError('Presentation owner unavailable');
    await preference.save(mode);
    _ctx.uiPlanning?.invalidate();
  }
  Future<UiPlannedPresentation> planUiFromUserControl(String taskId) {
    _freezePresentation(taskId, UiPresentationRequest.explicitControl());
    return planUi(taskId);
  }
  HostUiStreamProgress? uiStreamProgress(String taskId) => _ctx.uiPlanning?.streamProgress(taskId);
  final UiPlanningStateSource? uiPlanningSource;
  final Map<UiPlanningMode, UiPlanningPort> uiPlanningProviders;
  final UiPlanningMode uiPlanningMode;
  Future<UiPlannedPresentation> planUi(
    String taskId, {
    Map<String, Object?>? expected,
  }) async =>
      await _ctx.uiPlanning?.plan(taskId, expected: expected) ??
      UiPlanningHarness.fallback('planning_disabled');
  Future<PersonalTask> startUiSemantic(String taskId, String prompt) {
    final task = repository.task(taskId);
    if (task == null) return Future.error(StateError('task_unavailable'));
    return _start(
      conversationId: task.conversationId,
      prompt: prompt,
      profile: task.payload['profile'] is Map ? _ctx.profile(task) : null,
      scope: task.scope,
      previousAttemptId: task.id,
      trustedProfileChoice: false,
    );
  }

  // Request identity isolates concurrent turns and cached planning attempts.
  final _uiPlanningCancellations =
      <UiPlanningRequest, Future<void> Function()>{};

  Future<String> _requestUiModel(
    UiPlanningRequest request,
    String prompt, {void Function(String)? receive,}
  ) async {
    final source = repository.task(request.taskId);
    if (source == null || source.payload['profile'] is! Map) {
      throw StateError('model_unavailable');
    }
    final profile = _ctx.profile(source);
    if (receive != null && !profile.capabilities.streaming) throw StateError('stream_model_unavailable');
    final (built, _) = _factory.chatTask(
      conversationId: source.conversationId,
      prompt: prompt,
      profile: profile,
      scope: source.scope,
      previousAttemptId: source.id,
      uiPlanningInternal: true,
      uiPlanningStream: receive != null,
    );
    // Charge all planning attempts to the original turn. Each child persists
    // its starting usage so deltas remain auditable after a host restart.
    var usage = BudgetUsage.fromPayload(source.payload);
    for (final prior in repository.tasks(
      conversationId: source.conversationId,
    )) {
      if (prior.payload['uiPlanningInternal'] != true ||
          prior.previousAttemptId != source.id) {
        continue;
      }
      if (!prior.terminal) throw StateError('planning_attempt_pending');
      final before = BudgetUsage.fromPayload(
        Map<String, Object?>.from(
          prior.payload['uiPlanningBudgetStart'] as Map? ?? source.payload,
        ),
      );
      final after = BudgetUsage.fromPayload(prior.payload);
      usage = BudgetUsage(
        steps: usage.steps + (after.steps - before.steps).clamp(0, 1000000),
        active:
            usage.active +
            (after.active > before.active
                ? after.active - before.active
                : Duration.zero),
        tokens:
            usage.tokens + (after.tokens - before.tokens).clamp(0, 1000000000),
        estimated: usage.estimated || after.estimated,
      );
    }
    final task = built.copy({
      ...usage.toPayload(),
      'uiPlanningBudgetStart': usage.toPayload(),
    });
    final completed = Completer<String>();
    var expired = false;
    final created = Completer<void>();
    _uiPlanningCancellations[request] = () async {
      expired = true;
      await created.future;
      await cancel(task.id);
      if (!completed.isCompleted) {
        completed.completeError(TimeoutException('UI planning deadline expired'));
      }
    };
    _ctx.uiModelReplies[task.id] = completed;
    if (receive != null) _ctx.uiModelChunks[task.id] = receive;
    _ctx.uiModelChecks[task.id] = () async {
      final planning = _ctx.uiPlanning;
      final latest = repository.task(request.taskId);
      final state = latest == null ? null : await planning?.source(latest);
      if (expired ||
          planning?.enabled != true ||
          planning?.isCurrentRequest(request) != true ||
          (presentationPreference != null && !_allowsPresentation(source.id)) ||
          planning?.mode != request.mode ||
          state == null ||
          state.snapshot.ref != request.snapshot.ref ||
          state.catalog.version != request.catalog.version ||
          state.currentView.surfaceId != request.currentView.surfaceId ||
          state.currentView.revision != request.currentView.revision ||
          jsonEncode(state.currentView.values) !=
              jsonEncode(request.currentView.values) ||
          !state.allowedActionRefs.containsAll(request.allowedActionRefs)) {
        throw StateError('planning_source_changed');
      }
    };
    // Install a handler before advance: local policy may finish synchronously.
    final observed = completed.future;
    unawaited(observed.catchError((Object _) => ''));
    try {
      try {
        await repository.createTask(task);
      } finally {
        // Cancellation can be requested while the first database write awaits.
        created.complete();
      }
      if (expired) throw TimeoutException('UI planning deadline expired');
      await _model.advance(task);
      await _ctx.event(source, 'ui_planning_model', {'taskId': task.id});
      // The harness owns the sole deadline, including startup and cleanup.
      return await observed;
    } finally {
      await cancel(task.id);
      _uiPlanningCancellations.remove(request);
      _ctx.uiModelReplies.remove(task.id);
      _ctx.uiModelChunks.remove(task.id);
      _ctx.uiModelChecks.remove(task.id);
    }
  }

  bool get uiPlanningEnabled => presentationPreference == null
    ? _ctx.uiPlanning?.enabled ?? false
    : presentationMode != UiPresentationMode.textOnly;
  UiPlanningMode get currentUiPlanningMode =>
      _ctx.uiPlanning?.mode ?? uiPlanningMode;
  void configureUiPlanning({bool? enabled, UiPlanningMode? mode}) {
    if (enabled != null && presentationPreference == null) _ctx.uiPlanning?.enabled = enabled;
    if (mode != null) _ctx.uiPlanning?.mode = mode;
  }

  /// Commit the user's presentation choice before applying it in memory.
  final _uiPreferenceSaves = <Future<void>>{};
  Future<void> saveUiPlanningPreference(bool enabled) {
    if (_ctx.closing) return Future.error(StateError('Assistant is closing'));
    if (presentationPreference != null) return savePresentationMode(
      enabled ? UiPresentationMode.automatic : UiPresentationMode.textOnly);
    final future = UiPlanningPreference(repository).save(enabled).then((_) {
      configureUiPlanning(enabled: enabled);
      repository.refresh();
    });
    _uiPreferenceSaves.add(future);
    return future.whenComplete(() => _uiPreferenceSaves.remove(future));
  }

  UiPlannedPresentation? uiPresentation(String taskId) =>
      presentationPreference != null && !_allowsPresentation(taskId)
        ? null : _ctx.uiPlanning?.presentation(taskId);
  final FoundationRepository repository;
  final OpenAiModelGateway gateway;
  final ToolRegistry tools;
  final String executionDeviceId;
  final OutboundContentReviewer? toolReviewer;
  final HostModelAuthorization? modelAuthorization;
  final Budget budget;

  /// Derives authority from this live dispatcher and actual host source owners.
  /// Recreated snapshots and callers outside the Agent have no invocation owner.
  ToolGrantContext? hostGrantContext(
    ToolCallRequest request,
    HostScopeAuthority authority,
  ) {
    final live = _ctx.invocationRequests[request.invocationId];
    final facts = _ctx.factsFor(request);
    if (live == null ||
        facts == null ||
        facts.conversationId == null ||
        AgentContext.digest([
              live.toolId,
              live.replayKey,
              live.scope.toJson(),
              live.parameters,
              live.destination,
            ]) !=
            AgentContext.digest([
              request.toolId,
              request.replayKey,
              request.scope.toJson(),
              request.parameters,
              request.destination,
            ])) {
      return null;
    }
    final modules = tools.authorityModules(request.toolId);
    return ToolGrantContext(
      taskId: facts.taskId,
      conversationId: facts.conversationId!,
      taskTainted: facts.requiresConfirmation,
      scopeRevision: authority.stamp(request.scope, modules) ?? '',
      allowedModuleIds: modules,
    );
  }

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
    toolReviewer: toolReviewer,
    modelAuthorization: modelAuthorization,
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
  late final AgentResume _resume = AgentResume(_ctx);

  Future<PersonalTask> _trackStart(Future<PersonalTask> Function() run) {
    if (_ctx.closing) return Future.error(StateError("Assistant is closing"));
    final future = run();
    _ctx.activeStarts.add(future);
    return future.whenComplete(() => _ctx.activeStarts.remove(future));
  }

  /// Read-only drafts of the replies being streamed (memory only, never
  /// stored; see agent_drafts.dart).
  Stream<AgentDraft> get drafts => _ctx.drafts.stream;

  /// The draft in flight for [taskId], if any.
  AgentDraft? draftOf(String taskId) => _ctx.drafts.of(taskId);

  static String digest(Object? value) => AgentContext.digest(value);

  Future<PersonalTask> start({
    required String conversationId,
    required String prompt,
    ModelProfile? profile,
    AssistantScope? scope,
    String? previousAttemptId,
  }) => _start(
    conversationId: conversationId,
    prompt: prompt,
    profile: profile,
    scope: scope,
    previousAttemptId: previousAttemptId,
    trustedProfileChoice: true,
  );

  Future<PersonalTask> _start({
    required String conversationId,
    required String prompt,
    required bool trustedProfileChoice,
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
    _freezePresentation(task.id, UiPresentationRequest.ordinary());
    await repository.createTask(task);
    if (profile != null && trustedProfileChoice) {
      modelAuthorization?.bindLiveProfile(task.id, profile);
    }
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
    _freezePresentation(task.id, UiPresentationRequest.ordinary());
    await repository.createTask(task);
    await repository.appendMessage(
      conversationId,
      'user',
      '运行工具 $toolId：${jsonEncode(AgentDispatch.displayParameters(parameters))}',
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
      // The approval of a model / summary request or of a held resume is
      // written with the state change that consumes the confirmation.
      final approves = [
        'model',
        'compaction',
        AgentResume.stage,
      ].contains(task.stage);
      final previewOk =
          task.stage == AgentResume.stage ||
          AgentContext.digest(task.payload['preview']) == requestDigest;
      if (!await _ctx.commit(
        task.copy({
          'state': 'running',
          'waitingFor': null,
          if (task.stage == AgentResume.stage && task.profileId == null) ...{
            // Consume the verification in the same transaction as its approval.
            // Fresh prepare can fail before replacing the historical tool call.
            'preview': null,
            'resumeAcknowledged': {
              'invocationId': (task.payload['toolCall'] as Map)['invocationId'],
            },
          },
        }),
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
        } else if (task.stage == AgentResume.stage) {
          await _resume.continueHeld(task);
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
    final reply = _ctx.uiModelReplies[id];
    if (reply != null && !reply.isCompleted) reply.completeError(StateError('planning_model_cancelled'));
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
    if (task?.payload['uiPlanningInternal'] == true) {
      throw StateError('planning_session_expired');
    }
    if (task == null ||
        ![
          PersonalTaskState.paused,
          PersonalTaskState.interrupted,
          PersonalTaskState.failed,
        ].contains(task.state)) {
      throw StateError('Task is not resumable');
    }
    // From the last checkpoint: what the earlier attempt's receipts show was
    // done is taken over, never run again; what cannot be decided stops at a
    // confirmation (see [AgentResume]).
    PersonalTask? taken;
    await _trackStart(() async {
      taken = await _resume.attempt(task);
      return taken ?? task;
    });
    if (taken != null) return taken!;
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
    return _start(
      trustedProfileChoice: false,
      conversationId: task.conversationId,
      prompt: task.prompt,
      profile: task.profileId == null ? null : _ctx.profile(task),
      previousAttemptId: id,
    );
  }

  Future<void> close() async {
    _ctx.closing = true;
    await presentationPreference?.close();
    _ctx.uiPlanning?.invalidate();
    await Future.wait(_uiPlanningCancellations.values.toList().map((cancel) => cancel()));
    await Future.wait(_uiPreferenceSaves.toList().map(
      (future) => future.then<void>((_) {}, onError: (Object _) {})));
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
