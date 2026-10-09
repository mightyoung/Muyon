import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:research_module/research_module.dart';

class ParsedDocument {
  ParsedDocument(this.digest, this.pages);
  final String digest;
  final List<String> pages;
}

class DocumentParser {
  static const version = 'pdfrx-engine-0.6.1/plain-v1';

  /// Reuses the parser without requiring a research object or importing one.
  Future<ParsedDocument> parseInput(String path, String displayName) => parse(
    ResearchDocument(
      id: 'selected-input',
      projectId: '',
      relativePath: displayName,
      absolutePath: path,
    ),
  );
  Future<ParsedDocument> parse(ResearchDocument document) async {
    final file = File(document.absolutePath);
    if (!await file.exists()) throw StateError('Source file is missing');
    if (await file.length() > 128 * 1024 * 1024) {
      throw StateError('Document exceeds indexing limit');
    }
    final before = (await sha256.bind(file.openRead()).first).toString();
    final pages = <String>[];
    if (document.isPdf) {
      await pdfrxFlutterInitialize();
      final pdf = await PdfDocument.openFile(document.absolutePath);
      try {
        if (pdf.pages.length > 10000) {
          throw StateError('Document has too many pages');
        }
        for (final page in pdf.pages) {
          pages.add((await page.loadText())?.fullText ?? '');
        }
      } finally {
        await pdf.dispose();
      }
    } else {
      final extension = document.relativePath.toLowerCase();
      if (!['.md', '.txt', '.json', '.jsonl', '.csv'].any(extension.endsWith)) {
        throw StateError('Unsupported text document');
      }
      pages.add(utf8.decode(await file.readAsBytes()));
    }
    final after = (await sha256.bind(file.openRead()).first).toString();
    if (before != after) throw StateError('Source changed while parsing');
    if (pages.every((text) => text.trim().isEmpty)) {
      throw StateError('No extractable text; OCR is unavailable');
    }
    if (pages.fold<int>(0, (sum, text) => sum + text.length) > 16000000) {
      throw StateError('Text exceeds indexing limit');
    }
    return ParsedDocument(after, List.unmodifiable(pages));
  }
}
