part of 'agent_eval.dart';

const agentTaskCategories = ['read_single', 'read_multi', 'write', 'abstain'];

/// Failure codes of [judgeTask].
class AgentFailure {
  static const requestFailed = 'request_failed';

  /// The task failed because a write changed a selected record and the
  /// conversation scope pins that record's revision: current product
  /// behaviour (`business_tools.dart` `resolveAssistantScope`), not a model
  /// error. Reported apart from [requestFailed].
  static const scopePinned = 'scope_pinned';
  static const toolMissing = 'tool_missing';
  static const toolOrder = 'tool_order';
  static const unexpectedTool = 'unexpected_tool';
  static const extraWrite = 'extra_write';
  static const writeMissing = 'write_missing';
  static const writeMismatch = 'write_mismatch';
  static const factMismatch = 'fact_mismatch';
  static const all = [
    requestFailed,
    scopePinned,
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
/// (`2080` matches `2,080.00`); a text is a substring. This is a containment
/// check: it does not verify what the number is about. A small or ambiguous
/// number can carry [anchors] (text that must follow it, e.g. `条` for "4 条")
/// and [prefixAnchors] (text that may precede it, e.g. `¥`); then the number
/// counts only next to one of them (spaces between are ignored, letters
/// compare without case). A number directly after one of [rejectPrefixes]
/// (e.g. the ordinal `第`) never counts. Chinese numerals (`四`) are not
/// read.
class AgentFact {
  const AgentFact.number(
    String this.number, {
    this.anchors = const [],
    this.prefixAnchors = const [],
    this.rejectPrefixes = const [],
  }) : text = null;
  const AgentFact.text(String this.text)
    : number = null,
      anchors = const [],
      prefixAnchors = const [],
      rejectPrefixes = const [];
  final String? number, text;
  final List<String> anchors, prefixAnchors, rejectPrefixes;

  /// How a scripted correct answer writes the fact.
  String get label => number == null
      ? text!
      : anchors.isNotEmpty
      ? '$number${anchors.first}'
      : prefixAnchors.isNotEmpty
      ? '${prefixAnchors.first}$number'
      : number!;
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
    this.note,
  });
  final String id, category, prompt;

  /// Reading aid shown in the report next to a failure of this task.
  final String? note;

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
            ? AgentFact.number(
                f['number'] as String,
                anchors: [
                  for (final a in f['anchors'] as List? ?? const []) '$a',
                ],
                prefixAnchors: [
                  for (final a in f['prefixAnchors'] as List? ?? const []) '$a',
                ],
                rejectPrefixes: [
                  for (final a in f['rejectPrefixes'] as List? ?? const [])
                    '$a',
                ],
              )
            : AgentFact.text(f['text'] as String),
    ],
    note: item['note'] as String?,
    expectedWrites: [
      for (final w in item['expectedWrites'] as List)
        AgentExpectedWrite(
          tool: (w as Map)['tool'] as String,
          check: Map<String, Object?>.from(w['check'] as Map),
        ),
    ],
  );
}
