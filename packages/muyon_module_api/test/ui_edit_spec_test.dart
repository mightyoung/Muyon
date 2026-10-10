import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';

// F5b slice 1b (RED). Real validateUiPlan + UiSessionState.dispatch only; the
// spec classes are NOT-READY scaffolds, so every "accept" assertion fails today
// while the legacy gate rejects typed events. Reject assertions are paired with
// an accept in the same test so they cannot pass vacuously.

const _k = 'k';

final _rows = UiCollection(
  id: 'rows',
  columns: const [UiColumn('label', 'Label')],
  rows: [
    for (final id in ['a', 'b', 'c'])
      UiRow(itemId: id, cells: const {'label': BindingRef.fact('f')}),
  ],
);

class Obs {
  Obs(UiSessionState s)
    : rev = s.draftRevision,
      overrides = Map.of(s.userOverrides),
      view = Map.of(s.viewValues),
      value = s.resolve(const BindingRef.uiState(_k)),
      selections = Map.of(s.selections),
      viewSelections = Map.of(s.viewSelections),
      selectionOverrides = Set.of(s.selectionOverrides);
  final int rev;
  final Map<String, Object?> overrides, view;
  final Object? value;
  final Map<String, List<String>> selections, viewSelections;
  final Set<String> selectionOverrides;
}

class Rig {
  Rig(
    this.spec, {
    Object? initial,
    String version = 'library-2',
    bool register = true,
    Map<String, Object?> draft = const {},
    UiValueType? eventType,
  }) {
    final isIds = spec is UiItemIdsEdit;
    snapshot = DataSnapshot(
      ref: const SnapshotRef('s', 1),
      facts: {},
      initialUiState: isIds ? {} : {_k: initial},
      actionContext: UiActionContext(draftRevision: 5, draft: draft),
      editSpecs: register ? {_k: spec} : {},
      collections: {'rows': _rows},
    );
    catalog = UiCatalog(
      version: version,
      components: {
        'Page': UiComponentSchema(
          properties: {'title': UiValueType.string},
          allowsChildren: true,
        ),
        'Editor': UiComponentSchema(
          bindings: {
            'draft': {BindingKind.uiState},
          },
          requiredBindings: {'draft'},
          events: {'change': eventType ?? spec.payloadType},
          eventActions: {
            'change': {'edit'},
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
    intent = InteractionIntent(
      id: 'i',
      purpose: 'edit',
      snapshotRef: snapshot.ref,
      allowedActionRefs: {'edit'},
    );
    plan = UIPlan(
      surfaceId: 's',
      revision: 1,
      catalogVersion: version,
      snapshotRef: snapshot.ref,
      intentRef: 'i',
      root: 'root',
      nodes: [
        UiNode(
          id: 'root',
          component: 'Page',
          properties: {'title': 't'},
          children: ['ed'],
        ),
        UiNode(
          id: 'ed',
          component: 'Editor',
          bindings: {'draft': const BindingRef.uiState(_k)},
          events: {
            'change': ActionBinding(actionRef: 'edit', inputRefs: [_k]),
          },
        ),
      ],
    );
    result = validateUiPlan(plan, snapshot, intent, catalog);
    state = UiSessionState(snapshot);
    if (result.isValid) state.accept(result.validatedPlan!);
  }
  final UiEditSpec spec;
  late final DataSnapshot snapshot;
  late final UiCatalog catalog;
  late final InteractionIntent intent;
  late final UIPlan plan;
  late final UiValidationResult result;
  late final UiSessionState state;
  var _n = 0;

  UiEventOutcome send(Object? payload) => state.dispatch(
    UiEvent(
      eventId: 'e${_n++}',
      surfaceId: 's',
      nodeId: 'ed',
      observedRevision: 1,
      kind: 'change',
      payload: payload,
    ),
    result.validatedPlan!,
    catalog,
  );

  /// Valid plan is a precondition for every dispatch assertion.
  void expectPlanValid() =>
      expect(result.isValid, isTrue, reason: '${result.errors}');

  void accept(Object? payload, {bool bumps = true}) {
    final before = Obs(state);
    expect(send(payload), UiEventOutcome.applied, reason: '$payload');
    expect(state.draftRevision, before.rev + (bumps ? 1 : 0));
  }

  void rejectAll(List<Object?> payloads) {
    for (final p in payloads) {
      final before = Obs(state);
      expect(send(p), UiEventOutcome.invalid, reason: '$p');
      final after = Obs(state);
      expect(after.rev, before.rev, reason: '$p rev');
      expect(after.overrides, before.overrides, reason: '$p overrides');
      expect(after.view, before.view, reason: '$p view');
      expect(after.value, before.value, reason: '$p value');
      expect(after.selections, before.selections, reason: '$p selections');
      expect(after.viewSelections, before.viewSelections, reason: '$p viewSel');
      expect(
        after.selectionOverrides,
        before.selectionOverrides,
        reason: '$p selectionOverrides',
      );
    }
  }
}

void main() {
  group('library-2 typed edits through validate + dispatch', () {
    test('bool accepts true/false, rejects wrong type and null', () {
      final r = Rig(const UiBoolEdit(), initial: false)..expectPlanValid();
      r.accept(true);
      expect(r.state.resolve(const BindingRef.uiState(_k)), true);
      expect(r.state.userOverrides[_k], true);
      r.rejectAll(['true', 1, null, <String>[]]);
    });

    test('number grid/range/finite, non-integer finite accepted', () {
      final r = Rig(
        const UiNumberEdit(min: 0, max: 10, step: 0.5),
        initial: 1.0,
      )..expectPlanValid();
      r.accept(2.5);
      expect(r.state.resolve(const BindingRef.uiState(_k)), 2.5);
      r.accept(0);
      r.accept(10);
      r.rejectAll([
        2.3, // off-grid: never rounded
        10.5,
        -0.5,
        double.nan,
        double.infinity,
        double.negativeInfinity,
        '2.5',
        null,
      ]);
      expect(r.state.resolve(const BindingRef.uiState(_k)), 10);
    });

    test('integer number rejects fractions and unsafe integers', () {
      final r = Rig(
        const UiNumberEdit(min: 0, max: 1e16, integer: true),
        initial: 1,
      )..expectPlanValid();
      r.accept(9007199254740991); // 2^53-1
      r.rejectAll([1.5, 9007199254740992, 2.0 * 4503599627370496.0 + 2]);
    });

    test('nullable permits null only when declared', () {
      final n = Rig(
        const UiNumberEdit(min: 0, max: 10, nullable: true),
        initial: 1.0,
      )..expectPlanValid();
      n.accept(null);
      expect(n.state.resolve(const BindingRef.uiState(_k)), isNull);
      expect(n.state.userOverrides.containsKey(_k), isTrue);
      final s = Rig(const UiStringEdit(), initial: 'x')..expectPlanValid();
      s.rejectAll([null]);
      final d = Rig(
        const UiDateEdit(first: '2026-01-01', last: '2026-12-31'),
        initial: '2026-02-01',
      )..expectPlanValid();
      d.rejectAll([null, '']);
    });

    test('date strict calendar + inclusive bounds', () {
      final r = Rig(
        const UiDateEdit(first: '2026-01-01', last: '2026-12-31'),
        initial: '2026-02-01',
      )..expectPlanValid();
      r.accept('2026-01-01');
      r.accept('2026-12-31');
      r.accept('2026-02-28');
      r.rejectAll([
        '2026-02-30',
        '2025-12-31',
        '2027-01-01',
        '2026-2-3',
        '2026-02-28T00:00:00Z',
        '',
        20260228,
      ]);
    });

    test('decimal string predicate rejects without state or revision', () {
      final r = Rig(
        UiStringEdit(accepts: (v) => RegExp(r'^\d+(\.\d+)?$').hasMatch(v)),
        initial: '2',
      )..expectPlanValid();
      r.accept('3');
      expect(r.state.resolve(const BindingRef.uiState(_k)), '3');
      r.rejectAll(['oops', '', '.', '3.', null, 3]);
      expect(r.state.userOverrides, {_k: '3'});
    });

    test('string maxLength boundary N-1/N/N+1 in UTF-8 bytes', () {
      final r = Rig(const UiStringEdit(maxLength: 4), initial: '')
        ..expectPlanValid();
      r.accept('abc');
      r.accept('abcd');
      r.rejectAll(['abcde', 'ééé']); // 6 bytes
    });

    test('view specs write viewValues only and never bump revision', () {
      final r = Rig(const UiBoolEdit(view: true), initial: false)
        ..expectPlanValid();
      r.accept(true, bumps: false);
      expect(r.state.viewValues[_k], true);
      expect(r.state.userOverrides, isEmpty);
      // A view key must not also be a business draft input.
      final bad = Rig(
        const UiBoolEdit(view: true),
        initial: false,
        draft: {_k: false},
      );
      expect(bad.result.isValid, isFalse);
      expect(bad.result.errors, contains('view_business_input'));
    });

    test('itemIds: own selection store, normalised, never a scalar', () {
      final r = Rig(UiItemIdsEdit(collectionId: 'rows', multiple: true))
        ..expectPlanValid();
      r.accept(['c', 'a']);
      final s = r.state;
      expect(s.selections[_k], ['a', 'c']);
      expect(s.selectionOverrides, contains(_k));
      expect(r.state.userOverrides.containsKey(_k), isFalse);
      expect(r.state.resolve(const BindingRef.uiState(_k)), isNull);
      r.rejectAll([
        ['a', 'a'],
        ['z'],
        ['a', 'z'],
        'a',
        [1],
      ]);
      expect(s.selections[_k], ['a', 'c']);
    });

    test('itemIds single-select and view selection', () {
      final r = Rig(UiItemIdsEdit(collectionId: 'rows'))..expectPlanValid();
      r.accept(['b']);
      r.accept(<String>[]);
      r.rejectAll([
        ['a', 'b'],
      ]);
      final v = Rig(UiItemIdsEdit(collectionId: 'rows', view: true))
        ..expectPlanValid();
      v.accept(['a'], bumps: false);
      final s = v.state;
      expect(s.viewSelections[_k], ['a']);
      expect(s.selectionOverrides, isNot(contains(_k)));
    });

    test('initial value must satisfy its own spec', () {
      final ok = Rig(const UiNumberEdit(min: 0, max: 10), initial: 5.0)
        ..expectPlanValid();
      expect(ok.result.isValid, isTrue);
      final bad = Rig(const UiNumberEdit(min: 0, max: 10), initial: 11.0);
      expect(bad.result.isValid, isFalse);
      expect(bad.result.errors, contains('edit_input'));
    });
  });

  group('spec metadata (validateSpec / rejectPayload)', () {
    test('valid specs pass validateSpec', () {
      for (final s in <UiEditSpec>[
        const UiBoolEdit(),
        const UiStringEdit(),
        const UiNumberEdit(min: 0, max: 10, step: 0.5),
        const UiNumberEdit(min: 3, max: 3), // read-only constant
        const UiDateEdit(first: '2026-01-01', last: '2026-01-01'),
        UiItemIdsEdit(collectionId: 'rows', initial: ['a']),
      ]) {
        expect(s.validateSpec(), isNull, reason: '$s');
      }
    });

    test('invalid metadata is rejected', () {
      final bad = <UiEditSpec>[
        const UiStringEdit(maxLength: 0),
        const UiStringEdit(maxLength: -1),
        const UiNumberEdit(min: double.nan, max: 1),
        const UiNumberEdit(min: 0, max: double.infinity),
        const UiNumberEdit(min: 2, max: 1),
        const UiNumberEdit(min: 0, max: 1, step: 0),
        const UiNumberEdit(min: 0, max: 1, step: -0.5),
        const UiNumberEdit(min: 0, max: 1, step: double.nan),
        const UiDateEdit(first: '2026-12-31', last: '2026-01-01'),
        const UiDateEdit(first: '2026-02-30', last: '2026-12-31'),
        const UiDateEdit(first: '2026-01-01', last: '2026/12/31'),
        const UiDateEdit(first: '', last: ''),
        UiItemIdsEdit(collectionId: ''),
        UiItemIdsEdit(collectionId: 'rows', initial: ['a', 'a']),
        UiItemIdsEdit(collectionId: 'rows', initial: ['a', 'b']),
      ];
      // Paired so the check cannot pass vacuously on the scaffold.
      expect(const UiBoolEdit().validateSpec(), isNull);
      for (final s in bad) {
        expect(s.validateSpec(), isNotNull, reason: '$s');
        expect(s.validateSpec(), isNot('not_ready'), reason: '$s');
      }
    });

    test('pure rejectPayload agrees with the dispatch matrix', () {
      const n = UiNumberEdit(min: 0, max: 10, step: 0.5);
      expect(n.rejectPayload(2.5), isNull);
      expect(n.rejectPayload(2.3), isNotNull);
      expect(n.rejectPayload(double.nan), isNotNull);
      expect(n.rejectPayload(null), isNotNull);
      expect(
        const UiNumberEdit(min: 0, max: 1, nullable: true).rejectPayload(null),
        isNull,
      );
      final ids = UiItemIdsEdit(collectionId: 'rows', multiple: true);
      final ctx = UiEditContext(collections: {'rows': _rows});
      expect(ids.rejectInContext(['a', 'b'], ctx), isNull);
      expect(ids.rejectInContext(['z'], ctx), isNotNull);
      expect(ids.rejectInContext(['a'], UiEditContext()), isNotNull);
    });
  });

  group('contract guards', () {
    test('number/stringList are event-only; properties throw at runtime', () {
      for (final t in [UiValueType.number, UiValueType.stringList]) {
        expect(
          () => UiComponentSchema(properties: {'p': t}),
          throwsArgumentError,
        );
        expect(() => UiComponentSchema(events: {'change': t}), returnsNormally);
      }
      expect(
        () => UiComponentSchema(properties: {'p': UiValueType.string}),
        returnsNormally,
      );
    });

    test('matchesUiValue number/stringList', () {
      expect(matchesUiValue(UiValueType.number, 1.5), isTrue);
      expect(matchesUiValue(UiValueType.number, double.nan), isFalse);
      expect(matchesUiValue(UiValueType.number, '1'), isFalse);
      expect(matchesUiValue(UiValueType.stringList, ['a']), isTrue);
      expect(matchesUiValue(UiValueType.stringList, [1]), isFalse);
      expect(matchesUiValue(UiValueType.stringList, null), isFalse);
    });

    test('invalid plan inputs: type mismatch, bad initial, bad metadata', () {
      Rig(const UiNumberEdit(min: 0, max: 10), initial: 1.0).expectPlanValid();
      final mismatch = Rig(
        const UiNumberEdit(min: 0, max: 10),
        initial: 1.0,
        eventType: UiValueType.boolean,
      );
      expect(mismatch.result.errors, contains('edit_input'));
      final wrongInitial = Rig(
        const UiNumberEdit(min: 0, max: 10),
        initial: '1',
      );
      expect(wrongInitial.result.errors, contains('edit_input'));
      final badMeta = Rig(const UiNumberEdit(min: 2, max: 1), initial: 1.5);
      expect(badMeta.result.errors, contains('edit_spec:$_k'));
      final badIds = Rig(UiItemIdsEdit(collectionId: 'rows', initial: ['z']));
      expect(badIds.result.errors, contains('edit_input'));
      Rig(UiItemIdsEdit(collectionId: 'rows', initial: ['a']))
          .expectPlanValid();
    });

    test('direct edit/selectView cannot bypass the active spec', () {
      final r = Rig(const UiNumberEdit(min: 0, max: 10), initial: 1.0)
        ..expectPlanValid();
      final before = Obs(r.state);
      r.state.edit(_k, 11.0);
      r.state.edit(_k, 'x');
      r.state.selectView(_k, 99);
      final after = Obs(r.state);
      expect(after.rev, before.rev);
      expect(after.overrides, before.overrides);
      expect(after.view, before.view);
      r.state.edit(_k, 2.5);
      expect(r.state.resolve(const BindingRef.uiState(_k)), 2.5);

      final ids = Rig(UiItemIdsEdit(collectionId: 'rows'))..expectPlanValid();
      ids.state.edit(_k, ['z']);
      ids.state.edit(_k, ['a', 'b']);
      expect(Obs(ids.state).selections[_k], isEmpty);
      ids.state.edit(_k, ['a']);
      expect(Obs(ids.state).selections[_k], ['a']);

      final view = Rig(const UiBoolEdit(view: true), initial: false)
        ..expectPlanValid();
      view.state.edit(_k, true); // view keys are not draft edits
      expect(Obs(view.state).value, false);
    });

    test('direct edit without a current library-2 plan keeps legacy rules', () {
      final r = Rig(UiStringEdit(accepts: (v) => v == 'x'), initial: 'x')
        ..expectPlanValid();
      final fresh = UiSessionState(r.snapshot); // no accepted plan
      fresh.edit(_k, 'oops');
      expect(fresh.resolve(const BindingRef.uiState(_k)), 'oops');
      fresh.edit(_k, true); // legacy String lock
      expect(fresh.resolve(const BindingRef.uiState(_k)), 'oops');
    });

    test('nullable spec does not let other events skip the coarse gate', () {
      // Two independent keys: `k` is a nullable draft edit key, `s` is a
      // view:true String key that sortRows may write.
      const s = 's';
      final snapshot = DataSnapshot(
        ref: const SnapshotRef('s', 1),
        facts: {},
        initialUiState: {_k: 'original', s: 'original'},
        editSpecs: {
          _k: const UiStringEdit(nullable: true),
          s: const UiStringEdit(view: true),
        },
      );
      final catalog = UiCatalog(
        version: 'library-2',
        components: {
          'Page': UiComponentSchema(
            properties: {'title': UiValueType.string},
            allowsChildren: true,
          ),
          'Editor': UiComponentSchema(
            bindings: {
              'draft': {BindingKind.uiState},
              'sortKey': {BindingKind.uiState},
            },
            requiredBindings: {'draft', 'sortKey'},
            events: {'change': UiValueType.string, 'sort': UiValueType.string},
            eventActions: {
              'change': {'edit'},
              'sort': {'sort'},
            },
          ),
        },
        actions: {
          'edit': const UiActionDefinition(
            route: UiActionRoute.local,
            localAction: UiLocalAction.editField,
          ),
          'sort': const UiActionDefinition(
            route: UiActionRoute.local,
            localAction: UiLocalAction.sortRows,
          ),
        },
      );
      final intent = InteractionIntent(
        id: 'i',
        purpose: 'edit',
        snapshotRef: snapshot.ref,
        allowedActionRefs: {'edit', 'sort'},
      );
      final plan = UIPlan(
        surfaceId: 's',
        revision: 1,
        catalogVersion: 'library-2',
        snapshotRef: snapshot.ref,
        intentRef: 'i',
        root: 'root',
        nodes: [
          UiNode(
            id: 'root',
            component: 'Page',
            properties: {'title': 't'},
            children: ['ed'],
          ),
          UiNode(
            id: 'ed',
            component: 'Editor',
            bindings: {
              'draft': const BindingRef.uiState(_k),
              'sortKey': const BindingRef.uiState(s),
            },
            events: {
              'change': ActionBinding(actionRef: 'edit', inputRefs: [_k]),
              'sort': ActionBinding(actionRef: 'sort', inputRefs: [s]),
            },
          ),
        ],
      );
      final result = validateUiPlan(plan, snapshot, intent, catalog);
      expect(result.isValid, isTrue, reason: '${result.errors}');
      // A registered non-view spec on the sort key is a draft bypass: refused.
      final nonView = validateUiPlan(
        plan,
        DataSnapshot(
          ref: snapshot.ref,
          facts: {},
          initialUiState: snapshot.initialUiState,
          editSpecs: {
            _k: const UiStringEdit(nullable: true),
            s: const UiStringEdit(),
          },
        ),
        intent,
        catalog,
      );
      expect(nonView.isValid, isFalse);
      expect(nonView.errors, contains('edit_input'));
      // No spec on the sort key keeps the legacy default sort mapping.
      final unregistered = validateUiPlan(
        plan,
        DataSnapshot(
          ref: snapshot.ref,
          facts: {},
          initialUiState: snapshot.initialUiState,
          editSpecs: {_k: const UiStringEdit(nullable: true)},
        ),
        intent,
        catalog,
      );
      expect(unregistered.isValid, isTrue, reason: '${unregistered.errors}');
      final state = UiSessionState(snapshot)..accept(result.validatedPlan!);
      UiEventOutcome send(String kind, Object? payload) => state.dispatch(
        UiEvent(
          eventId: '$kind$payload',
          surfaceId: 's',
          nodeId: 'ed',
          observedRevision: 1,
          kind: kind,
          payload: payload,
        ),
        result.validatedPlan!,
        catalog,
      );
      expect(send('sort', null), UiEventOutcome.invalid);
      expect(send('sort', 'value'), UiEventOutcome.applied);
      expect(state.viewValues[s], 'value');
      expect(state.draftRevision, 0);
      expect(send('change', null), UiEventOutcome.applied);
      expect(state.resolve(const BindingRef.uiState(_k)), isNull);
    });

    test('adoptExtracted restores spec.initial and bumps revision', () {
      final r = Rig(
        UiItemIdsEdit(collectionId: 'rows', multiple: true, initial: ['b']),
      )..expectPlanValid();
      expect(r.state.selections[_k], ['b']);
      r.accept(['c', 'a']);
      final s = Rig(const UiStringEdit(), initial: 'x')..expectPlanValid();
      s.accept('y');
      final rev = r.state.draftRevision;
      r.state.adoptExtracted(_k);
      expect(r.state.selections[_k], ['b']);
      expect(r.state.selectionOverrides, isEmpty);
      expect(r.state.draftRevision, rev + 1);
      // Scalar layer is independent and unchanged by itemIds adoption.
      expect(s.state.userOverrides, {_k: 'y'});
      r.state.adoptExtracted(_k); // no override left: no-op
      expect(r.state.draftRevision, rev + 1);
    });
  });

  group('legacy catalogs stay string-only (controls)', () {
    for (final version in ['minimal-1', 'dynamic-1', 'library-1']) {
      test('$version ignores registered specs', () {
        final n = Rig(
          const UiNumberEdit(min: 0, max: 10),
          initial: 1.0,
          version: version,
        );
        expect(n.result.isValid, isFalse, reason: version);
        expect(n.result.errors, contains('edit_input'));
        final b = Rig(const UiBoolEdit(), initial: false, version: version);
        expect(b.result.isValid, isFalse, reason: version);
        final s = Rig(
          UiStringEdit(accepts: (_) => false),
          initial: 'x',
          version: version,
        );
        expect(s.result.isValid, isTrue, reason: version);
        // The registered predicate is ignored; legacy accepts any String.
        s.accept('oops');
        expect(s.state.resolve(const BindingRef.uiState(_k)), 'oops');
        s.rejectAll([true, 3, null]);
      });
    }
  });
  group('review regressions: typed entry gates', () {
    test('finite inputs whose step ratio overflows are rejected', () {
      final r = Rig(
        const UiNumberEdit(min: 0, max: 1e308, step: 1e-308),
        initial: 0.0,
      )..expectPlanValid();
      r.rejectAll([1e308]);
    });
    test('non-view typed key cannot mutate through selectView', () {
      final r = Rig(const UiNumberEdit(min: 0, max: 10), initial: 1.0)
        ..expectPlanValid();
      final before = Obs(r.state);
      r.state.selectView(_k, 5.0);
      final after = Obs(r.state);
      expect(after.value, before.value);
      expect(after.view, before.view);
      expect(after.rev, before.rev);
    });
    test('missing spec uses default string limit for direct edits too', () {
      final r = Rig(const UiStringEdit(), initial: 'x', register: false)
        ..expectPlanValid();
      final before = Obs(r.state);
      r.state.edit(_k, List.filled(4097, 'a').join());
      final after = Obs(r.state);
      expect(after.value, before.value);
      expect(after.overrides, before.overrides);
      expect(after.rev, before.rev);
      // Boundary pair: the default limit still admits exactly 4096 bytes, and
      // an unknown key writes nothing.
      r.state.edit(_k, List.filled(4096, 'a').join());
      expect(Obs(r.state).rev, before.rev + 1);
      r.state.edit('unknown', 'x');
      expect(Obs(r.state).rev, before.rev + 1);
    });
    test('view specs allow direct view selection without a revision', () {
      final r = Rig(const UiBoolEdit(view: true), initial: false)
        ..expectPlanValid();
      r.state.selectView(_k, true);
      expect(r.state.viewValues[_k], true);
      expect(r.state.draftRevision, 5);
      r.state.selectView(_k, 'x'); // spec still checked
      expect(r.state.viewValues[_k], true);
      final ids = Rig(UiItemIdsEdit(collectionId: 'rows', view: true))
        ..expectPlanValid();
      ids.state.selectView(_k, ['a']);
      expect(ids.state.viewSelections[_k], ['a']);
      ids.state.selectView(_k, ['z']);
      expect(ids.state.viewSelections[_k], ['a']);
      expect(ids.state.selectionOverrides, isEmpty);
    });
    test('non-view itemIds cannot mutate through selectView', () {
      final r = Rig(UiItemIdsEdit(collectionId: 'rows'))..expectPlanValid();
      r.state.selectView(_k, ['a']);
      expect(r.state.selections[_k], isEmpty);
      expect(r.state.viewSelections, isEmpty);
    });
  });
}
