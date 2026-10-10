import 'intent.dart';
import 'plan.dart';
import 'snapshot.dart';
import 'validation.dart' show isUiScalar;

/// Frozen host input. Current values stay separate from extracted snapshot state.
///
/// This is the complete scalar state map, not a changed-key patch. Selection
/// lists belong to the separate selection layer. Invalid shape or non-scalar
/// values throw [ArgumentError]; Strings are preserved without decimal coercion.
final class UiRecomputeInput {
  UiRecomputeInput({
    required this.previousSnapshot,
    required Map<String, Object?> currentUiState,
    required this.token,
  }) : currentUiState = Map.unmodifiable(currentUiState) {
    final declared = previousSnapshot.initialUiState;
    if (this.currentUiState.length != declared.length ||
        this.currentUiState.keys.any((key) => !declared.containsKey(key))) {
      throw ArgumentError('currentUiState must contain exactly the declared keys');
    }
    if (this.currentUiState.values.any((value) => !isUiScalar(value))) {
      throw ArgumentError('currentUiState must contain only finite UI scalars');
    }
  }

  final DataSnapshot previousSnapshot;
  final Map<String, Object?> currentUiState;
  final UiPublishToken token;
}

/// A complete candidate pair with no errors, or no candidate with errors.
///
/// Mixed or empty outcomes throw [ArgumentError]. Errors are blocking
/// diagnostics, not warnings. A registered nullable computed output can still
/// form a candidate. Snapshot/intent identity is retained; admission belongs to
/// the existing validator and subsequent publisher. The host must carry the
/// input token unchanged, including all generations.
final class UiRecomputeResult {
  UiRecomputeResult({
    required this.token,
    this.nextSnapshot,
    this.nextIntent,
    List<String> errors = const [],
  }) : errors = List.unmodifiable(errors) {
    final candidate = nextSnapshot != null && nextIntent != null;
    final failure = nextSnapshot == null && nextIntent == null;
    if (!((candidate && this.errors.isEmpty) ||
        (failure && this.errors.isNotEmpty))) {
      throw ArgumentError('Provide a complete candidate or failure diagnostics');
    }
  }

  final UiPublishToken token;
  final DataSnapshot? nextSnapshot;
  final InteractionIntent? nextIntent;
  final List<String> errors;
}

/// Host-only rebuild boundary; no model, executor or IO implementation here.
///
/// Implementations retain [UiRecomputeInput.token], keep extracted values in the
/// next snapshot, and actually recompute every displayed computed instance using
/// current values. Formula state inputs must be Strings and not view state.
/// Callers handle asynchronous exceptions, cancellation and stale candidates.
abstract interface class UiRecomputePort {
  Future<UiRecomputeResult> rebuild(UiRecomputeInput input);
}

/// Host freshness value. Every component participates in equality and hashing.
///
/// Scope is opaque and compared verbatim. This token does not grant permission
/// or validate generation ranges; the host owns the counters and their meaning.
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

  @override
  bool operator ==(Object other) =>
      other is UiPublishToken &&
      baseSnapshotRef == other.baseSnapshotRef &&
      draftRevision == other.draftRevision &&
      hostGeneration == other.hostGeneration &&
      sourceGeneration == other.sourceGeneration &&
      permissionGeneration == other.permissionGeneration &&
      scopeKey == other.scopeKey;

  @override
  int get hashCode => Object.hash(
    baseSnapshotRef,
    draftRevision,
    hostGeneration,
    sourceGeneration,
    permissionGeneration,
    scopeKey,
  );
}

/// Host-prepared raw candidate; retains snapshot, intent and plan identity.
///
/// No second validator is introduced. The synchronous publisher must check
/// complete token freshness, strictly increasing plan revision, surface/catalog
/// and snapshot/intent relationships, then use the existing plan validator.
/// Referenced objects retain their existing type contracts and freeze guarantees.
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

/// Results of the subsequent synchronous publication boundary.
enum UiPublishOutcome {
  /// The complete candidate was admitted and atomically installed.
  published,

  /// At least one frozen token component no longer matches the host.
  staleToken,

  /// Candidate admission failed; the controller exposes publicationErrors.
  invalid,

  /// The receiving controller has been disposed.
  disposed,
}

/// Synchronous host reader of all current token components, re-read at commit.
/// No await may separate the final complete comparison from atomic publication.
typedef UiPublishTokenProbe = UiPublishToken Function();
