import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../models/model_gateway.dart';
import 'knowledge_service.dart';

class EmbeddingService {
  EmbeddingService(this.knowledge, this.gateway);
  final KnowledgeService knowledge;
  final OpenAiModelGateway gateway;
  Map<String, Object?> preview(String documentId) {
    final texts = knowledge.database.raw
        .select(
          'SELECT text FROM page_text WHERE document_id=? ORDER BY page_index',
          [documentId],
        )
        .map((r) => r['text'] as String)
        .toList();
    return {
      'documentId': documentId,
      'sourceDigest': knowledge.require(documentId).digest,
      'textDigest': sha256.convert(utf8.encode(jsonEncode(texts))).toString(),
      'pageCount': texts.length,
      'characters': texts.fold<int>(0, (n, t) => n + t.length),
      'preview': texts.isEmpty
          ? ''
          : texts.first.substring(0, texts.first.length.clamp(0, 500)),
    };
  }

  /// Every batch calls beforeSend. Host approvals bind endpoint, model and text.
  Future<void> index(
    String documentId, {
    required ModelProfile profile,
    required Future<void> Function() beforeSend,
    ModelCancellation? cancellation,
    void Function()? checkBeforeEffect,
    String? expectedTextDigest,
  }) async {
    final token = cancellation ?? ModelCancellation();
    token.check();
    final doc = knowledge.require(documentId);
    if (doc.status != 'ready' || !await knowledge.isCurrent(documentId)) {
      throw StateError('Source is not indexed/current');
    }
    final pages = knowledge.database.raw.select(
      'SELECT page_index,text FROM page_text WHERE document_id=? ORDER BY page_index',
      [documentId],
    );
    final texts = pages.map((r) => r['text'] as String).toList();
    final textDigest = sha256
        .convert(utf8.encode(jsonEncode(texts)))
        .toString();
    if (expectedTextDigest != null && textDigest != expectedTextDigest) {
      throw StateError('Embedding text differs from approved preview');
    }
    if (pages.isEmpty || pages.length > 128) {
      throw StateError('Embedding requires 1–128 indexed pages per document');
    }
    final vectors = await gateway.embed(
      profile: profile,
      texts: texts,
      cancellation: token,
      beforeSend: beforeSend,
    );
    token.check();
    if (!await knowledge.isCurrent(documentId)) {
      throw StateError('Source changed during embedding');
    }
    await knowledge.database.write((db) {
      checkBeforeEffect?.call();
      token.check();
      if (knowledge.require(documentId).digest != doc.digest) {
        throw StateError('Source was replaced');
      }
      for (var i = 0; i < pages.length; i++) {
        db.execute(
          'INSERT OR REPLACE INTO knowledge_vectors VALUES(?,?,?,?,?,?,?,?)',
          [
            documentId,
            pages[i]['page_index'],
            doc.digest,
            profile.id,
            profile.endpointIdentity,
            profile.modelId,
            vectors[i].length,
            jsonEncode(vectors[i]),
          ],
        );
      }
    });
  }

  /// Uses previously computed query vectors; no network is needed.
  Future<List<KnowledgeHit>> searchVector(
    List<double> query, {
    required String profileId,
    required String endpointIdentity,
    required String modelId,
    required List<String> documentIds,
    int limit = 10,
  }) async {
    if (query.isEmpty ||
        query.any((n) => !n.isFinite) ||
        limit < 1 ||
        limit > 100) {
      throw ArgumentError('Invalid vector search bounds');
    }
    final norm = math.sqrt(query.fold<double>(0, (n, v) => n + v * v));
    if (norm == 0) throw ArgumentError('Zero query vector');
    final hits = <KnowledgeHit>[];
    for (final id in documentIds.toSet()) {
      final doc = knowledge.require(id);
      if (!await knowledge.isCurrent(id)) {
        throw StateError('stale_vector_source');
      }
      final rows = knowledge.database.raw.select(
        'SELECT v.*,p.text FROM knowledge_vectors v JOIN page_text p ON p.document_id=v.document_id AND p.page_index=v.page_index WHERE v.document_id=? AND v.profile_id=?',
        [id, profileId],
      );
      for (final row in rows) {
        if (row['model_id'] != modelId ||
            row['endpoint_identity'] != endpointIdentity ||
            row['source_digest'] != doc.digest ||
            row['dimension'] != query.length) {
          throw StateError('embedding_profile_or_dimension_mismatch');
        }
        final vector = (jsonDecode(row['vector_json'] as String) as List)
            .cast<num>();
        var dot = 0.0, square = 0.0;
        for (var i = 0; i < vector.length; i++) {
          dot += query[i] * vector[i];
          square += vector[i] * vector[i];
        }
        if (square == 0) continue;
        hits.add(
          KnowledgeHit(
            id: '$id:${row['page_index']}',
            documentId: id,
            title: doc.title,
            pageIndex: row['page_index'] as int,
            text: row['text'] as String,
            score: dot / (norm * math.sqrt(square)),
            sourceRef: doc.source,
          ),
        );
      }
    }
    if (hits.isEmpty) throw StateError('embedding_index_unavailable');
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(limit).toList();
  }

  Future<List<KnowledgeHit>> search(
    String query, {
    required ModelProfile profile,
    required List<String> documentIds,
    required Future<void> Function() beforeSend,
    ModelCancellation? cancellation,
  }) async {
    final vectors = await gateway.embed(
      profile: profile,
      texts: [query],
      beforeSend: beforeSend,
      cancellation: cancellation,
    );
    return searchVector(
      vectors.single,
      profileId: profile.id,
      endpointIdentity: profile.endpointIdentity,
      modelId: profile.modelId,
      documentIds: documentIds,
    );
  }
}
