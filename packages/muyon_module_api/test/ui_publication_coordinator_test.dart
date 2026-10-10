import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/src/ui/publication.dart';
import 'package:muyon_module_api/src/ui/recomputation.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'ui/fixtures.dart';

UiPublishToken token({
  SnapshotRef base = const SnapshotRef('comparison', 4),
  int draft = 15,
  int host = 1,
  int source = 2,
  int permission = 3,
  String scope = 'fixture:comparison',
}) => UiPublishToken(
  baseSnapshotRef: base,
  draftRevision: draft,
  hostGeneration: host,
  sourceGeneration: source,
  permissionGeneration: permission,
  scopeKey: scope,
);

UiVersionBatch nextBatch(ContractFixture f, {UiPublishToken? frozen}) {
  const nextRef = SnapshotRef('comparison', 5);
  final snapshot = DataSnapshot(
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
  );
  final intent = InteractionIntent(
    id: f.intent.id,
    purpose: f.intent.purpose,
    snapshotRef: nextRef,
    requiredBindings: f.intent.requiredBindings,
    mandatoryStates: f.intent.mandatoryStates,
    allowedActionRefs: f.intent.allowedActionRefs,
  );
  return UiVersionBatch(
    token: frozen ?? token(),
    snapshot: snapshot,
    intent: intent,
    plan: f.plan.copyWith(revision: 5, snapshotRef: nextRef),
  );
}

void main() {
  test('publishes one validated S/I/P bundle synchronously', () {
    final f = ContractFixture();
    final initial = f.validate(f.plan).validatedPlan!;
    final coordinator = UiPublicationCoordinator(initial);
    final candidate = nextBatch(f);
    expect(coordinator.publish(candidate, () => token()), UiPublishOutcome.published);
    final published = coordinator.current;
    expect(published.plan, same(candidate.plan));
    expect(published.snapshot, same(candidate.snapshot));
    expect(published.intent, same(candidate.intent));
    expect(published.catalog, same(initial.catalog));
    expect(published.snapshot.computations['total']!.value, '180');
    expect(initial.snapshot.computations['total']!.value, 120);
    expect(coordinator.publicationErrors, isEmpty);
  });
}
