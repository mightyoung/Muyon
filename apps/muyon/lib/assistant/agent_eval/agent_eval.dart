/// Multi-step task evaluation of the current assistant (E-1): the
/// "before phase 2" baseline.
///
/// Drives the existing [PersonalAgent] on a fresh [MuyonHost] per task, seeded
/// with the inquiry North Star data, and confirms like the person would: every
/// model round with the digest the host showed, every expected write once.
/// A write the task does not expect is rejected (the person says no), which
/// ends the task and scores as an extra write. Per task it records success,
/// manual confirmations (model requests and tool approvals counted
/// separately), rounds, total time, time to the first complete model response
/// and token usage.
///
/// Tasks: `agent_task_set.json` beside this file. Scoring is [judgeTask], a
/// pure function of what was observed.
///
/// Evidence: normal `flutter test` runs only a loopback fixture model scripted
/// by the test. A fixture run proves the harness and the scoring, never model
/// quality, and [agentEvalReport] refuses to write one. The real run needs
/// `MUYON_EVAL_REAL=1` plus `MUYON_EVAL_MODEL_ENDPOINT` and
/// `MUYON_EVAL_MODEL_ID` (a non-loopback endpoint also needs HTTPS and
/// `MUYON_EVAL_MODEL_KEY`, visible ASCII only). Optional:
/// `MUYON_EVAL_MODEL_TIMEOUT_SECONDS` (per request, default 45) and
/// `MUYON_WRITE_EVAL_REPORT=1`, which writes
/// `docs/implementation/agent-task-eval-<model slug>.md`; without it nothing
/// is written. The key is read from the environment only and is never printed
/// or written.
///
/// ```bash
/// cd apps/muyon
/// env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \
///   NO_PROXY=localhost,127.0.0.1,::1 \
///   MUYON_EVAL_REAL=1 \
///   MUYON_EVAL_MODEL_ENDPOINT=https://api.deepseek.com \
///   MUYON_EVAL_MODEL_ID=deepseek-chat \
///   MUYON_EVAL_MODEL_KEY="$DEEPSEEK_API_KEY" \
///   MUYON_WRITE_EVAL_REPORT=1 \
///   flutter test --no-pub test/agent_eval_test.dart --plain-name 'real model'
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';

import '../../app/bootstrap.dart';
import '../../platform/business_tools.dart';
import '../../platform/foundation_repository.dart';
import '../../services/models/credential_redaction.dart';
import '../../services/models/model_gateway.dart';
import '../personal_agent.dart';
import '../selection_eval/llm_selection_eval.dart'
    show llmReportSlug, reportEndpoint;

export '../selection_eval/llm_selection_eval.dart'
    show llmReportSlug, reportEndpoint;

const agentTaskCategories = ['read_single', 'read_multi', 'write', 'abstain'];

/// Failure codes of [judgeTask].
class AgentFailure {
  static const requestFailed = 'request_failed';
  static const toolMissing = 'tool_missing';
  static const toolOrder = 'tool_order';
  static const unexpectedTool = 'unexpected_tool';
  static const extraWrite = 'extra_write';
  static const writeMissing = 'write_missing';
  static const writeMismatch = 'write_mismatch';
  static const factMismatch = 'fact_mismatch';
  static const all = [
    requestFailed,
    toolMissing,
    toolOrder,
    unexpectedTool,
    extraWrite,
    writeMissing,
    writeMismatch,
    factMismatch,
  ];
}

/// A fact the final answer must state. A number compares as a decimal
/// (`2080` matches `2,080.00`); a text is a substring.
class AgentFact {
  const AgentFact.number(String this.number) : text = null;
  const AgentFact.text(String this.text) : number = null;
  final String? number, text;
  String get label => number ?? text!;
}

class AgentExpectedWrite {
  const AgentExpectedWrite({required this.tool, required this.check});
  final String tool;

  /// Post-state check: `kind` plus its fields, see [checkWriteState].
  final Map<String, Object?> check;
}

class AgentTask {
  const AgentTask({
    required this.id,
    required this.category,
    required this.prompt,
    required this.scopeKind,
    required this.scopeObjects,
    required this.expectedTools,
    required this.orderMatters,
    required this.noTools,
    required this.facts,
    required this.expectedWrites,
  });
  final String id, category, prompt;

  /// `global` or `selected`; [scopeObjects] are seed keys.
  final String scopeKind;
  final List<String> scopeObjects;
  final List<String> expectedTools;
  final bool orderMatters, noTools;
  final List<AgentFact> facts;
  final List<AgentExpectedWrite> expectedWrites;
  bool get expectsWrite => expectedWrites.isNotEmpty;

  /// The prompt with every `{key}` replaced by its seed id. An unknown key
  /// throws, so a typo cannot reach a model.
  String promptFor(Map<String, String> ids) => fillPlaceholders(prompt, ids);
}

String fillPlaceholders(String text, Map<String, String> ids) =>
    text.replaceAllMapped(RegExp(r'\{([a-z_]+)\}'), (m) {
      final id = ids[m[1]];
      if (id == null) throw StateError('Unknown placeholder {${m[1]}}');
      return id;
    });

class AgentTaskSet {
  const AgentTaskSet(this.seedKeys, this.tasks);
  final List<String> seedKeys;
  final List<AgentTask> tasks;
}

AgentTaskSet? _taskSet;

/// Checked-in tasks, loaded from `agent_task_set.json` beside this file.
AgentTaskSet loadAgentTaskSet() {
  final cached = _taskSet;
  if (cached != null) return cached;
  final decoded = jsonDecode(agentTaskSetFile().readAsStringSync());
  if (decoded is! Map) throw const FormatException('agent task set');
  return _taskSet = parseAgentTaskSet(decoded);
}

List<AgentTask> get agentTasks => loadAgentTaskSet().tasks;

AgentTaskSet parseAgentTaskSet(Map<dynamic, dynamic> decoded) {
  final keys = [for (final k in decoded['seedKeys'] as List) k as String];
  final tasks = [
    for (final raw in decoded['tasks'] as List)
      _task(Map<String, Object?>.from(raw as Map)),
  ];
  final seen = <String>{};
  for (final task in tasks) {
    if (!seen.add(task.id)) throw FormatException('duplicate ${task.id}');
    if (!agentTaskCategories.contains(task.category)) {
      throw FormatException('${task.id}: unknown category ${task.category}');
    }
    for (final m in RegExp(r'\{([a-z_]+)\}').allMatches(task.prompt)) {
      if (!keys.contains(m[1])) {
        throw FormatException('${task.id}: unknown placeholder ${m[0]}');
      }
    }
    for (final key in task.scopeObjects) {
      if (!keys.contains(key)) {
        throw FormatException('${task.id}: unknown scope key $key');
      }
    }
  }
  return AgentTaskSet(keys, tasks);
}

File agentTaskSetFile() {
  const names = [
    'lib/assistant/agent_eval/agent_task_set.json',
    'apps/muyon/lib/assistant/agent_eval/agent_task_set.json',
  ];
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    for (final name in names) {
      final file = File('${dir.path}/$name');
      if (file.existsSync()) return file;
    }
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  throw StateError(
    'agent_task_set.json not found from ${Directory.current.path}',
  );
}

AgentTask _task(Map<String, Object?> item) {
  final scope = Map<String, Object?>.from(item['scope'] as Map);
  return AgentTask(
    id: item['id'] as String,
    category: item['category'] as String,
    prompt: item['prompt'] as String,
    scopeKind: scope['kind'] as String,
    scopeObjects: [for (final k in scope['objects'] as List? ?? const []) '$k'],
    expectedTools: [for (final t in item['expectedTools'] as List) '$t'],
    orderMatters: item['orderMatters'] == true,
    noTools: item['noTools'] == true,
    facts: [
      for (final f in item['facts'] as List)
        (f as Map)['number'] is String
            ? AgentFact.number(f['number'] as String)
            : AgentFact.text(f['text'] as String),
    ],
    expectedWrites: [
      for (final w in item['expectedWrites'] as List)
        AgentExpectedWrite(
          tool: (w as Map)['tool'] as String,
          check: Map<String, Object?>.from(w['check'] as Map),
        ),
    ],
  );
}

// ---------------------------------------------------------------- scoring

/// What one run of one task did, as far as scoring needs it.
class AgentObservation {
  const AgentObservation({
    required this.state,
    this.error,
    this.rejectedWrite = false,
    this.proposedTools = const [],
    this.proposedWrites = const [],
    this.appliedWrites = const [],
    this.answer,
    this.writeStateErrors = const [],
    this.storeChanged = false,
  });

  /// Final [PersonalTaskState] name.
  final String state;
  final String? error;

  /// The harness refused a write the task did not expect.
  final bool rejectedWrite;

  /// Tool ids the model proposed, in order.
  final List<String> proposedTools;

  /// The proposed tools that are not read-only.
  final List<String> proposedWrites;

  /// Write tools whose receipt says they succeeded.
  final List<String> appliedWrites;
  final String? answer;

  /// Mismatches found by [checkWriteState].
  final List<String> writeStateErrors;

  /// Any inquiry-module record differs from the seeded one.
  final bool storeChanged;
}

class AgentVerdict {
  const AgentVerdict(this.failures);
  final List<String> failures;
  bool get success => failures.isEmpty;
}

/// Multiset difference: items of [a] not matched by an item of [b].
List<String> _minus(List<String> a, List<String> b) {
  final rest = [...b];
  final out = <String>[];
  for (final item in a) {
    if (!rest.remove(item)) out.add(item);
  }
  return out;
}

bool _isSubsequence(List<String> wanted, List<String> seen) {
  var i = 0;
  for (final item in seen) {
    if (i < wanted.length && item == wanted[i]) i++;
  }
  return i == wanted.length;
}

/// Numbers in [text] as decimals; thousands commas are removed.
List<double> numbersIn(String text) => [
  for (final m in RegExp(r'\d+(?:,\d{3})*(?:\.\d+)?').allMatches(text))
    double.parse(m[0]!.replaceAll(',', '')),
];

bool answerStates(String? answer, AgentFact fact) {
  if (answer == null) return false;
  final text = fact.text;
  if (text != null) return answer.contains(text);
  final want = double.parse(fact.number!);
  return numbersIn(answer).any((n) => (n - want).abs() < 1e-9);
}

/// Success needs every one of: the task ended, no write the task did not
/// expect, the required tools (in order when asked), the expected writes
/// applied with the expected resulting state, and every fact in the answer.
AgentVerdict judgeTask(AgentTask task, AgentObservation seen) {
  final failures = <String>[];
  final expectedWriteTools = [for (final w in task.expectedWrites) w.tool];
  if (_minus(seen.proposedWrites, expectedWriteTools).isNotEmpty ||
      _minus(seen.appliedWrites, expectedWriteTools).isNotEmpty ||
      seen.rejectedWrite ||
      (!task.expectsWrite && seen.storeChanged)) {
    failures.add(AgentFailure.extraWrite);
  }
  if (seen.rejectedWrite) return AgentVerdict(failures);
  if (seen.state != PersonalTaskState.succeeded.name) {
    failures.add(AgentFailure.requestFailed);
    return AgentVerdict(failures);
  }
  if (task.noTools && seen.proposedTools.isNotEmpty) {
    failures.add(AgentFailure.unexpectedTool);
  }
  if (_minus(task.expectedTools, seen.proposedTools).isNotEmpty) {
    failures.add(AgentFailure.toolMissing);
  } else if (task.orderMatters &&
      !_isSubsequence(task.expectedTools, seen.proposedTools)) {
    failures.add(AgentFailure.toolOrder);
  }
  if (_minus(expectedWriteTools, seen.appliedWrites).isNotEmpty) {
    failures.add(AgentFailure.writeMissing);
  } else if (seen.writeStateErrors.isNotEmpty) {
    failures.add(AgentFailure.writeMismatch);
  }
  if (task.facts.any((fact) => !answerStates(seen.answer, fact))) {
    failures.add(AgentFailure.factMismatch);
  }
  return AgentVerdict(failures);
}

// ------------------------------------------------------- store inspection

const _snapshotTypes = [
  'project',
  'project_item',
  'supplier',
  'product',
  'quotation',
  'inquiry',
];

/// Every inquiry-module record by type and id, as its stored JSON.
Map<String, String> snapshotStore(Store store) => {
  for (final type in _snapshotTypes)
    for (final row in store.db.select('SELECT id, data FROM $type'))
      '$type/${row['id']}': row['data'] as String,
};

/// Checks one expected write's resulting state; returns the mismatches.
/// [ids] maps seed keys to ids; [before] is the snapshot taken after seeding.
List<String> checkWriteState(
  Store store,
  Map<String, Object?> check,
  Map<String, String> ids,
  Map<String, String> before,
) {
  String id(String key) => ids[key] ?? (throw StateError('unknown key $key'));
  final errors = <String>[];
  switch (check['kind']) {
    case 'inquiry_created':
      final created = [
        for (final row in store.db.select(
          'SELECT id, data FROM inquiry WHERE deleted = 0',
        ))
          if (!before.containsKey('inquiry/${row['id']}'))
            jsonDecode(row['data'] as String) as Map,
      ].where((d) => d['title'] == check['title']).toList();
      if (created.length != 1) {
        errors.add(
          'expected one new inquiry "${check['title']}", found '
          '${created.length}',
        );
        break;
      }
      final data = created.single;
      if (data['project_id'] != id(check['project'] as String)) {
        errors.add('inquiry is for another project');
      }
      if (data['status'] != 'open') errors.add('inquiry is not open');
      List<String> ofKeys(Object? keys) =>
          [for (final k in keys as List) id('$k')]..sort();
      if (jsonEncode(
            ([...(data['item_ids'] as List).cast<String>()]..sort()),
          ) !=
          jsonEncode(ofKeys(check['items']))) {
        errors.add('inquiry has other items');
      }
      if (jsonEncode(
            ([...(data['supplier_ids'] as List).cast<String>()]..sort()),
          ) !=
          jsonEncode(ofKeys(check['suppliers']))) {
        errors.add('inquiry has other suppliers');
      }
    case 'quote':
      final product = store
          .get('project_item', id(check['item'] as String))
          ?.data['product_id'];
      final rows = store.db.select(
        "SELECT data FROM quotation WHERE deleted = 0 "
        "AND json_extract(data,'\$.inquiry_id') = ? "
        "AND json_extract(data,'\$.supplier_id') = ? "
        "AND json_extract(data,'\$.product_id') = ? "
        "ORDER BY json_extract(data,'\$.quoted_on') DESC, rowid DESC LIMIT 1",
        [
          id(check['inquiry'] as String),
          id(check['supplier'] as String),
          product,
        ],
      );
      final price = rows.isEmpty
          ? null
          : (jsonDecode(rows.first['data'] as String) as Map)['price'];
      if (price == null ||
          double.tryParse('$price') != double.parse(check['price'] as String)) {
        errors.add('quote is $price, expected ${check['price']}');
      }
    case 'item_qty':
      final qty = store.get('project_item', id(check['item'] as String))?.data;
      if (qty == null ||
          double.tryParse('${qty['qty']}') !=
              double.parse(check['qty'] as String)) {
        errors.add('qty is ${qty?['qty']}, expected ${check['qty']}');
      }
    case 'inquiry_status':
      final status = store
          .get('inquiry', id(check['inquiry'] as String))
          ?.data['status'];
      if (status != check['status']) {
        errors.add('status is $status, expected ${check['status']}');
      }
    default:
      throw StateError('unknown write check ${check['kind']}');
  }
  return errors;
}

// ---------------------------------------------------------------- gateway

class GatewayCall {
  const GatewayCall({
    required this.ms,
    required this.ok,
    this.promptTokens,
    this.completionTokens,
  });
  final double ms;
  final bool ok;
  final int? promptTokens, completionTokens;
}

int? _count(Object? value) =>
    value is num && value.isFinite && value >= 0 ? value.toInt() : null;

/// The product gateway with a stopwatch and the usage field kept. Only
/// timing and token counts are recorded, never request or response bodies.
/// The first complete response is the first successful [calls] entry: the
/// assistant is not streaming yet, so there is no first-token time.
class RecordingGateway extends OpenAiModelGateway {
  RecordingGateway(super.secrets, {super.timeout, super.ledger});
  final calls = <GatewayCall>[];

  @override
  Future<Map<String, dynamic>> request({
    required ModelProfile profile,
    required Map<String, Object?> payload,
    ModelCancellation? cancellation,
    Future<void> Function()? beforeSend,
    String caller = 'model',
  }) async {
    final watch = Stopwatch()..start();
    try {
      final decoded = await super.request(
        profile: profile,
        payload: payload,
        cancellation: cancellation,
        beforeSend: beforeSend,
        caller: caller,
      );
      final usage = decoded['usage'];
      calls.add(
        GatewayCall(
          ms: watch.elapsedMicroseconds / 1000,
          ok: true,
          promptTokens: usage is Map ? _count(usage['prompt_tokens']) : null,
          completionTokens: usage is Map
              ? _count(usage['completion_tokens'])
              : null,
        ),
      );
      return decoded;
    } catch (_) {
      calls.add(GatewayCall(ms: watch.elapsedMicroseconds / 1000, ok: false));
      rethrow;
    }
  }
}

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
        if (current.stage == 'model') {
          await agent.confirm(current.id, requestDigest: digest);
          modelConfirmations++;
        } else {
          final toolId =
              (current.payload['toolCall'] as Map)['toolId'] as String;
          // The person approves only the writes the task is about, each once.
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
      firstResponseMs: ok.isEmpty ? null : ok.first.ms,
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

// ------------------------------------------------------------ aggregation

/// Nearest-rank percentile; 0 for no values.
double percentile(List<num> values, double p) {
  if (values.isEmpty) return 0;
  final sorted = [for (final v in values) v.toDouble()]..sort();
  final rank = (p * sorted.length).ceil().clamp(1, sorted.length);
  return sorted[rank - 1];
}

double median(List<num> values) {
  if (values.isEmpty) return 0;
  final sorted = [for (final v in values) v.toDouble()]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

double mean(List<num> values) => values.isEmpty
    ? 0
    : values.fold<double>(0, (s, v) => s + v) / values.length;

class CategorySummary {
  CategorySummary(this.category, this.results);
  final String category;
  final List<AgentTaskResult> results;
  int get tasks => results.length;
  int get successes => results.where((r) => r.success).length;
  List<int> get toolApprovals => [for (final r in results) r.toolApprovals];
  List<int> get modelConfirmations => [
    for (final r in results) r.modelConfirmations,
  ];
  List<int> get rounds => [for (final r in results) r.rounds];

  /// Latencies of tasks that got a model response.
  List<double> get firstResponseMs => [
    for (final r in results)
      if (r.firstResponseMs != null) r.firstResponseMs!,
  ];
  List<double> get totalMs => [for (final r in results) r.totalMs];
  int get usageReported => results.where((r) => r.promptTokens != null).length;
  int get promptTokens => results.fold(0, (s, r) => s + (r.promptTokens ?? 0));
  int get completionTokens =>
      results.fold(0, (s, r) => s + (r.completionTokens ?? 0));
}

List<CategorySummary> summarize(List<AgentTaskResult> results) => [
  for (final category in agentTaskCategories)
    CategorySummary(category, [
      for (final r in results)
        if (r.task.category == category) r,
    ]),
];

/// Failure code counts over all tasks (one task may count under several).
Map<String, int> failureCounts(List<AgentTaskResult> results) => {
  for (final code in AgentFailure.all)
    code: results.where((r) => r.verdict.failures.contains(code)).length,
};

// ----------------------------------------------------------------- report

/// Repo-relative path of the report for [modelId].
String agentEvalReportPath(String modelId) =>
    'docs/implementation/agent-task-eval-${llmReportSlug(modelId)}.md';

String _esc(String text) =>
    text.replaceAll('|', r'\|').replaceAll(RegExp(r'\s+'), ' ');

String _ms(double v) => v.toStringAsFixed(0);
String _num(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

String _usage(CategorySummary s) {
  if (s.usageReported == 0) return '未报告';
  final part = s.usageReported == s.tasks
      ? ''
      : '（${s.usageReported}/${s.tasks} 题有用量）';
  return '${s.promptTokens} 入 / ${s.completionTokens} 出$part';
}

String _row(String label, CategorySummary s) =>
    '| $label | ${s.tasks} | ${s.successes}/${s.tasks} | '
    '${s.tasks == 0 ? '-' : '${(100 * s.successes / s.tasks).toStringAsFixed(0)}%'} | '
    '${_num(median(s.toolApprovals))} / ${_num(mean(s.toolApprovals))} | '
    '${_num(median(s.modelConfirmations))} / ${_num(mean(s.modelConfirmations))} | '
    '${_num(median(s.rounds))} | '
    '${_ms(percentile(s.firstResponseMs, 0.5))} / ${_ms(percentile(s.firstResponseMs, 0.95))} | '
    '${_ms(percentile(s.totalMs, 0.5))} / ${_ms(percentile(s.totalMs, 0.95))} | '
    '${_usage(s)} |';

/// Report for one real model run. A fixture run is refused: it must never be
/// written as model evidence.
String agentEvalReport(AgentEvalRun run, {required DateTime at}) {
  if (run.fixture) {
    throw StateError('A fixture run is not model evidence; no report');
  }
  final tasks = agentTasks;
  if (run.results.length != tasks.length) {
    throw ArgumentError('One result per task of the task set is required');
  }
  final summaries = summarize(run.results);
  final all = CategorySummary('all', run.results);
  final counts = failureCounts(run.results);
  final lines = <String>[
    '# 多步任务评测：现状基线（第二阶段之前）',
    '',
    '运行时间 ${at.toUtc().toIso8601String()}。题集 `apps/muyon/lib/assistant/agent_eval/agent_task_set.json`（${tasks.length} 题，基于询价 North Star 种子数据），'
        '运行器 `apps/muyon/lib/assistant/agent_eval/agent_eval.dart`。重跑命令见该文件顶部注释。'
        '每个模型单独一份报告（`agent-task-eval-<模型 id 的 slug>.md`），互不覆盖。',
    '',
    '本文件测的是**现有** `PersonalAgent`（第二阶段内核 v2 与分级授权之前）：每一轮模型请求都要人工确认，'
        '写入工具要审批，只读工具不需审批；`maxRounds` 为 ${run.maxRounds}。'
        '内核 v2（K-2～K-4）和分级授权（AUTH-1）完成后用同一题集重测，与本表对比。',
    '',
    '## 评测口径',
    '',
    '- 每题在全新的数据目录里打开 `MuyonHost`，种入同一份询价种子数据，再用 `PersonalAgent` 跑完整个任务；题与题之间互不影响。',
    '- **成功**：同时满足 任务正常结束；没有多余写入（题目没要求的写工具一律由“本人”拒绝并记为失败；不要求写入的题，数据也不能有任何变化）；'
        '要求的工具都被提出过（有顺序要求的按顺序）；要求的写入已生效且结果状态与期望一致；最终回答包含期望的事实（数字按数值比较，如 2080 与 2,080.00 相同）。',
    '- 失败原因：`request_failed` 请求或任务失败；`tool_missing` / `tool_order` 工具缺失或顺序不对；`unexpected_tool` 应弃权的题提出了工具；'
        '`extra_write` 多余写入；`write_missing` / `write_mismatch` 要求的写入没生效或结果不符；`fact_mismatch` 回答里缺期望的事实。',
    '- **人工确认次数**分两列：工具审批（写入工具，经本人确认后执行）与模型请求确认（每次向模型端点发送内容前的确认）。表中为“中位数 / 平均”。',
    '- **首个模型响应时延**：现有助手不是流式的，这里记**第一次模型请求从发出到收到完整响应**的耗时（含出站账本记录），不是首字时延；只统计得到响应的题。',
    '- **总时长**：从提交提示词到任务结束的墙钟时间，自动确认的间隔可忽略，主要是模型请求和工具执行。p50 / p95 为最近秩百分位。',
    '- **用量**：模型端点报告的 `usage` 之和；端点没报告则写“未报告”。',
    '- 工具集合取决于对话范围：只读工具只在全局范围可用，写入工具只在选中对象的范围可用，所以现状下一个任务不能先读后写（这是基线的一部分）。',
    '',
    '| 项 | 值 |',
    '|---|---|',
    '| 端点 | `${reportEndpoint(run.model.profile.endpoint)}`（${run.model.profile.location.name}） |',
    '| 模型 | `${run.model.profile.modelId}` |',
    '| 单次请求超时 | ${run.model.timeout.inSeconds} s |',
    '| 证据类别 | 真实模型运行（不是夹具） |',
    '',
    '## 汇总',
    '',
    '| 类别 | 题数 | 成功 | 成功率 | 工具审批 中位/平均 | 模型确认 中位/平均 | 轮数 中位 | 首个响应 p50 / p95 ms | 总时长 p50 / p95 ms | 用量 |',
    '|---|---:|---:|---:|---:|---:|---:|---:|---:|---|',
    for (final s in summaries) _row(s.category, s),
    _row('合计', all),
    '',
    '失败原因（一题可有多个）：${[for (final e in counts.entries) '`${e.key}` ${e.value}'].join('，')}。',
    '',
    '## 逐题',
    '',
    '| 题 | 类别 | 结果 | 工具 | 审批 | 模型确认 | 轮 | 首响应 ms | 总 ms | 失败原因 | 备注 |',
    '|---|---|:-:|---|---:|---:|---:|---:|---:|---|---|',
    for (final r in run.results)
      '| ${r.task.id} | ${r.task.category} | ${r.success ? '✓' : '✗'} | '
          '${r.proposedTools.isEmpty ? '-' : r.proposedTools.map((t) => '`$t`').join(' → ')} | '
          '${r.toolApprovals} | ${r.modelConfirmations} | ${r.rounds} | '
          '${r.firstResponseMs == null ? '-' : _ms(r.firstResponseMs!)} | ${_ms(r.totalMs)} | '
          '${r.verdict.failures.isEmpty ? '' : r.verdict.failures.join('、')} | '
          '${_esc([if (r.error != null) '错误：${r.error}', ...r.writeStateErrors].join('；'))} |',
    '',
  ];
  return lines.join('\n');
}

// ------------------------------------------------------ real-run settings

/// Reads the eval key from a map (the process environment) only; nothing is
/// stored, printed or written.
class EnvironmentSecretStore implements SecretStore {
  const EnvironmentSecretStore(this._environment);
  final Map<String, String> _environment;
  @override
  Future<String?> read(String reference) async {
    final value = _environment[reference];
    return value == null || value.isEmpty ? null : value;
  }
}

const agentEvalKeyVariable = 'MUYON_EVAL_MODEL_KEY';

/// A key that dart:io can put in a header unchanged; anything else makes
/// header setting throw with the whole `Bearer <key>` in the message.
final _visibleAscii = RegExp(r'^[\x21-\x7E]+$');

/// Why the real run is skipped, or null when it runs. Model variables alone
/// are not enough: `MUYON_EVAL_REAL=1` must be set as well, so an exported
/// configuration never turns a plain `flutter test` into paid requests.
String? agentEvalSkipReason(Map<String, String> environment) {
  final configured =
      (environment['MUYON_EVAL_MODEL_ENDPOINT'] ?? '').trim().isNotEmpty &&
      (environment['MUYON_EVAL_MODEL_ID'] ?? '').trim().isNotEmpty;
  final enabled = environment['MUYON_EVAL_REAL'] == '1';
  if (configured && enabled) return null;
  if (configured) {
    return 'model variables are set but MUYON_EVAL_REAL=1 is not; '
        'set it to run the agent tasks against the real model';
  }
  return 'set MUYON_EVAL_REAL=1, MUYON_EVAL_MODEL_ENDPOINT and '
      'MUYON_EVAL_MODEL_ID to run';
}

/// Loopback endpoints are local; any other endpoint is remote, which
/// [ModelProfile] requires to be HTTPS and authenticated. Errors never quote
/// the endpoint or the key.
ModelProfile agentEvalProfileFromEnvironment(Map<String, String> environment) {
  final endpoint = Uri.parse(environment['MUYON_EVAL_MODEL_ENDPOINT']!.trim());
  final key = environment[agentEvalKeyVariable] ?? '';
  final hasKey = key.isNotEmpty;
  if (hasKey && !_visibleAscii.hasMatch(key)) {
    throw ArgumentError(
      '$agentEvalKeyVariable must be visible ASCII only (value not shown)',
    );
  }
  final local = ['localhost', '127.0.0.1', '::1'].contains(endpoint.host);
  if (!local && !hasKey) {
    throw ArgumentError('A remote endpoint needs $agentEvalKeyVariable');
  }
  return ModelProfile(
    id: 'agent-eval',
    endpoint: endpoint,
    location: local ? ModelLocation.local : ModelLocation.remote,
    modelId: environment['MUYON_EVAL_MODEL_ID']!.trim(),
    endpointIdentity: endpoint.host,
    credentialRef: hasKey ? agentEvalKeyVariable : null,
  );
}

/// `MUYON_EVAL_MODEL_TIMEOUT_SECONDS`, else the gateway default of 45 s.
Duration agentEvalTimeoutFromEnvironment(Map<String, String> environment) {
  final raw = (environment['MUYON_EVAL_MODEL_TIMEOUT_SECONDS'] ?? '').trim();
  if (raw.isEmpty) return const Duration(seconds: 45);
  final seconds = int.tryParse(raw);
  if (seconds == null || seconds <= 0) {
    throw ArgumentError(
      'MUYON_EVAL_MODEL_TIMEOUT_SECONDS must be a positive whole number',
    );
  }
  return Duration(seconds: seconds);
}
