import 'snapshot.dart';
import 'plan.dart';
import 'validation.dart';
import 'workspace.dart';

enum UiEventOutcome { applied, stale, invalid, unsupported }

/// In-memory view/draft state only. Never grants authority or executes business tools.
class UiSessionState {
  UiSessionState(this.snapshot)
    : _values = Map.of(snapshot.initialUiState),
      _digests = Map.of(snapshot.sourceDigests),
      draftRevision = snapshot.actionContext?.draftRevision ?? 0;
  final DataSnapshot snapshot;
  final Map<String, Object?> _values;
  final Map<String, String> _digests;
  final Map<String, Object?> _userOverrides = {};
  final Map<String, Object?> _viewValues = {};
  Map<String, Object?> get userOverrides => Map.unmodifiable(_userOverrides);
  Map<String, Object?> get viewValues => Map.unmodifiable(_viewValues);
  Set<String> get expandedSources => Set.unmodifiable(_expandedSources);
  Set<String> get cancelledNodes => Set.unmodifiable(_cancelled);
  final Set<String> _expandedSources = {};
  final Set<String> _cancelled = {};
  bool isCancelled(String nodeId) => _cancelled.contains(nodeId);
  final Set<String> _staleSources = {};
  ValidatedUiPlan? _currentPlan;
  ValidatedUiPlan? get currentPlan => _currentPlan;
  Set<String> get staleSources => Set.unmodifiable(_staleSources);
  bool isExpanded(String nodeId) => _expandedSources.contains(nodeId);
  String? detailNode;
  int draftRevision;
  Object? resolve(BindingRef ref) {
    switch (ref.kind) {
      case BindingKind.fact:
        return snapshot.facts[ref.id]?.value;
      case BindingKind.uiState:
        return _values[ref.id];
      case BindingKind.computed:
        final result = snapshot.computations[ref.id];
        return result?.inputVersion == snapshot.ref ? result?.value : null;
      case BindingKind.collection:
        // No host collection registry yet (slice 1b): never resolves.
        return null;
      case BindingKind.sourceSpan:
        final source = snapshot.sources[ref.id];
        if (source == null) return null;
        if (_digests[source.artifact.artifactId] !=
            source.artifact.contentDigest) {
          _staleSources.add(ref.id);
          return null;
        }
        if (source.start < 0 ||
            source.end > source.originalText.length ||
            source.end <= source.start)
          return null;
        return source.originalText.substring(source.start, source.end);
    }
  }

  void edit(String field, Object? value) =>
      _setValue(field, value, affectsDraft: true);

  void selectView(String field, Object? value) {
    if (snapshot.actionContext?.draft.containsKey(field) ?? false) return;
    _setValue(field, value, affectsDraft: false);
  }

  void _setValue(String field, Object? value, {required bool affectsDraft}) {
    if (!_values.containsKey(field) ||
        !isUiScalar(value) ||
        (_values[field] is String && value is! String))
      return;
    final explicitlyEdited = affectsDraft && !_userOverrides.containsKey(field);
    if (affectsDraft)
      _userOverrides[field] = value;
    else
      _viewValues[field] = value;
    if (_values[field] == value && !explicitlyEdited) return;
    _values[field] = value;
    if (affectsDraft) draftRevision++;
  }

  /// Restores UI scalars only; never changes snapshot facts or host inputs.
  void restoreWorkspace(StoredUiWorkspace value) {
    for (final entry in {...value.viewValues, ...value.userOverrides}.entries) {
      if (_values.containsKey(entry.key) &&
          isUiScalar(entry.value) &&
          (_values[entry.key] is! String || entry.value is String)) {
        _values[entry.key] = entry.value;
      }
    }
    _userOverrides.addAll(value.userOverrides);
    _viewValues.addAll(value.viewValues);
    draftRevision = value.draftRevision > draftRevision
        ? value.draftRevision
        : draftRevision;
    if (value.snapshotRef != snapshot.ref) draftRevision++;
    _expandedSources.addAll(value.expandedSources);
    _cancelled.addAll(value.cancelledNodes);
    detailNode = value.detailNode;
  }

  void adoptExtracted(String field) {
    if (!_userOverrides.containsKey(field) ||
        !snapshot.initialUiState.containsKey(field))
      return;
    _userOverrides.remove(field);
    _values[field] = snapshot.initialUiState[field];
    draftRevision++;
  }

  void updateSourceDigest(String artifactId, String digest) {
    _digests[artifactId] = digest;
  }

  bool accept(ValidatedUiPlan plan) {
    final current = _currentPlan;
    if (!identical(plan.snapshot, snapshot) ||
        (current != null &&
            (plan.plan.surfaceId != current.plan.surfaceId ||
                plan.plan.revision < current.plan.revision ||
                (plan.plan.revision == current.plan.revision &&
                    !identical(plan, current)))))
      return false;
    _currentPlan = plan;
    return true;
  }

  UiEventOutcome dispatch(
    UiEvent event,
    ValidatedUiPlan plan,
    UiCatalog catalog,
  ) {
    if (!identical(plan, _currentPlan) ||
        event.surfaceId != plan.plan.surfaceId ||
        event.observedRevision != plan.plan.revision ||
        !identical(catalog, plan.catalog))
      return UiEventOutcome.stale;
    final nodes = plan.plan.nodes.where((node) => node.id == event.nodeId);
    if (nodes.length != 1 || event.eventId.isEmpty)
      return UiEventOutcome.invalid;
    final node = nodes.single;
    final binding = node.events[event.kind];
    final definition = catalog.actions[binding?.actionRef];
    final schema = catalog.components[node.component];
    if (binding == null ||
        definition == null ||
        schema == null ||
        !schema.events.containsKey(event.kind) ||
        !(schema.eventActions[event.kind]?.contains(binding.actionRef) ??
            false))
      return UiEventOutcome.invalid;
    final payloadType = schema.events[event.kind];
    if (payloadType == null
        ? event.payload != null
        : !matchesUiValue(payloadType, event.payload))
      return UiEventOutcome.invalid;
    if (definition.route != UiActionRoute.local) {
      if (definition.route == UiActionRoute.business &&
          binding.expectedDraftRevision != draftRevision)
        return UiEventOutcome.stale;
      return UiEventOutcome.unsupported;
    }
    switch (definition.localAction) {
      case UiLocalAction.editField:
        if (binding.inputRefs.length != 1) return UiEventOutcome.invalid;
        edit(binding.inputRefs.single, event.payload);
      case UiLocalAction.sortRows:
        if (binding.inputRefs.length != 1 ||
            (snapshot.actionContext?.draft.containsKey(
                  binding.inputRefs.single,
                ) ??
                false) ||
            !['original', 'value'].contains(event.payload))
          return UiEventOutcome.invalid;
        selectView(binding.inputRefs.single, event.payload);
      case UiLocalAction.expandSource:
        if (!_expandedSources.add(node.id)) _expandedSources.remove(node.id);
      case UiLocalAction.openDetail:
        if (!node.bindings.containsKey('value')) return UiEventOutcome.invalid;
        detailNode = node.id;
      case UiLocalAction.back:
        detailNode = null;
      case UiLocalAction.cancelConfirmation:
        _cancelled.add(node.id);
      case null:
        return UiEventOutcome.invalid;
    }
    return UiEventOutcome.applied;
  }
}
