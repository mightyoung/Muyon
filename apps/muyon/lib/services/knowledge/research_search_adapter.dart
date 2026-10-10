import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/research_module.dart';

import '../../workspace/workspace_repository.dart';
import '../search/search_service.dart';
import 'knowledge_service.dart';
import 'registered_research_source.dart';

/// The research UI keeps its domain interface, while all new indexing and
/// retrieval go through the host's single public knowledge provider.
class ResearchSearchAdapter extends SearchService {
  ResearchSearchAdapter(
    this.knowledge,
    WorkspaceRepository workspaces,
    WorkbenchStore store,
  ) : _registered = null, super(workspaces.database, workspaces, store);

  /// Production path: metadata stays domain-owned; content comes only from the
  /// registered source and a pinned host authority read. The old constructor
  /// remains compatible with the existing standalone search fixture.
  ResearchSearchAdapter.registered(
    this.knowledge,
    WorkspaceRepository workspaces,
    WorkbenchStore store, {
    required List<SearchSource> Function() sources,
    required String? Function() authorityRevision,
  }) : _registered = RegisteredResearchSources(workspaces: workspaces,
         sources: sources, authorityRevision: authorityRevision),
       super(workspaces.database, workspaces, store);
  final RegisteredResearchSources? _registered;
  final KnowledgeService knowledge;
  void check(WorkspaceBinding binding) {
    _registered?.begin(binding);
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

  Future<String> hash(ResearchDocument doc) async {
    if (_registered != null) {
      throw UnsupportedError('Registered source requires a workspace binding');
    }
    return (await sha256.bind(File(doc.absolutePath).openRead()).first).toString();
  }
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
    ResearchDocument document, {
    ToolCancellationToken? cancellation,
  }) async {
    if (_registered != null) {
      await _indexRegistered(binding, document, cancellation);
      return;
    }
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
    ToolCancellationToken? cancellation,
  }) async {
    if (_registered != null) {
      return _searchRegistered(binding, question, selectedDocumentIds,
          limit, scanLimit, cancellation);
    }
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
  Future<void> _indexRegistered(WorkspaceBinding binding,
      ResearchDocument document, ToolCancellationToken? cancellation) async {
    final read = _registered!.begin(binding, cancellation: cancellation);
    final candidates = await read.list();
    final item = candidates.where((item) => item.ref.objectId == document.id).firstOrNull;
    if (item == null || document.projectId != binding.nativeProjectId ||
        await read.confirm(item.ref) == null) {
      throw StateError('Selected document outside current registered source');
    }
    // The file path comes from the module, never from the caller's document.
    var entry = indexed(document);
    if (entry != null && entry.digest != item.contentDigest) {
      await knowledge.delete(entry.id, checkBeforeEffect: read.requireCurrent);
      entry = null;
    }
    entry ??= await knowledge.importFile(item.filePath!, source: item.ref,
      expectedDigest: item.contentDigest, checkBeforeEffect: read.requireCurrent);
    read.requireCurrent();
    if (await read.confirm(item.ref) == null) throw StateError('Source changed during import');
    await knowledge.index(entry.id, checkBeforeEffect: read.requireCurrent);
    if (await read.confirm(item.ref) == null) throw StateError('Source changed during indexing');
    read.requireCurrent();
  }

  Future<SearchResult> _searchRegistered(WorkspaceBinding binding, String question,
      Set<String> selectedIds, int limit, int scanLimit,
      ToolCancellationToken? cancellation) async {
    final read = _registered!.begin(binding, cancellation: cancellation);
    if (limit < 1 || limit > 100 || scanLimit < 1 || scanLimit > 10000) {
      throw ArgumentError('Invalid search bounds');
    }
    if (selectedIds.isEmpty || question.trim().isEmpty) return const SearchResult([]);
    final available = {for (final item in await read.list()) item.ref.objectId: item};
    if (!selectedIds.every(available.containsKey)) throw StateError('Selected source outside scope');
    final unavailable = <String, String>{};
    final indices = <String, (IndexableItem, ObjectView)>{};
    for (final id in selectedIds) {
      final item = available[id]!;
      final entry = knowledge.documents().where((entry) =>
          sameObjectIdentity(entry.source, item.ref)).firstOrNull;
      if (entry == null) { unavailable[id] = 'not_indexed'; continue; }
      if (entry.status != 'ready') { unavailable[id] = entry.status; continue; }
      if (entry.digest != item.contentDigest) { unavailable[id] = 'stale'; continue; }
      final view = await read.confirm(item.ref);
      if (view == null) { unavailable[id] = 'stale'; continue; }
      indices[entry.id] = (item, view);
    }
    if (indices.isEmpty) return SearchResult(const [], unavailable: unavailable);
    final found = await knowledge.search(question, documentIds: indices.keys.toList(), limit: limit);
    read.requireCurrent();
    final hits = <SearchHit>[];
    for (final hit in found) {
      final value = indices[hit.documentId];
      if (value == null || hit.sourceRef != value.$1.ref) {
        throw StateError('Public provider returned source outside registered scope');
      }
      if (await read.confirm(value.$1.ref) == null) {
        unavailable[value.$1.ref.objectId] = 'stale'; continue;
      }
      hits.add(SearchHit(document: ResearchDocument(id: value.$1.ref.objectId,
        projectId: binding.nativeProjectId, relativePath: value.$2.title,
        absolutePath: value.$1.filePath!, sha256: value.$1.contentDigest),
        contentDigest: value.$1.contentDigest, pageIndex: hit.pageIndex, text: hit.text));
    }
    read.requireCurrent();
    return SearchResult(hits, unavailable: unavailable);
  }

}
