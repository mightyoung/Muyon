import 'plan.dart';
import 'recomputation.dart';
import 'validation.dart';

/// Owner mutation clock with a synchronous, monotonic advance only.
final class UiPublicationEpoch {
  int _value = 0;
  int get value => _value;
  void advance() => _value++;
}

/// Immutable preparation-time observation; no host callback runs at this fence.
final class UiPublicationFence {
  UiPublicationFence(this.source) : expected = source.value;
  final UiPublicationEpoch source;
  final int expected;
  bool get matches => source.value == expected;
}

/// Opaque request bound to one coordinator, base capability and request epoch.
final class UiRecomputeRequest {
  UiRecomputeRequest._(this._owner, this._base, this._epoch);
  final UiPublicationCoordinator _owner;
  final ValidatedUiPlan _base;
  final int _epoch;
}

/// Isolated host publication boundary, not a session or event executor.
///
/// Only this object's validated S/I/P bundle is atomically replaced. A surface
/// must integrate a prepared session rebase transaction before enabling it;
/// publishing here and then calling the legacy session.accept is unsafe.
final class UiPublicationCoordinator {
  UiPublicationCoordinator(ValidatedUiPlan initial)
    : _current = initial,
      _publishedDraftRevision =
          initial.snapshot.actionContext?.draftRevision ?? 0;

  ValidatedUiPlan _current;
  ValidatedUiPlan get current => _current;
  int _publishedDraftRevision;

  /// Monotonic publication floor; live edit revisions come from the host probe.
  int get publishedDraftRevision => _publishedDraftRevision;
  int _epoch = 0;
  bool _disposed = false;
  bool _recomputing = false;
  bool _outdated = false;
  List<String> _publicationErrors = const [];
  bool get recomputing => _recomputing;
  bool get outdated => _outdated;
  List<String> get publicationErrors => _publicationErrors;

  UiPublishOutcome _invalid(List<String> errors) {
    _publicationErrors = List.unmodifiable(errors);
    _outdated = true;
    return UiPublishOutcome.invalid;
  }

  UiPublishOutcome? _obsolete(int epoch, ValidatedUiPlan base) {
    if (_disposed) return UiPublishOutcome.disposed;
    if (epoch != _epoch || !identical(base, _current)) {
      return UiPublishOutcome.staleToken;
    }
    return null;
  }

  /// Advances an already validated same-snapshot stream/patch capability.
  /// Retains the draft publication floor and invalidates older preparations.
  bool adoptPlan(ValidatedUiPlan next) {
    if (_disposed) return false;
    if (identical(next, _current)) return true;
    if (!identical(next.snapshot, _current.snapshot) ||
        !identical(next.intent, _current.intent) ||
        !identical(next.catalog, _current.catalog) ||
        next.plan.surfaceId != _current.plan.surfaceId ||
        next.plan.revision <= _current.plan.revision) {
      return false;
    }
    _current = next;
    ++_epoch;
    if (_recomputing) {
      _recomputing = false;
      _outdated = true;
      _publicationErrors = const ['recompute_plan_advanced'];
    }
    return true;
  }

  /// Begin before host work; completion remains synchronous for surface install.
  UiRecomputeRequest? beginRecompute() {
    if (_disposed) return null;
    ++_epoch;
    _recomputing = true;
    _publicationErrors = const [];
    return UiRecomputeRequest._(this, _current, _epoch);
  }

  UiPublishOutcome? _requestObsolete(UiRecomputeRequest request) {
    if (_disposed) return UiPublishOutcome.disposed;
    if (!identical(request._owner, this)) return UiPublishOutcome.staleToken;
    return _obsolete(request._epoch, request._base);
  }

  bool isCurrentRequest(UiRecomputeRequest request) =>
      _requestObsolete(request) == null;

  /// No await between final probe, coordinator publication and caller install.
  UiPublishOutcome completeRecompute(
    UiRecomputeRequest request,
    UiVersionBatch batch,
    UiPublishTokenProbe probe, {
    UiPublicationFence? fence,
  }) {
    final obsolete = _requestObsolete(request);
    if (obsolete != null) return obsolete;
    final outcome = publish(batch, probe, fence: fence);
    if (request._epoch == _epoch) {
      _recomputing = false;
      if (outcome != UiPublishOutcome.published) _outdated = true;
    }
    return outcome;
  }

  UiPublishOutcome failRecompute(UiRecomputeRequest request) {
    final obsolete = _requestObsolete(request);
    if (obsolete != null) return obsolete;
    _recomputing = false;
    return _invalid(['recompute_failed']);
  }

  /// Validate a raw host batch, then perform a final synchronous complete probe.
  /// No await, notification or external commit callback occurs in this method.
  UiPublishOutcome publish(
    UiVersionBatch batch,
    UiPublishTokenProbe probe, {
    UiPublicationFence? fence,
  }) {
    if (_disposed) return UiPublishOutcome.disposed;
    if (fence != null && !fence.matches) return UiPublishOutcome.staleToken;
    final base = _current;
    final epoch = _epoch;
    try {
      final live = probe();
      final obsolete = _obsolete(epoch, base);
      if (obsolete != null) return obsolete;
      if (batch.token != live ||
          batch.token.baseSnapshotRef != base.snapshot.ref ||
          batch.token.draftRevision < _publishedDraftRevision) {
        return UiPublishOutcome.staleToken;
      }
    } catch (_) {
      return _obsolete(epoch, base) ?? _invalid(['publish_probe_failed']);
    }
    final plan = batch.plan;
    if (plan.revision <= base.plan.revision ||
        plan.surfaceId != base.plan.surfaceId ||
        plan.catalogVersion != base.catalog.version ||
        plan.snapshotRef != batch.snapshot.ref ||
        batch.intent.snapshotRef != batch.snapshot.ref ||
        plan.intentRef != batch.intent.id ||
        batch.intent.id != base.intent.id ||
        batch.snapshot.ref.id != base.snapshot.ref.id ||
        batch.snapshot.ref.revision <= base.snapshot.ref.revision) {
      return _invalid(['publish_identity_or_revision']);
    }
    if (batch.intent.allowedActionRefs.any(
      (ref) => !base.intent.allowedActionRefs.contains(ref),
    )) {
      return _invalid(['publish_permission_expansion']);
    }
    final UiValidationResult checked;
    try {
      checked = validateUiPlan(
        plan,
        batch.snapshot,
        batch.intent,
        base.catalog,
      );
    } catch (_) {
      return _obsolete(epoch, base) ?? _invalid(['publish_validation_failed']);
    }
    final obsolete = _obsolete(epoch, base);
    if (obsolete != null) return obsolete;
    if (!checked.isValid) return _invalid(checked.errors);
    final accepted = checked.validatedPlan;
    if (accepted == null) return _invalid(['publish_validation_failed']);
    var draft = batch.token.draftRevision;
    final candidateDraft = batch.snapshot.actionContext?.draftRevision ?? 0;
    if (candidateDraft > draft) draft = candidateDraft;
    if (_publishedDraftRevision > draft) draft = _publishedDraftRevision;

    try {
      final live = probe();
      final obsolete = _obsolete(epoch, base);
      if (obsolete != null) return obsolete;
      if (batch.token != live || (fence != null && !fence.matches)) {
        return UiPublishOutcome.staleToken;
      }
    } catch (_) {
      return _obsolete(epoch, base) ?? _invalid(['publish_probe_failed']);
    }
    // Everything below is local non-throwing assignment in one synchronous turn.
    _current = accepted;
    _publishedDraftRevision = draft;
    ++_epoch; // Direct publication also supersedes older async preparations.
    _recomputing = false;
    _outdated = false;
    _publicationErrors = const [];
    return UiPublishOutcome.published;
  }

  /// Fence before invoking preparation; only the latest request may publish.
  /// Cancellation discards results, without claiming to abort underlying work.
  Future<UiPublishOutcome> recompute(
    Future<UiVersionBatch> Function() prepare,
    UiPublishTokenProbe probe,
  ) async {
    final request = beginRecompute();
    if (request == null) return UiPublishOutcome.disposed;
    try {
      final batch = await prepare();
      return completeRecompute(request, batch, probe);
    } catch (_) {
      return failRecompute(request);
    }
  }

  /// Admission only: the existing session/validator still validates payloads.
  /// The owner must consult this inside dispatch and supply real pending state.
  bool allowsDispatch(
    UiActionDefinition action, {
    required bool readOnly,
    required bool pending,
  }) {
    if (_disposed || readOnly || (_outdated && !_recomputing)) return false;
    if (action.route == UiActionRoute.business && (_recomputing || pending)) {
      return false;
    }
    if (pending && action.localAction == UiLocalAction.cancelConfirmation) {
      return false;
    }
    return true;
  }

  void cancelRecompute() {
    if (_disposed || !_recomputing) return;
    ++_epoch;
    _recomputing = false;
    _outdated = true;
    _publicationErrors = const ['recompute_cancelled'];
  }

  void dispose() {
    if (_disposed) return;
    ++_epoch;
    _disposed = true;
    _recomputing = false;
    _outdated = true;
  }
}
