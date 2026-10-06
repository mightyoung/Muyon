import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/research_module.dart';

import '../../workspace/workspace_repository.dart';
import '../search/search_service.dart';
import 'knowledge_service.dart';

/// The research UI keeps its domain interface, while all new indexing and
/// retrieval go through the host's single public knowledge provider.
class ResearchSearchAdapter extends SearchService {
  ResearchSearchAdapter(
    this.knowledge,
    WorkspaceRepository workspaces,
    WorkbenchStore store,
  ) : super(workspaces.database, workspaces, store);
  final KnowledgeService knowledge;
  void check(WorkspaceBinding binding) {
    if (binding.moduleId != 'research' ||
        workspaces.binding(binding.workspaceId, 'research')?.nativeProjectId !=
            binding.nativeProjectId) {
      throw StateError('scope_mismatch');
    }
  }

  @override
  List<ResearchDocument> documents(WorkspaceBinding binding) {
    check(binding);
    return currentVersions(store.documents(binding.nativeProjectId));
  }

  Future<String> hash(ResearchDocument doc) async =>
      (await sha256.bind(File(doc.absolutePath).openRead()).first).toString();
  KnowledgeDocument? indexed(ResearchDocument doc) => knowledge
      .documents()
      .where(
        (entry) =>
            entry.source.moduleId == 'research' &&
            entry.source.objectType == 'document' &&
            entry.source.nativeProjectId == doc.projectId &&
            entry.source.objectId == doc.id,
      )
      .firstOrNull;
  @override
  Future<void> index(
    WorkspaceBinding binding,
    ResearchDocument document,
  ) async {
    check(binding);
    if (!documents(binding).any((current) => current.id == document.id)) {
      throw StateError('Selected document outside scope');
    }
    final digest = await hash(document);
    var entry = indexed(document);
    if (entry != null && entry.digest != digest) {
      await knowledge.delete(entry.id);
      entry = null;
    }
    entry ??= await knowledge.importFile(
      document.absolutePath,
      source: ObjectRef(
        moduleId: 'research',
        objectType: 'document',
        objectId: document.id,
        nativeProjectId: document.projectId,
        contentDigest: digest,
      ),
    );
    await knowledge.index(entry.id);
    check(binding);
    if (await hash(document) != digest) {
      throw StateError('Source changed during indexing');
    }
  }

  @override
  Future<SearchResult> search(
    WorkspaceBinding binding,
    String question, {
    required Set<String> selectedDocumentIds,
    int limit = 5,
    int scanLimit = 500,
  }) async {
    check(binding);
    if (limit < 1 || limit > 100 || scanLimit < 1 || scanLimit > 10000) {
      throw ArgumentError('Invalid search bounds');
    }
    final available = {
      for (final document in documents(binding)) document.id: document,
    };
    if (!selectedDocumentIds.every(available.containsKey)) {
      throw StateError('Selected source outside scope');
    }
    if (selectedDocumentIds.isEmpty || question.trim().isEmpty) {
      return const SearchResult([]);
    }
    final indices = <String, ResearchDocument>{};
    final unavailable = <String, String>{};
    for (final id in selectedDocumentIds) {
      final document = available[id]!;
      final entry = indexed(document);
      if (entry == null) {
        unavailable[id] = 'not_indexed';
        continue;
      }
      if (entry.status != 'ready') {
        unavailable[id] = entry.status;
        continue;
      }
      try {
        if (entry.digest != await hash(document)) {
          unavailable[id] = 'stale';
          continue;
        }
      } catch (_) {
        unavailable[id] = 'missing';
        continue;
      }
      indices[entry.id] = document;
    }
    if (indices.isEmpty) {
      return SearchResult(const [], unavailable: unavailable);
    }
    final found = await knowledge.search(
      question,
      documentIds: indices.keys.toList(),
      limit: limit,
    );
    check(binding);
    final hits = <SearchHit>[];
    for (final hit in found) {
      final document = indices[hit.documentId];
      if (document == null) {
        throw StateError('Public provider returned source outside scope');
      }
      if (!documents(binding).any((current) => current.id == document.id) ||
          await hash(document) != hit.sourceRef.contentDigest) {
        unavailable[document.id] = 'stale';
        continue;
      }
      hits.add(
        SearchHit(
          document: document,
          contentDigest: hit.sourceRef.contentDigest!,
          pageIndex: hit.pageIndex,
          text: hit.text,
        ),
      );
    }
    return SearchResult(hits, unavailable: unavailable);
  }
}
