import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/research_module.dart';
import 'package:uuid/uuid.dart';

import '../documents/document_parser.dart';
import '../search/search_service.dart';
import '../../platform/grants/host_authorization_facts.dart';

class KnowledgeDocument {
  const KnowledgeDocument({
    required this.id,
    required this.title,
    required this.path,
    required this.source,
    required this.digest,
    required this.status,
    this.summary = '',
  });
  final String id, title, path, digest, status, summary;
  final ObjectRef source;
}

class KnowledgeHit {
  const KnowledgeHit({
    required this.id,
    required this.documentId,
    required this.title,
    required this.pageIndex,
    required this.text,
    required this.score,
    required this.sourceRef,
  });
  final String id, documentId, title, text;
  final int pageIndex;
  final double score;
  final ObjectRef sourceRef;
}

class KnowledgeParsedDocument extends ParsedDocument {
  KnowledgeParsedDocument(super.digest, super.pages, this.ocrMetadata);
  final Map<int, Map<String, Object?>> ocrMetadata;
}

class KnowledgeService {
  KnowledgeService(
    this.database,
    this.rootPath, {
    DocumentParser? parser,
    this.parseImage,
    this.parsePdf,
    this.authorizationFacts,
  }) : parser = parser ?? DocumentParser();
  final Future<ParsedDocument> Function(String path)? parseImage;
  final Future<ParsedDocument> Function(String path)? parsePdf;
  final ManagedDatabase database;
  final String rootPath;
  final DocumentParser parser;
  final HostAuthorizationFacts? authorizationFacts;

  /// Live check against the owning module. The index is not a source of truth.
  Future<bool> Function(ObjectRef ref)? confirmSource;

  /// One bootstrap assignment: remember [confirm] and return the projection hook.
  void Function(String moduleId, List<ModuleChange> applied) followProjections(
    Future<bool> Function(ObjectRef ref) confirm,
  ) {
    confirmSource = confirm;
    return invalidateApplied;
  }

  /// Deletes indexed copies of module objects that were deleted or revoked.
  /// Runs before the hook returns, so a following search cannot see them.
  void invalidateApplied(String moduleId, List<ModuleChange> applied) {
    final doomed = [
      for (final change in applied)
        if (change.ref.moduleId == moduleId &&
            (change.op == ChangeOp.delete || change.summary == 'revoked'))
          change.ref,
    ];
    if (doomed.isEmpty) return;
    final matches = [
      for (final doc in documents())
        if (doomed.any((ref) => _sameObject(doc.source, ref))) doc,
    ];
    if (matches.isEmpty) return;
    database.raw.execute('BEGIN IMMEDIATE');
    try {
      for (final doc in matches) {
        _removeIndex(doc.id);
        database.raw.execute('DELETE FROM knowledge_documents WHERE id=?', [
          doc.id,
        ]);
      }
      database.raw.execute('COMMIT');
    } catch (_) {
      database.raw.execute('ROLLBACK');
      rethrow;
    }
    for (final doc in matches) {
      final dir = Directory(p.dirname(doc.path));
      if (p.isWithin(rootPath, dir.path) && dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    }
  }

  /// Module-owned text may reach a model only after the module still has it.
  /// A private knowledge file has no other owner.
  Future<bool> allowModelContent(ObjectRef ref) async {
    if (ref.moduleId == 'knowledge') return true;
    final confirm = confirmSource;
    if (confirm == null) return false;
    return confirm(ref);
  }

  static bool _sameObject(ObjectRef source, ObjectRef change) =>
      source.moduleId == change.moduleId &&
      source.objectType == change.objectType &&
      source.objectId == change.objectId &&
      source.nativeProjectId == change.nativeProjectId;
  static const maxFileBytes = 128 * 1024 * 1024;
  static final schema = ModuleSchema(
    version: 4,
    definitionDigest: 'public-knowledge-v4',
    migrations: [
      ModuleMigration(
        version: 1,
        id: 'public-knowledge-v1',
        definitionDigest: 'public-knowledge-v1',
        migrate: (db) {
          SearchService.schema.migrations.single.migrate(db);
          db.execute('''
CREATE TABLE knowledge_documents(id TEXT PRIMARY KEY,title TEXT NOT NULL,path TEXT NOT NULL,source TEXT NOT NULL,digest TEXT NOT NULL,status TEXT NOT NULL,summary TEXT NOT NULL DEFAULT '');
CREATE TABLE knowledge_vectors(document_id TEXT NOT NULL,page_index INTEGER NOT NULL,source_digest TEXT NOT NULL,profile_id TEXT NOT NULL,endpoint_identity TEXT NOT NULL,model_id TEXT NOT NULL,dimension INTEGER NOT NULL,vector_json TEXT NOT NULL,PRIMARY KEY(document_id,page_index,profile_id));
CREATE TABLE transfer_receipts(digest TEXT PRIMARY KEY,receipt_id TEXT NOT NULL,payload TEXT NOT NULL,received_at TEXT NOT NULL);
''');
        },
      ),
      ModuleMigration(
        version: 2,
        id: 'public-knowledge-v2',
        definitionDigest: 'public-knowledge-v2',
        migrate: (db) => db.execute(
          'CREATE TABLE knowledge_ocr(document_id TEXT NOT NULL,page_index INTEGER NOT NULL,source_digest TEXT NOT NULL,metadata TEXT NOT NULL,PRIMARY KEY(document_id,page_index))',
        ),
      ),
      ModuleMigration(
        version: 3,
        id: 'public-knowledge-v3',
        definitionDigest: 'public-knowledge-v3',
        migrate: (db) => db.execute('''
CREATE TABLE transfer_items(
  item_id TEXT PRIMARY KEY,
  peer_fingerprint TEXT NOT NULL,
  path TEXT,
  delivered INTEGER NOT NULL DEFAULT 0,
  attachment_state TEXT NOT NULL,
  attachment_length INTEGER,
  attachment_sha256 TEXT,
  imported INTEGER NOT NULL DEFAULT 0,
  read_at TEXT,
  acceptance TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL
)'''),
      ),
      ModuleMigration(
        version: 4,
        id: 'public-knowledge-v4',
        definitionDigest: 'public-knowledge-v4',
        migrate: (db) => db.execute('''
CREATE TABLE chat_messages(
  peer_fingerprint TEXT NOT NULL,
  message_id TEXT NOT NULL,
  direction TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL,
  sent_at TEXT,
  received_at TEXT,
  send_state TEXT,
  error TEXT,
  read_at TEXT,
  acceptance TEXT NOT NULL DEFAULT 'none',
  package_item_id TEXT,
  PRIMARY KEY (peer_fingerprint, message_id)
)'''),
      ),
    ],
  );

  static ObjectRef decodeRef(Map data) => ObjectRef(
    moduleId: data['moduleId'] as String,
    objectType: data['objectType'] as String,
    objectId: data['objectId'] as String,
    nativeProjectId: data['nativeProjectId'] as String?,
    revisionRef: data['revisionRef'] as String?,
    contentDigest: data['contentDigest'] as String?,
  );

  List<KnowledgeDocument> documents() => [
    for (final r in database.raw.select(
      'SELECT * FROM knowledge_documents ORDER BY rowid DESC',
    ))
      KnowledgeDocument(
        id: r['id'] as String,
        title: r['title'] as String,
        path: r['path'] as String,
        source: decodeRef(jsonDecode(r['source'] as String) as Map),
        digest: r['digest'] as String,
        status: r['status'] as String,
        summary: r['summary'] as String,
      ),
  ];
  KnowledgeDocument require(String id) =>
      documents().where((d) => d.id == id).firstOrNull ??
      (throw StateError('knowledge_document_missing'));
  List<ObjectRef> objects() {
    final refs = <String, ObjectRef>{};
    for (final doc in documents()) {
      final source = doc.source,
          key = jsonEncode([
            source.moduleId,
            source.objectType,
            source.nativeProjectId,
            source.objectId,
          ]);
      refs.putIfAbsent(key, () => source);
    }
    return refs.values.toList(growable: false);
  }

  Future<KnowledgeDocument> importFile(
    String path, {
    ObjectRef? source,
    void Function()? checkBeforeEffect,
    String? expectedDigest,
  }) async {
    checkBeforeEffect?.call();
    final input = File(path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file ||
        await input.length() > maxFileBytes) {
      throw const FormatException('File missing, linked or too large');
    }
    final ext = p.extension(path).toLowerCase();
    if (!{
      '.pdf',
      '.txt',
      '.md',
      '.markdown',
      '.json',
      '.jsonl',
      '.csv',
      '.png',
      '.jpg',
      '.jpeg',
      '.webp',
      '.bmp',
    }.contains(ext)) {
      throw const FormatException('Unsupported knowledge file');
    }
    final id = const Uuid().v4();
    final dir = Directory(p.join(rootPath, id));
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, p.basename(path)));
    try {
      final before = await fileDigest(input.path);
      if (expectedDigest != null && before != expectedDigest) {
        throw StateError('File differs from approved digest');
      }
      checkBeforeEffect?.call();
      await input.copy(target.path);
      if (await target.length() > maxFileBytes ||
          await fileDigest(target.path) != before ||
          await fileDigest(input.path) != before) {
        throw StateError('Source changed during import');
      }
      if (source?.contentDigest != null && source!.contentDigest != before) {
        throw StateError('Source digest does not match selected file');
      }
      final ref = source == null
          ? ObjectRef(
              moduleId: 'knowledge',
              objectType: 'document',
              objectId: id,
              contentDigest: before,
            )
          : ObjectRef(
              moduleId: source.moduleId,
              objectType: source.objectType,
              objectId: source.objectId,
              nativeProjectId: source.nativeProjectId,
              revisionRef: source.revisionRef,
              contentDigest: before,
            );
      // Different DB owners cannot share one SQL transaction. Commit the
      // conservative host marker first; failure prevents document acceptance.
      // A later domain failure may retain taint, never clear it.
      if (authorizationFacts != null) {
        await authorizationFacts!.markSourceExternal(
          HostSourceFact.object(ref),
        );
        await authorizationFacts!.markSourceExternal(
          HostSourceFact.object(
            ObjectRef(
              moduleId: 'knowledge',
              objectType: 'document',
              objectId: id,
              contentDigest: before,
            ),
          ),
        );
      }
      await database.write((db) {
        checkBeforeEffect?.call();
        db.execute(
          'INSERT INTO knowledge_documents(id,title,path,source,digest,status) VALUES(?,?,?,?,?,?)',
          [
            id,
            p.basename(path),
            target.path,
            jsonEncode(ref.toJson()),
            before,
            'imported',
          ],
        );
      });
      return require(id);
    } catch (_) {
      await dir.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> index(String id, {void Function()? checkBeforeEffect}) async {
    final doc = require(id);
    await database.write((db) {
      checkBeforeEffect?.call();
      db.execute(
        "UPDATE knowledge_documents SET status='indexing',summary='' WHERE id=?",
        [id],
      );
    });
    try {
      final image = {
        '.png',
        '.jpg',
        '.jpeg',
        '.webp',
        '.bmp',
      }.contains(p.extension(doc.path).toLowerCase());
      final pdf = p.extension(doc.path).toLowerCase() == '.pdf';
      final parsed = image && parseImage != null
          ? await parseImage!(doc.path)
          : pdf && parsePdf != null
          ? await parsePdf!(doc.path)
          : await parser.parse(
              ResearchDocument(
                id: id,
                projectId: 'public',
                relativePath: doc.title,
                absolutePath: doc.path,
              ),
            );
      if (parsed.digest != doc.digest || !await isCurrent(id)) {
        throw StateError('Source changed before indexing');
      }
      await database.write((db) {
        checkBeforeEffect?.call();
        final current = require(id);
        if (current.digest != parsed.digest) {
          throw StateError('Source replaced');
        }
        _removeIndex(id);
        for (var page = 0; page < parsed.pages.length; page++) {
          db.execute(
            'INSERT INTO page_text(project_id,document_id,digest,page_index,text) VALUES(?,?,?,?,?)',
            ['public', id, parsed.digest, page, parsed.pages[page]],
          );
          db.execute('INSERT INTO page_fts(rowid,tokens) VALUES(?,?)', [
            db.lastInsertRowId,
            SearchService.tokens(parsed.pages[page]).join(' '),
          ]);
        }
        if (parsed is KnowledgeParsedDocument) {
          for (final entry in parsed.ocrMetadata.entries) {
            db.execute('INSERT INTO knowledge_ocr VALUES(?,?,?,?)', [
              id,
              entry.key,
              parsed.digest,
              jsonEncode(entry.value),
            ]);
          }
        }
        db.execute('INSERT INTO index_documents VALUES(?,?,?,?,?,?,?)', [
          'public',
          id,
          parsed.digest,
          DocumentParser.version,
          SearchService.tokenizerVersion,
          'ready',
          null,
        ]);
        db.execute(
          "UPDATE knowledge_documents SET status='ready',summary=? WHERE id=?",
          [
            parsed.pages.first.substring(
              0,
              parsed.pages.first.length.clamp(0, 240),
            ),
            id,
          ],
        );
      });
    } catch (e) {
      await database.write((db) {
        checkBeforeEffect?.call();
        db.execute(
          "UPDATE knowledge_documents SET status='failed',summary=? WHERE id=?",
          [e.toString(), id],
        );
      });
      rethrow;
    }
  }

  void _removeIndex(String id) {
    database.raw.execute(
      'DELETE FROM page_fts WHERE rowid IN(SELECT id FROM page_text WHERE document_id=?)',
      [id],
    );
    database.raw.execute('DELETE FROM page_text WHERE document_id=?', [id]);
    database.raw.execute('DELETE FROM index_documents WHERE document_id=?', [
      id,
    ]);
    database.raw.execute('DELETE FROM knowledge_vectors WHERE document_id=?', [
      id,
    ]);
    database.raw.execute('DELETE FROM knowledge_ocr WHERE document_id=?', [id]);
  }

  Future<bool> isCurrent(String id) async {
    final doc = require(id);
    try {
      return await fileDigest(doc.path) == doc.digest;
    } catch (_) {
      return false;
    }
  }

  static Future<String> fileDigest(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();
  Map<String, Object?>? ocrMetadata(String id, int pageIndex) {
    require(id);
    final rows = database.raw.select(
      'SELECT metadata FROM knowledge_ocr WHERE document_id=? AND page_index=?',
      [id, pageIndex],
    );
    return rows.isEmpty
        ? null
        : Map<String, Object?>.from(
            jsonDecode(rows.single['metadata'] as String) as Map,
          );
  }

  Future<List<KnowledgeHit>> search(
    String query, {
    List<String>? documentIds,
    int limit = 10,
  }) async {
    if (limit < 1 || limit > 100 || query.length > 8192) {
      throw ArgumentError('Search bounds');
    }
    final selected = (documentIds ?? documents().map((d) => d.id).toList())
        .toSet();
    final valid = <String, KnowledgeDocument>{};
    for (final id in selected) {
      final doc = require(id);
      if (doc.status == 'ready' && await isCurrent(id)) {
        final versions = database.raw.select(
          'SELECT parser,tokenizer FROM index_documents WHERE document_id=?',
          [id],
        );
        if (versions.isNotEmpty &&
            versions.single['parser'] == DocumentParser.version &&
            versions.single['tokenizer'] == SearchService.tokenizerVersion) {
          valid[id] = doc;
        }
      } else if (doc.status == 'ready') {
        await database.write(
          (db) => db.execute(
            "UPDATE knowledge_documents SET status='stale' WHERE id=?",
            [id],
          ),
        );
      }
    }
    if (valid.isEmpty || query.trim().isEmpty) return [];
    final placeholders = List.filled(valid.length, '?').join(',');
    final tokens = SearchService.tokens(query).toSet();
    final List<Map<String, Object?>> rows;
    if (tokens.isEmpty && RegExp(r'^[\u3400-\u9fff]$').hasMatch(query.trim())) {
      rows = database.raw
          .select(
            'SELECT *,0.0 AS score FROM page_text WHERE document_id IN($placeholders) AND instr(text,?)>0 LIMIT ?',
            [...valid.keys, query.trim(), limit],
          )
          .map((r) => Map<String, Object?>.from(r))
          .toList();
    } else if (tokens.isNotEmpty) {
      rows = database.raw
          .select(
            'SELECT page_text.*,bm25(page_fts) AS score FROM page_fts JOIN page_text ON page_text.id=page_fts.rowid WHERE page_fts MATCH ? AND document_id IN($placeholders) ORDER BY score,page_index LIMIT ?',
            [tokens.map((t) => '"$t"').join(' OR '), ...valid.keys, limit],
          )
          .map((r) => Map<String, Object?>.from(r))
          .toList();
    } else {
      return [];
    }
    final hits = <KnowledgeHit>[];
    for (final row in rows) {
      final doc = valid[row['document_id']]!;
      if (!await isCurrent(doc.id)) continue;
      hits.add(
        KnowledgeHit(
          id: '${doc.id}:${row['page_index']}',
          documentId: doc.id,
          title: doc.title,
          pageIndex: row['page_index'] as int,
          text: row['text'] as String,
          score: (row['score'] as num).toDouble(),
          sourceRef: doc.source,
        ),
      );
    }
    return hits;
  }

  Future<void> delete(String id, {void Function()? checkBeforeEffect}) async {
    final doc = require(id);
    await database.write((db) {
      checkBeforeEffect?.call();
      _removeIndex(id);
      db.execute('DELETE FROM knowledge_documents WHERE id=?', [id]);
    });
    final dir = Directory(p.dirname(doc.path));
    if (p.isWithin(rootPath, dir.path) && await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
