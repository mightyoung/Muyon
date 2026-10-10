import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/research_module.dart';

import '../../workspace/workspace_repository.dart';

/// Host-only source consumer. An IndexScope is a filter, never a grant: every
/// operation pins the actual module authority and the current workspace binding.
class RegisteredResearchSources {
  const RegisteredResearchSources({
    required this.workspaces,
    required this.sources,
    required this.authorityRevision,
  });
  final WorkspaceRepository workspaces;
  final List<SearchSource> Function() sources;
  final String? Function() authorityRevision;

  ResearchSourceRead begin(WorkspaceBinding binding, {ToolCancellationToken? cancellation}) {
    final authority = authorityRevision();
    final workspaceAuthority = workspaces.scopeAuthorityRevision;
    final declared = sources().where((source) => source.id == 'research.documents');
    if (authority == null || workspaceAuthority == null || declared.length != 1 ||
        !declared.single.objectTypes.contains('document')) {
      throw StateError('Registered research source unavailable');
    }
    final read = ResearchSourceRead._(this, binding, declared.single,
      authority, workspaceAuthority, cancellation);
    read.requireCurrent();
    return read;
  }
}

class ResearchSourceRead {
  const ResearchSourceRead._(this.owner, this.binding, this.source,
      this.authority, this.workspaceAuthority, this.cancellation);
  final RegisteredResearchSources owner;
  final WorkspaceBinding binding;
  final SearchSource source;
  final String authority, workspaceAuthority;
  final ToolCancellationToken? cancellation;

  void requireCurrent() {
    cancellation?.throwIfCancelled();
    if (binding.moduleId != 'research' ||
        owner.authorityRevision() != authority ||
        owner.workspaces.scopeAuthorityRevision != workspaceAuthority ||
        owner.workspaces.binding(binding.workspaceId, 'research')?.nativeProjectId !=
            binding.nativeProjectId ||
        !owner.sources().any((candidate) => identical(candidate, source))) {
      throw StateError('Research source scope or authority changed');
    }
  }

  void requirePinned(ObjectRef ref) {
    requireCurrent();
    final current = source;
    if (!_inScope(ref) || current is! ResearchDocumentSearchSource) {
      throw StateError('Registered research source cannot verify a pin');
    }
    current.requirePinned(ref);
    requireCurrent();
  }

  Future<T> _await<T>(Future<T> Function() operation) async {
    requireCurrent();
    final future = operation();
    final token = cancellation;
    final result = token == null ? await future : await Future.any<T>([
      future,
      token.whenCancelled.then<T>((_) => throw const ToolCancelled()),
    ]);
    requireCurrent();
    return result;
  }

  bool _inScope(ObjectRef ref) => ref.moduleId == 'research' &&
      ref.objectType == 'document' &&
      ref.nativeProjectId == binding.nativeProjectId && ref.revisionRef == null &&
      ref.contentDigest != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(ref.contentDigest!);

  Future<List<IndexableItem>> list() async {
    final items = await _await(() => source.list(IndexScope(nativeProjectId: binding.nativeProjectId)));
    if (items.length > 1000) throw StateError('Research source item budget exceeded');
    final ids = <String>{};
    for (final item in items) {
      if (!_inScope(item.ref) || item.contentDigest != item.ref.contentDigest ||
          item.filePath == null || item.text != null || !ids.add(item.ref.objectId)) {
        throw StateError('Invalid registered research source identity');
      }
    }
    return items;
  }

  Future<ObjectView?> confirm(ObjectRef ref) async {
    requireCurrent();
    if (!_inScope(ref)) return null;
    final view = await _await(() => source.confirm(ref));
    if (view != null && view.ref != ref) {
      throw StateError('Registered source returned a different identity');
    }
    return view;
  }
}

/// Public knowledge invalidation has no workspace grant to broaden. This only
/// asks the registered owning source to revalidate its already-pinned document,
/// and refuses publication when the module's lifecycle changes during I/O.
Future<bool> confirmRegisteredResearchDocument(ObjectRef ref, {
  required List<SearchSource> Function() sources,
  required String? Function() authorityRevision,
}) async {
  final authority = authorityRevision();
  final declared = sources().where((source) => source.id == 'research.documents').toList();
  if (authority == null || declared.length != 1 ||
      declared.single is! ResearchDocumentSearchSource) return false;
  final source = declared.single;
  try {
    final view = await source.confirm(ref);
    return view?.ref == ref && authorityRevision() == authority &&
        sources().any((candidate) => identical(candidate, source));
  } on StateError {
    return false;
  }
}
