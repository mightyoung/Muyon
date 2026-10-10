import '../references.dart';
import 'edit_spec.dart';
import 'snapshot.dart';
import 'plan.dart';
import 'validation.dart';
import 'workspace.dart';

enum UiEventOutcome { applied, stale, invalid, unsupported }

/// Owner-prepared session state; only its originating session may install it.
class UiPreparedSessionRebase {
  UiPreparedSessionRebase._(this._owner, this._base, this._next);
  final UiSessionState _owner;
  final ValidatedUiPlan? _base;
  final ValidatedUiPlan _next;
}

/// In-memory view/draft state only. Never grants authority or executes business tools.
class UiSessionState {
  UiSessionState(this.snapshot)
    : _values = Map.of(snapshot.initialUiState),
      _digests = Map.of(snapshot.sourceDigests),
      _selections = {
        for (final e in snapshot.editSpecs.entries)
          if (e.value case final UiItemIdsEdit ids)
            e.key: UiItemIdsEdit.normalize(ids.initial),
      },
      draftRevision = snapshot.actionContext?.draftRevision ?? 0;
  final DataSnapshot snapshot;
  final Map<String, Object?> _values;
  // itemIds live outside _values/userOverrides: never scalar.
  final Map<String, List<String>> _selections;
  final Set<String> _selectionOverrides = {};
  final Map<String, List<String>> _viewSelections = {};
  Map<String, List<String>> get selections => Map.unmodifiable(_selections);
  Set<String> get selectionOverrides => Set.unmodifiable(_selectionOverrides);
  Map<String, List<String>> get viewSelections =>
      Map.unmodifiable(_viewSelections);
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
        // Collection metadata is read from the registry, never as a scalar value.
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
            source.end <= source.start) {
          return null;
        }
        return source.originalText.substring(source.start, source.end);
    }
  }

  /// Resolve a stable row identity only from the accepted host capability.
  ObjectRef? rowObject(UiNode node, Object? itemId) {
    final plan = _currentPlan;
    if (plan == null ||
        !usesTypedEdits(plan.catalog) ||
        itemId is! String ||
        !plan.plan.nodes.any((current) => identical(current, node))) {
      return null;
    }
    final refs = node.bindings.values.where(
      (ref) => ref.kind == BindingKind.collection,
    );
    if (refs.length != 1) return null;
    final rows = snapshot.collections[refs.single.id]?.rows.where(
      (row) => row.itemId == itemId,
    );
    if (rows == null || rows.length != 1) return null;
    final row = rows.single;
    final object = row.object;
    if (object == null ||
        !row.cells.values.any(
          (ref) =>
              ref.kind == BindingKind.fact &&
              snapshot.facts[ref.id]?.object == object,
        )) {
      return null;
    }
    for (final cell in row.cells.values) {
      final sourceRefs = switch (cell.kind) {
        BindingKind.fact =>
          snapshot.facts[cell.id]?.sourceRefs ?? const <String>[],
        BindingKind.computed =>
          snapshot.computedEvidence[cell.id]?.sourceRefs ?? const <String>[],
        _ => const <String>[],
      };
      for (final sourceId in sourceRefs) {
        final source = snapshot.sources[sourceId];
        if (source == null ||
            _digests[source.artifact.artifactId] !=
                source.artifact.contentDigest) {
          return null;
        }
      }
    }
    return object;
  }

  /// Typed rules are in force only while the accepted current plan uses a
  /// typed catalog; with no plan or an older catalog the legacy gate applies.
  bool get _typedActive {
    final plan = _currentPlan;
    return plan != null && usesTypedEdits(plan.catalog);
  }

  String? _specReject(UiEditSpec spec, Object? value) =>
      spec.validateSpec() != null
      ? 'spec_invalid'
      : spec.reject(value, UiEditContext(collections: snapshot.collections));

  void edit(String field, Object? value) => _editCore(field, value);

  void selectView(String field, Object? value) => _selectViewCore(field, value);

  /// A key without a registered spec is a default [UiStringEdit].
  bool _editCore(String field, Object? value) {
    if (!_typedActive) return _setValue(field, value, affectsDraft: true);
    final spec = snapshot.editSpecs[field] ?? const UiStringEdit();
    // View keys are never draft edits.
    if (spec.view || _specReject(spec, value) != null) return false;
    return _applyTyped(field, spec, value, affectsDraft: true);
  }

  /// Returns whether the view value was written (or already equal).
  bool _selectViewCore(String field, Object? value) {
    if (snapshot.actionContext?.draft.containsKey(field) ?? false) {
      return false;
    }
    if (!_typedActive) return _setValue(field, value, affectsDraft: false);
    final registered = snapshot.editSpecs[field];
    if (registered == null) {
      // Unregistered key keeps the legacy sort mapping under the default spec.
      return _specReject(const UiStringEdit(), value) == null &&
          _setValue(field, value, affectsDraft: false);
    }
    // A registered spec must itself be a view spec: no draft bypass.
    if (!registered.view || _specReject(registered, value) != null) {
      return false;
    }
    return _applyTyped(field, registered, value, affectsDraft: false);
  }

  bool _applyTyped(
    String field,
    UiEditSpec spec,
    Object? value, {
    required bool affectsDraft,
  }) {
    if (spec is! UiItemIdsEdit) {
      return _setValue(field, value, affectsDraft: affectsDraft, typed: true);
    }
    final ids = UiItemIdsEdit.normalize((value as List).cast<String>());
    final explicitlyEdited =
        affectsDraft && !_selectionOverrides.contains(field);
    if (affectsDraft) {
      _selectionOverrides.add(field);
    } else {
      _viewSelections[field] = ids;
    }
    final changed = !_sameIds(_selections[field], ids);
    _selections[field] = ids;
    if (affectsDraft && (changed || explicitlyEdited)) draftRevision++;
    return true;
  }

  static bool _sameIds(List<String>? a, List<String> b) =>
      a != null &&
      a.length == b.length &&
      Iterable.generate(b.length).every((i) => a[i] == b[i]);

  bool _setValue(
    String field,
    Object? value, {
    required bool affectsDraft,
    bool typed = false,
  }) {
    // Typed values were already checked against their spec; the legacy
    // "String stays String" lock would wrongly block nullable string/date.
    if (!_values.containsKey(field) ||
        !isUiScalar(value) ||
        (!typed && _values[field] is String && value is! String)) {
      return false;
    }
    final explicitlyEdited = affectsDraft && !_userOverrides.containsKey(field);
    if (affectsDraft) {
      _userOverrides[field] = value;
    } else {
      _viewValues[field] = value;
    }
    if (_values[field] == value && !explicitlyEdited) return true;
    _values[field] = value;
    if (affectsDraft) draftRevision++;
    return true;
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
    final spec = snapshot.editSpecs[field];
    if (spec is UiItemIdsEdit && _selectionOverrides.remove(field)) {
      _selections[field] = UiItemIdsEdit.normalize(spec.initial);
      draftRevision++;
      return;
    }
    if (!_userOverrides.containsKey(field) ||
        !snapshot.initialUiState.containsKey(field)) {
      return;
    }
    _userOverrides.remove(field);
    _values[field] = snapshot.initialUiState[field];
    draftRevision++;
  }

  void updateSourceDigest(String artifactId, String digest) {
    _digests[artifactId] = digest;
  }

  UiPreparedSessionRebase prepareRebase(ValidatedUiPlan next) =>
      UiPreparedSessionRebase._(this, _currentPlan, next);

  // RED: no live snapshot/layer mutation until the owner transaction exists.
  bool commitPreparedRebase(UiPreparedSessionRebase prepared) => false;

  bool accept(ValidatedUiPlan plan) {
    final current = _currentPlan;
    if (!identical(plan.snapshot, snapshot) ||
        (current != null &&
            (plan.plan.surfaceId != current.plan.surfaceId ||
                plan.plan.revision < current.plan.revision ||
                (plan.plan.revision == current.plan.revision &&
                    !identical(plan, current))))) {
      return false;
    }
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
        !identical(catalog, plan.catalog)) {
      return UiEventOutcome.stale;
    }
    final nodes = plan.plan.nodes.where((node) => node.id == event.nodeId);
    if (nodes.length != 1 || event.eventId.isEmpty) {
      return UiEventOutcome.invalid;
    }
    final node = nodes.single;
    final binding = node.events[event.kind];
    final definition = catalog.actions[binding?.actionRef];
    final schema = catalog.components[node.component];
    if (binding == null ||
        definition == null ||
        schema == null ||
        !schema.events.containsKey(event.kind) ||
        !(schema.eventActions[event.kind]?.contains(binding.actionRef) ??
            false)) {
      return UiEventOutcome.invalid;
    }
    final payloadType = schema.events[event.kind];
    // library-2 editField: the host spec, not the coarse type, owns the payload.
    UiEditSpec? spec;
    if (usesTypedEdits(catalog) &&
        definition.route == UiActionRoute.local &&
        definition.localAction == UiLocalAction.editField) {
      if (binding.inputRefs.length != 1) return UiEventOutcome.invalid;
      if (node.component == 'Tabs' && !node.children.contains(event.payload)) {
        return UiEventOutcome.invalid;
      }
      spec =
          snapshot.editSpecs[binding.inputRefs.single] ?? const UiStringEdit();
      if (spec.payloadType != payloadType) return UiEventOutcome.invalid;
    }
    if (!(spec != null && spec.nullable && event.payload == null) &&
        (payloadType == null
            ? event.payload != null
            : !matchesUiValue(payloadType, event.payload))) {
      return UiEventOutcome.invalid;
    }
    if (definition.route != UiActionRoute.local) {
      if (definition.route == UiActionRoute.business &&
          binding.expectedDraftRevision != draftRevision) {
        return UiEventOutcome.stale;
      }
      return UiEventOutcome.unsupported;
    }
    switch (definition.localAction) {
      case UiLocalAction.editField:
        if (binding.inputRefs.length != 1) return UiEventOutcome.invalid;
        final key = binding.inputRefs.single;
        if (spec == null) {
          edit(key, event.payload);
        } else {
          if (_specReject(spec, event.payload) != null ||
              (spec.view &&
                  (snapshot.actionContext?.draft.containsKey(key) ?? false))) {
            return UiEventOutcome.invalid;
          }
          _applyTyped(key, spec, event.payload, affectsDraft: !spec.view);
        }
      case UiLocalAction.sortRows:
        if (binding.inputRefs.length != 1 ||
            (snapshot.actionContext?.draft.containsKey(
                  binding.inputRefs.single,
                ) ??
                false) ||
            !['original', 'value'].contains(event.payload)) {
          return UiEventOutcome.invalid;
        }
        final written = _selectViewCore(
          binding.inputRefs.single,
          event.payload,
        );
        // Legacy catalogs keep their historic always-applied sort; library-2
        // never reports applied for a write that was refused.
        if (!written && usesTypedEdits(catalog)) return UiEventOutcome.invalid;
      case UiLocalAction.expandSource:
        if (!_expandedSources.add(node.id)) _expandedSources.remove(node.id);
      case UiLocalAction.openDetail:
        if (!node.bindings.containsKey('value')) return UiEventOutcome.invalid;
        detailNode = node.id;
      case UiLocalAction.openRow:
        if (rowObject(node, event.payload) == null) {
          return UiEventOutcome.invalid;
        }
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
