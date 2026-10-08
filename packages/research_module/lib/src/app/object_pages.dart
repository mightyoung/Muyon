import 'package:flutter/material.dart';
import 'package:muyon_ui/muyon_ui.dart';

import '../core/card_title.dart';
import '../core/models.dart';
import '../core/research_kinds.dart';
import 'run_assessment_dialog.dart' show assessmentSummary;

/// Read-only detail pages for research objects opened from outside the
/// workbench (assistant answers, execution panel). They only display data
/// passed in from the workbench store and never edit, delete or accept
/// anything; editing stays in the research workbench.

class ResearchEntryPage extends StatelessWidget {
  const ResearchEntryPage({super.key, required this.entry});
  final ResearchEntry entry;

  @override
  Widget build(BuildContext context) {
    final body = _firstText(entry.data, const [
      'statement',
      'summary',
      'abstract',
      'text',
      'body',
    ]);
    final source = _firstText(entry.data, const ['source', 'locator', 'venue']);
    return _Page(
      title: entry.title,
      children: [
        _Field('类型', recordKinds[entry.kind] ?? entry.kind),
        if (body.isNotEmpty) _Field('正文', body),
        if (source.isNotEmpty) _Field('来源', source),
      ],
    );
  }
}

class ResearchOutlinePage extends StatelessWidget {
  const ResearchOutlinePage({
    super.key,
    required this.heading,
    this.sectionHeading,
    this.content,
  });
  final String heading;
  final String? sectionHeading;
  final String? content;

  @override
  Widget build(BuildContext context) => _Page(
    title: heading,
    children: [
      if (sectionHeading != null && sectionHeading!.isNotEmpty)
        _Field('所属段落', sectionHeading!),
      if (content != null && content!.isNotEmpty) _Field('正文', content!),
    ],
  );
}

class ResearchSectionPage extends StatelessWidget {
  const ResearchSectionPage({
    super.key,
    required this.heading,
    required this.projectTitle,
    required this.argument,
  });
  final String heading;
  final String projectTitle;
  final String argument;

  @override
  Widget build(BuildContext context) => _Page(
    title: heading,
    children: [
      _Field('所属项目', projectTitle),
      if (argument.isNotEmpty) _Field('正文', argument),
    ],
  );
}

class ResearchTaskPage extends StatelessWidget {
  const ResearchTaskPage({
    super.key,
    required this.task,
    this.revisionRunStatus,
    required this.isLatestRevision,
  });
  final ResearchTask task;
  final String? revisionRunStatus;
  final bool isLatestRevision;

  @override
  Widget build(BuildContext context) => _Page(
    title: task.title,
    children: [
      _Field('修订号', 'r${task.revision}'),
      if (!isLatestRevision) const _StaleRevision(),
      if (revisionRunStatus != null) _Field('状态', revisionRunStatus!),
      if (task.goal.isNotEmpty) _Field('说明', task.goal),
    ],
  );
}

class ResearchRunPage extends StatelessWidget {
  const ResearchRunPage({
    super.key,
    required this.run,
    required this.taskTitle,
    required this.isLatestRevision,
  });
  final ResearchRun run;
  final String taskTitle;
  final bool isLatestRevision;

  @override
  Widget build(BuildContext context) {
    final assessment = assessmentSummary(run);
    final assessmentText = _withoutSummaryLabel(assessment);
    final hasAssessment = assessment != null || run.accepted;
    return _Page(
      title: taskTitle,
      children: [
        _Field('修订号', 'r${run.taskRevision}'),
        if (!isLatestRevision) const _StaleRevision(),
        _Field('状态', run.status),
        if (hasAssessment) ...[
          _Field('评价', run.accepted ? '已接纳为证据' : '未接纳为证据'),
          if (assessmentText != null) _Field('研究结论', assessmentText),
        ],
      ],
    );
  }
}

class ResearchCardPage extends StatelessWidget {
  const ResearchCardPage({
    super.key,
    required this.bodyMarkdown,
    required this.revisionId,
    required this.citations,
    required this.isLatestRevision,
  });
  final String bodyMarkdown;
  final String revisionId;
  final List<String> citations;
  final bool isLatestRevision;

  @override
  Widget build(BuildContext context) => _Page(
    title: cardTitleFromMarkdown(bodyMarkdown, fallback: '研究卡'),
    children: [
      if (bodyMarkdown.trim().isNotEmpty) _Field('正文', bodyMarkdown),
      _Field('修订号', revisionId),
      if (!isLatestRevision) const _StaleRevision(),
      if (citations.isNotEmpty) _Field('引用列表', citations.join('\n')),
    ],
  );
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(MuyonTokens.space4),
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: MuyonTokens.space3),
      ...children,
    ],
  );
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: MuyonTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          SelectableText(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _StaleRevision extends StatelessWidget {
  const _StaleRevision();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: MuyonTokens.space3),
    child: Text(
      '不是最新修订',
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: MuyonTokens.of(context).amber),
    ),
  );
}

String _firstText(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is String && value.trim().isNotEmpty) return value;
  }
  return '';
}

/// `assessmentSummary` already begins with the field label; drop it when the
/// summary is shown under its own label.
String? _withoutSummaryLabel(String? summary) {
  const label = '研究结论：';
  if (summary == null || !summary.startsWith(label)) return summary;
  return summary.substring(label.length);
}
