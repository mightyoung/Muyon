import 'dart:async';
import 'dart:convert';

import 'package:muyon_module_api/ui_contract.dart';

import '../platform/foundation_repository.dart';
import 'stream_ui_planning.dart';
import 'ui_planning_reason.dart';
import 'model_tool_result_projection.dart';

class UiPlanningHostState {
  const UiPlanningHostState({
    required this.snapshot,
    required this.intent,
    required this.currentView,
    required this.catalog,
    required this.allowedActionRefs,
    this.modelDisclosedFactRefs = const {},
    this.modelDisclosedComputedRefs = const {},
    this.modelDisclosedUiStateRefs = const {},
  });
  final DataSnapshot snapshot;
  final InteractionIntent intent;
  final UiCurrentView currentView;
  final UiCatalog catalog;
  final Set<String> allowedActionRefs;
  final Set<String> modelDisclosedFactRefs;
  final Set<String> modelDisclosedComputedRefs;
  final Set<String> modelDisclosedUiStateRefs;
}

/// The facts owner reads actual current data; no model-authored facts enter here.
typedef UiPlanningStateSource = Future<UiPlanningHostState?> Function(
  PersonalTask task,
);

class UiPlannedPresentation {
  const UiPlannedPresentation(
    this.result,
    this.request,
    this.validated, {
    this.stream,
  });
  final HostUiStreamProgress? stream;
  final UiPlanningResult result;
  UiPlanningReason get reason => UiPlanningReason.forCode(result.reasonCode);
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
    this.modelHistory,
    this.enabled = true,
    this.cancelTimedOutRequest,
    this.allowsPresentation,
    this.presentationBlockReason,
    this.presentationIdentity,
  });
  final FoundationRepository repository;
  bool canPlanTask(String id) =>
      enabled && (allowsPresentation?.call(id) ?? true);
  final UiPlanningStateSource source;
  final bool Function(String)? allowsPresentation;
  final String? Function(String)? presentationBlockReason;
  final Object? Function(String)? presentationIdentity;
  final _streamProgress = <String, HostUiStreamProgress>{};
  final _activeRequests = <String, UiPlanningRequest>{};
  final _requestProviders = Map<UiPlanningRequest, UiPlanningPort>.identity();
  final _closedRequests = Set<UiPlanningRequest>.identity();
  final _cancelledTasks = <String>{};
  final _terminalResults =
      Map<UiPlanningRequest, Future<UiPlannedPresentation>>.identity();
  int _epoch = 0;
  final _requestIdentities = Map<UiPlanningRequest, Object?>.identity();
  bool isCurrentRequest(UiPlanningRequest request) =>
      enabled &&
      (allowsPresentation?.call(request.taskId) ?? true) &&
      _requestIdentities.containsKey(request) &&
      identical(_activeRequests[request.taskId], request) &&
      identical(
        _requestIdentities[request],
        presentationIdentity?.call(request.taskId),
      );
  HostUiStreamProgress? streamProgress(String taskId) {
    final progress = _streamProgress[taskId];
    return progress != null && isCurrentRequest(progress.request)
        ? progress
        : null;
  }

  void publishStream(HostUiStreamProgress value) {
    if (isCurrentRequest(value.request) &&
        !_closedRequests.contains(value.request)) {
      _streamProgress[value.request.taskId] = value;
      repository.refresh();
    }
  }

  void invalidate() {
    ++_epoch;
    _latest.clear();
    _streamProgress.clear();
    _requests.clear();
    _requestIdentities.clear();
    _activeRequests.clear();
    _requestProviders.clear();
    _closedRequests.clear();
    _terminalResults.clear();
    repository.refresh();
  }

  HostUiStreamProgress? _progressFor(UiPlanningRequest request) {
    final provider = _requestProviders[request];
    return provider is StreamMotivationUiPlanningProvider
        ? provider.progressFor(request)
        : identical(_streamProgress[request.taskId]?.request, request)
        ? _streamProgress[request.taskId]
        : null;
  }

  Future<void> _recordProgress(
    UiPlanningRequest request,
    HostUiStreamProgress? progress, {
    String? code,
  }) async {
    final view = progress?.view;
    final codes = <String>{
      if (code != null) UiPlanningReason.host(code).code,
      if (progress?.failureCode case final failure?)
        UiPlanningReason.host(failure).code,
      if (view != null)
        for (final diagnostic in view.diagnostics)
          diagnostic.code.name.replaceAllMapped(
            RegExp(r'[A-Z]'),
            (match) => '_${match[0]!.toLowerCase()}',
          ),
      if (view?.batchValidation?.isValid == false) 'invalid_plan',
    };
    if (codes.isEmpty) return;
    await repository.appendTaskEvent(request.taskId, {
      'type': 'ui_stream_diagnostics',
      'data': {
        'codes': codes.toList(),
        'phase': view?.phase.name,
        'compilerPhase': (progress?.compilationPhase ?? view?.phase)?.name,
        'receivedLines': view?.receivedLines,
        'badLines': view?.badLines,
        'diagnosticCount': view?.diagnosticCount,
        'validationPassed': view?.batchValidation?.isValid,
        'validationErrorCount': view?.batchValidation?.errors.length ?? 0,
      },
    });
  }

  UiPlannedPresentation _readOnlyFailure(
    String code,
    UiPlanningRequest request, [
    HostUiStreamProgress? progress,
  ]) {
    code = UiPlanningReason.host(code).code;
    final frozen = progress?.revoke(code);
    if (frozen != null && isCurrentRequest(request)) {
      _streamProgress[request.taskId] = frozen;
    }
    return UiPlannedPresentation(
      UiPlanningResult(decision: UiDisplayDecision.textOnly, reasonCode: code),
      request,
      null,
      stream: frozen,
    );
  }

  /// Fence only this task synchronously; its current host identity remains
  /// available to display the disabled snapshot fallback after cleanup.
  Future<void> cancelTask(String taskId) async {
    _cancelledTasks.add(taskId);
    final request = _activeRequests[taskId];
    if (request == null) return;
    final existing = _terminalResults[request];
    if (existing != null) {
      await existing;
      return;
    }
    _closedRequests.add(request);
    final completion = Completer<UiPlannedPresentation>();
    _terminalResults[request] = completion.future;
    final progress = _progressFor(request);
    _latest.remove(taskId);
    _streamProgress.remove(taskId);
    repository.refresh();
    try {
      await cancelTimedOutRequest?.call(request);
    } finally {
      final value = _readOnlyFailure('cancelled', request, progress);
      try {
        await _recordProgress(request, value.stream, code: 'cancelled');
      } finally {
        // A persistence failure must still settle late receivers. The caller
        // sees the failure, while the revoked capability can never revive.
        if (isCurrentRequest(request)) _latest[taskId] = value;
        completion.complete(value);
        repository.refresh();
      }
    }
  }

  Future<UiPlanningHostState?> _sourceState(PersonalTask task) async {
    try {
      return await source(task);
    } catch (_) {
      return null;
    }
  }

  bool _sameHost(UiPlanningHostState? now, UiPlanningHostState state) =>
      now != null &&
      now.snapshot.ref == state.snapshot.ref &&
      now.currentView.surfaceId == state.currentView.surfaceId &&
      now.currentView.revision == state.currentView.revision &&
      now.catalog.version == state.catalog.version;

  /// Drops the fallback only when [request] still owns the task. A newer
  /// request for the same task keeps its identity.
  void _dropTask(String taskId, UiPlanningRequest? request) {
    if (request != null &&
        !identical(_activeRequests[taskId], request) &&
        _activeRequests.containsKey(taskId)) {
      if (identical(_latest[taskId]?.request, request)) {
        _latest.remove(taskId);
      }
      if (identical(_streamProgress[taskId]?.request, request)) {
        _streamProgress.remove(taskId);
      }
      _requestIdentities.remove(request);
      return;
    }
    _latest.remove(taskId);
    _streamProgress.remove(taskId);
    if (request != null) _requestIdentities.remove(request);
    _activeRequests.remove(taskId);
  }

  /// A later read of a closed task. Matching facts keep the revoked terminal.
  /// A null or moved host read clears it, so a timeout that settled before the
  /// refusal cannot leave the fallback in place.
  void reconcileRead(String taskId, UiPlanningHostState? now) {
    final task = repository.task(taskId);
    final closed =
        _cancelledTasks.contains(taskId) ||
        task?.state.name == 'cancelled' ||
        task?.state.name == 'interrupted';
    if (!closed) return;
    final request =
        _latest[taskId]?.request ??
        _streamProgress[taskId]?.request ??
        _activeRequests[taskId];
    final same =
        request != null &&
        now != null &&
        request.snapshot.ref == now.snapshot.ref &&
        request.currentView.surfaceId == now.currentView.surfaceId &&
        request.currentView.revision == now.currentView.revision &&
        request.catalog.version == now.catalog.version;
    if (same) return;
    _dropTask(taskId, request);
  }

  final Map<UiPlanningMode, UiPlanningPort> providers;
  UiPlanningMode mode;
  bool enabled;
  final UiGuideSource guides;
  final Duration timeout;

  /// Host cleanup must finish before a timeout fallback is exposed.
  final Future<void> Function(UiPlanningRequest)? cancelTimedOutRequest;
  final List<Object?> Function(PersonalTask)? requestView;
  /// Trusted host callback binds persisted results to current registry receipts.
  /// A model/body tag or an already-filtered view cannot grant this authority.
  final ModelToolHistory Function(PersonalTask)? modelHistory;
  final _requests = <String, Future<UiPlannedPresentation>>{};
  final _identityEpochs = Map<Object, int>.identity();
  int _nextIdentityEpoch = 0;
  final _latest = <String, UiPlannedPresentation>{};
  UiPlannedPresentation? presentation(String taskId) => _latest[taskId];
  static UiPlannedPresentation fallback(
    String code, [
    UiPlanningRequest? request,
  ]) => UiPlannedPresentation(
    UiPlanningResult(
      decision: UiDisplayDecision.textOnly,
      reasonCode: UiPlanningReason.host(code).code,
    ),
    request,
    null,
  );
  String _revocationCode(String taskId, String fallbackCode) =>
      presentationBlockReason?.call(taskId) ?? fallbackCode;

  Future<UiPlannedPresentation> plan(
    String taskId, {
    Map<String, Object?>? expected,
  }) async {
    final epoch = _epoch;
    final task = repository.task(taskId);
    final identity = presentationIdentity?.call(taskId);
    if (!enabled ||
        !(allowsPresentation?.call(taskId) ?? true) ||
        task == null ||
        task.payload['uiPlanningDisabled'] == true) {
      return fallback(
        enabled && task != null && task.payload['uiPlanningDisabled'] != true
            ? presentationBlockReason?.call(taskId) ?? 'planning_disabled'
            : 'planning_disabled',
      );
    }
    final state = await _sourceState(task);
    if (epoch != _epoch ||
        !(allowsPresentation?.call(taskId) ?? true) ||
        !identical(identity, presentationIdentity?.call(taskId))) {
      return fallback(_revocationCode(taskId, 'host_request_changed'));
    }
    // A closed task is decided before a null source is treated as a wipe.
    // Matching facts keep the revoked terminal. An unreadable re-read clears it.
    if (_cancelledTasks.contains(taskId) ||
        task.state.name == 'cancelled' ||
        task.state.name == 'interrupted') {
      final previous = _latest[taskId], request = previous?.request;
      if (previous != null &&
          request != null &&
          isCurrentRequest(request) &&
          state != null &&
          request.snapshot.ref == state.snapshot.ref &&
          request.currentView.surfaceId == state.currentView.surfaceId &&
          request.currentView.revision == state.currentView.revision &&
          request.catalog.version == state.catalog.version) {
        return previous;
      }
      _dropTask(taskId, request);
      return fallback('cancelled');
    }
    if (state == null) {
      _latest.remove(taskId);
      _streamProgress.remove(taskId);
      return fallback('host_state_unavailable');
    }
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
      identity == null
          ? 0
          : _identityEpochs.putIfAbsent(identity, () => ++_nextIdentityEpoch),
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
        .putIfAbsent(
          key,
          () => _run(task, state, selectedMode, identity, epoch),
        )
        .then((value) async {
          final live = repository.task(task.id)!;
          final now = await _sourceState(live);
          var current = value;
          final request = value.request;
          final sameHost = _sameHost(now, state);
          final closed =
              _cancelledTasks.contains(task.id) ||
              live.state.name == 'cancelled' ||
              live.state.name == 'interrupted';
          final drifted =
              epoch != _epoch ||
              request == null ||
              !isCurrentRequest(request) ||
              !enabled ||
              !(allowsPresentation?.call(taskId) ?? true) ||
              presentationIdentity?.call(taskId) != identity ||
              mode != selectedMode;
          if (drifted) {
            current = fallback(
              _revocationCode(taskId, 'host_state_changed'),
              request,
            );
            if (epoch == _epoch &&
                request != null &&
                isCurrentRequest(request)) {
              _dropTask(taskId, request);
            }
          } else if (closed && !sameHost) {
            // The task is closed and the facts themselves are no longer readable.
            current = fallback('host_state_changed', request);
            _dropTask(taskId, request);
            repository.refresh();
          } else if (closed && _terminalResults.containsKey(request)) {
            // Cancellation can settle while the final host source is awaited.
            // Retain that terminal readonly result instead of the old success.
            current = await _terminalResults[request]!;
          } else if (closed) {
            current = _readOnlyFailure(
              'cancelled',
              request,
              _progressFor(request),
            );
          } else if (!sameHost) {
            current = fallback('host_state_changed', request);
            if (isCurrentRequest(request)) {
              _dropTask(taskId, request);
            }
          } else if (value.result.plan != null) {
            final allowed = now!.allowedActionRefs.intersection(
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
              // Narrowed actions revoke execution only. The identity and the
              // last read-only preview stay attached.
              current = _readOnlyFailure(
                'current_authority_changed',
                request,
                _progressFor(request),
              );
            }
          }
          if (epoch == _epoch &&
              value.request != null &&
              isCurrentRequest(value.request!) &&
              mode == selectedMode &&
              identical(identity, presentationIdentity?.call(taskId)) &&
              (allowsPresentation?.call(taskId) ?? true)) {
            _latest[task.id] = current;
            repository.refresh();
          }
          return current;
        });
  }

  Future<UiPlannedPresentation> _run(
    PersonalTask task,
    UiPlanningHostState state,
    UiPlanningMode selectedMode,
    Object? identity,
    int epoch,
  ) async {
    final stepAnswer =
        ((task.payload['step'] as Map?)?['assistant'] as Map?)?['content'];
    final history = modelToolHistory(
      task.payload['messages'] as List? ?? const [],
    );
    // Derivation provenance comes from the persisted host checkpoint, not the
    // already filtered requestView (which intentionally drops the legacy flag).
    // Keep local summaries/steps unchanged; suppress only this model projection.
    final hasUnclassifiedToolAnswer =
        history.hadLegacyResult ||
        (task.profileId == null && task.payload['toolCall'] != null);
    final answer = hasUnclassifiedToolAnswer
        ? '此前工具派生内容未登记披露，已省略'
        : task.state == PersonalTaskState.succeeded
        ? task.summary ?? ''
        : stepAnswer is String
        ? stepAnswer
        : task.summary ?? '';
    if (answer.trim().isEmpty) return fallback('answer_unavailable');
    final messages = [
      for (final m in modelToolHistory(
        requestView?.call(task) ?? history.messages,
      ).messages)
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
      modelDisclosedFactRefs: state.modelDisclosedFactRefs,
      modelDisclosedComputedRefs: state.modelDisclosedComputedRefs,
      modelDisclosedUiStateRefs: state.modelDisclosedUiStateRefs,
      intent: intent,
      currentView: state.currentView,
      catalog: state.catalog,
      allowedActionRefs: allowed,
      mode: selectedMode,
      guideEntries: entries,
    );
    final provider = providers[selectedMode];
    if (epoch != _epoch ||
        !enabled ||
        !(allowsPresentation?.call(task.id) ?? true) ||
        !identical(identity, presentationIdentity?.call(task.id))) {
      return fallback(
        _revocationCode(task.id, 'host_request_changed'),
        request,
      );
    }
    _requestIdentities[request] = identity;
    _activeRequests[task.id] = request;
    if (_cancelledTasks.contains(task.id) ||
        repository.task(task.id)?.state.name == 'cancelled' ||
        repository.task(task.id)?.state.name == 'interrupted') {
      return _readOnlyFailure('cancelled', request);
    }
    if (provider == null) {
      return _readOnlyFailure('provider_unavailable', request);
    }
    _requestProviders[request] = provider;
    try {
      final supplied = await provider
          .plan(request)
          .timeout(
            timeout,
            onTimeout: () async {
              await cancelTimedOutRequest?.call(request);
              throw TimeoutException('UI planning deadline expired', timeout);
            },
          );
      if (!isCurrentRequest(request)) {
        return fallback(
          _revocationCode(task.id, 'host_request_changed'),
          request,
        );
      }
      if (_closedRequests.contains(request)) {
        return await _terminalResults[request] ??
            _latest[task.id] ??
            _readOnlyFailure('cancelled', request, _progressFor(request));
      }
      final progress = _progressFor(request);
      if (progress != null) {
        _streamProgress[task.id] = progress;
        await _recordProgress(request, progress);
      }
      if (supplied.errors.isNotEmpty) {
        return fallback('invalid_decision', request);
      }
      final result = provider is StreamMotivationUiPlanningProvider
          ? supplied
          : UiPlanningReason.modelResult(supplied);
      if (result.plan == null) {
        if (provider is StreamMotivationUiPlanningProvider &&
            result.reasonCode == 'model_no_card') {
          _streamProgress.remove(task.id);
        }
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
      final now = await _sourceState(repository.task(task.id)!);
      if (now == null ||
          now.snapshot.ref != state.snapshot.ref ||
          now.currentView.surfaceId != state.currentView.surfaceId ||
          now.currentView.revision != state.currentView.revision ||
          now.catalog.version != state.catalog.version) {
        return fallback('host_state_changed', request);
      }
      if (!now.allowedActionRefs.containsAll(allowed)) {
        return _readOnlyFailure('current_authority_changed', request, progress);
      }
      if (!isCurrentRequest(request)) {
        return fallback(
          _revocationCode(task.id, 'host_request_changed'),
          request,
        );
      }
      if (_closedRequests.contains(request)) {
        return await _terminalResults[request] ??
            _latest[task.id] ??
            _readOnlyFailure('cancelled', request, _progressFor(request));
      }
      return UiPlannedPresentation(
        result,
        request,
        checked.validatedPlan,
        stream: provider is StreamMotivationUiPlanningProvider
            ? provider.progressFor(request)
            : null,
      );
    } on TimeoutException {
      _closedRequests.add(request);
      if (!isCurrentRequest(request)) {
        return fallback(
          _revocationCode(task.id, 'host_request_changed'),
          request,
        );
      }
      if (_cancelledTasks.contains(task.id)) {
        return await _terminalResults[request] ??
            _latest[task.id] ??
            _readOnlyFailure('cancelled', request, _progressFor(request));
      }
      final value = _readOnlyFailure(
        'planner_timeout',
        request,
        _progressFor(request),
      );
      await _recordProgress(request, value.stream, code: 'incomplete');
      repository.refresh();
      return value;
    } catch (_) {
      _closedRequests.add(request);
      if (!isCurrentRequest(request)) {
        return fallback(
          _revocationCode(task.id, 'host_request_changed'),
          request,
        );
      }
      if (_cancelledTasks.contains(task.id)) {
        return await _terminalResults[request] ??
            _latest[task.id] ??
            _readOnlyFailure('cancelled', request, _progressFor(request));
      }
      final progress = _progressFor(request);
      final code = progress?.failureCode ?? 'planner_unavailable';
      final value = _readOnlyFailure(code, request, progress);
      await _recordProgress(request, value.stream, code: code);
      repository.refresh();
      return value;
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
    return UiPlanningReason.modelResult(
      UiPlanningResult(
        decision: UiDisplayDecision.values.byName(j['decision'] as String),
        reasonCode: j['reasonCode'] as String,
        plan: j['plan'] == null
            ? null
            : decodeUiPresentation(Map<String, dynamic>.from(j['plan'] as Map)),
      ),
    );
  }
}
