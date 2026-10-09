import 'dart:async';
import 'dart:convert';

import 'package:muyon_module_api/ui_contract.dart';

import '../platform/foundation_repository.dart';

class UiPlanningHostState {
  const UiPlanningHostState({
    required this.snapshot,
    required this.intent,
    required this.currentView,
    required this.catalog,
    required this.allowedActionRefs,
  });
  final DataSnapshot snapshot;
  final InteractionIntent intent;
  final UiCurrentView currentView;
  final UiCatalog catalog;
  final Set<String> allowedActionRefs;
}

/// The facts owner reads actual current data; no model-authored facts enter here.
typedef UiPlanningStateSource = Future<UiPlanningHostState?> Function(
  PersonalTask task,
);

class UiPlannedPresentation {
  const UiPlannedPresentation(this.result, this.request, this.validated);
  final UiPlanningResult result;
  final UiPlanningRequest? request;
  final ValidatedUiPlan? validated;
}

class UiPlanningHarness {
  UiPlanningHarness({
    required this.repository,
    required this.source,
    required this.providers,
    this.mode = UiPlanningMode.intelligent,
    this.guides = const EmptyUiGuideSource(),
    this.timeout = const Duration(seconds: 15),
    this.requestView,
    this.enabled = true,
    this.cancelTimedOutRequest,
  });
  final FoundationRepository repository;
  final UiPlanningStateSource source;
  final Map<UiPlanningMode, UiPlanningPort> providers;
  UiPlanningMode mode;
  bool enabled;
  final UiGuideSource guides;
  final Duration timeout;
  /// Host cleanup must finish before a timeout fallback is exposed.
  final Future<void> Function(UiPlanningRequest)? cancelTimedOutRequest;
  final List<Object?> Function(PersonalTask)? requestView;
  final _requests = <String, Future<UiPlannedPresentation>>{};
  final _latest = <String, UiPlannedPresentation>{};
  UiPlannedPresentation? presentation(String taskId) => _latest[taskId];
  static UiPlannedPresentation fallback(
    String code, [
    UiPlanningRequest? request,
  ]) => UiPlannedPresentation(
    UiPlanningResult(decision: UiDisplayDecision.textOnly, reasonCode: code),
    request,
    null,
  );
  Future<UiPlannedPresentation> plan(
    String taskId, {
    Map<String, Object?>? expected,
  }) async {
    final task = repository.task(taskId);
    if (!enabled ||
        task == null ||
        task.payload['uiPlanningDisabled'] == true) {
      return fallback('planning_disabled');
    }
    final state = await source(task);
    if (state == null) return fallback('host_state_unavailable');
    if (expected != null &&
        (expected.length != 4 ||
            expected['snapshotId'] != state.snapshot.ref.id ||
            expected['expectedSnapshotRevision'] !=
                state.snapshot.ref.revision ||
            expected['surfaceId'] != state.currentView.surfaceId ||
            expected['expectedSurfaceRevision'] !=
                state.currentView.revision)) {
      return fallback('stale_host_state');
    }
    final stepAnswer =
        ((task.payload['step'] as Map?)?['assistant'] as Map?)?['content'];
    final answer = task.state == PersonalTaskState.succeeded
        ? task.summary ?? ''
        : stepAnswer is String
        ? stepAnswer
        : task.summary ?? '';
    if (answer.trim().isEmpty) return fallback('answer_unavailable');
    final key = jsonEncode([
      task.id,
      answer,
      state.snapshot.ref.id,
      state.snapshot.ref.revision,
      state.currentView.surfaceId,
      state.currentView.revision,
      state.catalog.version,
      mode.name,
    ]);
    final selectedMode = mode;
    return _requests
        .putIfAbsent(key, () => _run(task, state, selectedMode))
        .then((value) async {
          final now = await source(repository.task(task.id)!);
          var current = value;
          if (!enabled ||
              mode != selectedMode ||
              now == null ||
              now.snapshot.ref != state.snapshot.ref ||
              now.currentView.revision != state.currentView.revision ||
              now.currentView.surfaceId != state.currentView.surfaceId ||
              now.catalog.version != state.catalog.version) {
            current = fallback('host_state_changed', value.request);
          } else if (value.result.plan != null) {
            final allowed = now.allowedActionRefs.intersection(
              now.intent.allowedActionRefs,
            );
            final intent = InteractionIntent(
              id: now.intent.id,
              purpose: now.intent.purpose,
              snapshotRef: now.intent.snapshotRef,
              requiredBindings: now.intent.requiredBindings,
              mandatoryStates: now.intent.mandatoryStates,
              allowedActionRefs: allowed,
            );
            if (!validateUiPlan(
              value.result.plan!,
              now.snapshot,
              intent,
              now.catalog,
            ).isValid) {
              current = fallback('current_authority_changed', value.request);
            }
          }
          if (mode == selectedMode) _latest[task.id] = current;
          return current;
        });
  }

  Future<UiPlannedPresentation> _run(
    PersonalTask task,
    UiPlanningHostState state,
    UiPlanningMode selectedMode,
  ) async {
    final stepAnswer =
        ((task.payload['step'] as Map?)?['assistant'] as Map?)?['content'];
    final answer = task.state == PersonalTaskState.succeeded
        ? task.summary ?? ''
        : stepAnswer is String
        ? stepAnswer
        : task.summary ?? '';
    if (answer.trim().isEmpty) return fallback('answer_unavailable');
    final messages = [
      for (final m
          in (requestView?.call(task) ??
              task.payload['messages'] as List? ??
              const []))
        Map<String, Object?>.from(m as Map),
    ];
    if (messages.isEmpty ||
        messages.last['role'] != 'assistant' ||
        messages.last['content'] != answer) {
      messages.add({'role': 'assistant', 'content': answer});
    }
    List<UiGuideEntry> entries = const [];
    try {
      entries = await guides
          .lookup(
            UiGuideQuery(
              purpose: state.intent.purpose,
              catalogVersion: state.catalog.version,
              dataProfile: {'factCount': state.snapshot.facts.length},
            ),
          )
          .timeout(const Duration(seconds: 2));
      entries = entries
          .where((e) => e.catalogVersion == state.catalog.version)
          .toList();
    } catch (_) {
      /* Guides are optional, never a constraint or authority. */
    }
    final allowed = state.allowedActionRefs
        .intersection(state.intent.allowedActionRefs)
        .intersection(state.catalog.actions.keys.toSet());
    final intent = InteractionIntent(
      id: state.intent.id,
      purpose: state.intent.purpose,
      snapshotRef: state.intent.snapshotRef,
      requiredBindings: state.intent.requiredBindings,
      mandatoryStates: state.intent.mandatoryStates,
      allowedActionRefs: allowed,
    );
    final request = UiPlanningRequest(
      question: task.payload['prompt'] as String? ?? '',
      answer: answer,
      conversationMessages: messages,
      conversationVersion:
          '${task.conversationId}:${repository.messages(task.conversationId).length}',
      coverage: task.payload['compaction'] == null
          ? 'task_frozen_history_window'
          : 'host_compacted_request_view',
      taskId: task.id,
      turnId: task.id,
      snapshot: state.snapshot,
      intent: intent,
      currentView: state.currentView,
      catalog: state.catalog,
      allowedActionRefs: allowed,
      mode: selectedMode,
      guideEntries: entries,
    );
    final provider = providers[selectedMode];
    if (provider == null) return fallback('provider_unavailable', request);
    try {
      final result = await provider.plan(request).timeout(
        timeout,
        onTimeout: () async {
          await cancelTimedOutRequest?.call(request);
          throw TimeoutException('UI planning deadline expired', timeout);
        },
      );
      if (result.errors.isNotEmpty) {
        return fallback('invalid_decision', request);
      }
      if (result.plan == null) {
        return UiPlannedPresentation(result, request, null);
      }
      if (result.plan!.surfaceId != request.currentView.surfaceId ||
          result.plan!.revision <= request.currentView.revision) {
        return fallback('stale_surface', request);
      }
      final checked = validateUiPlan(
        result.plan!,
        request.snapshot,
        request.intent,
        request.catalog,
      );
      if (!checked.isValid) return fallback('invalid_plan', request);
      final now = await source(repository.task(task.id)!);
      if (now == null ||
          now.snapshot.ref != state.snapshot.ref ||
          now.currentView.surfaceId != state.currentView.surfaceId ||
          now.currentView.revision != state.currentView.revision ||
          now.catalog.version != state.catalog.version ||
          !now.allowedActionRefs.containsAll(allowed)) {
        return fallback('host_state_changed', request);
      }
      return UiPlannedPresentation(result, request, checked.validatedPlan);
    } on TimeoutException {
      return fallback('planner_timeout', request);
    } catch (_) {
      return fallback('planner_unavailable', request);
    }
  }
}

/// Same agent/gateway/HostModelAuthorization path as chat. The callback must be
/// supplied by the live harness, and its request gets the existing budget/card.
class MotivationUiPlanningProvider implements UiPlanningPort {
  const MotivationUiPlanningProvider(this.requestModel);
  final Future<String> Function(UiPlanningRequest, String) requestModel;
  @override
  Future<UiPlanningResult> plan(UiPlanningRequest request) async {
    final raw = await requestModel(
      request,
      jsonEncode({
        'instructions':
            'Plan presentation of existing host facts only. No execution or permission. '
            'Return an answer whose text is a JSON object {decision,reasonCode,plan}. '
            'plan uses surfaceId,revision,catalogVersion,snapshotId,snapshotRevision,intentRef,root,nodes. '
            'Keep every required binding/conflict visible. Use only supplied component/action contracts.',
        'request': request.toJson(),
      }),
    );
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return UiPlanningResult(
      decision: UiDisplayDecision.values.byName(j['decision'] as String),
      reasonCode: j['reasonCode'] as String,
      plan: j['plan'] == null
          ? null
          : decodeUiPresentation(Map<String, dynamic>.from(j['plan'] as Map)),
    );
  }
}
