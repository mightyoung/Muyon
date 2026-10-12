import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'ui/fixtures.dart';

// CF-FIX-T5 (RED): freshness is a per-value axis separate from FactState. A
// computed value whose recompute is pending or failed is previous, and only a
// successful publication restores current.

UiPublishToken _token() => UiPublishToken(
  baseSnapshotRef: const SnapshotRef('comparison', 4),
  draftRevision: 15,
  hostGeneration: 1,
  sourceGeneration: 2,
  permissionGeneration: 3,
  scopeKey: 'fixture:comparison',
);

UiVersionBatch _nextBatch(ContractFixture f) {
  const nextRef = SnapshotRef('comparison', 5);
  return UiVersionBatch(
    token: _token(),
    snapshot: DataSnapshot(
      ref: nextRef,
      facts: f.snapshot.facts,
      initialUiState: f.snapshot.initialUiState,
      computations: {
        'total': const ComputedValue(
          value: '180',
          inputVersion: nextRef,
          computationId: 'fixture-total',
        ),
      },
      sources: f.snapshot.sources,
      sourceDigests: f.snapshot.sourceDigests,
      actionContext: f.snapshot.actionContext,
    ),
    intent: InteractionIntent(
      id: f.intent.id,
      purpose: f.intent.purpose,
      snapshotRef: nextRef,
      requiredBindings: f.intent.requiredBindings,
      mandatoryStates: f.intent.mandatoryStates,
      allowedActionRefs: f.intent.allowedActionRefs,
    ),
    plan: f.plan.copyWith(revision: 5, snapshotRef: nextRef),
  );
}

void main() {
  test('a computed value is previous while a recompute is pending or after it fails, and current after publication', () {
    final f = ContractFixture();
    final coordinator = UiPublicationCoordinator(
      f.validate(f.plan).validatedPlan!,
    );
    expect(coordinator.freshnessOf('total'), UiValueFreshness.current);

    final failed = coordinator.beginRecompute()!;
    expect(coordinator.freshnessOf('total'), UiValueFreshness.previous);

    expect(coordinator.failRecompute(failed), UiPublishOutcome.invalid);
    expect(coordinator.freshnessOf('total'), UiValueFreshness.previous);

    final request = coordinator.beginRecompute()!;
    expect(
      coordinator.completeRecompute(request, _nextBatch(f), _token),
      UiPublishOutcome.published,
    );
    expect(coordinator.freshnessOf('total'), UiValueFreshness.current);
  });
}
