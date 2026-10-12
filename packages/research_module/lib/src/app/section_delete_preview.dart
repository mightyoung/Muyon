import 'dart:async';

import 'package:flutter/material.dart';

import '../core/section_delete_preview.dart';
import '../core/store.dart';

/// A read-only impact snapshot. This dialog never authorizes a deletion.
class SectionDeletePreviewDialog extends StatefulWidget {
  const SectionDeletePreviewDialog({
    super.key,
    required this.store,
    required this.projectId,
    required this.sectionId,
    this.maxLinks = 500,
    this.maxBytes = 1024 * 1024,
  });

  final WorkbenchStore store;
  final String projectId, sectionId;
  final int maxLinks, maxBytes;

  @override
  State<SectionDeletePreviewDialog> createState() =>
      _SectionDeletePreviewDialogState();
}

class _SectionDeletePreviewDialogState
    extends State<SectionDeletePreviewDialog> {
  SectionDeletePreview? _preview;
  bool _stale = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _capture();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _checkCurrent());
  }

  void _capture() {
    try {
      _preview = captureSectionDeletePreview(
        widget.store,
        widget.projectId,
        widget.sectionId,
        maxLinks: widget.maxLinks,
        maxBytes: widget.maxBytes,
      );
      _stale = false;
    } catch (error, stack) {
      // Scope and budget failures must not disclose database details or IDs.
      _reportUnexpected(error, stack, 'capturing a read-only deletion preview');
      _preview = null;
      _stale = false;
    }
  }

  void _checkCurrent() {
    final preview = _preview;
    if (preview == null || _stale || !mounted) return;
    var current = false;
    try {
      current = sectionDeletePreviewIsCurrent(widget.store, preview);
    } catch (error, stack) {
      _reportUnexpected(error, stack, 'checking deletion preview freshness');
      current = false;
    }
    if (!current) setState(() => _stale = true);
  }

  void _reportUnexpected(Object error, StackTrace stack, String operation) {
    if (error is SectionDeletePreviewRefused) return;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'research section delete preview',
        context: ErrorDescription(operation),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return AlertDialog(
      title: const Text('删除章节影响预览'),
      content: SizedBox(
        width: 520,
        height: MediaQuery.sizeOf(context).height * .5,
        child: SingleChildScrollView(
          key: const Key('section-delete-preview-scroll'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('只读预览，不是删除确认'),
              const SizedBox(height: 8),
              const Text('证据实体本身会保留'),
              const SizedBox(height: 12),
              if (preview == null)
                const Text('无法生成完整预览：超出预算或无权读取')
              else ...[
                if (_stale) const Text('预览已过期，请刷新；不能用于删除确认'),
                Text(preview.section.heading),
                Text('将移除 ${preview.totalLinks} 条证据关联'),
                Text(preview.complete ? '完整关联列表' : '不完整预览'),
                const SizedBox(height: 12),
                for (final link in preview.links)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      link.status == 'restricted'
                          ? '受限关联：详情不可读取'
                          : '关联 ${link.linkId ?? "未知"}\n'
                                '证据 ${link.evidenceId ?? "未知"}\n'
                                '${link.type == null ? "类型未知" : "类型 ${link.type}"}',
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(_capture),
          child: const Text('刷新预览'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
