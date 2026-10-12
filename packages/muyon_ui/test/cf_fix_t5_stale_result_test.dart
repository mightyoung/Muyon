import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

// CF-FIX-T5 (RED first): a computed value from the last publication is shown
// as an old result while a recompute is pending or after it fails, and as
// current again only after a successful publication. Freshness is a second
// axis beside FactState, so notDisclosed and other states keep their display.

const _ref = SnapshotRef('s', 1);
const _object = ObjectRef(moduleId: 'm', objectType: 't', objectId: 'a');

DataSnapshot _snapshot({required String value, SnapshotRef ref = _ref}) =>
    DataSnapshot(
      ref: ref,
      facts: {
        'price': SnapshotFact(
          object: _object,
          field: 'price',
          value: null,
          state: FactState.notDisclosed,
          unit: 'CNY/件',
        ),
      },
      computations: {
        'total': ComputedValue(
          value: value,
          inputVersion: _ref,
          computationId: 'review-total',
        ),
      },
      computedEvidence: {
        'total': UiComputedEvidence(
          state: FactState.verified,
          unit: 'CNY',
          sourceRefs: [],
        ),
      },
    );

InteractionIntent _intent(SnapshotRef ref) => InteractionIntent(
  id: 'i',
  purpose: 'review',
  snapshotRef: ref,
  mandatoryStates: const {FactState.notDisclosed},
  allowedActionRefs: library2UiCatalog.actions.keys.toSet(),
);

ValidatedUiPlan _validated() {
  final plan = UIPlan(
    surfaceId: 's',
    revision: 1,
    catalogVersion: 'library-2',
    snapshotRef: _ref,
    intentRef: 'i',
    root: 'root',
    nodes: [
      UiNode(
        id: 'root',
        component: 'PageScaffold',
        properties: {'title': 'review'},
        children: ['metric', 'kv'],
      ),
      UiNode(
        id: 'metric',
        component: 'Metric',
        properties: {'label': 'Total'},
        bindings: {'value': const BindingRef.computed('total')},
      ),
      UiNode(
        id: 'kv',
        component: 'KeyValue',
        bindings: {'value': const BindingRef.fact('price')},
      ),
    ],
  );
  return validateUiPlan(
    plan,
    _snapshot(value: '88'),
    _intent(_ref),
    library2UiCatalog,
  ).validatedPlan!;
}

class _UnavailablePort implements UiRecomputePort {
  @override
  Future<UiRecomputeResult> rebuild(UiRecomputeInput input) async =>
      throw StateError('host unavailable');
}

class _DeferredPort implements UiRecomputePort {
  final _inputs = <UiRecomputeInput>[];
  final _pending = <Completer<UiRecomputeResult>>[];
  @override
  Future<UiRecomputeResult> rebuild(UiRecomputeInput input) {
    _inputs.add(input);
    final result = Completer<UiRecomputeResult>();
    _pending.add(result);
    return result.future;
  }

  /// Completes the single pending request with a candidate showing [value].
  void complete(String value) {
    final input = _inputs.single;
    final ref = SnapshotRef(
      input.previousSnapshot.ref.id,
      input.previousSnapshot.ref.revision + 1,
    );
    _pending.single.complete(
      UiRecomputeResult(
        token: input.token,
        nextSnapshot: _snapshot(value: value, ref: ref),
        nextIntent: _intent(ref),
      ),
    );
  }
}

UiPublishToken Function() _probeFor(UiSurfaceController Function() of) =>
    () => UiPublishToken(
      baseSnapshotRef: of().current.snapshot.ref,
      draftRevision: 1,
      hostGeneration: 1,
      sourceGeneration: 1,
      permissionGeneration: 1,
      scopeKey: 'review',
    );

Future<void> _mount(WidgetTester tester, UiSurfaceController c) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DynamicUiSurface(plan: c.current, controller: c),
        ),
      ),
    );

void main() {
  testWidgets(
    'an outdated surface labels its previous values as an old result',
    (tester) async {
      final validated = _validated();
      late UiSurfaceController controller;
      controller = UiSurfaceController(
        validated,
        recomputePort: _UnavailablePort(),
        publishTokenProbe: _probeFor(() => controller),
      );
      expect(await controller.recompute(), UiPublishOutcome.invalid);
      expect(controller.outdated, isTrue);

      await _mount(tester, controller);
      await tester.pumpAndSettle();
      expect(find.textContaining('88'), findsWidgets);
      expect(find.textContaining('旧结果'), findsWidgets);
    },
  );

  testWidgets('the old-result label reaches semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    final validated = _validated();
    late UiSurfaceController controller;
    controller = UiSurfaceController(
      validated,
      recomputePort: _UnavailablePort(),
      publishTokenProbe: _probeFor(() => controller),
    );
    await controller.recompute();

    await _mount(tester, controller);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('旧结果.*88|88.*旧结果')), findsWidgets);
    semantics.dispose();
  });

  testWidgets(
    'a pending recompute shows the old result, and publication restores current',
    (tester) async {
      final validated = _validated();
      final port = _DeferredPort();
      late UiSurfaceController controller;
      controller = UiSurfaceController(
        validated,
        recomputePort: port,
        publishTokenProbe: _probeFor(() => controller),
      );
      await _mount(tester, controller);
      final running = controller.recompute();
      await tester.pumpAndSettle();
      expect(find.textContaining('旧结果'), findsWidgets);

      port.complete('180');
      expect(await running, UiPublishOutcome.published);
      await tester.pumpAndSettle();
      expect(find.textContaining('180'), findsWidgets);
      expect(find.textContaining('旧结果'), findsNothing);
    },
  );
}
