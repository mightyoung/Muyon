import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import '../platform/foundation_repository.dart';
import '../platform/task_records.dart';
import '../services/models/model_gateway.dart';
import '../services/models/model_provider.dart';
import '../platform/tool_registry.dart';
import '../platform/grants/outbound_content_reviewer.dart';
import '../platform/grants/host_tool_authorization.dart';
import '../platform/grants/host_authorization_facts.dart';
import 'agent_budget.dart';
import 'agent_drafts.dart';
import 'agent_event_sink.dart';
import 'context_compactor.dart';
import 'model_request_gate.dart';
import 'request_view.dart';
import 'tool_selection.dart';

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
    required this.executionDeviceId,
    required this.budget,
    required this.events,
    required this.selectionStrategy,
    required this.gate,
    required this.provider,
    required this.compactor,
    required this.compactionProfile,
    required this.clock,
  });

  final FoundationRepository repository;
  final OpenAiModelGateway gateway;
  final ToolRegistry tools;
  final OutboundContentReviewer? toolReviewer;
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
      if (c['disposition'] == 'card') c,
  ];

  /// The messages a request is built from: the stored conversation, or the
  /// compacted view of it (ADR-0005 §6.6). Preview, digest and what is sent
  /// all come from this one function.
  List<Object?> view(PersonalTask task) => buildRequestView(
    task.payload['messages'] as List,
    compactionState: task.payload['compaction'],
    references: task.payload['references'] as List? ?? const [],
  );

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
      assistantAnswer: answer,
      references: refs,
      canCommit: canCommit,
    );
    if (saved) {
      await repository.notify(
        title: '助手任务完成',
        body: answer.length > 160 ? answer.substring(0, 160) : answer,
        taskId: task.id,
      );
    }
  }

  Future<void> fail(PersonalTask task, String message, {String? code}) async {
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
