import 'package:flutter/material.dart';

import 'primitives.dart';
import 'tokens.dart';

class MuyonDialog extends StatelessWidget {
  const MuyonDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = '确认',
    this.onConfirm,
  });
  final String title, message, confirmLabel;
  final VoidCallback? onConfirm;
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                label: '对话框：$title',
                namesRoute: true,
                excludeSemantics: true,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 16),
              Text(message),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: onConfirm == null
                        ? null
                        : () {
                            onConfirm!();
                            Navigator.of(context).pop();
                          },
                    child: Text(confirmLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class MuyonToast extends StatelessWidget {
  const MuyonToast({
    super.key,
    required this.message,
    this.status = BusinessStatus.success,
    this.actionLabel,
    this.onAction,
  });
  final String message;
  final BusinessStatus status;
  final String? actionLabel;
  final VoidCallback? onAction;
  static void show(
    BuildContext context, {
    required String message,
    BusinessStatus status = BusinessStatus.success,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: MuyonToast(
          message: message,
          status: status,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    final (fg, bg) = switch (status.tone) {
      StatusTone.success => (t.green, t.greenBg),
      StatusTone.danger => (t.red, t.redbg),
      StatusTone.warn => (t.warn, t.warnbg),
      StatusTone.neutral => (t.ink, t.sk),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MuyonTokens.optionRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: '${status.label}：$message',
              liveRegion: true,
              excludeSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(status.icon, color: fg),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(message, style: TextStyle(color: fg)),
                  ),
                ],
              ),
            ),
            if (actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(foregroundColor: fg),
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}
