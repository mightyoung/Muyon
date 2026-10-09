import '../references.dart';

/// A return checkpoint in the existing task/surface projection, never a route
/// registry, approval or instruction to replay an operation.
class NavigationAnchor {
  const NavigationAnchor({
    required this.conversationId,
    required this.taskId,
    required this.surfaceId,
    required this.nodeId,
    required this.scrollOffset,
    required this.objectRef,
    this.sourceDigest,
    this.artifactRef,
  });
  final String conversationId, taskId, surfaceId, nodeId;
  final double scrollOffset;
  final ObjectRef objectRef;
  final String? sourceDigest;
  final ArtifactRef? artifactRef;

  Map<String, Object?> toJson() => {
    'conversationId': conversationId,
    'taskId': taskId,
    'surfaceId': surfaceId,
    'nodeId': nodeId,
    'scrollOffset': scrollOffset,
    'objectRef': objectRef.toJson(),
    'sourceDigest': sourceDigest,
    if (artifactRef != null)
      'artifactRef': {
        'moduleId': artifactRef!.moduleId,
        'artifactId': artifactRef!.artifactId,
        'contentDigest': artifactRef!.contentDigest,
      },
  };

  factory NavigationAnchor.fromJson(Map<String, dynamic> j) {
    final ref = j['objectRef'] as Map;
    final artifact = j['artifactRef'] as Map?;
    final offset = (j['scrollOffset'] as num).toDouble();
    if (!offset.isFinite || offset < 0) {
      throw const FormatException('Invalid return offset');
    }
    return NavigationAnchor(
      conversationId: j['conversationId'] as String,
      taskId: j['taskId'] as String,
      surfaceId: j['surfaceId'] as String,
      nodeId: j['nodeId'] as String,
      scrollOffset: offset,
      objectRef: ObjectRef(
        moduleId: ref['moduleId'] as String,
        objectType: ref['objectType'] as String,
        objectId: ref['objectId'] as String,
        nativeProjectId: ref['nativeProjectId'] as String?,
        revisionRef: ref['revisionRef'] as String?,
        contentDigest: ref['contentDigest'] as String?,
      ),
      sourceDigest: j['sourceDigest'] as String?,
      artifactRef: artifact == null
          ? null
          : ArtifactRef(
              moduleId: artifact['moduleId'] as String,
              artifactId: artifact['artifactId'] as String,
              contentDigest: artifact['contentDigest'] as String,
            ),
    );
  }
}
