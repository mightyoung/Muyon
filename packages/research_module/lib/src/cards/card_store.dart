import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:muspace_module_api/muspace_module_api.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../source_ref.dart';
import 'canonical_json.dart';

void installResearchKnowledgeSchema(Database db) => db.execute('''
CREATE TABLE rk_projects(local_project_id TEXT PRIMARY KEY REFERENCES projects(id), origin_key TEXT NOT NULL UNIQUE);
CREATE TABLE canonical_object_map(object_key TEXT PRIMARY KEY, local_object_id TEXT NOT NULL, local_project_id TEXT NOT NULL REFERENCES projects(id), object_type TEXT NOT NULL, UNIQUE(local_project_id,object_type,local_object_id));
CREATE TABLE rk_cards(object_key TEXT PRIMARY KEY REFERENCES canonical_object_map(object_key), head_revision_id TEXT NOT NULL);
CREATE TABLE rk_revisions(revision_id TEXT PRIMARY KEY, object_key TEXT NOT NULL REFERENCES canonical_object_map(object_key), digest TEXT NOT NULL, envelope TEXT NOT NULL, created_at TEXT NOT NULL, author TEXT NOT NULL);
CREATE INDEX rk_revisions_object ON rk_revisions(object_key);
CREATE TABLE rk_documents(object_key TEXT NOT NULL REFERENCES canonical_object_map(object_key), digest TEXT NOT NULL, file_name TEXT NOT NULL, bytes BLOB NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(object_key,digest));
CREATE TABLE rk_conflicts(object_key TEXT NOT NULL REFERENCES rk_cards(object_key), revision_id TEXT NOT NULL REFERENCES rk_revisions(revision_id), PRIMARY KEY(object_key,revision_id));
CREATE TABLE rk_import_receipts(operation_id TEXT PRIMARY KEY, identity TEXT NOT NULL, result TEXT NOT NULL, committed_at TEXT NOT NULL);
''');

class RevisionRef {
  const RevisionRef({required this.objectKey, required this.revisionId});
  final ObjectKey objectKey;
  final String revisionId;
  Map<String, Object?> toJson() => {
    'ObjectKey': objectKey.toJson(),
    'revisionId': revisionId,
  };
  factory RevisionRef.fromJson(Map<String, Object?> json) => RevisionRef(
    objectKey: ObjectKey.fromJson(
      Map<String, Object?>.from(json['ObjectKey'] as Map),
    ),
    revisionId: json['revisionId'] as String,
  );
}

class CardCitation {
  const CardCitation({required this.citationId, required this.source});
  final String citationId;
  final SourceRef source;
  Map<String, Object?> toJson() => {
    'citationId': citationId,
    'source': source.toJson(),
  };
  factory CardCitation.fromJson(Map<String, Object?> json) => CardCitation(
    citationId: json['citationId'] as String,
    source: SourceRef.fromJson(
      Map<String, Object?>.from(json['source'] as Map),
    ),
  );
}

class CardRelation {
  const CardRelation({
    required this.relationId,
    required this.target,
    required this.kind,
  });
  final String relationId;
  final ObjectKey target;
  final String kind;
  Map<String, Object?> toJson() => {
    'relationId': relationId,
    'target': target.toJson(),
    'kind': kind,
  };
  factory CardRelation.fromJson(Map<String, Object?> json) => CardRelation(
    relationId: json['relationId'] as String,
    kind: json['kind'] as String,
    target: ObjectKey.fromJson(
      Map<String, Object?>.from(json['target'] as Map),
    ),
  );
}

class CardRevision {
  CardRevision({
    required this.objectKey,
    required this.revisionId,
    required this.bodyMarkdown,
    List<RevisionRef> parents = const [],
    List<CardCitation> citations = const [],
    List<CardRelation> relations = const [],
  }) : parents = List.unmodifiable(
         [...parents]..sort((a, b) {
           final key = a.objectKey.compareTo(b.objectKey);
           return key == 0 ? a.revisionId.compareTo(b.revisionId) : key;
         }),
       ),
       citations = List.unmodifiable(citations),
       relations = List.unmodifiable(relations) {
    if (objectKey.objectType != 'card' ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(revisionId) ||
        parents.any(
          (p) => p.objectKey != objectKey || p.revisionId == revisionId,
        ) ||
        parents.map((p) => p.revisionId).toSet().length != parents.length ||
        citations.map((c) => c.citationId).toSet().length != citations.length ||
        relations.map((r) => r.relationId).toSet().length != relations.length) {
      throw const FormatException(
        'Invalid card revision identity or references',
      );
    }
    canonicalJson(toJson());
  }
  final ObjectKey objectKey;
  final String revisionId;
  final String bodyMarkdown;
  final List<RevisionRef> parents;
  final List<CardCitation> citations;
  final List<CardRelation> relations;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'ObjectKey': objectKey.toJson(),
    'revisionId': revisionId,
    'parents': parents.map((p) => p.toJson()).toList(),
    'bodyMarkdown': bodyMarkdown,
    'citationRefs': citations.map((c) => c.toJson()).toList(),
    'relations': relations.map((r) => r.toJson()).toList(),
  };
  String get canonical => canonicalJson(toJson());
  String get contentDigest => sha256.convert(utf8.encode(canonical)).toString();
  factory CardRevision.fromJson(Map<String, Object?> json) {
    const fields = {
      'schemaVersion',
      'ObjectKey',
      'revisionId',
      'parents',
      'bodyMarkdown',
      'citationRefs',
      'relations',
    };
    if (json['schemaVersion'] != 1 ||
        json.keys.toSet().difference(fields).isNotEmpty ||
        json.length != fields.length) {
      throw const FormatException('Unsupported revision envelope');
    }
    return CardRevision(
      objectKey: ObjectKey.fromJson(
        Map<String, Object?>.from(json['ObjectKey'] as Map),
      ),
      revisionId: json['revisionId'] as String,
      bodyMarkdown: json['bodyMarkdown'] as String,
      parents: (json['parents'] as List)
          .map((p) => RevisionRef.fromJson(Map<String, Object?>.from(p as Map)))
          .toList(),
      citations: (json['citationRefs'] as List)
          .map(
            (c) => CardCitation.fromJson(Map<String, Object?>.from(c as Map)),
          )
          .toList(),
      relations: (json['relations'] as List)
          .map(
            (r) => CardRelation.fromJson(Map<String, Object?>.from(r as Map)),
          )
          .toList(),
    );
  }
}

class CardConflict implements Exception {
  const CardConflict(this.currentHead, this.draft);
  final String? currentHead;
  final String draft;
  @override
  String toString() => 'Card changed since editing began; draft retained';
}

class ResearchCard {
  const ResearchCard({required this.cardId, required this.revision});
  final String cardId;
  final CardRevision revision;
}

class CardStore {
  CardStore(this.database);
  final ManagedDatabase database;
  Database get db => database.raw;

  void requireProject(String projectId) {
    if (db.select('SELECT 1 FROM projects WHERE id=?', [projectId]).isEmpty) {
      throw StateError('Project not found');
    }
  }

  String origin(String projectId) {
    requireProject(projectId);
    final rows = db.select(
      'SELECT origin_key FROM rk_projects WHERE local_project_id=?',
      [projectId],
    );
    if (rows.isNotEmpty) return rows.single['origin_key'] as String;
    final id = const Uuid().v4();
    db.execute('INSERT INTO rk_projects VALUES(?,?)', [projectId, id]);
    return id;
  }

  ObjectKey? keyFor(String projectId, String type, String localId) {
    final rows = db.select(
      'SELECT object_key FROM canonical_object_map WHERE local_project_id=? AND object_type=? AND local_object_id=?',
      [projectId, type, localId],
    );
    return rows.isEmpty
        ? null
        : ObjectKey.fromJson(
            Map<String, Object?>.from(
              jsonDecode(rows.single['object_key'] as String) as Map,
            ),
          );
  }

  ObjectKey ensureKey(String projectId, String type, String localId) {
    final existing = keyFor(projectId, type, localId);
    if (existing != null) return existing;
    final key = ObjectKey(
      originProjectKey: origin(projectId),
      objectType: type,
      objectUuid: const Uuid().v4(),
    );
    db.execute('INSERT INTO canonical_object_map VALUES(?,?,?,?)', [
      key.token,
      localId,
      projectId,
      type,
    ]);
    return key;
  }

  void requireObject(String projectId, ObjectKey key) {
    if (db.select(
      'SELECT 1 FROM canonical_object_map WHERE object_key=? AND local_project_id=?',
      [key.token, projectId],
    ).isEmpty) {
      throw StateError('Object scope mismatch');
    }
  }

  Future<ObjectKey> registerDocument({
    required String projectId,
    required String localDocumentId,
    required List<int> bytes,
    required String fileName,
  }) {
    final frozen = Uint8List.fromList(bytes);
    final digest = sha256.convert(frozen).toString();
    return database.write((_) {
      final key = ensureKey(projectId, 'document', localDocumentId);
      db.execute(
        'UPDATE rk_documents SET deleted=2 WHERE object_key=? AND deleted=0',
        [key.token],
      );
      db.execute(
        'INSERT INTO rk_documents VALUES(?,?,?,?,0) ON CONFLICT(object_key,digest) DO UPDATE SET deleted=0,file_name=excluded.file_name',
        [key.token, digest, fileName, frozen],
      );
      return key;
    });
  }

  Future<void> deleteDocument(String projectId, ObjectKey key) =>
      database.write((_) {
        requireObject(projectId, key);
        db.execute('UPDATE rk_documents SET deleted=1 WHERE object_key=?', [
          key.token,
        ]);
      });

  SourceAvailability sourceAvailability(String projectId, SourceRef source) {
    requireObject(projectId, source.documentRef);
    final rows = db.select(
      'SELECT digest FROM rk_documents WHERE object_key=? AND deleted=0',
      [source.documentRef.token],
    );
    return source.availability(
      exists: rows.isNotEmpty,
      currentDigest: rows.isEmpty ? null : rows.single['digest'] as String,
    );
  }

  Future<ResearchCard> save({
    required String projectId,
    required String cardId,
    required String? expectedHead,
    required String bodyMarkdown,
    List<CardCitation> citations = const [],
    List<CardRelation> relations = const [],
    String author = 'local-user',
  }) {
    final frozenCitations = List<CardCitation>.of(citations);
    final frozenRelations = List<CardRelation>.of(relations);
    return database.write((_) {
      requireProject(projectId);
      final existing = get(projectId, cardId);
      if (existing?.revision.revisionId != expectedHead) {
        throw CardConflict(existing?.revision.revisionId, bodyMarkdown);
      }
      final key = ensureKey(projectId, 'card', cardId);
      for (final citation in frozenCitations) {
        requireObject(projectId, citation.source.documentRef);
        // Existing citations can remain when their source has since disappeared.
        if (db.select(
          'SELECT 1 FROM rk_documents WHERE object_key=? AND digest=?',
          [citation.source.documentRef.token, citation.source.contentDigest],
        ).isEmpty) {
          throw StateError('Citation source version is missing');
        }
      }
      for (final relation in frozenRelations) {
        requireObject(projectId, relation.target);
      }
      final revision = CardRevision(
        objectKey: key,
        revisionId: const Uuid().v4(),
        bodyMarkdown: bodyMarkdown,
        citations: frozenCitations,
        relations: frozenRelations,
        parents: expectedHead == null
            ? []
            : [RevisionRef(objectKey: key, revisionId: expectedHead)],
      );
      insertRevision(revision, author: author);
      db.execute(
        'INSERT INTO rk_cards VALUES(?,?) ON CONFLICT(object_key) DO UPDATE SET head_revision_id=excluded.head_revision_id',
        [key.token, revision.revisionId],
      );
      return ResearchCard(cardId: cardId, revision: revision);
    });
  }

  void insertRevision(CardRevision revision, {String author = 'import'}) {
    final rows = db.select(
      'SELECT digest FROM rk_revisions WHERE revision_id=?',
      [revision.revisionId],
    );
    if (rows.isNotEmpty) {
      if (rows.single['digest'] != revision.contentDigest) {
        throw StateError('Revision content conflict');
      }
      return;
    }
    db.execute('INSERT INTO rk_revisions VALUES(?,?,?,?,?,?)', [
      revision.revisionId,
      revision.objectKey.token,
      revision.contentDigest,
      revision.canonical,
      DateTime.now().toUtc().toIso8601String(),
      author,
    ]);
  }

  CardRevision? revision(String id) {
    final rows = db.select(
      'SELECT envelope FROM rk_revisions WHERE revision_id=?',
      [id],
    );
    return rows.isEmpty
        ? null
        : CardRevision.fromJson(
            Map<String, Object?>.from(
              strictJsonDecode(rows.single['envelope'] as String) as Map,
            ),
          );
  }

  ResearchCard? get(String projectId, String cardId) {
    requireProject(projectId);
    final key = keyFor(projectId, 'card', cardId);
    if (key == null) return null;
    final rows = db.select(
      'SELECT head_revision_id FROM rk_cards WHERE object_key=?',
      [key.token],
    );
    return rows.isEmpty
        ? null
        : ResearchCard(
            cardId: cardId,
            revision: revision(rows.single['head_revision_id'] as String)!,
          );
  }

  List<ResearchCard> list(String projectId) {
    requireProject(projectId);
    return db
        .select(
          'SELECT m.local_object_id FROM canonical_object_map m JOIN rk_cards c ON c.object_key=m.object_key WHERE m.local_project_id=? ORDER BY m.local_object_id',
          [projectId],
        )
        .map((r) => get(projectId, r['local_object_id'] as String)!)
        .toList();
  }
}
