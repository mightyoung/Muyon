import 'package:muyon_module_api/ui_contract.dart';

class ContractFixture {
  final snapshot = DataSnapshot(
    ref: const SnapshotRef('comparison', 4),
    facts: {
      'qty': SnapshotFact(
        object: ObjectRef(
          moduleId: 'fixture',
          objectType: 'quote',
          objectId: 'a',
          revisionRef: 'r4',
        ),
        field: 'quantity',
        value: 10,
        state: FactState.conflict,
        unit: 'pieces',
        sourceRefs: ['quote'],
      ),
    },
    initialUiState: {'quantity': '10'},
    computations: {
      'total': const ComputedValue(
        value: 120,
        inputVersion: SnapshotRef('comparison', 4),
        computationId: 'fixture-total',
      ),
    },
    sources: {
      'quote': const SourceSpanRef(
        artifact: ArtifactRef(
          moduleId: 'fixture',
          artifactId: 'document',
          contentDigest: 'public-v1',
        ),
        originalText: 'Public fixture: quantity 10, unit price 12.',
        start: 0,
        end: 43,
        paragraph: 1,
      ),
    },
    sourceDigests: {'document': 'public-v1'},
    actionContext: UiActionContext(
      draftRevision: 15,
      draft: {'quantity': '10'},
      confirmedRecordRefs: {'record-a'},
      operations: {
        'host-operation-1': HostOperationRef(
          draftRevision: 15,
          inputRefs: {'quantity', 'record-a'},
        ),
      },
    ),
  );
  final intent = InteractionIntent(
    id: 'compare',
    purpose: 'compare public quotes',
    snapshotRef: const SnapshotRef('comparison', 4),
    requiredBindings: {
      const BindingRef.fact('qty'),
      const BindingRef.sourceSpan('quote'),
      const BindingRef.computed('total'),
    },
    mandatoryStates: {FactState.conflict},
    allowedActionRefs: {'edit', 'commit'},
  );
  final catalog = UiCatalog(
    version: 'minimal-1',
    components: {
      'PageScaffold': UiComponentSchema(
        properties: {'title': UiValueType.string},
        requiredProperties: {'title'},
        allowsChildren: true,
      ),
      'Field': UiComponentSchema(
        bindings: {
          'value': {BindingKind.fact},
          'draft': {BindingKind.uiState},
          'source': {BindingKind.sourceSpan},
          'total': {BindingKind.computed},
        },
        requiredBindings: {'value', 'draft', 'source', 'total'},
        events: {'change': UiValueType.string, 'tap': null},
        eventActions: {
          'change': {'edit'},
          'tap': {'commit'},
        },
      ),
      'Text': UiComponentSchema(),
    },
    actions: {
      'edit': const UiActionDefinition(
        route: UiActionRoute.local,
        localAction: UiLocalAction.editField,
      ),
      'commit': const UiActionDefinition(route: UiActionRoute.business),
    },
  );
  final plan = UIPlan(
    surfaceId: 'comparison',
    revision: 4,
    catalogVersion: 'minimal-1',
    snapshotRef: const SnapshotRef('comparison', 4),
    intentRef: 'compare',
    root: 'root',
    nodes: [
      UiNode(
        id: 'root',
        component: 'PageScaffold',
        properties: {'title': 'Comparison'},
        children: ['qty'],
      ),
      UiNode(
        id: 'qty',
        component: 'Field',
        bindings: {
          'value': BindingRef.fact('qty'),
          'draft': BindingRef.uiState('quantity'),
          'source': BindingRef.sourceSpan('quote'),
          'total': BindingRef.computed('total'),
        },
        events: {
          'change': ActionBinding(actionRef: 'edit', inputRefs: ['quantity']),
        },
      ),
    ],
  );
  UIPlan withNode({
    Map<String, BindingRef>? bindings,
    Map<String, ActionBinding>? events,
  }) => plan.copyWith(
    nodes: [
      plan.nodes.first,
      plan.nodes.last.copyWith(bindings: bindings, events: events),
    ],
  );
  UiValidationResult validate(UIPlan candidate) =>
      validateUiPlan(candidate, snapshot, intent, catalog);
}
