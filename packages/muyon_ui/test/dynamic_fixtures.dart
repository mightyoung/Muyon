import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

DataSnapshot publicSnapshot() => DataSnapshot(
  ref: const SnapshotRef('public', 1),
  facts: {
    'qty': SnapshotFact(
      object: const ObjectRef(
        moduleId: 'public',
        objectType: 'quote',
        objectId: 'a',
      ),
      field: 'quantity',
      value: 10,
      state: FactState.verified,
    ),
    'noise': SnapshotFact(
      object: const ObjectRef(
        moduleId: 'public',
        objectType: 'quote',
        objectId: 'a',
      ),
      field: 'noise',
      value: null,
      state: FactState.notDisclosed,
    ),
  },
  initialUiState: {'quantity': '12', 'sort': 'original'},
  computations: {
    'total': const ComputedValue(
      value: 120,
      inputVersion: SnapshotRef('public', 1),
      computationId: 'public-total',
    ),
  },
  sources: {
    'source': const SourceSpanRef(
      artifact: ArtifactRef(
        moduleId: 'public',
        artifactId: 'text',
        contentDigest: 'v1',
      ),
      originalText: 'Public original: 10 pieces.',
      start: 0,
      end: 27,
    ),
  },
  sourceDigests: {'text': 'v1'},
  actionContext: UiActionContext(
    draftRevision: 0,
    draft: {'quantity': '12'},
    operations: {
      'public-qty': HostOperationRef(draftRevision: 0, inputRefs: {'quantity'}),
    },
  ),
);
InteractionIntent publicIntent(DataSnapshot s) => InteractionIntent(
  id: 'compare',
  purpose: 'Compare public fixture',
  snapshotRef: s.ref,
  requiredBindings: {
    const BindingRef.fact('qty'),
    const BindingRef.fact('noise'),
    const BindingRef.sourceSpan('source'),
  },
  mandatoryStates: {FactState.notDisclosed},
  allowedActionRefs: {
    'edit',
    'source',
    'detail',
    'back',
    'sort',
    'confirm',
    'cancel',
    'explain',
  },
);
UIPlan publicPlan(DataSnapshot s) => UIPlan(
  surfaceId: 'comparison',
  revision: 4,
  catalogVersion: minimalUiCatalog.version,
  snapshotRef: s.ref,
  intentRef: 'compare',
  root: 'root',
  nodes: [
    UiNode(
      id: 'root',
      component: 'PageScaffold',
      properties: {'title': 'Public comparison'},
      children: ['quantity', 'noise', 'source', 'detail'],
    ),
    UiNode(
      id: 'quantity',
      component: 'Field',
      properties: {'label': 'Quantity'},
      bindings: {
        'value': const BindingRef.fact('qty'),
        'draft': const BindingRef.uiState('quantity'),
      },
      events: {
        'change': ActionBinding(actionRef: 'edit', inputRefs: ['quantity']),
      },
    ),
    UiNode(
      id: 'noise',
      component: 'ObjectChip',
      properties: {'label': 'Noise'},
      bindings: {'value': const BindingRef.fact('noise')},
    ),
    UiNode(
      id: 'source',
      component: 'SourceList',
      bindings: {'source': const BindingRef.sourceSpan('source')},
      events: {'tap': ActionBinding(actionRef: 'source')},
    ),
    UiNode(
      id: 'detail',
      component: 'ObjectChip',
      properties: {'label': 'Quote A'},
      bindings: {'value': const BindingRef.fact('qty')},
      events: {
        'tap': ActionBinding(actionRef: 'detail'),
        'back': ActionBinding(actionRef: 'back'),
      },
    ),
  ],
);

ValidatedUiPlan actionPlan() {
  final s = publicSnapshot(), p = publicPlan(publicSnapshot());
  return validateUiPlan(
    p.copyWith(
      catalogVersion: dynamicUiCatalog.version,
      nodes: [
        p.nodes.first.copyWith(
          children: [...p.nodes.first.children, 'confirm', 'warning'],
        ),
        ...p.nodes.skip(1),
        UiNode(
          id: 'confirm',
          component: 'ConfirmCard',
          properties: {'label': 'Public quantity update'},
          bindings: {'value': const BindingRef.fact('qty')},
          events: {
            'confirm': ActionBinding(
              actionRef: 'confirm',
              inputRefs: ['quantity'],
              expectedDraftRevision: 0,
              operationKeyRef: 'public-qty',
            ),
            'cancel': ActionBinding(actionRef: 'cancel'),
          },
        ),
        UiNode(
          id: 'warning',
          component: 'WarnBanner',
          bindings: {'value': const BindingRef.fact('noise')},
          events: {'tap': ActionBinding(actionRef: 'explain')},
        ),
      ],
    ),
    s,
    publicIntent(s),
    dynamicUiCatalog,
  ).validatedPlan!;
}

UiEvent event(
  String id,
  String node,
  String kind, {
  Object? payload,
  int revision = 4,
}) => UiEvent(
  eventId: id,
  surfaceId: 'comparison',
  nodeId: node,
  observedRevision: revision,
  kind: kind,
  payload: payload,
);
