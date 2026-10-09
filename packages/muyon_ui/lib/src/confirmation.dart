import 'package:flutter/material.dart';

import 'primitives.dart';
import 'tokens.dart';
import 'theme.dart';
import 'ui_components/state.dart';

enum ConfirmationKind {
  read('只读'),
  write('写入'),
  outboundNew('外传 · 新端点'),
  outboundKnown('外传 · 已授权端点'),
  model('远程模型');

  const ConfirmationKind(this.label);
  final String label;
  bool get outbound =>
      this == outboundNew || this == outboundKnown || this == model;
}

enum ConfirmationChoice {
  once('仅这一次'),
  sendOnce('仅发送这一次'),
  conversation('本次对话允许'),
  endpointConversation('本次对话允许发往此端点'),
  reject('拒绝'),
  task('本次任务'),
  always('始终允许');

  const ConfirmationChoice(this.label);
  final String label;
}

enum BatchState {
  pending('待决定'),
  individual('逐项决定'),
  completed('已决定'),
  rejected('已拒绝');

  const BatchState(this.label);
  final String label;
}

@immutable
class ConfirmItem {
  const ConfirmItem({
    required this.kind,
    required this.what,
    required this.who,
    required this.payload,
    required this.digest,
    required this.consequence,
  });
  final ConfirmationKind kind;
  final String what, who, payload, digest, consequence;
  @override
  bool operator ==(Object other) =>
      other is ConfirmItem &&
      kind == other.kind &&
      what == other.what &&
      who == other.who &&
      payload == other.payload &&
      digest == other.digest &&
      consequence == other.consequence;
  @override
  int get hashCode =>
      Object.hash(kind, what, who, payload, digest, consequence);
}

class ConfirmCard extends StatefulWidget {
  const ConfirmCard({
    super.key,
    required this.item,
    this.status = BusinessStatus.pending,
    this.externalContent = false,
    this.allowPersistentChoices = true,
    this.onDecision,
    this.uiState = UiComponentState.ready,
    this.errorMessage,
  });
  final ConfirmItem item;
  final BusinessStatus status;
  final bool externalContent;
  final bool allowPersistentChoices;
  final ValueChanged<ConfirmationChoice>? onDecision;

  /// Library state (AIUI-2); [UiComponentState.ready] is the UI-1a card.
  /// Read-only shows the card with every decision disabled.
  final UiComponentState uiState;
  final String? errorMessage;

  String get textEquivalent =>
      '确认卡（${item.kind.label}，${status.label}）：${item.what}；对谁：${item.who}'
      '${item.consequence.isEmpty ? '' : '；后果：${item.consequence}'}';
  @override
  State<ConfirmCard> createState() => _ConfirmCardState();
}

class _ConfirmCardState extends State<ConfirmCard> {
  bool expanded = false, more = false;
  bool _interactive = true;
  @override
  void didUpdateWidget(covariant ConfirmCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item != widget.item || oldWidget.status != widget.status) {
      expanded = false;
      more = false;
    }
  }

  Widget field(String label, Widget value) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        value,
      ],
    ),
  );
  Widget choice(
    ConfirmationChoice value, {
    bool primary = false,
    String? label,
  }) {
    final t = MuyonTokens.of(context);
    return TextButton(
      onPressed: widget.onDecision == null || !_interactive
          ? null
          : () => widget.onDecision!(value),
      style: primary
          ? TextButton.styleFrom(
              backgroundColor: t.acc,
              foregroundColor: t.onacc,
            )
          : null,
      child: Text(label ?? value.label),
    );
  }

  @override
  Widget build(BuildContext context) => UiStateGate(
    state: widget.uiState,
    textEquivalent: widget.textEquivalent,
    errorMessage: widget.errorMessage,
    builder: (context, interactive) {
      _interactive = interactive;
      return _card(context);
    },
  );

  Widget _card(BuildContext context) {
    final t = MuyonTokens.of(context);
    final item = widget.item;
    final active =
        widget.status.needsDecision && item.kind != ConfirmationKind.read;
    final external =
        widget.externalContent ||
        widget.status == BusinessStatus.externalContent;
    final choices = switch (item.kind) {
      ConfirmationKind.write => [
        ConfirmationChoice.once,
        ConfirmationChoice.reject,
      ],
      ConfirmationKind.outboundNew => [
        ConfirmationChoice.sendOnce,
        ConfirmationChoice.reject,
      ],
      ConfirmationKind.outboundKnown => [
        ConfirmationChoice.sendOnce,
        if (!external) ConfirmationChoice.conversation,
        ConfirmationChoice.reject,
      ],
      ConfirmationKind.model => [
        ConfirmationChoice.once,
        if (!external) ConfirmationChoice.endpointConversation,
        ConfirmationChoice.reject,
      ],
      ConfirmationKind.read => <ConfirmationChoice>[],
    };
    final allowMore =
        widget.allowPersistentChoices &&
        active &&
        item.kind == ConfirmationKind.write &&
        !external &&
        widget.status != BusinessStatus.contentReview;
    return UiPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusBadge(status: widget.status),
          const SizedBox(height: 8),
          Text(
            item.kind.label,
            style: TextStyle(
              color: item.kind.outbound
                  ? t.red
                  : item.kind == ConfirmationKind.write
                  ? t.deep
                  : t.ink2,
            ),
          ),
          field('做什么', Text(item.what)),
          field('对谁', Text(item.who)),
          field(
            '发送内容',
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton(
                  onPressed: () => setState(() => expanded = !expanded),
                  child: Text(expanded ? '收起内容' : '展开内容'),
                ),
                if (expanded) Text(item.payload),
              ],
            ),
          ),
          field(
            '摘要散列',
            Text(
              item.digest,
              style: const TextStyle(
                fontFamily: monoFamily,
                fontFamilyFallback: monoFallback,
              ),
            ),
          ),
          field('后果', Text(item.consequence)),
          if (external) const WarnBanner(),
          if (active)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < choices.length; i++)
                    choice(choices[i], primary: i == 0),
                  if (allowMore)
                    TextButton(
                      onPressed: () => setState(() => more = !more),
                      child: const Text('更多'),
                    ),
                ],
              ),
            ),
          if (allowMore && more)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  choice(ConfirmationChoice.task),
                  choice(ConfirmationChoice.conversation, label: '本次对话'),
                  choice(ConfirmationChoice.always),
                  const Text('同一工具、同一范围：当前项目 / 当前工作区'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A decorative panel only; content is never clipped or height-constrained.
class UiPanel extends StatelessWidget {
  const UiPanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.sf,
        border: Border.all(color: t.rule),
        borderRadius: BorderRadius.circular(MuyonTokens.cardRadius),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class BatchConfirmCard extends StatelessWidget {
  const BatchConfirmCard({
    super.key,
    required this.items,
    this.externalContent = false,
    this.state = BatchState.pending,
    this.onAllowAll,
    this.onIndividual,
    this.onReject,
    this.uiState = UiComponentState.ready,
    this.errorMessage,
  });
  final List<ConfirmItem> items;
  final bool externalContent;
  final BatchState state;
  final VoidCallback? onAllowAll, onIndividual, onReject;

  /// Library state (AIUI-2); named apart from [state] (the batch's status).
  final UiComponentState uiState;
  final String? errorMessage;

  String get textEquivalent =>
      '批量确认（${state.label}），${items.length} 项：'
      '${items.map((i) => '${i.kind.label} ${i.what}').join('；')}';

  @override
  Widget build(BuildContext context) => UiStateGate(
    state: uiState,
    textEquivalent: textEquivalent,
    errorMessage: errorMessage,
    builder: _card,
  );

  Widget _card(BuildContext context, bool interactive) {
    final onAllowAll = interactive ? this.onAllowAll : null;
    final onIndividual = interactive ? this.onIndividual : null;
    final onReject = interactive ? this.onReject : null;
    if (items.any((item) => item.kind == ConfirmationKind.read))
      throw ArgumentError(
        'Read-only operations do not enter batch confirmation',
      );
    final t = MuyonTokens.of(context);
    return UiPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(state.label, style: Theme.of(context).textTheme.titleMedium),
          if (externalContent) const WarnBanner(),
          if (items.isEmpty) const Text('没有需要决定的操作'),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.what),
                  Text('对谁：${item.who}'),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: item.kind.outbound ? t.redbg : t.tint,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        item.kind.label,
                        style: TextStyle(
                          color: item.kind.outbound ? t.red : t.deep,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (items.isNotEmpty &&
              (state == BatchState.pending || state == BatchState.individual))
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!externalContent)
                  TextButton(onPressed: onAllowAll, child: const Text('全部允许')),
                TextButton(onPressed: onIndividual, child: const Text('逐项决定')),
                TextButton(onPressed: onReject, child: const Text('拒绝')),
              ],
            ),
        ],
      ),
    );
  }
}

class WarnBanner extends StatelessWidget {
  const WarnBanner({
    super.key,
    this.message = '本任务包含外部内容，已暂停自动放行',
    this.actionLabel,
    this.onAction,
    this.uiState = UiComponentState.ready,
    this.errorMessage,
  });
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Library state (AIUI-2); [UiComponentState.ready] is the UI-1a banner.
  final UiComponentState uiState;
  final String? errorMessage;

  String get textEquivalent => '注意：$message';

  @override
  Widget build(BuildContext context) => UiStateGate(
    state: uiState,
    textEquivalent: textEquivalent,
    errorMessage: errorMessage,
    builder: (context, interactive) =>
        _banner(context, interactive ? onAction : null),
  );

  Widget _banner(BuildContext context, VoidCallback? onAction) {
    final t = MuyonTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.warnbg,
        borderRadius: BorderRadius.circular(MuyonTokens.optionRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: message,
              excludeSemantics: true,
              liveRegion: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: t.warn),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(message, style: TextStyle(color: t.warn)),
                  ),
                ],
              ),
            ),
            if (actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(foregroundColor: t.warn),
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}
