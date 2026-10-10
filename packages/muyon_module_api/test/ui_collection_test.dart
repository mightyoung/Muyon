import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';

// F5b slice 1c (RED). Real validateUiPlan / UiSessionState.dispatch / stream2
// compiler only. The declarations (UiCollectionShape, UiComputedEvidence,
// schema metadata, openRow, rowObject) are NOT-READY scaffolds, so every
// positive collection assertion fails on behaviour today. Each negative test
// first asserts its valid control, so no reject can pass vacuously.

const _ref = SnapshotRef('s', 1);
const _obj = ObjectRef(
  moduleId: 'm',
  objectType: 'quote',
  objectId: 'a',
  revisionRef: 'r1',
);
const _obj2 = ObjectRef(
  moduleId: 'm',
  objectType: 'quote',
  objectId: 'b',
  revisionRef: 'r1',
);
const _doc = SourceSpanRef(
  artifact: ArtifactRef(
    moduleId: 'm',
    artifactId: 'doc',
    contentDigest: 'd1',
  ),
  originalText: 'hello world',
  start: 0,
  end: 5,
);
const _bind = BindingRef.fact;

SnapshotFact _fact({
  Object? value = 'v',
  FactState state = FactState.verified,
  ObjectRef object = _obj,
}) => SnapshotFact(
  object: object,
  field: 'f',
  value: value,
  state: state,
  sourceRefs: const ['quote'],
);

UiCollection _coll({
  String id = 'rows',
  List<UiColumn>? columns,
  List<UiRow>? rows,
}) => UiCollection(
  id: id,
  columns: columns ?? const [UiColumn('c1', 'Name')],
  rows:
      rows ??
      [
        UiRow(itemId: 'r1', cells: {'c1': _bind('f1')}, object: _obj),
      ],
);

DataSnapshot _snapshot({
  Map<String, SnapshotFact>? facts,
  Map<String, UiCollection>? collections,
  Map<String, ComputedValue> computations = const {},
  Map<String, UiComputedEvidence> evidence = const {},
  Map<String, String> digests = const {'doc': 'd1'},
  Map<String, Object?> state = const {},
  Map<String, UiEditSpec> specs = const {},
}) => DataSnapshot(
  ref: _ref,
  facts: facts ?? {'f1': _fact()},
  collections: collections ?? {'rows': _coll()},
  computations: computations,
  computedEvidence: evidence,
  sources: const {'quote': _doc},
  sourceDigests: digests,
  initialUiState: state,
  editSpecs: specs,
  actionContext: UiActionContext(draftRevision: 3),
);

UiCatalog _catalog({
  String version = 'library-2',
  UiCollectionShape shape = UiCollectionShape.table,
}) => UiCatalog(
  version: version,
  components: {
    'Page': UiComponentSchema(
      allowsChildren: true,
      childComponents: {'Table', 'Chart', 'Heading', 'Readout'},
    ),
    'Table': UiComponentSchema(
      bindings: {
        'rows': {BindingKind.collection},
      },
      requiredBindings: {'rows'},
      collections: {'rows': shape},
      events: {'tap': UiValueType.string},
      eventActions: {
        'tap': {'open'},
      },
    ),
    'Chart': UiComponentSchema(
      properties: {'kind': UiValueType.string},
      requiredProperties: {'kind'},
      bindings: {
        'data': {BindingKind.collection},
      },
      requiredBindings: {'data'},
      collections: {'data': UiCollectionShape.series},
      allowedValues: {
        'kind': {'bar', 'line', 'pie'},
      },
    ),
    // allowedValues are real values (design §2): int levels, string kinds.
    'Heading': UiComponentSchema(
      properties: {'level': UiValueType.integer},
      requiredProperties: {'level'},
      allowedValues: {
        'level': {1, 2, 3},
      },
    ),
    'Readout': UiComponentSchema(
      bindings: {
        'v': {BindingKind.uiState},
      },
      requiredBindings: {'v'},
    ),
  },
  actions: {
    'open': const UiActionDefinition(
      route: UiActionRoute.local,
      localAction: UiLocalAction.openRow,
    ),
  },
);

InteractionIntent _intent({
  Set<BindingRef> required = const {},
  Set<FactState> mandatory = const {},
}) => InteractionIntent(
  id: 'i',
  purpose: 'p',
  snapshotRef: _ref,
  requiredBindings: required,
  mandatoryStates: mandatory,
  allowedActionRefs: {'open'},
);

UiNode _table(String cid) => UiNode(
  id: 't',
  component: 'Table',
  bindings: {'rows': BindingRef.collection(cid)},
  events: {'tap': ActionBinding(actionRef: 'open')},
);
UiNode _chart(String kind) => UiNode(
  id: 't',
  component: 'Chart',
  properties: {'kind': kind},
  bindings: {'data': const BindingRef.collection('rows')},
);

class Rig {
  Rig(
    this.snapshot, {
    UiCatalog? catalog,
    InteractionIntent? intent,
    String cid = 'rows',
    List<UiNode>? body,
  }) : catalog = catalog ?? _catalog(),
       intent = intent ?? _intent() {
    final nodes = body ?? [_table(cid)];
    plan = UIPlan(
      surfaceId: 's',
      revision: 1,
      catalogVersion: this.catalog.version,
      snapshotRef: _ref,
      intentRef: 'i',
      root: 'root',
      nodes: [
        UiNode(id: 'root', component: 'Page', children: [
          for (final n in nodes) n.id,
        ]),
        ...nodes,
      ],
    );
    result = validateUiPlan(plan, snapshot, this.intent, this.catalog);
  }
  final DataSnapshot snapshot;
  final UiCatalog catalog;
  final InteractionIntent intent;
  late final UIPlan plan;
  late final UiValidationResult result;
  late final UiSessionState state = UiSessionState(snapshot);
  UiNode get table => plan.nodes.firstWhere((n) => n.id == 't');
  var _n = 0;

  UiEventOutcome send(Object? payload) {
    if (state.currentPlan == null) state.accept(result.validatedPlan!);
    return state.dispatch(
      UiEvent(
        eventId: 'e${_n++}',
        surfaceId: 's',
        nodeId: 't',
        observedRevision: 1,
        kind: 'tap',
        payload: payload,
      ),
      result.validatedPlan!,
      catalog,
    );
  }
}

void ok(Rig r) =>
    expect(r.result.isValid, isTrue, reason: '${r.result.errors}');
void bad(Rig r, [String prefix = 'collection:rows:']) {
  expect(r.result.isValid, isFalse);
  expect(
    r.result.errors.any((e) => e.startsWith(prefix)),
    isTrue,
    reason: 'expected $prefix* in ${r.result.errors}',
  );
}

Rig _rigC(UiCollection c, {Map<String, SnapshotFact>? facts}) =>
    Rig(_snapshot(collections: {c.id: c}, facts: facts), cid: c.id);

/// Size contract used by these tests (execution clarification, pending parent
/// review): UTF-8 length of jsonEncode of the structural reference metadata
/// only: id; columns {id,label}; rows {itemId, cells[{kind,id}] in column
/// order, object (ObjectRef.toJson) only when present}. No fact/computed values.
int _metaBytes(UiCollection c) => utf8
    .encode(
      jsonEncode({
        'id': c.id,
        'columns': [
          for (final col in c.columns) {'id': col.id, 'label': col.label},
        ],
        'rows': [
          for (final row in c.rows)
            {
              'itemId': row.itemId,
              'cells': [
                for (final col in c.columns)
                  {
                    'kind': row.cells[col.id]!.kind.name,
                    'id': row.cells[col.id]!.id,
                  },
              ],
              if (row.object != null) 'object': row.object!.toJson(),
            },
        ],
      }),
    )
    .length;

UiCollection _wide(int rows, int cols, {int padTo = 0}) {
  final columns = [for (var c = 0; c < cols; c++) UiColumn('c$c', 'L$c')];
  UiCollection build(List<String> ids) => _coll(
    columns: columns,
    rows: [
      for (var i = 0; i < ids.length; i++)
        UiRow(
          itemId: ids[i],
          cells: {for (final c in columns) c.id: _bind('f1')},
        ),
    ],
  );
  var ids = [for (var i = 0; i < rows; i++) 'r$i'];
  if (padTo == 0) return build(ids);
  var extra = padTo - _metaBytes(build(ids));
  if (extra < 0) throw StateError('base already exceeds $padTo');
  ids = [
    for (final id in ids)
      () {
        final add = extra < 128 - id.length ? extra : 128 - id.length;
        extra -= add;
        return id + 'x' * add;
      }(),
  ];
  if (extra != 0) throw StateError('cannot pad to $padTo');
  final out = build(ids);
  if (_metaBytes(out) != padTo) throw StateError('size helper drift');
  return out;
}

void main() {
  group('table acceptance and shape metadata', () {
    test('one column, many columns, structure controls', () {
      ok(Rig(_snapshot()));
      ok(_rigC(_wide(3, 5)));
      final r = Rig(_snapshot());
      expect(r.snapshot.collections['rows']!.rows.single.itemId, 'r1');
    });

    test('shape accepts: exact column requirements', () {
      UiCollection cols(List<String> ids) => UiCollection(
        id: 'x',
        columns: [for (final i in ids) UiColumn(i, i)],
        rows: const [],
      );
      expect(UiCollectionShape.table.accepts(cols(['a'])), isTrue);
      expect(UiCollectionShape.table.accepts(cols([])), isFalse);
      expect(
        UiCollectionShape.series.accepts(cols(['label', 'value'])),
        isTrue,
      );
      // Column order is not part of the contract: cells are read by columnId.
      expect(
        UiCollectionShape.series.accepts(cols(['value', 'label'])),
        isTrue,
      );
      for (final no in [
        ['label'],
        ['label', 'value', 'x'],
        ['x', 'value'],
      ]) {
        expect(UiCollectionShape.series.accepts(cols(no)), isFalse, reason: '$no');
      }
      expect(UiCollectionShape.timeline.accepts(cols(['time', 'title'])), isTrue);
      expect(
        UiCollectionShape.timeline.accepts(cols(['time', 'title', 'detail'])),
        isTrue,
      );
      expect(UiCollectionShape.timeline.accepts(cols(['time'])), isFalse);
      expect(
        UiCollectionShape.timeline.accepts(cols(['time', 'title', 'x'])),
        isFalse,
      );
      for (final s in [UiCollectionShape.options, UiCollectionShape.items]) {
        expect(s.accepts(cols(['label'])), isTrue, reason: '$s');
        expect(s.accepts(cols(['label', 'x'])), isFalse, reason: '$s');
        expect(s.accepts(cols(['x'])), isFalse, reason: '$s');
        expect(s.accepts(cols([])), isFalse, reason: '$s');
      }
    });

    test('schema metadata is immutable (scaffold control)', () {
      final s = _catalog().components['Table']!;
      expect(() => s.collections['x'] = UiCollectionShape.table, throwsUnsupportedError);
      expect(() => _catalog().components['Page']!.childComponents.add('x'),
          throwsUnsupportedError);
      expect(() => _catalog().components['Chart']!.allowedValues['kind']!.add('x'),
          throwsUnsupportedError);
    });

    test('shape mismatch is rejected by the existing validator', () {
      ok(Rig(_snapshot(), catalog: _catalog(shape: UiCollectionShape.table)));
      final twoCols = _wide(2, 3);
      ok(_rigC(twoCols));
      final r = Rig(
        _snapshot(),
        catalog: _catalog(shape: UiCollectionShape.options),
      );
      // single-column collection fits options ...
      ok(r);
      // ... a 3-column one does not.
      bad(
        Rig(
          _snapshot(collections: {'rows': twoCols}),
          catalog: _catalog(shape: UiCollectionShape.options),
        ),
      );
    });
  });

  group('limits N-1/N/N+1 with real plan validation', () {
    void edge(String name, UiCollection okC, UiCollection badC,
        {UiCollection? below}) {
      test(name, () {
        if (below != null) ok(_rigC(below));
        ok(_rigC(okC));
        bad(_rigC(badC), 'collection:${badC.id}:');
      });
    }

    edge('rows 199/200/201', _wide(200, 1), _wide(201, 1), below: _wide(199, 1));
    edge('columns 31/32/33', _wide(2, 32), _wide(2, 33), below: _wide(2, 31));
    edge(
      'collection id 127/128/129 bytes',
      _coll(id: 'a' * 128),
      _coll(id: 'a' * 129),
      below: _coll(id: 'a' * 127),
    );
    edge(
      'collection id counts bytes not chars',
      _coll(id: 'é' * 64),
      _coll(id: 'é' * 65),
    );
    UiCollection withCol(String id, String label) => _coll(
      columns: [UiColumn(id, label)],
      rows: [UiRow(itemId: 'r1', cells: {id: _bind('f1')})],
    );
    edge('column id 127/128/129', withCol('a' * 128, 'L'), withCol('a' * 129, 'L'),
        below: withCol('a' * 127, 'L'));
    edge('column label 255/256/257', withCol('c', 'a' * 256), withCol('c', 'a' * 257),
        below: withCol('c', 'a' * 255));
    edge('label counts bytes', withCol('c', 'é' * 128), withCol('c', 'é' * 129));
    UiCollection withItem(String id) => _coll(
      rows: [UiRow(itemId: id, cells: {'c1': _bind('f1')})],
    );
    edge('item id 127/128/129', withItem('a' * 128), withItem('a' * 129),
        below: withItem('a' * 127));
    edge('item id counts bytes', withItem('é' * 64), withItem('é' * 65));

    test('metadata envelope 64 KiB: 65535/65536 ok, 65537 rejected', () {
      for (final n in [65535, 65536]) {
        ok(_rigC(_wide(200, 9, padTo: n)));
      }
      bad(_rigC(_wide(200, 9, padTo: 65537)));
    });

    test('fact values do not count toward the 64 KiB metadata size', () {
      final big = _wide(200, 9, padTo: 65536);
      ok(
        _rigC(big, facts: {'f1': _fact(value: 'x' * 100000)}),
      );
    });
  });

  group('structure', () {
    test('duplicate column / duplicate row rejected as a whole', () {
      ok(Rig(_snapshot()));
      bad(_rigC(_coll(
        columns: const [UiColumn('c1', 'A'), UiColumn('c1', 'B')],
      )));
      bad(_rigC(_coll(rows: [
        UiRow(itemId: 'r1', cells: {'c1': _bind('f1')}),
        UiRow(itemId: 'r1', cells: {'c1': _bind('f1')}),
      ])));
    });

    test('missing or extra cell rejects the whole collection', () {
      ok(_rigC(_wide(2, 2)));
      bad(_rigC(_coll(
        columns: const [UiColumn('c1', 'A'), UiColumn('c2', 'B')],
        rows: [
          UiRow(itemId: 'r1', cells: {'c1': _bind('f1'), 'c2': _bind('f1')}),
          UiRow(itemId: 'r2', cells: {'c1': _bind('f1')}),
        ],
      )));
      bad(_rigC(_coll(rows: [
        UiRow(itemId: 'r1', cells: {'c1': _bind('f1'), 'zz': _bind('f1')}),
      ])));
    });

    test('cell kind must be fact or computed and must resolve', () {
      ok(Rig(_snapshot()));
      for (final ref in [
        const BindingRef.uiState('s'),
        const BindingRef.sourceSpan('quote'),
        const BindingRef.collection('rows'),
        _bind('missing'),
      ]) {
        bad(_rigC(_coll(rows: [
          UiRow(itemId: 'r1', cells: {'c1': ref}),
        ])));
      }
    });

    test('row object must equal the cell fact object', () {
      ok(Rig(_snapshot()));
      bad(_rigC(_coll(rows: [
        UiRow(itemId: 'r1', cells: {'c1': _bind('f1')}, object: _obj2),
      ])));
    });
  });

  group('computed cells and evidence', () {
    final cols = const [UiColumn('c1', 'A'), UiColumn('c2', 'B')];
    UiCollection withComputed() => _coll(
      columns: cols,
      rows: [
        UiRow(
          itemId: 'r1',
          cells: {'c1': _bind('f1'), 'c2': const BindingRef.computed('k')},
        ),
      ],
    );
    ComputedValue cv([SnapshotRef v = _ref]) =>
        ComputedValue(value: 5, inputVersion: v, computationId: 'k');
    Rig rig({
      Map<String, UiComputedEvidence> ev = const {},
      SnapshotRef v = _ref,
      Map<String, String> digests = const {'doc': 'd1'},
    }) => Rig(
      _snapshot(
        collections: {'rows': withComputed()},
        computations: {'k': cv(v)},
        evidence: ev,
        digests: digests,
      ),
    );
    final good = {
      'k': UiComputedEvidence(
        state: FactState.verified,
        sourceRefs: const ['quote'],
      ),
    };

    test('evidence missing / bad source / stale generation rejected', () {
      ok(rig(ev: good));
      bad(rig());
      bad(rig(ev: {
        'k': UiComputedEvidence(
          state: FactState.verified,
          sourceRefs: const ['nope'],
        ),
      }));
      bad(rig(ev: good, v: const SnapshotRef('s', 0)));
      bad(rig(ev: good, digests: const {'doc': 'changed'}));
    });

    test('computedEvidence/copyWith carry state and are immutable', () {
      final s = _snapshot().copyWith(computedEvidence: good);
      expect(s.computedEvidence['k']!.state, FactState.verified);
      expect(() => s.computedEvidence['x'] = good['k']!, throwsUnsupportedError);
      expect(() => good['k']!.sourceRefs.add('x'), throwsUnsupportedError);
    });
  });

  group('missing values, shown coverage, provenance', () {
    test('null fact keeps its state and never becomes 0', () {
      for (final s in [
        FactState.notDisclosed,
        FactState.notApplicable,
        FactState.readFailed,
        FactState.verified,
      ]) {
        final r = Rig(_snapshot(facts: {'f1': _fact(value: null, state: s)}));
        ok(r);
        expect(r.state.resolve(_bind('f1')), isNull, reason: '$s');
        expect(r.snapshot.facts['f1']!.state, s);
      }
      // A fact value that is not a scalar is still refused.
      expect(
        Rig(_snapshot(facts: {'f1': _fact(value: double.nan)})).result.isValid,
        isFalse,
      );
    });

    test('collection cells count as shown for requiredBindings', () {
      ok(Rig(_snapshot(), intent: _intent(required: {_bind('f1')})));
      final facts = {'f1': _fact(), 'f2': _fact()};
      bad(
        Rig(_snapshot(facts: facts), intent: _intent(required: {_bind('f2')})),
        'required_binding:',
      );
    });

    test('collection cells count as shown for mandatoryStates', () {
      final shown = {
        'f1': _fact(value: null, state: FactState.notDisclosed),
      };
      ok(Rig(_snapshot(facts: shown),
          intent: _intent(mandatory: {FactState.notDisclosed})));
      final hidden = {
        ...shown,
        'f2': _fact(value: null, state: FactState.notDisclosed),
      };
      bad(
        Rig(_snapshot(facts: hidden),
            intent: _intent(mandatory: {FactState.notDisclosed})),
        'mandatory_state:',
      );
    });

    test('provenance is read through, never copied', () {
      final snap = _snapshot();
      final r = Rig(snap);
      ok(r);
      final v = r.result.validatedPlan!;
      expect(identical(v.snapshot, snap), isTrue);
      expect(identical(v.snapshot.collections['rows'], snap.collections['rows']), isTrue);
      expect(identical(v.snapshot.facts['f1'], snap.facts['f1']), isTrue);
      expect(identical(v.snapshot.facts['f1']!.sourceRefs, snap.facts['f1']!.sourceRefs), isTrue);
      expect(snap.collections['rows']!.rows.single.cells['c1'], _bind('f1'));
    });

    test('collection binding never resolves to a value', () {
      final r = Rig(_snapshot());
      ok(r);
      expect(r.state.resolve(const BindingRef.collection('rows')), isNull);
    });
  });

  group('old catalogs refuse collections even when declared', () {
    test('library-2 accepts; minimal/dynamic/library-1 reject', () {
      ok(Rig(_snapshot()));
      for (final v in ['minimal-1', 'dynamic-1', 'library-1']) {
        final r = Rig(_snapshot(), catalog: _catalog(version: v));
        expect(r.result.isValid, isFalse, reason: v);
      }
    });
  });

  group('series / chart', () {
    Rig series(List<(Object?, FactState)> values, {String kind = 'bar'}) {
      final facts = <String, SnapshotFact>{
        'lbl': _fact(),
        for (var i = 0; i < values.length; i++)
          'v$i': _fact(value: values[i].$1, state: values[i].$2),
      };
      return Rig(
        _snapshot(
          facts: facts,
          collections: {
            'rows': _coll(
              columns: const [UiColumn('label', 'L'), UiColumn('value', 'V')],
              rows: [
                for (var i = 0; i < values.length; i++)
                  UiRow(
                    itemId: 'p$i',
                    cells: {'label': _bind('lbl'), 'value': _bind('v$i')},
                  ),
              ],
            ),
          },
        ),
        body: [_chart(kind)],
      );
    }

    const v = FactState.verified;
    test('canonical numbers, decimal strings and legal gaps are accepted', () {
      ok(series([(3, v), (2.5, v), ('10.25', v), ('-1', v), (null, FactState.notApplicable), (null, FactState.notDisclosed)]));
      ok(series([(1, v), (2, v)], kind: 'pie'));
      ok(series([(-4, v)], kind: 'line'));
    });

    test('invalid value anywhere rejects the whole collection', () {
      ok(series([(1, v), (2, v)]));
      for (final badValue in <Object?>[
        double.infinity,
        double.nan,
        'abc',
        '',
        '1,5',
        '1e5',
        ' 1',
        true,
      ]) {
        bad(series([(1, v), (badValue, v), (2, v)]));
      }
    });

    test('pie rejects negatives as a whole; bar and line keep them', () {
      ok(series([(1, v), (-2, v)]));
      ok(series([(1, v), ('-2.5', v)], kind: 'line'));
      bad(series([(1, v), (-2, v)], kind: 'pie'));
      bad(series([(1, v), ('-2.5', v)], kind: 'pie'));
    });

    test('series slot refuses a non-series-shaped collection', () {
      ok(series([(1, v)]));
      bad(Rig(_snapshot(), body: [_chart('bar')]));
    });
  });

  group('allowedValues', () {
    Rig head(int level) => Rig(
      _snapshot(),
      body: [
        UiNode(id: 't', component: 'Heading', properties: {'level': level}),
      ],
    );
    test('Heading.level only 1..3', () {
      for (final l in [1, 2, 3]) {
        ok(head(l));
      }
      for (final l in [0, 4, -1]) {
        expect(head(l).result.isValid, isFalse, reason: 'level $l');
        expect(head(l).result.errors.any((e) => e.contains('level')), isTrue);
      }
    });

    test('Chart.kind only bar/line/pie', () {
      Rig chart(String k) => Rig(
        _snapshot(facts: {'f1': _fact(value: 1), 'lbl': _fact()}, collections: {
          'rows': _coll(
            columns: const [UiColumn('label', 'L'), UiColumn('value', 'V')],
            rows: [
              UiRow(itemId: 'p', cells: {'label': _bind('lbl'), 'value': _bind('f1')}),
            ],
          ),
        }),
        body: [_chart(k)],
      );
      for (final k in ['bar', 'line', 'pie']) {
        ok(chart(k));
      }
      final r = chart('donut');
      expect(r.result.isValid, isFalse);
      expect(r.result.errors.any((e) => e.contains('kind')), isTrue,
          reason: '${r.result.errors}');
    });
  });

  group('readonly typed bindings validate metadata and initial', () {
    Rig ro(UiEditSpec spec, Object? initial, {bool ids = false}) => Rig(
      _snapshot(
        state: ids ? const {} : {'k': initial},
        specs: {'k': spec},
      ),
      body: [
        UiNode(
          id: 't',
          component: 'Readout',
          bindings: {'v': const BindingRef.uiState('k')},
        ),
      ],
    );

    test('bad spec metadata is refused', () {
      ok(ro(const UiStringEdit(maxLength: 8), 'ok'));
      expect(ro(const UiStringEdit(maxLength: 0), 'ok').result.isValid, isFalse);
      expect(ro(const UiNumberEdit(min: 5, max: 1), 3).result.isValid, isFalse);
    });

    test('initial violating its spec is refused', () {
      ok(ro(const UiNumberEdit(min: 0, max: 10), 5));
      expect(ro(const UiNumberEdit(min: 0, max: 10), 99).result.isValid, isFalse);
      expect(ro(const UiStringEdit(maxLength: 2), 'toolong').result.isValid, isFalse);
    });

    test('itemIds initial must be known row ids', () {
      ok(ro(UiItemIdsEdit(collectionId: 'rows', initial: ['r1']), null, ids: true));
      expect(
        ro(UiItemIdsEdit(collectionId: 'rows', initial: ['nope']), null, ids: true)
            .result
            .isValid,
        isFalse,
      );
    });
  });

  group('openRow / rowObject', () {
    UiCollection two({bool swap = false, bool noObject2 = false}) {
      final rows = [
        UiRow(itemId: 'r1', cells: {'c1': _bind('f1')}, object: _obj),
        UiRow(
          itemId: 'r2',
          cells: {'c1': _bind('f2')},
          object: noObject2 ? null : _obj2,
        ),
      ];
      return _coll(rows: swap ? rows.reversed.toList() : rows);
    }

    Rig rig({bool swap = false, bool noObject2 = false}) => Rig(
      _snapshot(
        facts: {'f1': _fact(), 'f2': _fact(object: _obj2)},
        collections: {'rows': two(swap: swap, noObject2: noObject2)},
      ),
    );

    test('trusted row opens with the host object and no draft change', () {
      final r = rig();
      ok(r);
      final before = (r.state.draftRevision, Map.of(r.state.userOverrides));
      expect(r.send('r2'), UiEventOutcome.applied);
      expect(r.state.rowObject(r.table, 'r2'), _obj2);
      expect(r.state.rowObject(r.table, 'r1'), _obj);
      expect(r.state.draftRevision, before.$1);
      expect(r.state.userOverrides, before.$2);
    });

    test('forged, unknown, missing-object payloads are invalid and inert', () {
      final r = rig(noObject2: true);
      ok(r);
      final rev = r.state.draftRevision;
      expect(r.send('r1'), UiEventOutcome.applied); // control
      for (final p in <Object?>['zzz', 'a', 'm:quote:a', '', 'r2', null, 7]) {
        expect(r.send(p), UiEventOutcome.invalid, reason: '$p');
        expect(r.state.rowObject(r.table, p), isNull, reason: '$p');
      }
      expect(r.state.draftRevision, rev);
      expect(r.state.userOverrides, isEmpty);
      expect(r.state.rowObject(r.table, 'r1'), _obj);
    });

    test('row reorder keeps itemId identity', () {
      for (final swap in [false, true]) {
        final r = rig(swap: swap);
        ok(r);
        expect(r.send('r2'), UiEventOutcome.applied, reason: 'swap=$swap');
        expect(r.state.rowObject(r.table, 'r2'), _obj2);
        expect(r.state.rowObject(r.table, 'r1'), _obj);
      }
    });
  });

  group('stream2 end-to-end', () {
    UiStreamCompiler compile(Rig r) {
      final c = UiStreamCompiler(
        session: UiStreamSession(
          surfaceId: 's',
          revision: 1,
          snapshot: r.snapshot,
          intent: r.intent,
          catalog: r.catalog,
          root: 'root',
          protocolVersion: 'aiui-stream/2',
        ),
      );
      c.addLine(jsonEncode({
        'op': 'node',
        'id': 'root',
        'component': 'Page',
        'props': <String, Object?>{},
        'bind': <String, Object?>{},
      }));
      c.addLine(jsonEncode({
        'op': 'node',
        'id': 't',
        'component': 'Table',
        'parent': 'root',
        'props': <String, Object?>{},
        'bind': {
          'rows': {'kind': 'collection', 'id': 'rows'},
        },
      }));
      c.addLine('{"op":"end"}');
      return c;
    }

    test('valid collection reaches a final plan; broken one is rejected', () {
      final good = Rig(_snapshot());
      ok(good);
      final c = compile(good);
      expect(c.current.badLines, 0);
      expect(c.current.complete, isTrue);
      expect(c.current.finalPlan, isNotNull);

      final broken = Rig(_snapshot(collections: {
        'rows': _coll(
          columns: const [UiColumn('c1', 'A'), UiColumn('c2', 'B')],
        ),
      }));
      bad(broken);
      final d = compile(broken);
      expect(d.current.badLines, 0);
      expect(d.current.complete, isFalse);
      expect(d.current.finalPlan, isNull);
    });
  });
}
