import 'dart:async';

import 'package:sqlite3/sqlite3.dart';

import 'assistant_scope.dart';
import 'change_log.dart';
import 'context.dart';
import 'references.dart';
import 'storage.dart';

enum ToolAccessLevel { read, write, external }

enum ToolCallStatus { succeeded, failed, cancelled, interrupted, blocked }

class ToolCallRequest {
  ToolCallRequest({
    required this.invocationId,
    required this.toolId,
    required this.scope,
    Map<String, Object?> parameters = const {},
    this.destination,
    this.idempotencyKey,
    this.approvalId,
  }) : parameters = freezeJsonMap(parameters) {
    if (invocationId.isEmpty || toolId.isEmpty || idempotencyKey == '') {
      throw ArgumentError('Tool and invocation identities are required');
    }
  }
  final String invocationId;
  final String toolId;
  final AssistantScope scope;
  final Map<String, Object?> parameters;
  final String? destination;
  final String? idempotencyKey;
  final String? approvalId;
  String get replayKey => idempotencyKey ?? invocationId;
  ToolCallRequest withApproval(String id) => ToolCallRequest(
    invocationId: invocationId,
    toolId: toolId,
    scope: scope,
    parameters: parameters,
    destination: destination,
    idempotencyKey: idempotencyKey,
    approvalId: id,
  );
}

class ToolCallResult {
  ToolCallResult({
    required this.status,
    required this.summary,
    Map<String, Object?> data = const {},
    List<ObjectRef> objectRefs = const [],
    List<ArtifactRef> artifactRefs = const [],
    this.executionId,
    List<ObjectChange> changes = const [],
  }) : data = freezeJsonMap(data),
       objectRefs = List.unmodifiable(objectRefs),
       artifactRefs = List.unmodifiable(artifactRefs),
       changes = List.unmodifiable(changes);
  final ToolCallStatus status;
  final String summary;
  final Map<String, Object?> data;
  final List<ObjectRef> objectRefs;
  final List<ArtifactRef> artifactRefs;
  final String? executionId;

  /// Objects the call created, changed or deleted, for scope advancement
  /// (ADR-0004 §5.3). Not part of [toJson]: the receipt format is unchanged.
  final List<ObjectChange> changes;
  ToolCallResult forInvocation(String id) => ToolCallResult(
    status: status,
    summary: summary,
    data: data,
    objectRefs: objectRefs,
    artifactRefs: artifactRefs,
    executionId: id,
    changes: changes,
  );
  Map<String, Object?> toJson() => {
    'status': status.name,
    'summary': summary,
    'data': data,
    'executionId': executionId,
    'objectRefs': objectRefs.map((ref) => ref.toJson()).toList(),
    'artifactRefs': artifactRefs
        .map(
          (ref) => {
            'moduleId': ref.moduleId,
            'artifactId': ref.artifactId,
            'contentDigest': ref.contentDigest,
          },
        )
        .toList(),
  };
  factory ToolCallResult.fromJson(Map<String, Object?> json) => ToolCallResult(
    status: ToolCallStatus.values.byName(json['status'] as String),
    summary: json['summary'] as String,
    data: Map<String, Object?>.from(json['data'] as Map),
    executionId: json['executionId'] as String?,
    objectRefs: [
      for (final ref in json['objectRefs'] as List)
        objectRefFromJson(Map<String, Object?>.from(ref as Map)),
    ],
    artifactRefs: [
      for (final ref in json['artifactRefs'] as List)
        ArtifactRef(
          moduleId: ref['moduleId'] as String,
          artifactId: ref['artifactId'] as String,
          contentDigest: ref['contentDigest'] as String,
        ),
    ],
  );
}

class ObjectChange {
  const ObjectChange(this.ref, this.op);
  final ObjectRef ref;
  final ChangeOp op;
}

class ToolCancelled implements Exception {
  const ToolCancelled();
}

class ToolCancellationToken {
  final Completer<void> _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const ToolCancelled();
  }
}

class ToolCallContext {
  const ToolCallContext({
    required this.request,
    required this.resolvedScope,
    required this.cancellation,
    this.checkAuthorization,
  });
  final ToolCallRequest request;
  final ResolvedAssistantScope resolvedScope;
  final ToolCancellationToken cancellation;
  final void Function()? checkAuthorization;

  /// Call immediately before an external effect after asynchronous preparation.
  void checkBeforeEffect() {
    cancellation.throwIfCancelled();
    checkAuthorization?.call();
  }

  /// Recheck cancellation inside the queued short transaction, immediately
  /// before a domain commit. Async preparation belongs before this method.
  Future<T> write<T>(ManagedDatabase database, T Function(Database) body) =>
      database.write((db) {
        checkBeforeEffect();
        return body(db);
      });
}

class RegisteredToolInfo {
  const RegisteredToolInfo({
    required this.providerId,
    required this.descriptor,
    required this.available,
    this.unavailableReason,
  });
  final String providerId;
  final ToolDescriptor descriptor;
  final bool available;
  final String? unavailableReason;
  ToolAccessLevel get accessLevel => switch (descriptor.effect) {
    ToolEffect.read => ToolAccessLevel.read,
    ToolEffect.write => ToolAccessLevel.write,
    ToolEffect.export || ToolEffect.network => ToolAccessLevel.external,
  };
}
