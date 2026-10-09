import 'package:flutter/material.dart';

import '../tokens.dart';
import 'state.dart';

/// A heading, level 1 (page) to 3 (group).
class Heading extends StatelessWidget {
  const Heading({
    super.key,
    required this.text,
    this.level = 2,
    this.state = UiComponentState.ready,
    this.errorMessage,
  });
  final String text;
  final int level;
  final UiComponentState state;
  final String? errorMessage;

  String get textEquivalent => text;

  @override
  Widget build(BuildContext context) {
    final style = switch (level.clamp(1, 3)) {
      1 => Theme.of(context).textTheme.headlineSmall,
      2 => Theme.of(context).textTheme.titleLarge,
      _ => Theme.of(context).textTheme.titleMedium,
    };
    return UiComponentFrame(
      state: state,
      textEquivalent: textEquivalent,
      errorMessage: errorMessage,
      placeholderHeight: 32,
      excludeChildSemantics: true,
      child: Semantics(
        header: true,
        child: Text(text, style: style?.copyWith(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// Running text. Paragraphs are separated by a blank line; text is selectable.
class Prose extends StatelessWidget {
  const Prose({
    super.key,
    required this.text,
    this.state = UiComponentState.ready,
    this.errorMessage,
  });
  final String text;
  final UiComponentState state;
  final String? errorMessage;

  String get textEquivalent => text;

  @override
  Widget build(BuildContext context) {
    final paragraphs = text.split(RegExp(r'\n\s*\n'));
    return UiComponentFrame(
      state: state,
      textEquivalent: textEquivalent,
      errorMessage: errorMessage,
      excludeChildSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < paragraphs.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == paragraphs.length - 1 ? 0 : MuyonTokens.space3,
              ),
              child: SelectableText(
                paragraphs[i].trim(),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
        ],
      ),
    );
  }
}

/// A titled group with a rule and padding; children keep their own meaning.
class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.title,
    required this.children,
    this.state = UiComponentState.ready,
    this.errorMessage,
  });
  final String title;
  final List<Widget> children;
  final UiComponentState state;
  final String? errorMessage;

  String get textEquivalent => '分组：$title';

  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    return UiComponentFrame(
      state: state,
      textEquivalent: textEquivalent,
      errorMessage: errorMessage,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(MuyonTokens.space4),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.rule),
          borderRadius: BorderRadius.circular(MuyonTokens.cardRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            for (final c in children)
              Padding(
                padding: const EdgeInsets.only(top: MuyonTokens.space3),
                child: c,
              ),
          ],
        ),
      ),
    );
  }
}

/// Side by side when there is room, stacked when there is not.
class Columns extends StatelessWidget {
  const Columns({
    super.key,
    required this.children,
    this.minColumnWidth = 260,
    this.state = UiComponentState.ready,
    this.errorMessage,
  });
  final List<Widget> children;
  final double minColumnWidth;
  final UiComponentState state;
  final String? errorMessage;

  String get textEquivalent => '${children.length} 栏内容';

  @override
  Widget build(BuildContext context) => UiComponentFrame(
    state: state,
    textEquivalent: textEquivalent,
    errorMessage: errorMessage,
    child: LayoutBuilder(
      builder: (context, box) {
        final fit = (box.maxWidth / minColumnWidth).floor().clamp(
          1,
          children.length < 1 ? 1 : children.length,
        );
        if (fit <= 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in children)
                Padding(
                  padding: const EdgeInsets.only(bottom: MuyonTokens.space3),
                  child: c,
                ),
            ],
          );
        }
        final gap = MuyonTokens.space3;
        final width = (box.maxWidth - gap * (fit - 1)) / fit;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final c in children) SizedBox(width: width, child: c),
          ],
        );
      },
    ),
  );
}

/// Switchable panels. Tabs wrap onto further lines instead of scrolling away.
class MuyonTabs extends StatefulWidget {
  const MuyonTabs({
    super.key,
    required this.labels,
    required this.children,
    this.initial = 0,
    this.state = UiComponentState.ready,
    this.errorMessage,
  }) : assert(labels.length == children.length);
  final List<String> labels;
  final List<Widget> children;
  final int initial;
  final UiComponentState state;
  final String? errorMessage;

  String get textEquivalent => '标签页：${labels.join('、')}';

  @override
  State<MuyonTabs> createState() => _MuyonTabsState();
}

class _MuyonTabsState extends State<MuyonTabs> {
  late int index = widget.initial.clamp(0, widget.labels.length - 1);

  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    final enabled = widget.state == UiComponentState.ready;
    return UiComponentFrame(
      state: widget.state,
      textEquivalent: widget.textEquivalent,
      errorMessage: widget.errorMessage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: MuyonTokens.space2,
            children: [
              for (var i = 0; i < widget.labels.length; i++)
                Semantics(
                  button: true,
                  selected: i == index,
                  label:
                      '${widget.labels[i]}，第 ${i + 1} 个，共 ${widget.labels.length} 个',
                  excludeSemantics: true,
                  onTap: enabled ? () => setState(() => index = i) : null,
                  child: InkWell(
                    key: ValueKey('tab-$i'),
                    borderRadius: BorderRadius.circular(MuyonTokens.pillRadius),
                    onTap: enabled ? () => setState(() => index = i) : null,
                    child: UiMinTarget(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: MuyonTokens.space4,
                          vertical: MuyonTokens.space2,
                        ),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i == index ? t.accentTint : Colors.transparent,
                          borderRadius: BorderRadius.circular(
                            MuyonTokens.pillRadius,
                          ),
                        ),
                        child: Text(
                          widget.labels[i],
                          style: TextStyle(
                            color: i == index ? t.accent : t.ink2,
                            fontWeight: i == index
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: MuyonTokens.space3),
          if (widget.children.isNotEmpty) widget.children[index],
        ],
      ),
    );
  }
}

/// A heading that shows or hides its content.
class Disclosure extends StatefulWidget {
  const Disclosure({
    super.key,
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
    this.state = UiComponentState.ready,
    this.errorMessage,
  });
  final String title;
  final Widget child;
  final bool initiallyExpanded;
  final UiComponentState state;
  final String? errorMessage;

  String get textEquivalent => '可展开：${title}';

  @override
  State<Disclosure> createState() => _DisclosureState();
}

class _DisclosureState extends State<Disclosure> {
  late bool open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    final enabled = widget.state == UiComponentState.ready;
    return UiComponentFrame(
      state: widget.state,
      textEquivalent: widget.textEquivalent,
      errorMessage: widget.errorMessage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            expanded: open,
            label: widget.title,
            excludeSemantics: true,
            onTap: enabled ? () => setState(() => open = !open) : null,
            child: InkWell(
              key: const ValueKey('disclosure-toggle'),
              borderRadius: BorderRadius.circular(MuyonTokens.radius),
              onTap: enabled ? () => setState(() => open = !open) : null,
              child: UiMinTarget(
                child: Row(
                  children: [
                    Icon(
                      open ? Icons.expand_less : Icons.expand_more,
                      color: t.ink2,
                      size: MuyonTokens.iconSize,
                    ),
                    const SizedBox(width: MuyonTokens.space2),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(top: MuyonTokens.space2),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}
