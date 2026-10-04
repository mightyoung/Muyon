import 'package:flutter/material.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'source_locator.dart';

/// States the two outcomes of following a source reference separately:
/// the page jump and the text highlight.
class SourceJumpBanner extends StatelessWidget {
  const SourceJumpBanner({
    super.key,
    required this.pageNumber,
    required this.location,
    required this.onDismiss,
  });

  /// 1-based page the reader jumped to.
  final int pageNumber;

  /// Null while the locator is still working.
  final QuoteLocation? location;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final tokens = MuyonTokens.of(context);
    final theme = Theme.of(context);
    final loc = location;
    final unavailable = loc is SourceUnavailable;
    final (String page, String highlight, Color bg, Color fg) = switch (loc) {
      null => ('已回到第 $pageNumber 页', '正在查找原文…', tokens.sunken, tokens.ink2),
      PageOnly(:final reason) => (
        '已回到第 $pageNumber 页（页级回跳）',
        '未做文字高亮：$reason',
        tokens.sunken,
        tokens.ink2,
      ),
      ExactMatch() => (
        '已回到第 $pageNumber 页',
        '已精确定位并高亮原文',
        tokens.greenBg,
        tokens.green,
      ),
      AmbiguousMatch(:final count) => (
        '已回到第 $pageNumber 页（页级回跳）',
        '无法唯一定位：该段文字在此页出现 $count 处，未高亮',
        tokens.amberBg,
        tokens.amber,
      ),
      SourceUnavailable(:final reason) => (
        '无法回到来源',
        reason,
        tokens.redBg,
        tokens.red,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Material(
        color: bg,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MuyonTokens.space3,
            vertical: MuyonTokens.space2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      page,
                      style: theme.textTheme.titleSmall?.copyWith(color: fg),
                    ),
                    if (!unavailable || highlight.isNotEmpty)
                      Text(
                        highlight,
                        style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '关闭提示',
                onPressed: onDismiss,
                icon: Icon(Icons.close, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
