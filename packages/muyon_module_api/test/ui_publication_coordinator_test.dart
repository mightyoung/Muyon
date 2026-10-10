import 'dart:async';

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

UiVersionBatch replace(
  UiVersionBatch batch, {
  UIPlan? plan,
  DataSnapshot? snapshot,
  InteractionIntent? intent,
  UiPublishToken? frozen,
}) => UiVersionBatch(
  token: frozen ?? batch.token,
  snapshot: snapshot ?? batch.snapshot,
  intent: intent ?? batch.intent,
  plan: plan ?? batch.plan,
);

UIPlan planWith(UIPlan p, {String? surface, String? catalog}) => UIPlan(
  surfaceId: surface ?? p.surfaceId,
  revision: p.revision,
  catalogVersion: catalog ?? p.catalogVersion,
  snapshotRef: p.snapshotRef,
  intentRef: p.intentRef,
  root: p.root,
  nodes: p.nodes,
);

InteractionIntent intentWith(
  InteractionIntent i, {
  String? id,
  SnapshotRef? ref,
  Set<String>? allowed,
}) => InteractionIntent(
  id: id ?? i.id,
  purpose: i.purpose,
  snapshotRef: ref ?? i.snapshotRef,
  requiredBindings: i.requiredBindings,
  mandatoryStates: i.mandatoryStates,
  allowedActionRefs: allowed ?? i.allowedActionRefs,
);

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

  test('any changed token component discards the entire candidate', () {
    final f = ContractFixture();
    final initial = f.validate(f.plan).validatedPlan!;
    for (final changed in [
      token(base: const SnapshotRef('other', 4)),
      token(base: const SnapshotRef('comparison', 5)),
      token(draft: 16),
      token(host: 2),
      token(source: 3),
      token(permission: 4),
      token(scope: 'other'),
    ]) {
      final c = UiPublicationCoordinator(initial);
      expect(c.publish(nextBatch(f), () => changed), UiPublishOutcome.staleToken);
      expect(c.current, same(initial));
      expect(c.publicationErrors, isEmpty);
    }
    final wrongBase = token(base: const SnapshotRef('other', 4));
    final c = UiPublicationCoordinator(initial);
    expect(
      c.publish(nextBatch(f, frozen: wrongBase), () => wrongBase),
      UiPublishOutcome.staleToken,
    );
    expect(c.current, same(initial));
    final rollback = token(draft: 14);
    expect(c.publish(nextBatch(f, frozen: rollback), () => rollback),
        UiPublishOutcome.staleToken);
    expect(c.publishedDraftRevision, 15);
  });

  test('final synchronous probe catches revocation after validation', () {
    final f = ContractFixture();
    final initial = f.validate(f.plan).validatedPlan!;
    final c = UiPublicationCoordinator(initial);
    var reads = 0;
    expect(
      c.publish(nextBatch(f), () => ++reads == 1 ? token() : token(source: 3)),
      UiPublishOutcome.staleToken,
    );
    expect(reads, 2);
    expect(c.current, same(initial));
    expect(c.current.snapshot.ref, const SnapshotRef('comparison', 4));
  });

  test('reentrant disposal from the final probe prevents commit', () {
    final f = ContractFixture();
    final initial = f.validate(f.plan).validatedPlan!;
    final c = UiPublicationCoordinator(initial);
    var reads = 0;
    expect(c.publish(nextBatch(f), () {
      if (++reads == 2) c.dispose();
      return token();
    }), UiPublishOutcome.disposed);
    expect(c.current, same(initial));
  });

  test('strict identity, revision and validator failures preserve old bundle', () {
    final f = ContractFixture();
    final initial = f.validate(f.plan).validatedPlan!;
    final good = nextBatch(f);
    final candidates = [
      replace(good, plan: good.plan.copyWith(revision: 4)),
      replace(good, plan: good.plan.copyWith(revision: 3)),
      replace(good, plan: planWith(good.plan, surface: 'other')),
      replace(good, plan: planWith(good.plan, catalog: 'other')),
      replace(good, plan: good.plan.copyWith(snapshotRef: f.snapshot.ref)),
      replace(good, snapshot: f.snapshot),
      replace(good, snapshot: f.snapshot, intent: f.intent,
          plan: good.plan.copyWith(snapshotRef: f.snapshot.ref)),
      replace(good, intent: intentWith(good.intent, ref: f.snapshot.ref)),
      replace(good, intent: intentWith(good.intent, id: 'other')),
      replace(good, plan: good.plan.copyWith(intentRef: 'other')),
      replace(good, plan: good.plan.copyWith(nodes: [good.plan.nodes.first])),
      replace(good, snapshot: good.snapshot.copyWith(computations: {
        'total': const ComputedValue(
          value: 120,
          inputVersion: SnapshotRef('comparison', 4),
          computationId: 'fixture-total',
        ),
      })),
    ];
    for (final candidate in candidates) {
      final c = UiPublicationCoordinator(initial);
      expect(c.publish(candidate, () => token()), UiPublishOutcome.invalid);
      expect(c.current, same(initial));
      expect(c.publicationErrors, isNotEmpty);
      expect(c.outdated, isTrue);
      expect(() => c.publicationErrors.clear(), throwsUnsupportedError);
    }
  });

  test('candidate intent cannot expand allowed actions', () {
    final f = ContractFixture();
    final initial = f.validate(f.plan).validatedPlan!;
    final c = UiPublicationCoordinator(initial);
    final good = nextBatch(f);
    final expanded = replace(good, intent: intentWith(
      good.intent,
      allowed: {...good.intent.allowedActionRefs, 'extra'},
    ));
    expect(c.publish(expanded, () => token()), UiPublishOutcome.invalid);
    expect(c.publicationErrors, contains('publish_permission_expansion'));
    expect(c.current, same(initial));
    expect(c.publish(good, () => token()), UiPublishOutcome.published);
    expect(c.publicationErrors, isEmpty);
    expect(c.outdated, isFalse);
  });

  test('published draft floor never falls when candidate context is older', () {
    final f = ContractFixture();
    final c = UiPublicationCoordinator(f.validate(f.plan).validatedPlan!);
    final good = nextBatch(f);
    final olderContext = DataSnapshot(
      ref: good.snapshot.ref,
      facts: good.snapshot.facts,
      initialUiState: good.snapshot.initialUiState,
      computations: good.snapshot.computations,
      sources: good.snapshot.sources,
      sourceDigests: good.snapshot.sourceDigests,
      actionContext: UiActionContext(draftRevision: 1),
    );
    expect(c.publish(replace(good, snapshot: olderContext), () => token()),
        UiPublishOutcome.published);
    expect(c.publishedDraftRevision, 15);
    expect(c.current.snapshot.initialUiState, f.snapshot.initialUiState);
  });

  test('recomputing gate blocks business while allowing parameter edits', () async {
    final f = ContractFixture();
    final c = UiPublicationCoordinator(f.validate(f.plan).validatedPlan!);
    final complete = Completer<UiVersionBatch>();
    final work = c.recompute(() => complete.future, () => token());
    addTearDown(() async {
      if (!complete.isCompleted) complete.complete(nextBatch(f));
      await work;
    });
    expect(c.recomputing, isTrue);
    const business = UiActionDefinition(route: UiActionRoute.business);
    const edit = UiActionDefinition(
      route: UiActionRoute.local, localAction: UiLocalAction.editField);
    const cancel = UiActionDefinition(
      route: UiActionRoute.local, localAction: UiLocalAction.cancelConfirmation);
    const semantic = UiActionDefinition(route: UiActionRoute.semantic);
    expect(c.allowsDispatch(business, readOnly: false, pending: false), isFalse);
    expect(c.allowsDispatch(edit, readOnly: false, pending: false), isTrue);
    expect(c.allowsDispatch(cancel, readOnly: false, pending: true), isFalse);
    expect(c.allowsDispatch(cancel, readOnly: false, pending: false), isTrue);
    for (final action in [business, edit, cancel, semantic]) {
      expect(c.allowsDispatch(action, readOnly: true, pending: false), isFalse);
    }
    complete.complete(nextBatch(f));
    expect(await work, UiPublishOutcome.published);
    expect(c.recomputing, isFalse);
    expect(c.allowsDispatch(business, readOnly: false, pending: true), isFalse);
    expect(c.allowsDispatch(business, readOnly: false, pending: false), isTrue);
  });

  test('cancel fences late completion and leaves bundle untouched', () async {
    final f = ContractFixture();
    final initial = f.validate(f.plan).validatedPlan!;
    final c = UiPublicationCoordinator(initial);
    final complete = Completer<UiVersionBatch>();
    final work = c.recompute(() => complete.future, () => token());
    c.cancelRecompute();
    complete.complete(nextBatch(f));
    expect(await work, UiPublishOutcome.staleToken);
    expect(c.current, same(initial));
    expect(c.recomputing, isFalse);
    expect(c.outdated, isTrue);
    expect(c.publicationErrors, ['recompute_cancelled']);
    expect(await c.recompute(() async => nextBatch(f), () => token()),
        UiPublishOutcome.published);
    expect(c.outdated, isFalse);
  });

  test('latest request wins and old completion cannot reset its state', () async {
    final f = ContractFixture();
    final c = UiPublicationCoordinator(f.validate(f.plan).validatedPlan!);
    final first = Completer<UiVersionBatch>();
    final latest = Completer<UiVersionBatch>();
    final oldWork = c.recompute(() => first.future, () => token());
    final newWork = c.recompute(() => latest.future, () => token());
    first.complete(nextBatch(f));
    expect(await oldWork, UiPublishOutcome.staleToken);
    expect(c.recomputing, isTrue);
    latest.complete(nextBatch(f));
    expect(await newWork, UiPublishOutcome.published);
    expect(c.current.plan.revision, 5);
    expect(c.recomputing, isFalse);
    expect(c.outdated, isFalse);
  });

  test('cancellation inside final probe prevents reentrant publication', () async {
    final f = ContractFixture();
    final initial = f.validate(f.plan).validatedPlan!;
    final c = UiPublicationCoordinator(initial);
    var reads = 0;
    final outcome = await c.recompute(() async => nextBatch(f), () {
      if (++reads == 2) c.cancelRecompute();
      return token();
    });
    expect(outcome, UiPublishOutcome.staleToken);
    expect(c.current, same(initial));
    expect(c.publicationErrors, ['recompute_cancelled']);
    expect(c.recomputing, isFalse);
  });

  test('obsolete failure cannot degrade the latest successful publication', () async {
    final f = ContractFixture();
    final c = UiPublicationCoordinator(f.validate(f.plan).validatedPlan!);
    final first = Completer<UiVersionBatch>();
    final obsolete = c.recompute(() => first.future, () => token());
    expect(await c.recompute(() async => nextBatch(f), () => token()),
        UiPublishOutcome.published);
    final published = c.current;
    first.completeError(StateError('obsolete host failure'));
    expect(await obsolete, UiPublishOutcome.staleToken);
    expect(c.current, same(published));
    expect(c.outdated, isFalse);
    expect(c.publicationErrors, isEmpty);
  });

  test('prepare failures degrade without replacing data or exposing errors', () async {
    final f = ContractFixture();
    final initial = f.validate(f.plan).validatedPlan!;
    for (final prepare in <Future<UiVersionBatch> Function()>[
      () => throw StateError('private host details'),
      () async => throw StateError('private host details'),
    ]) {
      final c = UiPublicationCoordinator(initial);
      expect(await c.recompute(prepare, () => token()), UiPublishOutcome.invalid);
      expect(c.current, same(initial));
      expect(c.recomputing, isFalse);
      expect(c.outdated, isTrue);
      expect(c.publicationErrors, ['recompute_failed']);
      expect(c.allowsDispatch(f.catalog.actions['edit']!, readOnly: false,
          pending: false), isFalse);
    }
  });

  test('disposed receiver never starts preparation or publishes late work', () async {
    final f = ContractFixture();
    final initial = f.validate(f.plan).validatedPlan!;
    final c = UiPublicationCoordinator(initial);
    final complete = Completer<UiVersionBatch>();
    final work = c.recompute(() => complete.future, () => token());
    c.dispose();
    complete.complete(nextBatch(f));
    expect(await work, UiPublishOutcome.disposed);
    expect(c.current, same(initial));
    var starts = 0;
    expect(await c.recompute(() async {
      starts++;
      return nextBatch(f);
    }, () => token()), UiPublishOutcome.disposed);
    expect(starts, 0);
    expect(c.recomputing, isFalse);
  });

  test('direct publication supersedes an older async candidate', () async {
    final f = ContractFixture();
    final c = UiPublicationCoordinator(f.validate(f.plan).validatedPlan!);
    final complete = Completer<UiVersionBatch>();
    final work = c.recompute(() => complete.future, () => token());
    final candidate = nextBatch(f);
    expect(c.publish(candidate, () => token()), UiPublishOutcome.published);
    final published = c.current;
    complete.complete(candidate);
    expect(await work, UiPublishOutcome.staleToken);
    expect(c.current, same(published));
  });

  test('probe failures never install a candidate', () {
    final f = ContractFixture();
    final initial = f.validate(f.plan).validatedPlan!;
    for (final failingRead in [1, 2]) {
      final c = UiPublicationCoordinator(initial);
      var reads = 0;
      expect(c.publish(nextBatch(f), () {
        if (++reads == failingRead) throw StateError('host unavailable');
        return token();
      }), UiPublishOutcome.invalid);
      expect(c.current, same(initial));
      expect(c.publicationErrors, ['publish_probe_failed']);
    }
  });
}
