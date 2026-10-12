import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_module_api/ui_contract.dart' show ModelReferenceMap;

import '../platform/foundation_repository.dart';
import '../platform/task_records.dart';
import '../services/models/model_gateway.dart';
import '../services/models/model_provider.dart';
import '../platform/tool_registry.dart';
import '../platform/grants/outbound_content_reviewer.dart';
import '../platform/grants/host_model_authorization.dart';
import '../platform/grants/host_tool_authorization.dart';
import '../platform/grants/host_authorization_facts.dart';
import 'agent_budget.dart';
import 'agent_drafts.dart';
import 'agent_event_sink.dart';
import 'context_compactor.dart';
import 'model_request_gate.dart';
import 'request_view.dart';
import 'model_tool_result_projection.dart';
import 'tool_selection.dart';
import 'ui_planning.dart';

/// State and helpers shared by the collaborators of [PersonalAgent]: the
/// repository, gateway, cancellation tokens, `closing` flag and operation
/// table, plus the payload helpers and the terminal writes (`finish`, `fail`,
/// `settle`) every stage uses.
class AgentContext {
  AgentContext({
    required this.repository,
    required this.gateway,
    required this.tools,
    this.toolReviewer,
    this.modelAuthorization,
    required this.executionDeviceId,
    required this.budget,
    required this.events,
    required this.selectionStrategy,
    required this.gate,
    required this.provider,
    required this.compactor,
    required this.compactionProfile,
    required this.clock,
    this.uiPlanning,
  });

  final FoundationRepository repository;
  final OpenAiModelGateway gateway;
  final ToolRegistry tools;
  final OutboundContentReviewer? toolReviewer;
  final HostModelAuthorization? modelAuthorization;
  // Invocation ownership is created by the live dispatcher, not task/model JSON.
  final invocationTasks = <String, String>{};
  final invocationRequests = <String, ToolCallRequest>{};
  final toolReviews = <String, HostReviewOutcome>{};
  HostTaskFacts? factsFor(ToolCallRequest request) {
    final id = invocationTasks[request.invocationId];
    return id == null || repository.task(id) == null
        ? null
        : repository.authorizationFacts.readTask(id);
  }

  late final HostToolAuthorization? toolAuthorization = toolReviewer == null
      ? null
      : HostToolAuthorization(
          registry: tools,
          reviewer: toolReviewer!,
          taskFacts: factsFor,
        );

  final String executionDeviceId;
  final Budget budget;
  final AgentEventSink events;
  final DateTime Function() clock;
  UiPlanningHarness? uiPlanning;
  final uiModelChunks = <String, void Function(String)>{};
  final uiModelReplies = <String, Completer<String>>{};
  final uiModelChecks = <String, Future<void> Function()>{};
  final ToolSelectionStrategy selectionStrategy;
  final ModelRequestGate gate;
  final ModelProvider provider;
  final ContextCompactor compactor;
  final ModelProfile? compactionProfile;

  /// Drafts of replies being streamed (memory only; see agent_drafts.dart).
  final drafts = AgentDrafts();
  final modelTokens = <String, ModelCancellation>{};
  final toolTokens = <String, ToolCancellationToken>{};

  /// Tasks whose tool call is under way (between dispatch and the registry's
  /// receipt). Cancelling one of these only signals; the receipt decides.
  final toolActive = <String>{};
  final cancelRequested = <String>{};
  final operations = <String, Future<void>>{};
  bool closing = false;
  final activeStarts = <Future<PersonalTask>>{};

  List<Map<String, Object?>> memories(AssistantScope scope) => [
    for (final m in repository.memoriesFor(scope))
      {
        "id": m.id,
        "content": m.content,
        "source": m.source,
        "revision": m.revision,
        "scope": m.scope.toJson(),
      },
    for (final experience in repository.experiencesFor(scope))
      {
        "id": experience.id,
        "content": experience.content,
        "source": experience.source,
        "revision": experience.revision,
        "scope": experience.scope.toJson(),
        "kind": "experience",
      },
  ];
  static String digest(Object? value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();

  ModelProfile profile(PersonalTask task) {
    final p = task.payload['profile'] as Map;
    return ModelProfile(
      id: p['id'] as String,
      endpoint: Uri.parse(p['endpoint'] as String),
      location: ModelLocation.values.byName(p['location'] as String),
      modelId: p['modelId'] as String,
      endpointIdentity: p['endpointIdentity'] as String,
      credentialRef: p['credentialRef'] as String?,
      cloudProxy: p['cloudProxy'] == true,
      purpose: ModelPurpose.values.byName(p['purpose'] as String? ?? 'chat'),
      capabilities: ModelCapabilities.fromJson(p['capabilities']),
    );
  }

  static bool native(PersonalTask task) =>
      task.payload['uiPlanningStream'] != true &&
      ((task.payload['profile'] as Map?)?['capabilities']
              as Map?)?['nativeTools'] ==
          true;

  /// Compatibility mode previews exactly what it always did: the profile
  /// without the capability block, so the confirmed digest does not change.
  Object? previewProfile(PersonalTask task) {
    final profile = task.payload['profile'];
    if (native(task) ||
        profile is! Map ||
        !profile.containsKey('capabilities')) {
      return profile;
    }
    return <String, Object?>{
      for (final e in profile.entries)
        if (e.key != 'capabilities') e.key as String: e.value,
    };
  }

  /// The calls of the step in the model's order, as typed JSON maps (a
  /// payload only accepts those).
  static List<Map<String, Object?>> calls(PersonalTask task) => [
    for (final c
        in (task.payload['step'] as Map?)?['calls'] as List? ?? const [])
      Map<String, Object?>.from(c as Map),
  ];

  static List<Map<String, Object?>> cardCalls(PersonalTask task) => [
    for (final c in calls(task))
      if (c['disposition'] == 'card' && c['outcome'] == null) c,
  ];

  /// The messages a request is built from: the stored conversation, or the
  /// compacted view of it (ADR-0005 §6.6). Preview, digest and what is sent
  /// all come from this one function.
  List<Object?> view(PersonalTask task) {
    final history = modelTaskToolHistory(task, tools);
    return projectModelMessages(
      task,
      buildRequestView(
        history.messages,
        compactionState: modelCompaction(task),
        references: task.payload['references'] as List? ?? const [],
      ),
    );
  }

  final _referenceMaps = <String, ModelReferenceMap>{};
  var _referenceEpoch = 0;
  bool _referenceListening = false;
  void _referenceAuthorityChanged() {
    _referenceEpoch++;
    for (final map in _referenceMaps.values) {
      map.expire();
    }
    _referenceMaps.clear();
  }

  void closeModelReferences() {
    _referenceAuthorityChanged();
    if (_referenceListening) {
      repository.authorizationFacts.removeListener(_referenceAuthorityChanged);
      _referenceListening = false;
    }
  }

  // This is a host cache identity, never a field sent to a model. Grant use or
  // creation must not remint preview aliases; revocation invalidates them.
  String _referenceAuthority() {
    final db = repository.database.raw;
    final exists = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='assistant_grant_audit'",
    );
    final revoked = exists.isEmpty
        ? 0
        : db
              .select(
                "SELECT COALESCE(MAX(id),0) AS generation FROM assistant_grant_audit WHERE action='revoked'",
              )
              .single['generation'];
    return digest([
      _referenceEpoch,
      modelAuthorization?.policy.current.revision,
      revoked,
    ]);
  }

  ({Set<ObjectRef> objects, List<ArtifactRef> artifacts}) _hostReferencePins(
    PersonalTask task,
  ) {
    final objects = <ObjectRef>{...task.scope.objects};
    final artifacts = <ArtifactRef>[];
    for (final ref in task.payload['references'] as List? ?? const []) {
      objects.add(objectRefFromJson(Map<String, Object?>.from(ref as Map)));
    }
    for (final memory in memories(task.scope)) {
      final scope = AssistantScope.fromJson(
        Map<String, Object?>.from(memory['scope'] as Map),
      );
      objects.addAll(scope.objects);
    }
    final sources = task.payload['modelResultProducers'];
    if (sources is Map) {
      for (final entry in sources.entries) {
        final metadata = entry.value;
        if (entry.key is! String || metadata is! Map) continue;
        final receipt = tools.receiptFor(entry.key as String);
        final producer = receipt == null ? null : tools.inspect(receipt.toolId);
        if (receipt?.result == null ||
            receipt!.toolId != metadata['toolId'] ||
            receipt.identityDigest != metadata['identityDigest'] ||
            producer?.providerId != metadata['providerId']) {
          continue;
        }
        objects.addAll(receipt.result!.objectRefs);
        artifacts.addAll(receipt.result!.artifactRefs);
      }
    }
    return (objects: objects, artifacts: artifacts);
  }

  String _referenceSnapshot(PersonalTask task) {
    final pins = _hostReferencePins(task);
    return digest([
      task.scope.toJson(),
      [for (final ref in pins.objects) ref.toJson()],
      [
        for (final ref in pins.artifacts)
          {
            'moduleId': ref.moduleId,
            'artifactId': ref.artifactId,
            'contentDigest': ref.contentDigest,
          },
      ],
      _referenceAuthority(),
    ]);
  }

  /// The UI planner, normal turns and summarizer share this exact table.
  ModelReferenceMap modelReferences(PersonalTask task) {
    if (closing) throw StateError('model_reference_unavailable');
    if (!_referenceListening) {
      repository.authorizationFacts.addListener(_referenceAuthorityChanged);
      _referenceListening = true;
    }
    final snapshot = _referenceSnapshot(task);
    final scope = digest(task.scope.toJson());
    final previous = _referenceMaps[task.id];
    if (previous != null &&
        previous.snapshotKey == snapshot &&
        previous.scopeKey == scope) {
      return previous;
    }
    previous?.expire();
    final pins = _hostReferencePins(task);
    final loaded = repository.task(task.id);
    final loadedSnapshot = loaded == null
        ? snapshot
        : _referenceSnapshot(loaded);
    var committed = loadedSnapshot == snapshot;
    final map = ModelReferenceMap(
      taskId: task.id,
      scopeKey: scope,
      snapshotKey: snapshot,
      objects: pins.objects,
      artifacts: pins.artifacts,
      isCurrent: () {
        if (closing) return false;
        final current = repository.task(task.id) ?? task;
        final currentSnapshot = _referenceSnapshot(current);
        if (currentSnapshot == snapshot) {
          committed = true;
          return true;
        }
        // The dispatcher estimates a folded host result before committing it.
        // Admit exactly that immutable prior snapshot until the new one lands;
        // thereafter any changed scope/pin/authority invalidates this table.
        return !committed && currentSnapshot == loadedSnapshot;
      },
    );
    _referenceMaps[task.id] = map;
    return map;
  }

  String modelReferenceBinding(PersonalTask task) {
    final map = modelReferences(task);
    final pins = _hostReferencePins(task);
    return digest([
      for (final ref in pins.objects) map.projectObject(ref),
      for (final ref in pins.artifacts) map.projectArtifact(ref),
    ]);
  }

  bool modelReferenceBindingCurrent(PersonalTask task, Object? binding) {
    final cached = _referenceMaps[task.id];
    if (cached == null || cached.snapshotKey != _referenceSnapshot(task)) {
      return false;
    }
    try {
      return modelReferenceBinding(task) == binding;
    } on StateError {
      return false;
    }
  }

  Object? modelCompaction(PersonalTask task) {
    final stored = task.payload['compaction'];
    if (stored is Map &&
        stored['summary'] != null &&
        task.payload['compactionReferencePolicy'] != 1) {
      return null;
    }
    return modelTaskToolHistory(task, tools).compaction(stored);
  }

  List<Object?> modelHistoryMessages(PersonalTask task) =>
      projectModelMessages(task, modelTaskToolHistory(task, tools).messages);

  /// Only host-created frames are decoded. Genuine user text, including JSON,
  /// retains its existing policy. Projection follows citation replay as well.
  List<Object?> projectModelMessages(
    PersonalTask task,
    List<Object?> messages, {
    bool summaryRequest = false,
  }) {
    final map = modelReferences(task);
    final original = task.payload['messages'] as List? ?? const [];
    final human = <Object?>{
      if (task.payload['uiPlanningInternal'] != true) task.prompt,
      for (final index
          in task.payload['modelUserMessageIndices'] as List? ?? const [])
        if (index is int &&
            index >= 0 &&
            index < original.length &&
            original[index] is Map)
          (original[index] as Map)['content'],
    };
    final compaction = modelCompaction(task);
    final summary = compaction is Map && compaction['summary'] is Map
        ? (compaction['summary'] as Map)['content']
        : null;
    return modelReferenceMessages(
      messages,
      map,
      explicitUserContents: human,
      hostResultContents: {
        if (modelHostManualToolTask(task))
          for (final message in modelTaskToolHistory(task, tools).messages)
            if (message is Map) message['content'],
      },
      hostSummaryContents: {?summary},
      summaryRequest: summaryRequest,
    );
  }

  List<ObjectRef> references(PersonalTask task) => [
    for (final r in task.payload['references'] as List)
      objectRefFromJson(Map<String, Object?>.from(r as Map)),
  ];

  Future<void> finish(
    PersonalTask task,
    String answer,
    List<ObjectRef> refs, {
    bool Function()? canCommit,
  }) async {
    if (answer.trim().isEmpty) throw const FormatException('Empty answer');
    final saved = await commit(
      task.copy({
        'state': 'succeeded',
        'stage': 'completed',
        'waitingFor': null,
        'summary': answer,
        'references': refs.map((r) => r.toJson()).toList(),
      }),
      events: [
        (AgentEventType.done, {'chars': answer.length}),
      ],
      assistantAnswer: task.payload['uiPlanningInternal'] == true
          ? null
          : answer,
      references: refs,
      canCommit: canCommit,
    );
    if (saved) {
      uiModelReplies[task.id]?.complete(answer);
      if (uiPlanning?.enabled == true &&
          task.payload['uiPlanningDisabled'] != true) {
        UiPlannedPresentation presentation;
        try {
          presentation =
              await uiPlanning?.plan(task.id) ??
              UiPlanningHarness.fallback('planning_disabled');
        } catch (_) {
          presentation = UiPlanningHarness.fallback('planner_unavailable');
        }
        await event(task, 'ui_planning', {
          'decision': presentation.result.decision.name,
          'reasonCode': presentation.reason.code,
          'reasonDescription': presentation.reason.description,
          'reasonCategory': presentation.reason.category.name,
          'surfaceId': presentation.validated?.plan.surfaceId,
          'revision': presentation.validated?.plan.revision,
        });
      }
      if (task.payload['uiPlanningInternal'] == true) return;
      await repository.notify(
        title: '助手任务完成',
        body: answer.length > 160 ? answer.substring(0, 160) : answer,
        taskId: task.id,
      );
    }
  }

  Future<void> fail(PersonalTask task, String message, {String? code}) async {
    final reply = uiModelReplies[task.id];
    if (reply != null && !reply.isCompleted) {
      reply.completeError(StateError('planning_model_failed'));
    }
    if (await commit(
      task.copy({'state': 'failed', 'stage': 'failed', 'error': message}),
      events: [
        (AgentEventType.error, {'code': ?code, 'reason': message}),
      ],
    )) {
      await repository.notify(title: '助手任务未完成', body: message, taskId: task.id);
    }
  }

  /// Writes the new state of a task together with the events that go with
  /// it. With a [TransactionalEventSink] they are one transaction (a failed
  /// event write undoes the state change); with another sink the state is
  /// written first and the events follow, and a sink that cannot write does
  /// not change what the task does. False: the state was not written.
  Future<bool> commit(
    PersonalTask next, {
    List<(String, Map<String, Object?>)> events = const [],
    Set<PersonalTaskState>? expected,
    bool Function()? canCommit,
    String? assistantAnswer,
    List<ObjectRef> references = const [],
    bool keepStage = false,
  }) async {
    final step = BudgetUsage.fromPayload(next.payload).steps;
    final sink = this.events;
    final together = sink is TransactionalEventSink;
    final saved = await repository.updateTask(
      next.withEvents([
        if (together)
          for (final e in events) TaskEventDraft(e.$1, step: step, data: e.$2),
      ], keepStage: keepStage),
      expected: expected,
      canCommit: canCommit,
      assistantAnswer: assistantAnswer,
      references: references,
    );
    if (saved && !together) {
      for (final e in events) {
        await event(next, e.$1, e.$2);
      }
    }
    return saved;
  }

  /// Writes to the event sink. A sink that cannot write must not change what
  /// the task does.
  Future<void> event(
    PersonalTask task,
    String type, [
    Map<String, Object?> data = const {},
  ]) async {
    try {
      await events.append(
        task.id,
        AgentEvent(
          type,
          step: BudgetUsage.fromPayload(task.payload).steps,
          data: data,
        ),
      );
    } catch (_) {}
  }

  /// Final state of a running task from a tool outcome. Guarded so it cannot
  /// overwrite a state another path already wrote.
  Future<void> settle(
    PersonalTask task,
    PersonalTaskState state,
    String? error,
  ) async {
    final saved = await commit(
      task.copy({
        'state': state.name,
        'stage': state.name,
        'waitingFor': null,
        'error': ?error,
      }),
      events: [
        if (state == PersonalTaskState.cancelled)
          (AgentEventType.cancel, <String, Object?>{}),
        if (state == PersonalTaskState.interrupted)
          (AgentEventType.error, {'code': 'interrupted'}),
      ],
      expected: {PersonalTaskState.running},
    );
    if (saved && state == PersonalTaskState.interrupted) {
      if (task.payload['uiPlanningInternal'] == true) return;
      await repository.notify(
        title: '助手任务结果未知',
        body: error ?? '',
        taskId: task.id,
      );
    }
  }
}

/// One response, collected. A tool call in it is acted on only after [done].
class Reply {
  final text = StringBuffer();
  final calls = <ToolCallComplete>[];

  /// Charged to the token budget (`_bill`).
  Usage? usage;
  Done? done;
  ModelError? error;

  /// Length and digest of the draft the person was shown (never its text);
  /// null when no draft was shown (a request that is not a chat reply).
  ({int length, String digest})? draft;
}

/// A failure with a fixed code and text; never carries model or endpoint text.
class FixedFailure implements Exception {
  const FixedFailure(this.code, this.message);
  final String code, message;
  @override
  String toString() => code;
}

/// A call the model asked for, before the host has prepared it.
class Planned {
  const Planned(this.toolId, this.parameters, {this.destination, this.callId});
  final String toolId;
  final Map<String, Object?> parameters;
  final String? destination;

  /// The model's id for it (native mode), used only to pair the result.
  final String? callId;
}

enum RunKind { ran, cancelled, abandoned }

/// What one `ToolRegistry.invoke` came to, before the task is settled.
class Run {
  const Run.ran(ToolCallResult this.result) : kind = RunKind.ran;

  /// Stopped before dispatch: nothing ran.
  const Run.cancelled() : kind = RunKind.cancelled, result = null;

  /// The task ended meanwhile or the host is closing; someone else settled it.
  const Run.abandoned() : kind = RunKind.abandoned, result = null;
  final RunKind kind;
  final ToolCallResult? result;
}
