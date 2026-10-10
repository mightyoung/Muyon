import 'plan.dart';
import 'recomputation.dart';
import 'validation.dart';

/// Isolated host publication boundary, not a session or event executor.
///
/// Only this object's validated S/I/P bundle is atomically replaced. A surface
/// must integrate a prepared session rebase transaction before enabling it;
/// publishing here and then calling the legacy session.accept is unsafe.
final class UiPublicationCoordinator {
  UiPublicationCoordinator(ValidatedUiPlan initial)
    : _current = initial,
      _publishedDraftRevision = initial.snapshot.actionContext?.draftRevision ?? 0;

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

  /// Validate a raw host batch, then perform a final synchronous complete probe.
  /// No await, notification or external commit callback occurs in this method.
  UiPublishOutcome publish(UiVersionBatch batch, UiPublishTokenProbe probe) {
    if (_disposed) return UiPublishOutcome.disposed;
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
      checked = validateUiPlan(plan, batch.snapshot, batch.intent, base.catalog);
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
      if (batch.token != live) return UiPublishOutcome.staleToken;
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
    if (_disposed) return UiPublishOutcome.disposed;
    final epoch = ++_epoch;
    final base = _current;
    _recomputing = true;
    _publicationErrors = const [];
    try {
      final batch = await prepare();
      final obsolete = _obsolete(epoch, base);
      if (obsolete != null) return obsolete;
      final outcome = publish(batch, probe);
      if (outcome != UiPublishOutcome.published && epoch == _epoch) {
        _outdated = true;
      }
      return outcome;
    } catch (_) {
      return _obsolete(epoch, base) ?? _invalid(['recompute_failed']);
    } finally {
      if (epoch == _epoch) _recomputing = false;
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
