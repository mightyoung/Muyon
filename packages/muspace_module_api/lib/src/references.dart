class WorkspaceBinding {
  const WorkspaceBinding({
    required this.workspaceId,
    required this.moduleId,
    required this.nativeProjectId,
  });
  final String workspaceId;
  final String moduleId;
  final String nativeProjectId;
}

class ObjectRef {
  const ObjectRef({
    required this.moduleId,
    required this.objectType,
    required this.objectId,
    this.nativeProjectId,
    this.revisionRef,
    this.contentDigest,
  });
  final String moduleId;
  final String objectType;
  final String objectId;
  final String? nativeProjectId;
  final String? revisionRef;
  final String? contentDigest;

  Map<String, Object?> toJson() => {
    'moduleId': moduleId,
    'objectType': objectType,
    'objectId': objectId,
    'nativeProjectId': nativeProjectId,
    'revisionRef': revisionRef,
    'contentDigest': contentDigest,
  };

  @override
  bool operator ==(Object other) =>
      other is ObjectRef &&
      moduleId == other.moduleId &&
      objectType == other.objectType &&
      objectId == other.objectId &&
      nativeProjectId == other.nativeProjectId &&
      revisionRef == other.revisionRef &&
      contentDigest == other.contentDigest;
  @override
  int get hashCode => Object.hash(
    moduleId,
    objectType,
    objectId,
    nativeProjectId,
    revisionRef,
    contentDigest,
  );
}

class ObjectView {
  const ObjectView({required this.ref, required this.title, this.summary});
  final ObjectRef ref;
  final String title;
  final String? summary;
}

class ArtifactRef {
  const ArtifactRef({
    required this.moduleId,
    required this.artifactId,
    required this.contentDigest,
  });
  final String moduleId;
  final String artifactId;
  final String contentDigest;
}
