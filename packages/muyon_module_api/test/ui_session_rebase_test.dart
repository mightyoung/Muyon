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

ValidatedUiPlan bundle(
  int revision, {
  bool number = false,
  bool rowsB = true,
  UiStringEdit? stringSpec,
  bool draftSort = false,
  String collectionId = 'options',
}) {
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
          : stringSpec ?? const UiStringEdit(),
      'sort': const UiStringEdit(view: true),
      'selected': UiItemIdsEdit(collectionId: collectionId, initial: ['a']),
    },
    collections: {
      collectionId: UiCollection(
        id: collectionId,
        columns: const [UiColumn('label', 'Label')],
        rows: [
          for (final id in ['a', if (rowsB) 'b'])
            UiRow(itemId: id, cells: const {'label': BindingRef.fact('qty')}),
        ],
      ),
    },
    sources: {
      'source': const SourceSpanRef(
        artifact: ArtifactRef(
          moduleId: 'm',
          artifactId: 'a',
          contentDigest: 'v1',
        ),
        originalText: 'text',
        start: 0,
        end: 4,
      ),
    },
    sourceDigests: {'a': 'v1'},
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
    actionContext: UiActionContext(
      draftRevision: 0,
      draft: draftSort ? {'sort': 'original'} : {},
    ),
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
  test(
    'session view and source mutations fence the publisher final comparison',
    () {
      for (final source in [false, true]) {
        final old = bundle(1), next = bundle(2);
        final session = UiSessionState(old.snapshot)
          ..accept(old)
          ..edit('qty', '3');
        final prepared = session.prepareRebase(next);
        final c = UiPublicationCoordinator(old);
        final token = UiPublishToken(
          baseSnapshotRef: old.snapshot.ref,
          draftRevision: session.draftRevision,
          hostGeneration: 1,
          sourceGeneration: 1,
          permissionGeneration: 1,
          scopeKey: 'test',
        );
        final fence = session.publicationFence;
        var reads = 0;
        final result = c.publish(
          UiVersionBatch(
            token: token,
            snapshot: next.snapshot,
            intent: next.intent,
            plan: next.plan,
          ),
          () {
            if (++reads == 2) {
              if (source) {
                session.updateSourceDigest('a', 'changed');
              } else {
                session.selectView('sort', 'value');
              }
            }
            return token;
          },
          fence: fence,
        );
        expect(result, UiPublishOutcome.staleToken);
        expect(c.current, same(old));
        expect(session.snapshot, same(old.snapshot));
        expect(session.canCommitPreparedRebase(prepared), isFalse);
      }
    },
  );

  test(
    'a legal edit repairs retained unreadable draft through the event gate',
    () {
      final old = bundle(1);
      final next = bundle(
        2,
        stringSpec: UiStringEdit(
          accepts: (value) => value == '2' || value == '4',
        ),
      );
      final session = UiSessionState(old.snapshot)
        ..accept(old)
        ..edit('qty', '3');
      expect(session.commitPreparedRebase(session.prepareRebase(next)), isTrue);
      expect(session.readableDraft['qty'], '3');
      expect(session.unreadableReasons['qty'], 'format');
      final revision = session.draftRevision;
      for (final invalid in ['3', 4]) {
        expect(
          session.dispatch(
            UiEvent(
              eventId: 'invalid-$invalid',
              surfaceId: 's',
              nodeId: 'qty',
              observedRevision: 2,
              kind: 'change',
              payload: invalid,
            ),
            next,
            catalog,
          ),
          UiEventOutcome.invalid,
        );
        expect(session.readableDraft['qty'], '3');
        expect(session.draftRevision, revision);
      }
      final result = session.dispatch(
        UiEvent(
          eventId: 'repair',
          surfaceId: 's',
          nodeId: 'qty',
          observedRevision: 2,
          kind: 'change',
          payload: '4',
        ),
        next,
        catalog,
      );
      expect(result, UiEventOutcome.applied);
      expect(session.resolve(const BindingRef.uiState('qty')), '4');
      expect(session.userOverrides['qty'], '4');
      expect(session.readableDraft, isEmpty);
      expect(session.unreadableReasons, isEmpty);
      expect(session.draftRevision, revision + 1);
    },
  );

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

  test(
    'invalid override and removed selected ID stay readable without applying',
    () {
      final old = bundle(1), next = bundle(2, number: true, rowsB: false);
      final session = UiSessionState(old.snapshot)
        ..accept(old)
        ..edit('qty', '3')
        ..edit('selected', ['b']);
      final draft = session.draftRevision;
      expect(session.commitPreparedRebase(session.prepareRebase(next)), isTrue);
      expect(session.userOverrides, isEmpty);
      expect(session.resolve(const BindingRef.uiState('qty')), 2);
      expect(session.selections['selected'], ['a']);
      expect(session.readableDraft['qty'], '3');
      expect(session.readableDraft['selected'], ['b']);
      expect(session.unreadableReasons, {
        'qty': 'type',
        'selected': 'unknown_item',
      });
      expect(session.draftRevision, draft);
      session.adoptExtracted('qty');
      expect(session.readableDraft.containsKey('qty'), isFalse);
      expect(session.draftRevision, draft + 1);
      expect(session.readableDraft['selected'], ['b']);
    },
  );

  test(
    'view edit and source digest updates fence previously prepared state',
    () {
      for (final source in [false, true]) {
        final old = bundle(1), next = bundle(2);
        final session = UiSessionState(old.snapshot)
          ..accept(old)
          ..edit('qty', '3');
        final prepared = session.prepareRebase(next);
        if (source) {
          session.updateSourceDigest('a', 'changed');
        } else {
          session.selectView('sort', 'value');
        }
        expect(session.commitPreparedRebase(prepared), isFalse);
        expect(session.snapshot, same(old.snapshot));
        expect(session.userOverrides['qty'], '3');
        if (!source) expect(session.viewValues['sort'], 'value');
      }
    },
  );

  test(
    'a host predicate failure during preparation cannot change old layers',
    () {
      final old = bundle(1);
      final next = bundle(
        2,
        stringSpec: UiStringEdit(
          accepts: (value) =>
              value == '2' ? true : throw StateError('host failure'),
        ),
      );
      final session = UiSessionState(old.snapshot)
        ..accept(old)
        ..edit('qty', '3');
      expect(() => session.prepareRebase(next), throwsStateError);
      expect(session.snapshot, same(old.snapshot));
      expect(session.userOverrides['qty'], '3');
      expect(session.readableDraft, isEmpty);
      expect(session.draftRevision, 1);
    },
  );

  test('install uses the actual publisher capability only for identical prepared references', () {
    final old = bundle(1), next = bundle(2);
    final session = UiSessionState(old.snapshot)..accept(old);
    final prepared = session.prepareRebase(next);
    expect(
      session.commitPreparedRebase(prepared, accepted: bundle(2)),
      isFalse,
    );
    expect(session.snapshot, same(old.snapshot));
    final accepted = validateUiPlan(
      next.plan,
      next.snapshot,
      next.intent,
      next.catalog,
    ).validatedPlan!;
    expect(accepted, isNot(same(next)));
    expect(session.commitPreparedRebase(prepared, accepted: accepted), isTrue);
    expect(session.currentPlan, same(accepted));
  });

  test('an unbound view key colliding with new business draft is retained only as unreadable', () {
    final old = bundle(1), next = bundle(2, draftSort: true);
    final session = UiSessionState(old.snapshot)
      ..accept(old)
      ..selectView('sort', 'value');
    expect(session.commitPreparedRebase(session.prepareRebase(next)), isTrue);
    expect(session.viewValues, isEmpty);
    expect(session.resolve(const BindingRef.uiState('sort')), 'original');
    expect(session.readableDraft['sort'], 'value');
    expect(session.unreadableReasons['sort'], 'view_business_input');
    expect(session.draftRevision, 0);
  });

  test('changing selection collection cannot silently rebind an existing chosen ID', () {
    final old = bundle(1), next = bundle(2, collectionId: 'other');
    final session = UiSessionState(old.snapshot)
      ..accept(old)
      ..edit('selected', ['b']);
    expect(session.commitPreparedRebase(session.prepareRebase(next)), isTrue);
    expect(session.selections['selected'], ['a']);
    expect(session.readableDraft['selected'], ['b']);
    expect(
      session.unreadableReasons['selected'],
      'selection_collection_changed',
    );
    expect(session.draftRevision, 1);
  });

  test('accepted fresh source metadata clears prior stale-read cache', () {
    final old = bundle(1), next = bundle(2);
    final session = UiSessionState(old.snapshot)
      ..accept(old)
      ..updateSourceDigest('a', 'changed');
    expect(session.resolve(const BindingRef.sourceSpan('source')), isNull);
    expect(session.staleSources, contains('source'));
    expect(session.commitPreparedRebase(session.prepareRebase(next)), isTrue);
    expect(session.staleSources, isEmpty);
    expect(session.resolve(const BindingRef.sourceSpan('source')), 'text');
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
