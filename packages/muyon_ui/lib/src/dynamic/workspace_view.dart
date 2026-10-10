import 'package:flutter/material.dart';

import 'dart:async';

import 'workspace.dart';
import 'surface.dart';

/// Explicit actions on isolated values; recovery never invokes a business port.
class UiDraftRecoveryActions extends StatelessWidget {
  const UiDraftRecoveryActions({super.key, required this.controller});
  final UiWorkspaceController controller;

  Future<void> resolve(String key, bool discard) async {
    try {
      await controller.resolveDraft(key, discard: discard);
    } catch (_) {
      // The controller preserves the draft and exposes the error in the view.
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final entry in controller.quarantinedDraft.entries)
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          SelectableText('隔离 ${entry.key}: ${entry.value}'),
          TextButton(
            onPressed: controller.canResolveDraft
                ? () => resolve(entry.key, false) : null,
            child: Text('恢复 ${entry.key}'),
          ),
          TextButton(
            onPressed: controller.canResolveDraft
                ? () => resolve(entry.key, true) : null,
            child: Text('丢弃 ${entry.key}（采用当前提取值）'),
          ),
        ]),
    ],
  );
}

/// Same view for native storage and public browser fixtures. The caller owns
/// controller lifetime; back waits for the durable checkpoint.
class UiWorkspaceView extends StatefulWidget {
  const UiWorkspaceView({
    super.key,
    required this.controller,
    required this.originalAnswer,
    this.banner,
    this.references,
  });
  final UiWorkspaceController controller;
  final String originalAnswer;
  final String? banner;
  final Widget? references;
  @override
  State<UiWorkspaceView> createState() => _UiWorkspaceViewState();
}

class _UiWorkspaceViewState extends State<UiWorkspaceView> {
  late final ScrollController scroll = ScrollController(
    initialScrollOffset: widget.controller.scrollOffset,
  );
  bool leaving = false;
  bool returning = false;
  UiWorkspaceController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.addListener(changed);
    scroll.addListener(scrolled);
  }

  void scrolled() {
    if (!scroll.hasClients || returning || c.readOnly) return;
    c.scrollOffset = scroll.offset < 0 ? 0 : scroll.offset;
    unawaited(c.flush().catchError((Object _) {}));
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(changed);
    scroll.dispose();
    super.dispose();
  }

  Future<void> back() async {
    if (leaving || returning) return;
    returning = true;
    c.scrollOffset = scroll.hasClients ? scroll.offset : c.scrollOffset;
    try {
      await c.flush();
      if (mounted) {
        setState(() => leaving = true);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.of(context).pop();
      }
    } catch (_) {
      returning = false;
      changed();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaving,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) back();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('草稿现场'),
        leading: IconButton(
          onPressed: back,
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SingleChildScrollView(
        controller: scroll,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.banner != null) Text(widget.banner!),
              if (widget.references != null) widget.references!,
              Text(
                'Current surface revision: ${c.surface.current.plan.revision}',
              ),
              if (c.saveError != null) ...[
                Text('保存失败，旧草稿仍保留：${c.saveError}'),
                TextButton(
                  onPressed: () {
                    setState(() => leaving = true);
                    Navigator.of(context).pop();
                  },
                  child: const Text('返回（仅保留上次保存）'),
                ),
              ],
              if (c.readOnly) ...[
                const Text('版本已变化，保留旧草稿供阅读。重新核对后再继续。'),
                for (final entry in (c.readableDraft ?? {}).entries)
                  SelectableText('${entry.key}: ${entry.value}'),
              ] else ...[
                DynamicUiSurface(
                  plan: c.surface.current,
                  controller: c.surface,
                ),
                for (final entry in c.surface.session.userOverrides.entries)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '人工 ${entry.key}: ${entry.value} · 提取建议 ${c.surface.current.snapshot.initialUiState[entry.key]}',
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          try {
                            await c.adoptExtracted(entry.key);
                          } catch (_) {
                            changed();
                          }
                        },
                        child: const Text('采用提取值'),
                      ),
                    ],
                  ),
              ],
              UiDraftRecoveryActions(controller: c),
              for (final e in c.recoveredOperations.entries)
                Text('回执 ${e.key}: ${e.value.name} · 未自动重放'),
              Text('继续步骤：${c.step}'),
              if (c.selectedRecords.isNotEmpty)
                Text('选中记录：${c.selectedRecords.join(', ')}'),
              SelectableText(widget.originalAnswer),
            ],
          ),
        ),
      ),
    ),
  );
}
