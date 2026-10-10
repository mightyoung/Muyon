import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';

final catalog = UiCatalog(
  version: 'library-2',
  components: {
    'Page': UiComponentSchema(allowsChildren: true),
    'Field': UiComponentSchema(
      bindings: {
        'value': {BindingKind.fact},
        'draft': {BindingKind.uiState},
      },
      events: {'change': UiValueType.string},
      eventActions: {
        'change': {'edit'},
      },
    ),
    'Text': UiComponentSchema(
      bindings: {
        'value': {BindingKind.computed},
      },
    ),
  },
  actions: {
    'edit': const UiActionDefinition(
      route: UiActionRoute.local,
      localAction: UiLocalAction.editField,
    ),
  },
);

ValidatedUiPlan bundle(int revision, {bool number = false, bool rowsB = true}) {
  final ref = SnapshotRef('s', revision);
  final snapshot = DataSnapshot(
    ref: ref,
    facts: {
      'qty': SnapshotFact(
        object: const ObjectRef(
          moduleId: 'm',
          objectType: 'item',
          objectId: 'a',
        ),
        field: 'qty',
        value: '2',
        state: FactState.verified,
      ),
    },
    initialUiState: {'qty': number ? 2 : '2', 'sort': 'original'},
    editSpecs: {
      'qty': number
          ? const UiNumberEdit(min: 0, max: 10)
          : const UiStringEdit(),
      'sort': const UiStringEdit(view: true),
      'selected': UiItemIdsEdit(collectionId: 'options', initial: ['a']),
    },
    collections: {
      'options': UiCollection(
        id: 'options',
        columns: const [UiColumn('label', 'Label')],
        rows: [
          for (final id in ['a', if (rowsB) 'b'])
            UiRow(itemId: id, cells: const {'label': BindingRef.fact('qty')}),
        ],
      ),
    },
    computations: {
      'total': ComputedValue(
        value: revision == 1 ? '20' : '30',
        inputVersion: ref,
        computationId: 'total',
      ),
    },
    computedEvidence: {
      'total': UiComputedEvidence(state: FactState.verified, unit: 'CNY'),
    },
    actionContext: UiActionContext(draftRevision: 0),
  );
  final intent = InteractionIntent(
    id: 'i',
    purpose: 'rebase',
    snapshotRef: ref,
    allowedActionRefs: {'edit'},
  );
  final plan = UIPlan(
    surfaceId: 's',
    revision: revision,
    catalogVersion: 'library-2',
    snapshotRef: ref,
    intentRef: 'i',
    root: 'root',
    nodes: [
      UiNode(id: 'root', component: 'Page', children: ['qty', 'total']),
      UiNode(
        id: 'qty',
        component: 'Field',
        bindings: {
          'value': const BindingRef.fact('qty'),
          'draft': const BindingRef.uiState('qty'),
        },
        events: number
            ? {}
            : {
                'change': ActionBinding(actionRef: 'edit', inputRefs: ['qty']),
              },
      ),
      UiNode(
        id: 'total',
        component: 'Text',
        bindings: {'value': const BindingRef.computed('total')},
      ),
    ],
  );
  final checked = validateUiPlan(plan, snapshot, intent, catalog);
  expect(checked.isValid, isTrue, reason: checked.errors.join(','));
  return checked.validatedPlan!;
}

void main() {
  test('prepared rebase preserves same session extracted override view and selections', () {
    final old = bundle(1), next = bundle(2);
    final session = UiSessionState(old.snapshot)
      ..accept(old)
      ..edit('qty', '3')
      ..edit('selected', ['b'])
      ..selectView('sort', 'value');
    final draft = session.draftRevision;
    final prepared = session.prepareRebase(next);
    expect(session.snapshot, same(old.snapshot));
    expect(session.resolve(const BindingRef.computed('total')), '20');
    expect(session.commitPreparedRebase(prepared), isTrue);
    expect(session.snapshot, same(next.snapshot));
    expect(session.currentPlan, same(next));
    expect(session.snapshot.initialUiState['qty'], '2');
    expect(session.resolve(const BindingRef.uiState('qty')), '3');
    expect(session.userOverrides['qty'], '3');
    expect(session.viewValues['sort'], 'value');
    expect(session.selections['selected'], ['b']);
    expect(session.selectionOverrides, contains('selected'));
    expect(session.draftRevision, draft);
    expect(session.resolve(const BindingRef.computed('total')), '30');
    session.adoptExtracted('qty');
    expect(session.resolve(const BindingRef.uiState('qty')), '2');
    expect(session.userOverrides, isNot(contains('qty')));
    expect(session.draftRevision, draft + 1);
  });

  test('prepared state cannot install in a foreign session', () {
    final old = bundle(1), next = bundle(2);
    final first = UiSessionState(old.snapshot)..accept(old);
    final other = UiSessionState(old.snapshot)..accept(old);
    final prepared = first.prepareRebase(next);
    expect(other.commitPreparedRebase(prepared), isFalse);
    expect(first.commitPreparedRebase(prepared), isTrue);
    expect(other.snapshot, same(old.snapshot));
  });
}
