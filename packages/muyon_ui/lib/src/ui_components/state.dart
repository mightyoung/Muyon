import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';

/// The four states every library component implements, besides normal use.
///
/// [readOnly] shows the content with every control disabled, [loading] a
/// placeholder of the same footprint, [error] a short reason, and [degraded]
/// the component's text equivalent instead of its visual form (used when the
/// data cannot be drawn, for example a malformed binding).
enum UiComponentState {
  ready,
  readOnly,
  loading,
  error,
  degraded;

  String get label => switch (this) {
    ready => '正常',
    readOnly => '只读',
    loading => '加载中',
    error => '出错',
    degraded => '降级显示',
  };
}

/// Smallest tap target; 200% text must not push content outside its box.
const double uiMinTarget = MuyonTokens.minimumTarget;

/// Gives [child] at least [uiMinTarget] in both directions.
class UiMinTarget extends StatelessWidget {
  const UiMinTarget({super.key, required this.child, this.alignment});
  final Widget child;
  final AlignmentGeometry? alignment;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(
      minWidth: uiMinTarget,
      minHeight: uiMinTarget,
    ),
    child: alignment == null
        ? child
        : Align(alignment: alignment!, child: child),
  );
}

/// One wrapper for the non-ready states and for the text equivalent.
///
/// [textEquivalent] is what a screen reader announces and what "复制文字"
/// copies; it is also what [UiComponentState.degraded] shows.
class UiComponentFrame extends StatelessWidget {
  const UiComponentFrame({
    super.key,
    required this.state,
    required this.textEquivalent,
    required this.child,
    this.errorMessage,
    this.placeholderHeight = 72,
    this.excludeChildSemantics = false,
  });
  final UiComponentState state;
  final String textEquivalent;
  final String? errorMessage;
  final double placeholderHeight;

  /// Display-only components read as one sentence; interactive ones keep
  /// their own controls reachable.
  final bool excludeChildSemantics;
  final Widget child;

  void _copy() => Clipboard.setData(ClipboardData(text: textEquivalent));

  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    final copy = <CustomSemanticsAction, VoidCallback>{
      const CustomSemanticsAction(label: '复制文字'): _copy,
    };
    switch (state) {
      case UiComponentState.loading:
        return Semantics(
          container: true,
          liveRegion: true,
          label: '加载中：$textEquivalent',
          excludeSemantics: true,
          child: Container(
            height: placeholderHeight,
            decoration: BoxDecoration(
              color: t.sunken,
              borderRadius: BorderRadius.circular(MuyonTokens.radius),
            ),
            alignment: Alignment.center,
            child: Text('加载中…', style: TextStyle(color: t.ink3)),
          ),
        );
      case UiComponentState.error:
        return Semantics(
          container: true,
          liveRegion: true,
          label: '出错：${errorMessage ?? '无法显示'}。$textEquivalent',
          excludeSemantics: true,
          customSemanticsActions: copy,
          child: _Box(
            background: t.redBg,
            border: t.red,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  color: t.red,
                  size: MuyonTokens.iconSize,
                ),
                const SizedBox(width: MuyonTokens.space2),
                Expanded(
                  child: Text(
                    errorMessage ?? '无法显示这部分内容',
                    style: TextStyle(color: t.red),
                  ),
                ),
              ],
            ),
          ),
        );
      case UiComponentState.degraded:
        return Semantics(
          container: true,
          label: '已降级为文字：$textEquivalent',
          excludeSemantics: true,
          customSemanticsActions: copy,
          child: _Box(
            background: t.sunken,
            border: t.rule,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('无法按原样显示，已改为文字', style: TextStyle(color: t.ink3)),
                const SizedBox(height: MuyonTokens.space2),
                SelectableText(textEquivalent, style: TextStyle(color: t.ink)),
              ],
            ),
          ),
        );
      case UiComponentState.ready:
      case UiComponentState.readOnly:
        // Controls inside stay their own nodes (explicitChildNodes), so a
        // screen reader gets the summary and each control separately.
        return Semantics(
          container: true,
          explicitChildNodes: true,
          label: textEquivalent,
          excludeSemantics: excludeChildSemantics,
          customSemanticsActions: copy,
          child: child,
        );
    }
  }
}

/// The four states for components that predate the library (UI-1a).
///
/// [UiComponentState.ready] builds the component exactly as before, so its
/// look and semantics do not change; [UiComponentState.readOnly] builds it
/// with every control off (`interactive: false`); the other states use the
/// library's [UiComponentFrame].
class UiStateGate extends StatelessWidget {
  const UiStateGate({
    super.key,
    required this.state,
    required this.textEquivalent,
    required this.builder,
    this.errorMessage,
    this.placeholderHeight = uiMinTarget,
  });
  final UiComponentState state;
  final String textEquivalent;
  final String? errorMessage;
  final double placeholderHeight;
  final Widget Function(BuildContext context, bool interactive) builder;

  @override
  Widget build(BuildContext context) => switch (state) {
    UiComponentState.ready => builder(context, true),
    UiComponentState.readOnly => Semantics(
      readOnly: true,
      child: builder(context, false),
    ),
    _ => UiComponentFrame(
      state: state,
      textEquivalent: textEquivalent,
      errorMessage: errorMessage,
      placeholderHeight: placeholderHeight,
      child: const SizedBox.shrink(),
    ),
  };
}

class _Box extends StatelessWidget {
  const _Box({
    required this.background,
    required this.border,
    required this.child,
  });
  final Color background, border;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(MuyonTokens.space3),
    decoration: BoxDecoration(
      color: background,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(MuyonTokens.radius),
    ),
    child: child,
  );
}

/// Defensive JSON-ish readers for bound values; `null` means "cannot draw".
String? uiString(Object? v) =>
    v is String ? v : (v is num || v is bool ? '$v' : null);
double? uiNum(Object? v) =>
    v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
List<Object?>? uiList(Object? v) => v is List ? v : null;
Map<String, Object?>? uiMap(Object? v) =>
    v is Map ? {for (final e in v.entries) '${e.key}': e.value} : null;

/// Formats a number without a trailing `.0`.
String uiFormatNumber(num v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);
