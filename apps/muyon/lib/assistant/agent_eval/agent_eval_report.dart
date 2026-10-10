part of 'agent_eval.dart';

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
    '- 失败原因：`request_failed` 请求或任务失败；`scope_pinned` 同一任务里先写入了被选中的记录，随后的工具调用因对话范围固定了记录修订号而被拒（现状的产品行为，不是模型错误，单独列出）；`tool_missing` / `tool_order` 工具缺失或顺序不对；`unexpected_tool` 应弃权的题提出了工具；'
        '`extra_write` 多余写入；`write_missing` / `write_mismatch` 要求的写入没生效或结果不符；`fact_mismatch` 回答里缺期望的事实。',
    '- 事实判定只是“包含”检查：回答里出现期望的数字或文字即算，不核对它说的是什么；容易误撞的小数字要求紧邻锚点（数量认“条/个/笔/项/家”等量词，序数“第 4 项”不算；金额认“元/块/CNY/RMB”后缀或“¥/RMB/人民币/单价/价格”前缀）。中文数字（如“四”）不识别，只认阿拉伯数字。',
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
          '${_esc([if (r.error != null) '错误：${r.error}', ...r.writeStateErrors, if (r.verdict.failures.contains(AgentFailure.scopePinned)) '范围修订号固定（business_tools.dart:164-172）：现状产品行为，不是模型错误', if (!r.success && r.task.note != null) '题注：${r.task.note}'].join('；'))} |',
    '',
  ];
  return lines.join('\n');
}
