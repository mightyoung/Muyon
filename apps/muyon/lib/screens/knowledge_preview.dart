import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../services/knowledge/knowledge_service.dart';

class KnowledgePreview extends StatelessWidget {
  const KnowledgePreview({super.key, required this.document});
  final KnowledgeDocument document;

  @override
  Widget build(BuildContext context) {
    final extension = p.extension(document.path).toLowerCase();
    if (extension == '.pdf') return PdfViewer.file(document.path);
    if ({'.png', '.jpg', '.jpeg', '.webp', '.bmp'}.contains(extension)) {
      return InteractiveViewer(
        child: Center(child: Image.file(File(document.path))),
      );
    }
    return FutureBuilder<String>(
      future: _text(),
      builder: (context, snapshot) => snapshot.hasError
          ? Center(child: Text('无法预览：${snapshot.error}'))
          : snapshot.data == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SelectableText(snapshot.data!),
            ),
    );
  }

  Future<String> _text() async {
    final file = File(document.path);
    // Preview is bounded independently of the import limit.
    final bytes = await file
        .openRead(0, 1024 * 1024)
        .fold<List<int>>([], (result, chunk) => result..addAll(chunk));
    return utf8.decode(bytes, allowMalformed: true);
  }
}
