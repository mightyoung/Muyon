import 'package:flutter/material.dart';

import 'action_surface.dart';
import 'tokens.dart';

enum StatusTone { success, danger, warn, neutral }

/// Single vocabulary used by badges, confirmation cards and the catalog.
enum BusinessStatus {
  success('已成功'),
  failed('失败'),
  warning('需注意'),
  neutral('未开始'),
  pending('待确认'),
  running('进行中'),
  confirmed('已确认'),
  rejected('已拒绝'),
  authorized('已由授权放行'),
  expired('授权已过期，需重新确认'),
  scopeChanged('范围已变化，需重新确认'),
  contentReview('被内容审查要求确认'),
  blocked('被内容审查拦截'),
  externalContent('因外部内容需逐次确认'),
  deleted('已不存在');

  const BusinessStatus(this.label);
  final String label;
  StatusTone get tone => switch (this) {
    success || confirmed || authorized => StatusTone.success,
    failed || blocked => StatusTone.danger,
    warning ||
    expired ||
    scopeChanged ||
    contentReview ||
    externalContent => StatusTone.warn,
    _ => StatusTone.neutral,
  };
  IconData get icon => switch (tone) {
    StatusTone.success => Icons.check_circle_outline,
    StatusTone.danger => Icons.error_outline,
    StatusTone.warn => Icons.warning_amber_rounded,
    StatusTone.neutral =>
      this == pending ? Icons.pending_actions : Icons.info_outline,
  };
  bool get needsDecision => switch (this) {
    pending ||
    expired ||
    scopeChanged ||
    contentReview ||
    externalContent => true,
    _ => false,
  };
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});
  final BusinessStatus status;
  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    final (fg, bg) = switch (status.tone) {
      StatusTone.success => (t.green, t.greenBg),
      StatusTone.danger => (t.red, t.redBg),
      StatusTone.warn => (t.warn, t.warnBg),
      StatusTone.neutral =>
        status == BusinessStatus.pending ? (t.deep, t.tint) : (t.ink2, t.sk),
    };
    return Semantics(
      label: status.label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(MuyonTokens.inputRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(MuyonTokens.space2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(status.icon, color: fg, size: MuyonTokens.iconSize),
              const SizedBox(width: MuyonTokens.space2),
              Flexible(
                child: Text(status.label, style: TextStyle(color: fg)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ObjectChip extends StatelessWidget {
  const ObjectChip({
    super.key,
    required this.label,
    this.onPressed,
    this.missing = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool missing;
  @override
  Widget build(BuildContext context) {
    final text = missing ? '$label，${BusinessStatus.deleted.label}' : label;
    if (missing) {
      final color = MuyonTokens.of(context).ink3;
      return Semantics(
        label: text,
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.all(MuyonTokens.space2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link_off, color: color),
              const SizedBox(width: 8),
              Flexible(
                child: Text(text, style: TextStyle(color: color)),
              ),
            ],
          ),
        ),
      );
    }
    return ActionSurface(
      label: text,
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.article_outlined),
          const SizedBox(width: 8),
          Flexible(child: Text(text)),
        ],
      ),
    );
  }
}

class ScopeChip extends StatefulWidget {
  const ScopeChip({super.key, required this.label, this.objects = const []});
  final String label;
  final List<String> objects;
  @override
  State<ScopeChip> createState() => _ScopeChipState();
}

class _ScopeChipState extends State<ScopeChip> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ActionSurface(
          label: '范围：${widget.label}，${expanded ? "收起" : "展开"}',
          background: t.tint,
          foreground: t.deep,
          onPressed: () => setState(() => expanded = !expanded),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text('范围：${widget.label}')),
              Icon(expanded ? Icons.expand_less : Icons.expand_more),
            ],
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final object in widget.objects) Text(object),
                if (widget.objects.isEmpty) const Text('范围内没有选中对象'),
                const Text('只读范围内对象，不顺着关系读取'),
              ],
            ),
          ),
      ],
    );
  }
}

class SegmentedPill extends StatelessWidget {
  const SegmentedPill({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  }) : assert(labels.length >= 2 && labels.length <= 3),
       assert(selected >= 0 && selected < labels.length);
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.sk,
        borderRadius: BorderRadius.circular(MuyonTokens.pillRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (var i = 0; i < labels.length; i++)
              ActionSurface(
                label: labels[i],
                selected: i == selected,
                background: i == selected ? t.sf : t.sk,
                foreground: i == selected ? t.deep : t.ink2,
                onPressed: () => onChanged(i),
                child: Text(labels[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.filled = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;
  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    return ActionSurface(
      label: label,
      onPressed: onPressed,
      background: filled ? t.acc : t.sf,
      foreground: filled ? t.onacc : t.ink,
      child: Icon(icon),
    );
  }
}

class TitlePill extends StatelessWidget {
  const TitlePill({super.key, required this.label, this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => ActionSurface(
    label: label,
    onPressed: onPressed,
    background: MuyonTokens.of(context).sk,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label)),
        if (onPressed != null) const Icon(Icons.expand_more),
      ],
    ),
  );
}
