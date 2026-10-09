import 'package:flutter/material.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;

import '../app/bootstrap.dart';

import 'package:muyon_module_api/ui_contract.dart' show NavigationAnchor;

import '../services/knowledge/knowledge_service.dart';
import 'knowledge_preview.dart';

/// Reads a file registered by the host. Artifact IDs are never interpreted as
/// arbitrary paths or fetched URLs, and model prose is never a file preview.
class ArtifactPreview extends StatefulWidget {
  const ArtifactPreview({
    super.key,
    required this.host,
    required this.reference,
    required this.anchor,
  });
  final MuyonHost host;
  final ArtifactRef reference;
  final NavigationAnchor anchor;
  @override
  State<ArtifactPreview> createState() => _ArtifactPreviewState();
}

class _ArtifactPreviewState extends State<ArtifactPreview> {
  KnowledgeDocument? document;
  bool ready = false, stale = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      if (widget.reference.moduleId == 'knowledge') {
        final d = widget.host.services.knowledge.require(
          widget.reference.artifactId,
        );
        final current = await widget.host.services.knowledge.isCurrent(d.id);
        if (!mounted) return;
        document = d;
        stale =
            !current ||
            d.digest != widget.reference.contentDigest ||
            (widget.anchor.sourceDigest != null &&
                widget.anchor.sourceDigest != d.digest);
      }
    } catch (_) {
      // A deleted or unavailable artifact keeps its saved return route.
    }
    if (mounted) setState(() => ready = true);
  }

  @override
  Widget build(BuildContext context) {
    final d = document;
    final extension = d == null ? '' : p.extension(d.path).toLowerCase();
    return Scaffold(
      appBar: AppBar(title: Text(d?.title ?? '原文件预览')),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : d == null
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Text('该文件或插件未提供可用预览；原现场仍保留，可以返回。'),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (stale)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('来源已变化，原定位已失效。当前显示实际文件，返回后请重新核对。'),
                  ),
                if ({'.md', '.markdown', '.html', '.htm'}.contains(extension))
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      {'.html', '.htm'}.contains(extension)
                          ? 'HTML 只读文本预览'
                          : 'Markdown 原文预览',
                    ),
                  ),
                Expanded(child: KnowledgePreview(document: d)),
              ],
            ),
    );
  }
}
