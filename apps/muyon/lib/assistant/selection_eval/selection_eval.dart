import 'dart:convert';
import 'dart:io';

import 'package:muyon_module_api/muyon_module_api.dart';

import '../tool_selection.dart';

/// A probability from selection is a candidate, never an authorization.
const selectionAbstainThreshold = 1.0;

const layaOnDeviceFinding =
    'not measured. This run did not install Laya, download a checkpoint, or call a local service. '
    'The project README (not a measurement here) says the English checkpoint\'s noul head has label bias and that score is the weakest head; tool selection would use choice over tool ids plus "none", with abstention below min_confidence. '
    'Python is not available on Android. An on-device trial would need an ONNX export through the existing flutter_onnxruntime, a tokenizer, the checkpoint size, and CPU latency on this machine. Those numbers were not collected.';

class ChoiceDecision {
  const ChoiceDecision({this.toolId, required this.confidence});
  final String? toolId;
  final double confidence;
  bool get abstains => toolId == null || confidence < selectionAbstainThreshold;
}

/// Maps the offline rule onto one choice. Model-widened candidate lists are not choices.
ChoiceDecision choiceFromRule(ToolSelection selection) {
  final id = selection.ruleToolId;
  if (id == null) return const ChoiceDecision(confidence: 0);
  return ChoiceDecision(toolId: id, confidence: 1);
}

class SelectionTask {
  const SelectionTask({
    required this.id,
    required this.prompt,
    required this.expected,
    required this.category,
  });
  final String id, prompt, expected, category;
}

class CategoryScore {
  const CategoryScore({
    required this.category,
    required this.tasks,
    required this.top1,
    required this.falseWriteOrExternal,
    required this.shouldAbstain,
    required this.abstained,
  });
  final String category;
  final int tasks, top1, falseWriteOrExternal, shouldAbstain, abstained;
}

class CalibrationBucket {
  const CalibrationBucket({
    required this.label,
    required this.tasks,
    required this.correct,
  });
  final String label;
  final int tasks, correct;
}

class SelectionScore {
  const SelectionScore({
    required this.strategyId,
    required this.tasks,
    required this.top1,
    required this.topK,
    required this.falseWriteOrExternal,
    required this.shouldAbstain,
    required this.abstained,
    required this.latencyMs,
    required this.cost,
    required this.byCategory,
    required this.calibration,
  });
  final String strategyId, cost;
  final int tasks, top1, topK, falseWriteOrExternal, shouldAbstain, abstained;
  final double latencyMs;
  final List<CategoryScore> byCategory;
  final List<CalibrationBucket> calibration;
  double get top1Accuracy => tasks == 0 ? 0 : top1 / tasks;
  double get abstentionQuality =>
      shouldAbstain == 0 ? 0 : abstained / shouldAbstain;
}

class SelectionSet {
  const SelectionSet(this.tools, this.tasks);
  final List<RegisteredToolInfo> tools;
  final List<SelectionTask> tasks;
}

SelectionSet? _set;

/// Checked-in synthetic prompts. Loaded from [selection_set.json] beside this file.
SelectionSet loadSelectionSet() {
  final cached = _set;
  if (cached != null) return cached;
  final decoded = jsonDecode(selectionSetFile().readAsStringSync());
  if (decoded is! Map) throw const FormatException('selection set');
  final tools = [
    for (final raw in decoded['tools'] as List)
      _tool(Map<String, Object?>.from(raw as Map)),
  ];
  final tasks = [
    for (final raw in decoded['tasks'] as List)
      _task(Map<String, Object?>.from(raw as Map)),
  ];
  return _set = SelectionSet(tools, tasks);
}

File selectionSetFile() {
  const names = [
    'lib/assistant/selection_eval/selection_set.json',
    'apps/muyon/lib/assistant/selection_eval/selection_set.json',
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
    'selection_set.json not found from ${Directory.current.path}',
  );
}

RegisteredToolInfo _tool(Map<String, Object?> item) => RegisteredToolInfo(
  providerId: 'eval',
  descriptor: ToolDescriptor(
    toolId: item['id'] as String,
    moduleId: item['module'] as String,
    effect: _effect(item['effect'] as String),
    description: item['description'] as String? ?? '',
  ),
  available: true,
);

SelectionTask _task(Map<String, Object?> item) => SelectionTask(
  id: item['id'] as String,
  prompt: item['prompt'] as String,
  expected: item['expected'] as String,
  category: item['category'] as String,
);

ToolEffect _effect(String name) => switch (name) {
  'read' => ToolEffect.read,
  'write' => ToolEffect.write,
  'export' => ToolEffect.export,
  'network' => ToolEffect.network,
  _ => throw FormatException('unknown effect $name'),
};

/// Real registered tool ids and effects. The eval does not register or switch them.
List<RegisteredToolInfo> evaluationTools() => loadSelectionSet().tools;

List<SelectionTask> get selectionTasks => loadSelectionSet().tasks;

SelectionScore scoreRule(ToolSelectionStrategy strategy) {
  final tools = evaluationTools();
  final watch = Stopwatch()..start();
  final decisions = [
    for (final task in selectionTasks)
      choiceFromRule(
        strategy.select(
          prompt: task.prompt,
          scope: const AssistantScope.global(),
          availableTools: tools,
          modelAvailable: false,
        ),
      ),
  ];
  watch.stop();
  return scoreChoices(
    strategyId: strategy.id,
    decisions: decisions,
    latencyMs: watch.elapsedMicroseconds / 1000,
    cost: '0',
  );
}

/// Abstaining is correct only when the task expects "none"; a choice is
/// correct only when it is the expected registered id.
bool choiceIsCorrect(SelectionTask task, ChoiceDecision decision) =>
    decision.abstains
    ? task.expected == 'none'
    : decision.toolId == task.expected;

/// Scores one decision per task of [selectionTasks], in order. Shared by the
/// offline rule and model strategies so their numbers are comparable.
SelectionScore scoreChoices({
  required String strategyId,
  required List<ChoiceDecision> decisions,
  required double latencyMs,
  required String cost,
}) {
  final tasks = selectionTasks;
  if (decisions.length != tasks.length) {
    throw ArgumentError('One decision per selection task is required');
  }
  final tools = evaluationTools();
  final byId = {for (final tool in tools) tool.descriptor.toolId: tool};
  var top1 = 0, topK = 0, falseWrite = 0, shouldAbstain = 0, abstained = 0;
  final categories = <String, _CategoryAcc>{};
  final buckets = {for (final label in _bucketOrder) label: _BucketAcc(label)};
  for (var i = 0; i < tasks.length; i++) {
    final task = tasks[i];
    final decision = decisions[i];
    final choseNone = decision.abstains;
    final category = categories.putIfAbsent(
      task.category,
      () => _CategoryAcc(task.category),
    );
    category.tasks++;
    if (task.expected == 'none') {
      shouldAbstain++;
      category.shouldAbstain++;
      if (choseNone) {
        abstained++;
        category.abstained++;
      }
    }
    final hit = choiceIsCorrect(task, decision);
    if (hit) {
      top1++;
      topK++;
      category.top1++;
    }
    final chosen = decision.toolId == null ? null : byId[decision.toolId];
    final dangerous =
        chosen != null &&
        (chosen.accessLevel == ToolAccessLevel.write ||
            chosen.accessLevel == ToolAccessLevel.external);
    if (!choseNone && dangerous && decision.toolId != task.expected) {
      falseWrite++;
      category.falseWrite++;
    }
    final label = decision.abstains
        ? 'abstain'
        : _confidenceBucket(decision.confidence);
    final bucket = buckets[label]!;
    bucket.tasks++;
    if (hit) bucket.correct++;
  }
  return SelectionScore(
    strategyId: strategyId,
    tasks: tasks.length,
    top1: top1,
    topK: topK,
    falseWriteOrExternal: falseWrite,
    shouldAbstain: shouldAbstain,
    abstained: abstained,
    latencyMs: latencyMs,
    cost: cost,
    byCategory: [
      for (final name in _categoryOrder)
        if (categories.containsKey(name)) categories[name]!.toScore(),
      for (final entry in categories.entries)
        if (!_categoryOrder.contains(entry.key)) entry.value.toScore(),
    ],
    calibration: [for (final label in _bucketOrder) buckets[label]!.toScore()],
  );
}

const _categoryOrder = [
  'exact',
  'chinese',
  'mixed',
  'paraphrase',
  'ambiguous',
  'misleading',
  'adversarial',
];

const _bucketOrder = ['abstain', '[0,0.5)', '[0.5,0.9)', '[0.9,1)', '1.0'];

String _confidenceBucket(double confidence) {
  if (confidence >= 1) return '1.0';
  if (confidence >= 0.9) return '[0.9,1)';
  if (confidence >= 0.5) return '[0.5,0.9)';
  return '[0,0.5)';
}

class _CategoryAcc {
  _CategoryAcc(this.category);
  final String category;
  int tasks = 0, top1 = 0, falseWrite = 0, shouldAbstain = 0, abstained = 0;
  CategoryScore toScore() => CategoryScore(
    category: category,
    tasks: tasks,
    top1: top1,
    falseWriteOrExternal: falseWrite,
    shouldAbstain: shouldAbstain,
    abstained: abstained,
  );
}

class _BucketAcc {
  _BucketAcc(this.label);
  final String label;
  int tasks = 0, correct = 0;
  CalibrationBucket toScore() =>
      CalibrationBucket(label: label, tasks: tasks, correct: correct);
}

String unevaluated(String? endpoint) => endpoint == null || endpoint.isEmpty
    ? 'not measured'
    : 'not measured — endpoint is set, but this run does not send prompts';

String _categoryTable(SelectionScore rule) {
  final lines = [
    '| 类别 | 题数 | top-1 | 误选写入/外发 | 应弃权 | 实际弃权 |',
    '|---|---:|---:|---:|---:|---:|',
  ];
  for (final row in rule.byCategory) {
    lines.add(
      '| ${row.category} | ${row.tasks} | ${row.top1}/${row.tasks} | ${row.falseWriteOrExternal} | ${row.shouldAbstain} | ${row.abstained} |',
    );
  }
  return lines.join('\n');
}

String _calibrationTable(SelectionScore rule) {
  final lines = ['| 置信度 | 题数 | 其中判断正确 |', '|---|---:|---:|'];
  for (final row in rule.calibration) {
    lines.add('| ${row.label} | ${row.tasks} | ${row.correct} |');
  }
  return lines.join('\n');
}

String selectionReport({
  required SelectionScore rule,
  required String llm,
  required String laya,
  required String jev,
}) =>
    '''
# 工具选择评测 2026-10-05

数字来自 `apps/muyon/lib/assistant/selection_eval/selection_set.json` 这一次对离线规则的运行。生产策略没有被切换。概率不是授权：低于 $selectionAbstainThreshold 的 choice 弃权，并且即使命中也只是候选，仍要走宿主审批。

启动时 `public_tools.dart` 和 `business_tools.dart` 注册的 `ToolDescriptor.description` 仍是空字符串。评测集里的说明来自 `agent_tools.dart` 和各工具的实际用途，只放在题面和标签对照里，没有改生产注册。

重跑并写回本文件。普通 `flutter test` 不带 `MUYON_WRITE_EVAL_REPORT=1`，因此不会改这个文件：

```bash
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \\
  NO_PROXY=localhost,127.0.0.1,::1 \\
  MUYON_WRITE_EVAL_REPORT=1 \\
  flutter test --no-pub --timeout 120s apps/muyon/test/selection_eval_test.dart
```

| 策略 | top-1 | top-3 | 误选写入/外发 | 弃权质量 | 延迟 ms | 费用 |
|---|---:|---:|---:|---:|---:|---:|
| ${rule.strategyId}（离线精确匹配工具 id，否则弃权） | ${rule.top1}/${rule.tasks} | ${rule.topK}/${rule.tasks} | ${rule.falseWriteOrExternal} | ${rule.abstained}/${rule.shouldAbstain} | ${rule.latencyMs.toStringAsFixed(3)} | ${rule.cost} |
| LLM | $llm | | | | | |
| Laya | $laya | | | | | |
| Jev | $jev | | | | | |

## 分类

${_categoryTable(rule)}

## 校准

离线规则只有弃权（置信度 0，计入 abstain）和精确工具 id（置信度 1.0）。中间桶在这次规则运行里应为空。弃权桶里“判断正确”只计预期就是 none 的题。

${_calibrationTable(rule)}

离线规则只在提示词去掉空白后等于某个已注册工具 id 时给出候选。自然语言、含糊请求和让助手自行批准或改选写入工具的对抗提示都会弃权。这是当前基线，不是上线选择。

Laya：$laya

Jev：$jev
''';
