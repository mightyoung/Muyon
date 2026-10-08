import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

/// Public, invented fixtures, not reviewed gold data or real model output.
class PreviewFixture {
  const PreviewFixture({
    required this.snapshot,
    required this.intent,
    required this.plan,
    required this.answer,
  });
  final DataSnapshot snapshot;
  final InteractionIntent intent;
  final UiPlanningResult plan;
  final String answer;
}

PreviewFixture comparisonFixture({
  bool invalid = false,
  bool alternative = false,
}) {
  final source = alternative
      ? 'Public source B: 10 pieces; unit price 12. Conflicting delivery estimates 3 and 5 days.'
      : 'Public source A: 10 pieces; unit price 12.';
  final snapshot = DataSnapshot(
    ref: const SnapshotRef('public', 1),
    facts: {
      'qty': SnapshotFact(
        object: ObjectRef(
          moduleId: 'public-fixture',
          objectType: 'quote',
          objectId: alternative ? 'b' : 'a',
          revisionRef: '1',
        ),
        field: 'quantity',
        value: 10,
        unit: 'pieces',
        state: FactState.verified,
        sourceRefs: ['original'],
      ),
      if (alternative)
        'delivery': SnapshotFact(
          object: const ObjectRef(
            moduleId: 'public-fixture',
            objectType: 'quote',
            objectId: 'b',
            revisionRef: '1',
          ),
          field: 'delivery',
          value: '3 or 5',
          unit: 'days',
          state: FactState.conflict,
          sourceRefs: ['original'],
        ),
    },
    initialUiState: {'quantity': '10'},
    computations: {
      'total': const ComputedValue(
        value: 120,
        inputVersion: SnapshotRef('public', 1),
        computationId: 'public-fixture-total',
      ),
    },
    sources: {
      'original': SourceSpanRef(
        artifact: const ArtifactRef(
          moduleId: 'public-fixture',
          artifactId: 'public-document',
          contentDigest: 'public-v1',
        ),
        originalText: source,
        start: 0,
        end: source.length,
        paragraph: 1,
      ),
    },
    sourceDigests: {'public-document': 'public-v1'},
  );
  final intent = InteractionIntent(
    id: 'compare',
    purpose: 'Compare invented public quotes',
    snapshotRef: snapshot.ref,
    requiredBindings: {
      const BindingRef.fact('qty'),
      if (alternative) const BindingRef.fact('delivery'),
      const BindingRef.computed('total'),
      const BindingRef.sourceSpan('original'),
    },
    mandatoryStates: {FactState.conflict},
    allowedActionRefs: {'edit', 'source', 'detail', 'back'},
  );
  final plan = UIPlan(
    surfaceId: 'comparison',
    revision: 1,
    catalogVersion: minimalUiCatalog.version,
    snapshotRef: snapshot.ref,
    intentRef: intent.id,
    root: 'root',
    nodes: [
      UiNode(
        id: 'root',
        component: 'PageScaffold',
        properties: {'title': 'Quote comparison'},
        children: [
          'quantity',
          'total',
          'source-a',
          'quote-a',
          if (alternative) 'delivery',
        ],
      ),
      UiNode(
        id: 'quantity',
        component: 'Field',
        properties: {'label': 'Fact quantity'},
        bindings: {
          'value': BindingRef.fact(invalid ? 'missing' : 'qty'),
          'draft': const BindingRef.uiState('quantity'),
        },
        events: {
          'change': ActionBinding(actionRef: 'edit', inputRefs: ['quantity']),
        },
      ),
      UiNode(
        id: 'total',
        component: 'Table',
        properties: {'label': 'Fixture total'},
        bindings: {'value': const BindingRef.computed('total')},
      ),
      UiNode(
        id: 'source-a',
        component: 'SourceList',
        bindings: {'source': const BindingRef.sourceSpan('original')},
        events: {'tap': ActionBinding(actionRef: 'source')},
      ),
      if (alternative)
        UiNode(
          id: 'delivery',
          component: 'ObjectChip',
          properties: {'label': 'Delivery estimate: 3 or 5 days'},
          bindings: {'value': const BindingRef.fact('delivery')},
        ),
      UiNode(
        id: 'quote-a',
        component: 'ObjectChip',
        properties: {'label': alternative ? 'Quote B' : 'Quote A'},
        bindings: {'value': const BindingRef.fact('qty')},
        events: {
          'tap': ActionBinding(actionRef: 'detail'),
          'back': ActionBinding(actionRef: 'back'),
        },
      ),
    ],
  );
  return PreviewFixture(
    snapshot: snapshot,
    intent: intent,
    plan: UiPlanningResult(
      decision: UiDisplayDecision.supplement,
      reasonCode: 'public-comparison',
      plan: plan,
    ),
    answer: 'Public comparison: 10 pieces at 12 per piece.',
  );
}
