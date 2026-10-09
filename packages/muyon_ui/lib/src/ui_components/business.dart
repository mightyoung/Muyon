import 'package:flutter/material.dart';

import '../primitives.dart' show StatusTone;
import '../tokens.dart';
import 'state.dart';

bool _enabled(UiComponentState state, Object? callback) =>
    state == UiComponentState.ready && callback != null;

Widget _card(BuildContext context, Widget child) {
  final t = MuyonTokens.of(context);
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(MuyonTokens.space4),
    decoration: BoxDecoration(
      color: t.surface,
      border: Border.all(color: t.rule),
      borderRadius: BorderRadius.circular(MuyonTokens.cardRadius),
    ),
    child: child,
  );
}

/// A quoted passage and where it came from; opening it is the host's job.
class SourceCard extends StatelessWidget {
  const SourceCard({
    super.key,
    required this.title,
    required this.excerpt,
    this.location,
    this.onOpen,
    this.state = UiComponentState.ready,
    this.errorMessage,
  });
  final String title, excerpt;
  final String? location;
  final VoidCallback? onOpen;
  final UiComponentState state;
  final String? errorMessage;

  String get textEquivalent =>
      '来源「$title」${location == null ? '' : '，$location'}：$excerpt';

  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    final on = _enabled(state, onOpen);
    return UiComponentFrame(
      state: state,
      textEquivalent: textEquivalent,
      errorMessage: errorMessage,
      placeholderHeight: 120,
      child: _card(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.format_quote,
                  color: t.ink3,
                  size: MuyonTokens.iconSize,
                ),
                const SizedBox(width: MuyonTokens.space2),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (location != null)
              Padding(
                padding: const EdgeInsets.only(top: MuyonTokens.space1),
                child: Text(location!, style: TextStyle(color: t.ink3)),
              ),
            const SizedBox(height: MuyonTokens.space2),
            SelectableText(excerpt, style: TextStyle(color: t.ink)),
            const SizedBox(height: MuyonTokens.space2),
            Align(
              alignment: Alignment.centerLeft,
              child: UiMinTarget(
                child: TextButton(
                  key: const ValueKey('source-open'),
                  onPressed: on ? onOpen : null,
                  child: const Text('查看原文'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A file by name, kind and size.
class FileCard extends StatelessWidget {
  const FileCard({
    super.key,
    required this.name,
    this.sizeText,
    this.onOpen,
    this.state = UiComponentState.ready,
    this.errorMessage,
  });
  final String name;
  final String? sizeText;
  final VoidCallback? onOpen;
  final UiComponentState state;
  final String? errorMessage;

  String get _ext =>
      name.contains('.') ? name.split('.').last.toLowerCase() : '';
  String get textEquivalent =>
      '文件「$name」${sizeText == null ? '' : '，$sizeText'}';

  IconData get _icon => switch (_ext) {
    'pdf' => Icons.picture_as_pdf_outlined,
    'xlsx' || 'xls' || 'csv' => Icons.table_chart_outlined,
    'png' || 'jpg' || 'jpeg' || 'gif' => Icons.image_outlined,
    'zip' => Icons.folder_zip_outlined,
    _ => Icons.insert_drive_file_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    final on = _enabled(state, onOpen);
    return UiComponentFrame(
      state: state,
      textEquivalent: textEquivalent,
      errorMessage: errorMessage,
      placeholderHeight: 72,
      child: Semantics(
        button: on,
        label: '打开文件「$name」',
        excludeSemantics: true,
        onTap: on ? onOpen : null,
        child: InkWell(
          key: const ValueKey('file-open'),
          borderRadius: BorderRadius.circular(MuyonTokens.cardRadius),
          onTap: on ? onOpen : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: uiMinTarget),
            child: _card(
              context,
              Row(
                children: [
                  Icon(_icon, color: t.accent, size: MuyonTokens.iconSize),
                  const SizedBox(width: MuyonTokens.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            color: t.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (sizeText != null)
                          Text(sizeText!, style: TextStyle(color: t.ink3)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A task's progress. A null [progress] means "working, length unknown".
class ProgressCard extends StatelessWidget {
  const ProgressCard({
    super.key,
    required this.title,
    this.progress,
    this.step,
    this.tone = StatusTone.neutral,
    this.state = UiComponentState.ready,
    this.errorMessage,
  });
  final String title;
  final double? progress;
  final String? step;
  final StatusTone tone;
  final UiComponentState state;
  final String? errorMessage;

  int? get _percent =>
      progress == null ? null : (progress!.clamp(0, 1) * 100).round();

  String get textEquivalent =>
      '$title：${_percent == null ? '进行中' : '进度 $_percent%'}${step == null ? '' : '，$step'}';

  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    final color = switch (tone) {
      StatusTone.success => t.green,
      StatusTone.danger => t.red,
      StatusTone.warn => t.warn,
      StatusTone.neutral => t.accent,
    };
    return UiComponentFrame(
      state: state,
      textEquivalent: textEquivalent,
      errorMessage: errorMessage,
      placeholderHeight: 96,
      excludeChildSemantics: true,
      child: _card(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (_percent != null)
                  Text('$_percent%', style: TextStyle(color: t.ink2)),
              ],
            ),
            const SizedBox(height: MuyonTokens.space2),
            ClipRRect(
              borderRadius: BorderRadius.circular(MuyonTokens.pillRadius),
              child: LinearProgressIndicator(
                key: const ValueKey('progress-bar'),
                value: progress?.clamp(0, 1).toDouble(),
                minHeight: 8,
                color: color,
                backgroundColor: t.sunken,
              ),
            ),
            if (step != null)
              Padding(
                padding: const EdgeInsets.only(top: MuyonTokens.space2),
                child: Text(step!, style: TextStyle(color: t.ink3)),
              ),
          ],
        ),
      ),
    );
  }
}

class ChecklistItem {
  const ChecklistItem(this.label, {this.checked = false});
  final String label;
  final bool checked;
}

/// Items that can be ticked off, one per row.
class Checklist extends StatelessWidget {
  const Checklist({
    super.key,
    required this.items,
    this.onToggle,
    this.state = UiComponentState.ready,
    this.errorMessage,
  });
  final List<ChecklistItem> items;
  final void Function(int index, bool checked)? onToggle;
  final UiComponentState state;
  final String? errorMessage;

  String get textEquivalent {
    final done = items.where((i) => i.checked).length;
    return '清单，已完成 $done/${items.length}：'
        '${items.map((i) => '${i.checked ? '已完成' : '未完成'} ${i.label}').join('；')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    final on = _enabled(state, onToggle);
    return UiComponentFrame(
      state: state,
      textEquivalent: textEquivalent,
      errorMessage: errorMessage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++)
            Semantics(
              checked: items[i].checked,
              label: items[i].label,
              excludeSemantics: true,
              onTap: on ? () => onToggle!(i, !items[i].checked) : null,
              child: InkWell(
                key: ValueKey('check-$i'),
                borderRadius: BorderRadius.circular(MuyonTokens.radius),
                onTap: on ? () => onToggle!(i, !items[i].checked) : null,
                child: UiMinTarget(
                  child: Row(
                    children: [
                      Icon(
                        items[i].checked
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        color: items[i].checked ? t.accent : t.ink3,
                        size: MuyonTokens.iconSize,
                      ),
                      const SizedBox(width: MuyonTokens.space3),
                      Expanded(
                        child: Text(
                          items[i].label,
                          style: TextStyle(
                            color: items[i].checked ? t.ink3 : t.ink,
                            decoration: items[i].checked
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class TimelineEvent {
  const TimelineEvent(this.time, this.title, {this.detail});
  final String time, title;
  final String? detail;
}

/// Events in order, newest or oldest first as supplied.
class Timeline extends StatelessWidget {
  const Timeline({
    super.key,
    required this.events,
    this.state = UiComponentState.ready,
    this.errorMessage,
  });
  final List<TimelineEvent> events;
  final UiComponentState state;
  final String? errorMessage;

  String get textEquivalent =>
      '时间线，${events.length} 项：${events.map((e) => '${e.time} ${e.title}${e.detail == null ? '' : '，${e.detail}'}').join('；')}';

  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    return UiComponentFrame(
      state: state,
      textEquivalent: textEquivalent,
      errorMessage: errorMessage,
      excludeChildSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < events.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 24,
                    child: Column(
                      children: [
                        const SizedBox(height: 6),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: t.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        if (i < events.length - 1)
                          Expanded(child: Container(width: 2, color: t.rule)),
                      ],
                    ),
                  ),
                  const SizedBox(width: MuyonTokens.space2),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(
                        bottom: MuyonTokens.space4,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(events[i].time, style: TextStyle(color: t.ink3)),
                          Text(
                            events[i].title,
                            style: TextStyle(
                              color: t.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (events[i].detail != null)
                            Text(
                              events[i].detail!,
                              style: TextStyle(color: t.ink2),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
