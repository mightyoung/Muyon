import 'references.dart';

enum AssistantScopeKind { global, workspace, selectedObjects }

/// A request for data, never an authorization and never a provider identity.
class AssistantScope {
  const AssistantScope.global()
    : kind = AssistantScopeKind.global,
      workspaceId = null,
      objects = const [];
  AssistantScope.workspace(String id)
    : kind = AssistantScopeKind.workspace,
      workspaceId = id,
      objects = const [] {
    if (id.trim().isEmpty) throw ArgumentError('Workspace ID is required');
  }
  AssistantScope.selectedObjects(List<ObjectRef> refs, {this.workspaceId})
    : kind = AssistantScopeKind.selectedObjects,
      objects = List.unmodifiable(refs) {
    if (refs.isEmpty || workspaceId?.trim() == '') {
      throw ArgumentError('Select objects and use a valid optional workspace');
    }
    _validateObjects(refs);
  }
  final AssistantScopeKind kind;
  final String? workspaceId;
  final List<ObjectRef> objects;
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'workspaceId': workspaceId,
    'objects': objects.map((ref) => ref.toJson()).toList(),
  };
  factory AssistantScope.fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        'global'
            when json['workspaceId'] == null &&
                (json['objects'] as List).isEmpty =>
          const AssistantScope.global(),
        'workspace' when (json['objects'] as List).isEmpty =>
          AssistantScope.workspace(json['workspaceId'] as String),
        'selectedObjects' => AssistantScope.selectedObjects([
          for (final ref in json['objects'] as List)
            objectRefFromJson(Map<String, Object?>.from(ref as Map)),
        ], workspaceId: json['workspaceId'] as String?),
        _ => throw const FormatException('Invalid assistant scope'),
      };
}

/// Produced by the host after checking workspace bindings, object visibility,
/// existence and current versions. Global scope resolves to explicit objects.
class ResolvedAssistantScope {
  ResolvedAssistantScope({
    required this.requested,
    required List<ObjectRef> objects,
  }) : objects = List.unmodifiable(objects) {
    _validateObjects(objects);
    if (requested.kind == AssistantScopeKind.selectedObjects &&
        (requested.objects.length != objects.length ||
            requested.objects.any(
              (request) => !objects.any(
                (resolved) =>
                    sameObjectIdentity(request, resolved) &&
                    (request.revisionRef == null ||
                        request.revisionRef == resolved.revisionRef) &&
                    (request.contentDigest == null ||
                        request.contentDigest == resolved.contentDigest),
              ),
            ))) {
      throw ArgumentError('Selected object scope changed or expanded');
    }
  }
  final AssistantScope requested;
  final List<ObjectRef> objects;
  Set<String> get moduleIds =>
      Set.unmodifiable(objects.map((ref) => ref.moduleId));
  bool contains(ObjectRef ref) => objects.contains(ref);
  Map<String, Object?> toJson() => {
    'requested': requested.toJson(),
    'objects': objects.map((ref) => ref.toJson()).toList(),
  };
}

bool sameObjectIdentity(ObjectRef a, ObjectRef b) =>
    a.moduleId == b.moduleId &&
    a.objectType == b.objectType &&
    a.nativeProjectId == b.nativeProjectId &&
    a.objectId == b.objectId;

ObjectRef objectRefFromJson(Map<String, Object?> json) => ObjectRef(
  moduleId: json['moduleId'] as String,
  objectType: json['objectType'] as String,
  objectId: json['objectId'] as String,
  nativeProjectId: json['nativeProjectId'] as String?,
  revisionRef: json['revisionRef'] as String?,
  contentDigest: json['contentDigest'] as String?,
);

void _validateObjects(List<ObjectRef> refs) {
  final identities = <String>{};
  for (final ref in refs) {
    if (ref.moduleId.isEmpty ||
        ref.objectType.isEmpty ||
        ref.objectId.isEmpty ||
        !identities.add(
          '${ref.moduleId.length}:${ref.moduleId}'
          '${ref.objectType.length}:${ref.objectType}'
          '${ref.nativeProjectId?.length ?? -1}:${ref.nativeProjectId}'
          '${ref.objectId.length}:${ref.objectId}',
        )) {
      throw ArgumentError(
        'Object scope contains invalid or duplicate identities',
      );
    }
  }
}
