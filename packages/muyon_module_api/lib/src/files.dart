import 'context.dart';
import 'references.dart';

abstract interface class ModuleFiles {
  String get rootPath;
  Future<SelectedInput> freeze(SelectedInput input);
}

class SelectedInput {
  const SelectedInput({required this.path, required this.displayName});
  final String path;
  final String displayName;
}

enum ImportKind { create, refresh }

class ImportTarget {
  const ImportTarget.create(this.binding) : kind = ImportKind.create;
  const ImportTarget.refresh(this.binding) : kind = ImportKind.refresh;
  final WorkspaceBinding binding;
  final ImportKind kind;
}

class PreparedImport {
  const PreparedImport({
    required this.target,
    required this.inputDigest,
    required this.stagingToken,
  });
  final ImportTarget target;
  final String inputDigest;
  final String stagingToken;

  bool matches(ImportIntent intent) =>
      target.binding.workspaceId == intent.workspaceId &&
      target.binding.moduleId == intent.moduleId &&
      target.binding.nativeProjectId == intent.targetProjectId &&
      target.kind == intent.kind &&
      inputDigest == intent.inputDigest &&
      stagingToken == intent.stagingToken;
}

class ImportIntent {
  const ImportIntent({
    required this.operationId,
    required this.workspaceId,
    required this.moduleId,
    required this.targetProjectId,
    required this.kind,
    required this.inputDigest,
    required this.stagingToken,
  });
  final String operationId;
  final String workspaceId;
  final String moduleId;
  final String targetProjectId;
  final ImportKind kind;
  final String inputDigest;
  final String stagingToken;

  bool sameIdentity(ImportIntent other) =>
      operationId == other.operationId &&
      workspaceId == other.workspaceId &&
      moduleId == other.moduleId &&
      targetProjectId == other.targetProjectId &&
      kind == other.kind &&
      inputDigest == other.inputDigest &&
      stagingToken == other.stagingToken;
}

class ImportReceipt {
  ImportReceipt({
    required this.intent,
    required Map<String, Object?> result,
    required this.committedAt,
  }) : result = freezeJsonMap(result);
  final ImportIntent intent;
  final Map<String, Object?> result;
  final DateTime committedAt;
  String get operationId => intent.operationId;
  String get workspaceId => intent.workspaceId;
  String get moduleId => intent.moduleId;
  String get targetProjectId => intent.targetProjectId;
  ImportKind get kind => intent.kind;
  String get inputDigest => intent.inputDigest;
}
