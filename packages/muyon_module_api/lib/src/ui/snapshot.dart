import '../references.dart';
import 'collection.dart';
import 'edit_spec.dart';

enum FactState {
  verified,
  unverified,
  notDisclosed,
  notApplicable,
  readFailed,
  conflict,
}

enum BindingKind { fact, uiState, computed, sourceSpan, collection }

class SnapshotRef {
  const SnapshotRef(this.id, this.revision);
  final String id;
  final int revision;
  @override
  bool operator ==(Object other) =>
      other is SnapshotRef && id == other.id && revision == other.revision;
  @override
  int get hashCode => Object.hash(id, revision);
}

class BindingRef {
  const BindingRef(this.kind, this.id);
  const BindingRef.fact(this.id) : kind = BindingKind.fact;
  const BindingRef.uiState(this.id) : kind = BindingKind.uiState;
  const BindingRef.computed(this.id) : kind = BindingKind.computed;
  const BindingRef.sourceSpan(this.id) : kind = BindingKind.sourceSpan;
  const BindingRef.collection(this.id) : kind = BindingKind.collection;
  final BindingKind kind;
  final String id;
  @override
  bool operator ==(Object other) =>
      other is BindingRef && kind == other.kind && id == other.id;
  @override
  int get hashCode => Object.hash(kind, id);
}

class SnapshotFact {
  SnapshotFact({
    required this.object,
    required this.field,
    required this.value,
    required this.state,
    this.unit,
    List<String> sourceRefs = const [],
  }) : sourceRefs = List.unmodifiable(sourceRefs);
  final ObjectRef object;
  final String field;
  final Object? value;
  final FactState state;
  final String? unit;
  final List<String> sourceRefs;
}

class ComputedValue {
  const ComputedValue({
    required this.value,
    required this.inputVersion,
    required this.computationId,
  });
  final Object? value;
  final SnapshotRef inputVersion;
  final String computationId;
}

/// Host evidence required by library-2 computed bindings and collection cells.
class UiComputedEvidence {
  UiComputedEvidence({
    required this.state,
    this.unit,
    List<String> sourceRefs = const [],
  }) : sourceRefs = List.unmodifiable(sourceRefs);
  final FactState state;
  final String? unit;
  final List<String> sourceRefs;
}

class SourceSpanRef {
  const SourceSpanRef({
    required this.artifact,
    required this.originalText,
    required this.start,
    required this.end,
    this.page,
    this.paragraph,
  });
  final ArtifactRef artifact;
  final String originalText;
  final int start, end;
  final int? page, paragraph;
}

class HostOperationRef {
  HostOperationRef({
    required this.draftRevision,
    required Set<String> inputRefs,
  }) : inputRefs = Set.unmodifiable(inputRefs);
  final int draftRevision;
  final Set<String> inputRefs;
}

class UiActionContext {
  UiActionContext({
    required this.draftRevision,
    Map<String, Object?> draft = const {},
    Set<String> confirmedRecordRefs = const {},
    Map<String, HostOperationRef> operations = const {},
  }) : draft = Map.unmodifiable(draft),
       confirmedRecordRefs = Set.unmodifiable(confirmedRecordRefs),
       operations = Map.unmodifiable(operations);
  final int draftRevision;
  final Map<String, Object?> draft;
  final Set<String> confirmedRecordRefs;
  final Map<String, HostOperationRef> operations;
}

class DataSnapshot {
  DataSnapshot({
    required this.ref,
    required Map<String, SnapshotFact> facts,
    Map<String, Object?> initialUiState = const {},
    Map<String, ComputedValue> computations = const {},
    Map<String, SourceSpanRef> sources = const {},
    Map<String, String> sourceDigests = const {},
    this.actionContext,
    Map<String, UiEditSpec> editSpecs = const {},
    Map<String, UiCollection> collections = const {},
    Map<String, UiComputedEvidence> computedEvidence = const {},
  }) : facts = Map.unmodifiable(facts),
       editSpecs = Map.unmodifiable(editSpecs),
       collections = Map.unmodifiable(collections),
       computedEvidence = Map.unmodifiable(computedEvidence),
       initialUiState = Map.unmodifiable(initialUiState),
       computations = Map.unmodifiable(computations),
       sources = Map.unmodifiable(sources),
       sourceDigests = Map.unmodifiable(sourceDigests);
  final SnapshotRef ref;
  final Map<String, SnapshotFact> facts;
  final Map<String, Object?> initialUiState;
  final Map<String, ComputedValue> computations;
  final Map<String, SourceSpanRef> sources;
  final Map<String, String> sourceDigests;
  final UiActionContext? actionContext;

  /// Host-owned edit rules checked by library-2 validation and dispatch.
  final Map<String, UiEditSpec> editSpecs;
  final Map<String, UiCollection> collections;
  final Map<String, UiComputedEvidence> computedEvidence;
  DataSnapshot copyWith({
    Map<String, String>? sourceDigests,
    Map<String, ComputedValue>? computations,
    Map<String, UiComputedEvidence>? computedEvidence,
  }) => DataSnapshot(
    ref: ref,
    facts: facts,
    initialUiState: initialUiState,
    computations: computations ?? this.computations,
    sources: sources,
    sourceDigests: sourceDigests ?? this.sourceDigests,
    actionContext: actionContext,
    editSpecs: editSpecs,
    collections: collections,
    computedEvidence: computedEvidence ?? this.computedEvidence,
  );
}
