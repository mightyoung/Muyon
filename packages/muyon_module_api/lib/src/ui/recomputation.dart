import 'intent.dart';
import 'plan.dart';
import 'snapshot.dart';

final class UiRecomputeInput {
  UiRecomputeInput({
    required this.previousSnapshot,
    required Map<String, Object?> currentUiState,
    required this.token,
  }) : currentUiState = Map.of(currentUiState);

  final DataSnapshot previousSnapshot;
  final Map<String, Object?> currentUiState;
  final UiPublishToken token;
}

final class UiRecomputeResult {
  UiRecomputeResult({
    required this.token,
    this.nextSnapshot,
    this.nextIntent,
    List<String> errors = const [],
  }) : errors = List.of(errors);

  final UiPublishToken token;
  final DataSnapshot? nextSnapshot;
  final InteractionIntent? nextIntent;
  final List<String> errors;
}

abstract interface class UiRecomputePort {
  Future<UiRecomputeResult> rebuild(UiRecomputeInput input);
}

final class UiPublishToken {
  const UiPublishToken({
    required this.baseSnapshotRef,
    required this.draftRevision,
    required this.hostGeneration,
    required this.sourceGeneration,
    required this.permissionGeneration,
    required this.scopeKey,
  });

  final SnapshotRef baseSnapshotRef;
  final int draftRevision;
  final int hostGeneration;
  final int sourceGeneration;
  final int permissionGeneration;
  final String scopeKey;
}

final class UiVersionBatch {
  const UiVersionBatch({
    required this.token,
    required this.snapshot,
    required this.intent,
    required this.plan,
  });

  final UiPublishToken token;
  final DataSnapshot snapshot;
  final InteractionIntent intent;
  final UIPlan plan;
}

enum UiPublishOutcome { published, staleToken, invalid, disposed }

typedef UiPublishTokenProbe = UiPublishToken Function();
