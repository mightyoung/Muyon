import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:muspace_module_api/muspace_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/research_module.dart';
import 'package:uuid/uuid.dart';
import '../documents/document_parser.dart';
import '../search/search_service.dart';

class KnowledgeDocument {
  const KnowledgeDocument({required this.id, required this.title, required this.path,
    required this.source, required this.digest, required this.status, this.summary = ''});
  final String id, title, path, digest, status, summary;
  final ObjectRef source;
}

class KnowledgeHit {
  const KnowledgeHit({required this.id, required this.documentId, required this.title,
    required this.pageIndex, required this.text, required this.score, required this.sourceRef});
  final String id, documentId, title, text;
  final int pageIndex;
  final double score;
  final ObjectRef sourceRef;
}

class KnowledgeService {
  KnowledgeService(this.database, this.rootPath, {DocumentParser? parser}) : parser = parser ?? DocumentParser();
  final ManagedDatabase database;
  final String rootPath;
  final DocumentParser parser;
  static const maxFileBytes = 128 * 1024 * 1024;
  static final schema = ModuleSchema(version: 1, definitionDigest: 'public-knowledge-v1', migrations: [
    ModuleMigration(version: 1, id: 'public-knowledge-v1', definitionDigest: 'public-knowledge-v1', migrate: (db) {
      SearchService.schema.migrations.single.migrate(db);
      db.execute('''
CREATE TABLE knowledge_documents(id TEXT PRIMARY KEY,title TEXT NOT NULL,path TEXT NOT NULL,source TEXT NOT NULL,digest TEXT NOT NULL,status TEXT NOT NULL,summary TEXT NOT NULL DEFAULT '');
CREATE TABLE knowledge_vectors(document_id TEXT NOT NULL,page_index INTEGER NOT NULL,source_digest TEXT NOT NULL,profile_id TEXT NOT NULL,endpoint_identity TEXT NOT NULL,model_id TEXT NOT NULL,dimension INTEGER NOT NULL,vector_json TEXT NOT NULL,PRIMARY KEY(document_id,page_index,profile_id));
CREATE TABLE transfer_receipts(digest TEXT PRIMARY KEY,receipt_id TEXT NOT NULL,payload TEXT NOT NULL,received_at TEXT NOT NULL);
''');
    }),
  ]);

  static ObjectRef decodeRef(Map data) => ObjectRef(moduleId: data['moduleId'] as String,
    objectType: data['objectType'] as String, objectId: data['objectId'] as String,
    nativeProjectId: data['nativeProjectId'] as String?, revisionRef: data['revisionRef'] as String?,
    contentDigest: data['contentDigest'] as String?);

  List<KnowledgeDocument> documents() => [for (final r in database.raw.select('SELECT * FROM knowledge_documents ORDER BY rowid DESC'))
    KnowledgeDocument(id: r['id'] as String, title: r['title'] as String, path: r['path'] as String,
      source: decodeRef(jsonDecode(r['source'] as String) as Map), digest: r['digest'] as String,
      status: r['status'] as String, summary: r['summary'] as String)];
  KnowledgeDocument require(String id) => documents().where((d) => d.id == id).firstOrNull ?? (throw StateError('knowledge_document_missing'));
  List<ObjectRef> objects() => documents().map((d) => d.source).toList(growable: false);

  Future<KnowledgeDocument> importFile(String path, {ObjectRef? source}) async {
    final input = File(path);
    if (await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.file ||
        await input.length() > maxFileBytes) throw const FormatException('File missing, linked or too large');
    final ext = p.extension(path).toLowerCase();
    if (!{'.pdf','.txt','.md','.markdown','.json','.jsonl','.csv'}.contains(ext)) {
      throw const FormatException('Unsupported knowledge file');
    }
    final id = const Uuid().v4();
    final dir = Directory(p.join(rootPath, id));
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, p.basename(path)));
    try {
      final before = await fileDigest(input.path);
      await input.copy(target.path);
      if (await target.length() > maxFileBytes || await fileDigest(target.path) != before || await fileDigest(input.path) != before) {
        throw StateError('Source changed during import');
      }
      if (source?.contentDigest != null && source!.contentDigest != before) throw StateError('Source digest does not match selected file');
      final ref = source == null
        ? ObjectRef(moduleId: 'knowledge', objectType: 'document', objectId: id, contentDigest: before)
        : ObjectRef(moduleId: source.moduleId, objectType: source.objectType, objectId: source.objectId,
            nativeProjectId: source.nativeProjectId, revisionRef: source.revisionRef, contentDigest: before);
      await database.write((db) => db.execute('INSERT INTO knowledge_documents(id,title,path,source,digest,status) VALUES(?,?,?,?,?,?)',
        [id,p.basename(path),target.path,jsonEncode(ref.toJson()),before,'imported']));
      return require(id);
    } catch (_) { await dir.delete(recursive: true); rethrow; }
  }

  Future<void> index(String id) async {
    final doc = require(id);
    await database.write((db) => db.execute("UPDATE knowledge_documents SET status='indexing',summary='' WHERE id=?", [id]));
    try {
      final parsed = await parser.parse(ResearchDocument(id: id, projectId: 'public', relativePath: doc.title, absolutePath: doc.path));
      if (parsed.digest != doc.digest || !await isCurrent(id)) throw StateError('Source changed before indexing');
      await database.write((db) {
        final current = require(id);
        if (current.digest != parsed.digest) throw StateError('Source replaced');
        _removeIndex(id);
        for (var page = 0; page < parsed.pages.length; page++) {
          db.execute('INSERT INTO page_text(project_id,document_id,digest,page_index,text) VALUES(?,?,?,?,?)', ['public',id,parsed.digest,page,parsed.pages[page]]);
          db.execute('INSERT INTO page_fts(rowid,tokens) VALUES(?,?)', [db.lastInsertRowId,SearchService.tokens(parsed.pages[page]).join(' ')]);
        }
        db.execute('INSERT INTO index_documents VALUES(?,?,?,?,?,?,?)', ['public',id,parsed.digest,DocumentParser.version,SearchService.tokenizerVersion,'ready',null]);
        db.execute("UPDATE knowledge_documents SET status='ready',summary=? WHERE id=?", [parsed.pages.first.substring(0, parsed.pages.first.length.clamp(0,240)),id]);
      });
    } catch (e) {
      await database.write((db) => db.execute("UPDATE knowledge_documents SET status='failed',summary=? WHERE id=?", [e.toString(),id]));
      rethrow;
    }
  }

  void _removeIndex(String id) {
    database.raw.execute('DELETE FROM page_fts WHERE rowid IN(SELECT id FROM page_text WHERE document_id=?)',[id]);
    database.raw.execute('DELETE FROM page_text WHERE document_id=?',[id]);
    database.raw.execute('DELETE FROM index_documents WHERE document_id=?',[id]);
    database.raw.execute('DELETE FROM knowledge_vectors WHERE document_id=?',[id]);
  }

  Future<bool> isCurrent(String id) async {
    final doc = require(id);
    try { return await fileDigest(doc.path) == doc.digest; } catch (_) { return false; }
  }
  static Future<String> fileDigest(String path) async => (await sha256.bind(File(path).openRead()).first).toString();

  Future<List<KnowledgeHit>> search(String query, {List<String>? documentIds, int limit = 10}) async {
    if (limit < 1 || limit > 100 || query.length > 8192) throw ArgumentError('Search bounds');
    final selected = (documentIds ?? documents().map((d)=>d.id).toList()).toSet();
    final valid = <String,KnowledgeDocument>{};
    for (final id in selected) {
      final doc = require(id);
      if (doc.status == 'ready' && await isCurrent(id)) {
        final versions = database.raw.select('SELECT parser,tokenizer FROM index_documents WHERE document_id=?',[id]);
        if (versions.isNotEmpty && versions.single['parser'] == DocumentParser.version && versions.single['tokenizer'] == SearchService.tokenizerVersion) valid[id]=doc;
      } else if (doc.status == 'ready') {
        await database.write((db)=>db.execute("UPDATE knowledge_documents SET status='stale' WHERE id=?",[id]));
      }
    }
    if (valid.isEmpty || query.trim().isEmpty) return [];
    final placeholders = List.filled(valid.length,'?').join(',');
    final tokens = SearchService.tokens(query).toSet();
    final List<Map<String,Object?>> rows;
    if (tokens.isEmpty && RegExp(r'^[\u3400-\u9fff]$').hasMatch(query.trim())) {
      rows = database.raw.select('SELECT *,0.0 AS score FROM page_text WHERE document_id IN($placeholders) AND instr(text,?)>0 LIMIT ?', [...valid.keys,query.trim(),limit]).map((r)=>Map<String,Object?>.from(r)).toList();
    } else if (tokens.isNotEmpty) {
      rows = database.raw.select('SELECT page_text.*,bm25(page_fts) AS score FROM page_fts JOIN page_text ON page_text.id=page_fts.rowid WHERE page_fts MATCH ? AND document_id IN($placeholders) ORDER BY score,page_index LIMIT ?', [tokens.map((t)=>'"$t"').join(' OR '),...valid.keys,limit]).map((r)=>Map<String,Object?>.from(r)).toList();
    } else { return []; }
    final hits=<KnowledgeHit>[];
    for(final row in rows) {
      final doc=valid[row['document_id']]!;
      if (!await isCurrent(doc.id)) continue;
      hits.add(KnowledgeHit(id:'${doc.id}:${row['page_index']}',documentId:doc.id,title:doc.title,pageIndex:row['page_index'] as int,text:row['text'] as String,score:(row['score'] as num).toDouble(),sourceRef:doc.source));
    }
    return hits;
  }

  Future<void> delete(String id) async {
    final doc=require(id);
    await database.write((db) { _removeIndex(id); db.execute('DELETE FROM knowledge_documents WHERE id=?',[id]); });
    final dir=Directory(p.dirname(doc.path));
    if(p.isWithin(rootPath,dir.path) && await dir.exists()) await dir.delete(recursive:true);
  }
}
