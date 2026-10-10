part of 'agent_eval.dart';

// ----------------------------------------------------------------- runner

class AgentTaskResult {
  const AgentTaskResult({
    required this.task,
    required this.verdict,
    required this.state,
    required this.modelConfirmations,
    required this.toolApprovals,
    required this.rounds,
    required this.requests,
    required this.totalMs,
    required this.proposedTools,
    this.maxRounds = 0,
    this.firstResponseMs,
    this.promptTokens,
    this.completionTokens,
    this.error,
    this.writeStateErrors = const [],
  });
  final AgentTask task;
  final AgentVerdict verdict;
  final String state;
  final int modelConfirmations, toolApprovals, rounds, requests;
  final int maxRounds;
  final double totalMs;

  /// Null when no model request completed.
  final double? firstResponseMs;

  /// Null when the endpoint reported no usage.
  final int? promptTokens, completionTokens;
  final String? error;
  final List<String> proposedTools;
  final List<String> writeStateErrors;
  bool get success => verdict.success;
  int get confirmations => modelConfirmations + toolApprovals;
}

/// Model side of a run. [fixture] says the endpoint is a scripted loopback
/// fixture; such a run is never written as a model report.
class AgentEvalModel {
  const AgentEvalModel({
    required this.profile,
    required this.secrets,
    required this.fixture,
    this.timeout = const Duration(seconds: 45),
  });
  final ModelProfile profile;
  final SecretStore secrets;
  final bool fixture;
  final Duration timeout;
}

/// Seeds the opened inquiry store and returns the ids by seed key (see
/// `seedKeys` in the task set).
typedef AgentSeeder = Map<String, String> Function(Store store);

typedef AgentTaskHook = Future<void> Function(
  AgentTask task,
  Map<String, String> ids,
);

class AgentEvalRun {
  const AgentEvalRun({
    required this.model,
    required this.results,
    required this.startedAt,
  });
  final AgentEvalModel model;
  final List<AgentTaskResult> results;
  final DateTime startedAt;
  bool get fixture => model.fixture;

  /// The assistant's round limit, as the runs saw it.
  int get maxRounds =>
      results.map((r) => r.maxRounds).fold(0, (a, b) => a > b ? a : b);
  int get successes => results.where((r) => r.success).length;
}

/// Runs [task] on a fresh host under [rootPath] and scores it. Never throws
/// for a model or task failure; that is the result.
Future<AgentTaskResult> runAgentTask({
  required AgentTask task,
  required AgentEvalModel model,
  required AgentSeeder seed,
  required String rootPath,
  AgentTaskHook? beforeTask,
}) async {
  final host = await MuyonHost.open(rootPath);
  PersonalAgent? agent;
  try {
    await host.activateInquiry();
    final store = host.inquiry?.runtime.state.store;
    if (store == null) throw StateError(host.inquiryError ?? 'inquiry');
    final ids = seed(store);
    final before = snapshotStore(store);
    final gateway = RecordingGateway(
      model.secrets,
      timeout: model.timeout,
      ledger: host.outbound,
    );
    agent = PersonalAgent(
      repository: host.foundation,
      gateway: gateway,
      tools: host.tools,
      executionDeviceId: 'agent-eval',
      // Evaluation remains manual, but real local intents still require the
      // host's local review proof before each actual domain write.
      toolReviewer: host.personalAgent.toolReviewer,
    );
    await beforeTask?.call(task, ids);

    final scope = task.scopeKind == 'global'
        ? const AssistantScope.global()
        : AssistantScope.selectedObjects(
            await _selected(host, [for (final k in task.scopeObjects) ids[k]!]),
          );
    final conversation = await host.foundation.createConversation(
      title: task.id,
      scope: scope,
    );

    final watch = Stopwatch()..start();
    var modelConfirmations = 0, toolApprovals = 0;
    var rejected = false;
    String? driveError;
    final expectedWrites = [for (final w in task.expectedWrites) w.tool];
    final approved = <String>[];
    var current = await agent.start(
      conversationId: conversation.id,
      prompt: task.promptFor(ids),
      profile: model.profile,
    );
    var guard = 0;
    while (!current.terminal) {
      if (++guard > 3 * agent.maxRounds) {
        driveError = 'task did not settle (${current.state.name})';
        break;
      }
      if (current.state != PersonalTaskState.waitingConfirmation) {
        driveError = 'unexpected ${current.state.name}/${current.stage}';
        break;
      }
      final digest = current.payload['requestDigest'] as String;
      try {
        if (confirmsAsModelRequest(current.stage)) {
          // A summary request is a model request the person confirms.
          await agent.confirm(current.id, requestDigest: digest);
          modelConfirmations++;
        } else {
          final toolId =
              (current.payload['toolCall'] as Map)['toolId'] as String;
          // The person approves only the writes the task is about, each once.
          // Approval is by tool id and count only: it does not check the
          // arguments. A wanted write with wrong arguments is approved and
          // executed, and is then caught by the post-state check as
          // `write_mismatch`, not here.
          final wanted = _minus(expectedWrites, approved).contains(toolId);
          if (!wanted) {
            await agent.cancel(current.id);
            rejected = true;
          } else {
            await agent.confirm(current.id, requestDigest: digest);
            approved.add(toolId);
            toolApprovals++;
          }
        }
      } catch (error) {
        driveError = redactCredentials(error);
        break;
      }
      current = host.foundation.task(current.id)!;
    }
    watch.stop();

    final proposed = _proposedTools(current);
    bool isWrite(String toolId) =>
        host.tools.inspect(toolId)?.accessLevel != ToolAccessLevel.read;
    final receipts = [
      for (final row in host.foundation.database.raw.select(
        'SELECT tool_id, state FROM tool_invocation_receipts ORDER BY rowid',
      ))
        if (row['state'] == 'succeeded' && isWrite(row['tool_id'] as String))
          row['tool_id'] as String,
    ];
    final stateErrors = [
      for (final w in task.expectedWrites)
        ...checkWriteState(store, w.check, ids, before),
    ];
    final after = snapshotStore(store);
    final changed =
        before.length != after.length ||
        before.entries.any((e) => after[e.key] != e.value);
    final succeeded = current.state == PersonalTaskState.succeeded;
    // `scope_pinned` only when the call the model proposed last is a
    // registered tool whose parameters pass the tool's schema and the pinned
    // scope is what rejects it. `prepare` is read-only and checks, in order,
    // registration, availability, scope kind and parameter schema before it
    // resolves the scope; so a StateError "Selected object is missing" from
    // it means all of those passed. A parameter, availability or unknown-tool
    // failure keeps `request_failed`, since the agent reports all of them
    // with one generic message.
    var scopePinned = false;
    final proposal = _lastProposal(current);
    if (current.state == PersonalTaskState.failed &&
        receipts.isNotEmpty &&
        proposal != null &&
        host.tools.inspect(proposal.$1) != null &&
        (current.error ?? '').contains('范围校验')) {
      try {
        await host.tools.prepare(
          ToolCallRequest(
            invocationId: 'scope-probe',
            toolId: proposal.$1,
            scope: scope,
            parameters: proposal.$2,
          ),
        );
      } on StateError catch (error) {
        scopePinned = '$error'.contains('Selected object is missing');
      } catch (_) {}
    }
    final observation = AgentObservation(
      state: current.state.name,
      error: driveError ?? current.error,
      rejectedWrite: rejected,
      proposedTools: proposed,
      proposedWrites: proposed.where(isWrite).toList(),
      appliedWrites: receipts,
      answer: succeeded ? current.summary : null,
      writeStateErrors: stateErrors,
      storeChanged: changed,
      scopePinned: scopePinned,
    );
    final ok = gateway.calls.where((c) => c.ok).toList();
    final usage = ok.where(
      (c) => c.promptTokens != null || c.completionTokens != null,
    );
    return AgentTaskResult(
      task: task,
      verdict: judgeTask(task, observation),
      state: current.state.name,
      modelConfirmations: modelConfirmations,
      toolApprovals: toolApprovals,
      rounds: current.payload['round'] as int? ?? 0,
      maxRounds: agent.maxRounds,
      requests: gateway.calls.length,
      totalMs: watch.elapsedMicroseconds / 1000,
      firstResponseMs: ok.isEmpty
          ? null
          : (ok.first.firstEventMs ?? ok.first.ms),
      promptTokens: usage.isEmpty
          ? null
          : usage.fold<int>(0, (s, c) => s + (c.promptTokens ?? 0)),
      completionTokens: usage.isEmpty
          ? null
          : usage.fold<int>(0, (s, c) => s + (c.completionTokens ?? 0)),
      error: _short(observation.error),
      proposedTools: proposed,
      writeStateErrors: stateErrors,
    );
  } catch (error) {
    // A setup or driver error is a failed task, not a crashed run.
    return AgentTaskResult(
      task: task,
      verdict: const AgentVerdict([AgentFailure.requestFailed]),
      state: 'failed',
      modelConfirmations: 0,
      toolApprovals: 0,
      rounds: 0,
      requests: 0,
      totalMs: 0,
      proposedTools: const [],
      error: _short(redactCredentials(error)),
    );
  } finally {
    try {
      await agent?.close();
    } catch (_) {}
    try {
      await host.close();
    } catch (_) {}
  }
}

String? _short(String? text) {
  if (text == null) return null;
  final flat = text.replaceAll(RegExp(r'\s+'), ' ');
  return flat.length > 160 ? '${flat.substring(0, 160)}…' : flat;
}

Future<List<ObjectRef>> _selected(MuyonHost host, List<String> ids) async {
  final all = await resolveAssistantScope(host, const AssistantScope.global());
  return [
    for (final ref in all.objects)
      if (ref.moduleId == 'inquiry' && ids.contains(ref.objectId)) ref,
  ];
}

/// The last tool call the model proposed: tool id and parameters.
(String, Map<String, Object?>)? _lastProposal(PersonalTask task) {
  (String, Map<String, Object?>)? last;
  for (final m in task.payload['messages'] as List? ?? const []) {
    if ((m as Map)['role'] != 'assistant') continue;
    if (_tryJson(m['content'] as String) case {
      'type': 'tool',
      'toolId': final String id,
      'parameters': final Map params,
    }) {
      last = (id, Map<String, Object?>.from(params));
    }
  }
  return last;
}

List<String> _proposedTools(PersonalTask task) => [
  for (final m in task.payload['messages'] as List? ?? const [])
    if ((m as Map)['role'] == 'assistant')
      if (_tryJson(m['content'] as String) case {
        'type': 'tool',
        'toolId': final String id,
      })
        id,
];

Object? _tryJson(String text) {
  try {
    return jsonDecode(text);
  } catch (_) {
    return null;
  }
}

/// Runs [tasks] one after another, each on its own fresh data directory under
/// [workRoot], so no task sees another's writes.
Future<AgentEvalRun> runAgentEval({
  required AgentEvalModel model,
  required AgentSeeder seed,
  required String workRoot,
  List<AgentTask>? tasks,
  AgentTaskHook? beforeTask,
  void Function(int done, int total)? onProgress,
}) async {
  final list = tasks ?? agentTasks;
  final startedAt = DateTime.now().toUtc();
  final results = <AgentTaskResult>[];
  for (final task in list) {
    results.add(
      await runAgentTask(
        task: task,
        model: model,
        seed: seed,
        rootPath: '$workRoot/${task.id}',
        beforeTask: beforeTask,
      ),
    );
    onProgress?.call(results.length, list.length);
  }
  return AgentEvalRun(model: model, results: results, startedAt: startedAt);
}
