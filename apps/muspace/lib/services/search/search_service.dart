import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:muspace_module_api/muspace_module_api.dart';
import 'package:research_module/research_module.dart';

import '../../workspace/workspace_repository.dart';
import '../documents/document_parser.dart';

class SearchHit {
  const SearchHit({
    required this.document,
    required this.contentDigest,
    required this.pageIndex,
    required this.text,
  });
  final ResearchDocument document;
  final String contentDigest;
  final int pageIndex;
  final String text;
}

class SearchResult {
  const SearchResult(
    this.hits, {
    this.partial = false,
    this.unavailable = const {},
  });
  final List<SearchHit> hits;
  final bool partial;
  final Map<String, String> unavailable;
}

class SearchService {
  SearchService(
    this.database,
    this.workspaces,
    this.store, {
    DocumentParser? parser,
  }) : parser = parser ?? DocumentParser();
  final ManagedDatabase database;
  final WorkspaceRepository workspaces;
  final WorkbenchStore store;
  final DocumentParser parser;
  static const tokenizerVersion = 'cjk-bigram-latin-v1';
  static final schema = ModuleSchema(
    version: 1,
    definitionDigest: 'search-v1',
    migrations: [
      ModuleMigration(
        version: 1,
        id: 'search-v1',
        definitionDigest: 'search-v1',
        migrate: (db) => db.execute('''
CREATE TABLE index_documents(project_id TEXT NOT NULL,document_id TEXT NOT NULL,digest TEXT NOT NULL,parser TEXT NOT NULL,tokenizer TEXT NOT NULL,state TEXT NOT NULL,error TEXT,PRIMARY KEY(project_id,document_id));
CREATE TABLE page_text(id INTEGER PRIMARY KEY,project_id TEXT NOT NULL,document_id TEXT NOT NULL,digest TEXT NOT NULL,page_index INTEGER NOT NULL,text TEXT NOT NULL);
CREATE VIRTUAL TABLE page_fts USING fts5(tokens);
'''),
      ),
    ],
  );

  static List<String> tokens(String text) {
    final values = <String>[];
    final normalized = text.toLowerCase();
    for (final match in RegExp(
      r'[a-z0-9]+|[\u3400-\u9fff]+',
    ).allMatches(normalized)) {
      final word = match.group(0)!;
      if (RegExp(r'^[a-z0-9]').hasMatch(word)) {
        values.add(
          'w${word.codeUnits.map((c) => c.toRadixString(16)).join('_')}',
        );
      } else {
        final chars = word.runes.toList();
        for (var i = 0; i < chars.length - 1; i++) {
          values.add(
            'c${chars[i].toRadixString(16)}_${chars[i + 1].toRadixString(16)}',
          );
        }
      }
    }
    return values;
  }

  void _scope(WorkspaceBinding binding) {
    final current = workspaces.binding(binding.workspaceId, binding.moduleId);
    if (binding.moduleId != 'research' ||
        current?.nativeProjectId != binding.nativeProjectId) {
      throw StateError('scope_mismatch');
    }
  }

  List<ResearchDocument> documents(WorkspaceBinding binding) {
    _scope(binding);
    return currentVersions(store.documents(binding.nativeProjectId));
  }

  Future<String> _digest(ResearchDocument doc) async =>
      (await sha256.bind(File(doc.absolutePath).openRead()).first).toString();

  Future<void> index(
    WorkspaceBinding binding,
    ResearchDocument document,
  ) async {
    _scope(binding);
    if (!documents(binding).any((d) => d.id == document.id)) {
      throw StateError('scope_mismatch');
    }
    final project = binding.nativeProjectId;
    await database.write(
      (db) => db.execute(
        'INSERT OR REPLACE INTO index_documents VALUES(?,?,?,?,?,?,?)',
        [
          project,
          document.id,
          '',
          DocumentParser.version,
          tokenizerVersion,
          'indexing',
          null,
        ],
      ),
    );
    try {
      final parsed = await parser.parse(document);
      _scope(binding);
      if (!documents(binding).any((d) => d.id == document.id) ||
          await _digest(document) != parsed.digest) {
        throw StateError('Source invalidated while indexing');
      }
      await database.write((db) {
        db.execute(
          'DELETE FROM page_fts WHERE rowid IN (SELECT id FROM page_text WHERE project_id=? AND document_id=?)',
          [project, document.id],
        );
        db.execute(
          'DELETE FROM page_text WHERE project_id=? AND document_id=?',
          [project, document.id],
        );
        for (var i = 0; i < parsed.pages.length; i++) {
          db.execute(
            'INSERT INTO page_text(project_id,document_id,digest,page_index,text) VALUES(?,?,?,?,?)',
            [project, document.id, parsed.digest, i, parsed.pages[i]],
          );
          final rowId = db.lastInsertRowId;
          db.execute('INSERT INTO page_fts(rowid,tokens) VALUES(?,?)', [
            rowId,
            tokens(parsed.pages[i]).join(' '),
          ]);
        }
        db.execute(
          'INSERT OR REPLACE INTO index_documents VALUES(?,?,?,?,?,?,?)',
          [
            project,
            document.id,
            parsed.digest,
            DocumentParser.version,
            tokenizerVersion,
            'ready',
            null,
          ],
        );
      });
    } catch (e) {
      await database.write(
        (db) => db.execute(
          'UPDATE index_documents SET state=?,error=? WHERE project_id=? AND document_id=?',
          ['failed', e.toString(), project, document.id],
        ),
      );
      rethrow;
    }
  }

  Future<SearchResult> search(
    WorkspaceBinding binding,
    String question, {
    required Set<String> selectedDocumentIds,
    int limit = 5,
    int scanLimit = 500,
  }) async {
    _scope(binding);
    if (limit < 1 || limit > 100 || scanLimit < 1 || scanLimit > 10000) {
      throw ArgumentError('Invalid search bounds');
    }
    final available = {for (final d in documents(binding)) d.id: d};
    if (!selectedDocumentIds.every(available.containsKey)) {
      throw StateError('Selected source is missing or outside scope');
    }
    if (selectedDocumentIds.isEmpty || question.trim().isEmpty) {
      return const SearchResult([]);
    }
    final valid = <String, ResearchDocument>{};
    final unavailable = <String, String>{};
    for (final id in selectedDocumentIds) {
      final rows = database.raw.select(
        'SELECT * FROM index_documents WHERE project_id=? AND document_id=?',
        [binding.nativeProjectId, id],
      );
      if (rows.isEmpty) {
        unavailable[id] = 'not_indexed';
        continue;
      }
      final row = rows.first;
      if (row['state'] != 'ready') {
        unavailable[id] = row['state'] as String;
        continue;
      }
      try {
        if (row['parser'] != DocumentParser.version ||
            row['tokenizer'] != tokenizerVersion ||
            row['digest'] != await _digest(available[id]!)) {
          unavailable[id] = 'stale';
          continue;
        }
      } catch (_) {
        unavailable[id] = 'missing';
        continue;
      }
      valid[id] = available[id]!;
    }
    if (valid.isEmpty) return SearchResult(const [], unavailable: unavailable);
    final placeholders = List.filled(valid.length, '?').join(',');
    final queryTokens = tokens(question).toSet();
    final singleCjk = RegExp(r'^[\u3400-\u9fff]$').hasMatch(question.trim());
    if (queryTokens.isEmpty && !singleCjk) {
      return SearchResult(const [], unavailable: unavailable);
    }
    final hits = <SearchHit>[];
    var partial = false;
    if (singleCjk) {
      final rows = database.raw.select(
        'SELECT * FROM page_text WHERE project_id=? AND document_id IN ($placeholders) ORDER BY document_id,page_index LIMIT ?',
        [binding.nativeProjectId, ...valid.keys, scanLimit + 1],
      );
      partial = rows.length > scanLimit;
      for (final row in rows.take(scanLimit)) {
        if ((row['text'] as String).contains(question.trim())) {
          hits.add(
            SearchHit(
              document: valid[row['document_id']]!,
              contentDigest: row['digest'] as String,
              pageIndex: row['page_index'] as int,
              text: row['text'] as String,
            ),
          );
        }
      }
    } else {
      final expression = queryTokens.map((token) => '"$token"').join(' OR ');
      final rows = database.raw.select(
        'SELECT page_text.* FROM page_fts JOIN page_text ON page_text.id=page_fts.rowid WHERE page_fts MATCH ? AND project_id=? AND document_id IN ($placeholders) ORDER BY bm25(page_fts),document_id,page_index LIMIT ?',
        [expression, binding.nativeProjectId, ...valid.keys, limit],
      );
      for (final row in rows) {
        hits.add(
          SearchHit(
            document: valid[row['document_id']]!,
            contentDigest: row['digest'] as String,
            pageIndex: row['page_index'] as int,
            text: row['text'] as String,
          ),
        );
      }
    }
    // Scope and physical source identity are rechecked after asynchronous reads.
    _scope(binding);
    final current = {for (final doc in documents(binding)) doc.id: doc};
    final checked = <SearchHit>[];
    for (final hit in hits.take(limit)) {
      if (current.containsKey(hit.document.id) &&
          await _digest(current[hit.document.id]!) == hit.contentDigest) {
        checked.add(hit);
      }
    }
    return SearchResult(
      List.unmodifiable(checked),
      partial: partial,
      unavailable: Map.unmodifiable(unavailable),
    );
  }
}
