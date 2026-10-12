// Independent tests for library-2 recompute provenance and redaction.
//
// Candidate baseline: 940eaaf1da297b295bd15232db28463f8d212723 (review
// combination commit, not develop). Exercises the real
// UiFormulaRecomputeAdapter / UiLiveFormulaRecomputePort, the real
// UiFormulaRegistry evaluator, the real validateUiPlan validator, the real
// UiSurfaceController publication path and the real library-2
// DynamicUiSurface renderer together.
//
// Synthetic in-memory data only: no database, ledger, model or network.
// Every test names the production mutation it is expected to catch
// ("Catches:"). Paths are relative to apps/muyon/lib or packages/.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/ui_formula_registry.dart';
import 'package:muyon/platform/ui_recompute_adapter.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_ui/muyon_ui.dart' as ui;

const _ref = SnapshotRef('lib2-provenance', 4);
const _nextRef = SnapshotRef('lib2-provenance', 5);
const _artifact = ArtifactRef(
  moduleId: 'inquiry',
  artifactId: 'lib2-provenance-quote',
  contentDigest: 'lib2-provenance-digest',
);
const _limits = UiFormulaLimits(
  maxInputs: 32,
  maxDecimalBytes: 256,
  maxInputBytes: 16384,
);

/// Matches the evidence word "verified" but not "unverified".
final _verifiedWord = RegExp(r'(?<!un)verified');

SourceSpanRef _span(String text) => SourceSpanRef(
  artifact: _artifact,
  originalText: text,
  start: 0,
  end: text.length,
);

ObjectRef _obj(String id) => ObjectRef(
  moduleId: 'inquiry',
  objectType: 'quote_line',
  objectId: id,
  revisionRef: '1',
);

/// Host-shaped token: the draft revision is the live session/context
/// revision, as a real host probe reads it.
UiPublishToken _token(SnapshotRef base, {int draftRevision = 0}) =>
    UiPublishToken(
      baseSnapshotRef: base,
      draftRevision: draftRevision,
      hostGeneration: 1,
      sourceGeneration: 1,
      permissionGeneration: 1,
      scopeKey: 'lib2-provenance',
    );

SnapshotFact _fact(
  String object,
  String field,
  Object? value,
  FactState state, {
  required String unit,
  List<String> sources = const [],
}) => SnapshotFact(
  object: _obj(object),
  field: field,
  value: value,
  state: state,
  unit: unit,
  sourceRefs: sources,
);

UiFormulaDefinition _product(
  String computationId,
  String priceFact, {
  String object = 'a',
  String field = 'price',
}) => UiFormulaDefinition.product(
  computationId: computationId,
  quantity: const UiFormulaSlot.uiState('qty', unit: '件'),
  unitPrice: UiFormulaSlot.fact(
    priceFact,
    object: _obj(object),
    field: field,
    unit: 'CNY/件',
  ),
  currency: 'CNY',
  quantityUnit: '件',
  decimalPolicy: UiFormulaDecimalPolicy.supplierCoreUnsigned,
);

UiFormulaDefinition _sum(String computationId, Map<String, String> facts) =>
    UiFormulaDefinition.sum(
      computationId: computationId,
      amounts: {
        for (final e in facts.entries)
          e.key: UiFormulaSlot.fact(
            e.value,
            object: _obj(e.value),
            field: 'amount',
            unit: 'CNY',
          ),
      },
      unit: 'CNY',
      decimalPolicy: UiFormulaDecimalPolicy.supplierCoreUnsigned,
    );

UiNode _metric(String id, String computed, {String label = '行成本'}) => UiNode(
  id: id,
  component: 'Metric',
  properties: {'label': label},
  bindings: {'value': BindingRef.computed(computed)},
);

UiNode _table(String id, String collection) => UiNode(
  id: id,
  component: 'CompareTable',
  properties: {'label': '对比'},
  bindings: {'rows': BindingRef.collection(collection)},
);

UiCollection _costs(Map<String, String> rowToComputed) => UiCollection(
  id: 'costs',
  columns: [const UiColumn('cost', '成本')],
  rows: [
    for (final e in rowToComputed.entries)
      UiRow(itemId: e.key, cells: {'cost': BindingRef.computed(e.value)}),
  ],
);

/// A host-accepted library-2 base. Every [oldValues] entry is a previously
/// published computed result that claims `verified` with a stale unit and a
/// stale source, so any reuse is observable.
ValidatedUiPlan _base({
  required Map<String, SnapshotFact> facts,
  required Map<String, UiFormulaDefinition> defs,
  required Map<String, Object?> oldValues,
  required List<UiNode> nodes,
  Map<String, SourceSpanRef> sources = const {},
  Map<String, Object?> state = const {'qty': '2'},
  Map<String, UiEditSpec> specs = const {'qty': UiStringEdit()},
  Map<String, UiCollection> collections = const {},
  Set<BindingRef> required = const {},
  Set<FactState> mandatory = const {},
  Set<String> actions = const {'edit', 'detail', 'back'},
  UiActionContext? actionContext,
}) {
  final snapshot = DataSnapshot(
    ref: _ref,
    facts: facts,
    initialUiState: state,
    editSpecs: specs,
    sources: {'s-old': _span('旧来源 88'), ...sources},
    sourceDigests: {_artifact.artifactId: _artifact.contentDigest},
    computations: {
      for (final e in oldValues.entries)
        e.key: ComputedValue(
          value: e.value,
          inputVersion: _ref,
          computationId: defs[e.key]!.computationId,
        ),
    },
    computedEvidence: {
      for (final id in oldValues.keys)
        id: UiComputedEvidence(
          state: FactState.verified,
          unit: 'STALE',
          sourceRefs: ['s-old'],
        ),
    },
    collections: collections,
    actionContext: actionContext,
  );
  final intent = InteractionIntent(
    id: 'lib2-provenance-intent',
    purpose: 'readonly recompute',
    snapshotRef: _ref,
    requiredBindings: required,
    mandatoryStates: mandatory,
    allowedActionRefs: actions,
  );
  final checked = validateUiPlan(
    UIPlan(
      surfaceId: 'lib2-provenance',
      revision: 6,
      catalogVersion: library2UiCatalog.version,
      snapshotRef: _ref,
      intentRef: intent.id,
      root: 'root',
      nodes: [
        UiNode(
          id: 'root',
          component: 'PageScaffold',
          properties: {'title': '来源核对'},
          children: [for (final n in nodes) n.id],
        ),
        ...nodes,
      ],
    ),
    snapshot,
    intent,
    library2UiCatalog,
  );
  expect(checked.errors, isEmpty, reason: 'fixture must be host-accepted');
  return checked.validatedPlan!;
}

UiFormulaRegistry _registry(Map<String, UiFormulaDefinition> defs) =>
    UiFormulaRegistry(definitions: defs.values.toList(), limits: _limits);

UiPreparedFormulaRecompute _prepare(
  ValidatedUiPlan base,
  Map<String, UiFormulaDefinition> defs, {
  Map<String, Object?> state = const {},
  Set<String> keys = const {'qty'},
}) =>
    UiFormulaRecomputeAdapter(
      basePlan: base,
      registry: _registry(defs),
      computations: defs,
      parameterStateKeys: keys,
    ).prepare(
      UiRecomputeInput(
        previousSnapshot: base.snapshot,
        currentUiState: {...base.snapshot.initialUiState, ...state},
        token: _token(
          base.snapshot.ref,
          draftRevision: base.snapshot.actionContext?.draftRevision ?? 0,
        ),
      ),
    );

Future<UiSurfaceController> _mount(
  WidgetTester tester,
  ValidatedUiPlan base,
  Map<String, UiFormulaDefinition> defs, {
  Set<String> keys = const {'qty'},
  UiEventSink? onEvent,
}) async {
  late UiSurfaceController controller;
  controller = UiSurfaceController(
    base,
    onEvent: onEvent,
    recomputePort: UiLiveFormulaRecomputePort(
      currentPlan: () => controller.current,
      registry: _registry(defs),
      computations: defs,
      parameterStateKeys: keys,
    ),
    publishTokenProbe: () => _token(
      controller.current.snapshot.ref,
      draftRevision: controller.session.draftRevision,
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: ui.muyonTheme(Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: DynamicUiSurface(
            key: ObjectKey(controller),
            plan: controller.current,
            controller: controller,
          ),
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  group('1 notDisclosed never yields a visible value or verified result', () {
    // Catches (any one):
    //  M1a ui_recompute_adapter.dart:206-210 reuse `prior.value` when the
    //      evaluation is unavailable (old '88' would stay visible).
    //  M1b ui_recompute_adapter.dart:196-197 replace
    //      `unavailable.first.state` with FactState.verified (evidence/text
    //      would read "verified"; table mark would disappear).
    //  M1c ui_recompute_adapter.dart:202 or :215 carry
    //      previous.computedEvidence sourceRefs/unit (stale 's-old'/'STALE').
    //  M1d component_adapter.dart:220-222 marking only `unverified` cells
    //      (notDisclosed cell would lose its 未核验 semantics mark).
    testWidgets('rendered text and semantics show no value and no verified', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final defs = {
        'total': _product('cost:a', 'price'),
        'row_total': _product('cost:a-row', 'price'),
      };
      final base = _base(
        facts: {
          'price': _fact(
            'a',
            'price',
            null,
            FactState.notDisclosed,
            unit: 'CNY/件',
          ),
        },
        defs: defs,
        oldValues: {'total': '88', 'row_total': '88'},
        collections: {
          'costs': _costs({'a': 'row_total'}),
        },
        nodes: [
          _metric('metric', 'total'),
          _table('table', 'costs'),
          UiNode(
            id: 'kv',
            component: 'KeyValue',
            bindings: {'value': const BindingRef.fact('price')},
          ),
        ],
        required: {const BindingRef.computed('total')},
        mandatory: {FactState.notDisclosed},
      );
      final controller = await _mount(tester, base, defs);
      // Precondition: the stale verified value really is rendered before the
      // recompute, so its absence afterwards is meaningful.
      expect(find.textContaining('88'), findsWidgets);
      expect(find.textContaining(_verifiedWord), findsWidgets);

      expect(await controller.recompute(), UiPublishOutcome.published);
      await tester.pump();

      final next = controller.current.snapshot;
      expect(next.ref, _nextRef);
      for (final id in ['total', 'row_total']) {
        expect(next.computations[id]!.value, isNull, reason: id);
        expect(next.computations[id]!.inputVersion, _nextRef, reason: id);
        expect(next.computedEvidence[id]!.state, FactState.notDisclosed);
        expect(next.computedEvidence[id]!.unit, 'CNY');
        expect(next.computedEvidence[id]!.sourceRefs, isEmpty);
      }
      // Rendered text.
      expect(find.textContaining('88'), findsNothing);
      expect(find.textContaining(_verifiedWord), findsNothing);
      expect(find.textContaining('STALE'), findsNothing);
      expect(find.textContaining('s-old'), findsNothing);
      expect(
        find.text('total: 未提供 · notDisclosed · CNY · 来源未提供'),
        findsOneWidget,
      );
      expect(
        find.text('row_total: 未提供 · notDisclosed · CNY · 来源未提供'),
        findsOneWidget,
      );
      // Semantics of the real library-2 components.
      expect(find.bySemanticsLabel(RegExp('行成本：未提供')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('成本 未提供（未核验）')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('88')), findsNothing);
      expect(find.bySemanticsLabel(_verifiedWord), findsNothing);
      semantics.dispose();
    });

    // Catches: ui_formula_registry.dart:285-288 removed (a notDisclosed fact
    // that still carries a residual value would be multiplied: 2 x 7.77 =
    // 15.54, status ready, evidence verified).
    test('residual value on a notDisclosed fact is never computed', () {
      final defs = {'total': _product('cost:a', 'price')};
      final base = _base(
        facts: {
          'price': _fact(
            'a',
            'price',
            '7.77',
            FactState.notDisclosed,
            unit: 'CNY/件',
          ),
        },
        defs: defs,
        oldValues: {'total': '88'},
        nodes: [_metric('metric', 'total')],
      );
      final p = _prepare(base, defs);
      expect(p.result.errors, isEmpty);
      final next = p.result.nextSnapshot!;
      expect(p.evaluations['total']!.status, UiFormulaStatus.unavailable);
      expect(p.evaluations['total']!.value, isNull);
      expect(p.evaluations['total']!.errors, ['fact_unavailable:unit_price']);
      expect(next.computations['total']!.value, isNull);
      expect(next.computedEvidence['total']!.state, FactState.notDisclosed);
      expect(
        next.computations.values.map((v) => v.value),
        isNot(contains(anyOf('15.54', '88'))),
      );
    });
  });

  group('2 sourceRefs merge, unit and new snapshot version', () {
    // Catches (any one):
    //  M2a ui_recompute_adapter.dart:202-203 union over all previous.facts
    //      (unrelated 's-z' would appear) or drop dedupe/sort.
    //  M2b ui_recompute_adapter.dart:202 keep only the first fact's refs.
    //  M2c ui_recompute_adapter.dart:201 use slot/fact unit ('CNY/件' or
    //      '件') or previous evidence unit ('STALE') instead of output unit.
    //  M2d ui_recompute_adapter.dart:113/165 reuse previous.ref (inputVersion
    //      would equal the base ref; validator/resolve would hide the value).
    //  M2e surface.dart:189-203 or adapter :230-233 not advancing plan
    //      snapshotRef/revision.
    testWidgets('edited quantity publishes merged sorted sources', (
      tester,
    ) async {
      final defs = {
        'sum': _sum('sum:ab', {'first': 'p1', 'second': 'p2'}),
        'line': _product('line:c', 'p3', object: 'c'),
      };
      final base = _base(
        facts: {
          'p1': _fact(
            'p1',
            'amount',
            '1.5',
            FactState.verified,
            unit: 'CNY',
            sources: ['s-b', 's-a'],
          ),
          'p2': _fact(
            'p2',
            'amount',
            '2.25',
            FactState.verified,
            unit: 'CNY',
            sources: ['s-a', 's-c'],
          ),
          'p3': _fact(
            'c',
            'price',
            '2',
            FactState.verified,
            unit: 'CNY/件',
            sources: ['s-d', 's-c'],
          ),
          'z': _fact(
            'z',
            'note',
            'x',
            FactState.verified,
            unit: 'CNY',
            sources: ['s-z'],
          ),
        },
        sources: {
          for (final id in ['s-a', 's-b', 's-c', 's-d', 's-z'])
            id: _span('原文 $id'),
        },
        defs: defs,
        oldValues: {'sum': '88', 'line': '88'},
        nodes: [
          _metric('m-sum', 'sum', label: '合计'),
          _metric('m-line', 'line', label: '行'),
          UiNode(
            id: 'qty',
            component: 'Field',
            properties: {'label': '数量', 'inputType': 'text'},
            bindings: {
              'value': const BindingRef.fact('p3'),
              'draft': const BindingRef.uiState('qty'),
            },
            events: {
              'change': ActionBinding(actionRef: 'edit', inputRefs: ['qty']),
            },
          ),
        ],
      );
      final controller = await _mount(tester, base, defs);
      await tester.enterText(find.byKey(const ValueKey('qty-field')), '3');
      await tester.pump();
      await tester.pump();

      expect(controller.publicationErrors, isEmpty);
      final cur = controller.current;
      final next = cur.snapshot;
      expect(next.ref, _nextRef);
      expect(cur.plan.snapshotRef, _nextRef);
      expect(cur.intent.snapshotRef, _nextRef);
      expect(cur.plan.revision, 7);

      expect(next.computations['sum']!.value, '3.75');
      expect(next.computations['sum']!.inputVersion, _nextRef);
      expect(next.computedEvidence['sum']!.sourceRefs, ['s-a', 's-b', 's-c']);
      expect(next.computedEvidence['sum']!.unit, 'CNY');
      expect(next.computedEvidence['sum']!.state, FactState.verified);

      expect(next.computations['line']!.value, '6');
      expect(next.computations['line']!.inputVersion, _nextRef);
      expect(next.computedEvidence['line']!.sourceRefs, ['s-c', 's-d']);
      expect(next.computedEvidence['line']!.unit, 'CNY');

      expect(
        find.text('sum: 3.75 · verified · CNY · 来源 s-a、s-b、s-c'),
        findsOneWidget,
      );
      expect(
        find.text('line: 6 · verified · CNY · 来源 s-c、s-d'),
        findsOneWidget,
      );
      expect(find.textContaining('s-z'), findsNothing);
      expect(find.textContaining('s-old'), findsNothing);
      expect(find.textContaining('STALE'), findsNothing);
    });
  });

  group('3 unverified input never becomes verified', () {
    // Catches (any one):
    //  M3a ui_recompute_adapter.dart:198-200 always FactState.verified.
    //  M3b ui_formula_registry.dart:272 not recording unverified inputs.
    //  M3c adapter copying previous.computedEvidence[id].state (base says
    //      verified).
    //  M3d a second recompute laundering the state (checked by recomputing
    //      the already published candidate again).
    testWidgets('unverified price stays unverified across two recomputes', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final defs = {'row_total': _product('cost:a-row', 'price')};
      final base = _base(
        facts: {
          'price': _fact(
            'a',
            'price',
            '10',
            FactState.unverified,
            unit: 'CNY/件',
            sources: ['s-p'],
          ),
        },
        sources: {'s-p': _span('10')},
        defs: defs,
        oldValues: {'row_total': '20'},
        collections: {
          'costs': _costs({'a': 'row_total'}),
        },
        nodes: [_table('table', 'costs')],
      );
      final controller = await _mount(tester, base, defs);
      expect(
        find.text('row_total: 20 · verified · STALE · 来源 s-old'),
        findsOneWidget,
      );
      for (var round = 1; round <= 2; round++) {
        expect(await controller.recompute(), UiPublishOutcome.published);
        await tester.pump();
        final next = controller.current.snapshot;
        expect(next.ref, SnapshotRef(_ref.id, _ref.revision + round));
        expect(
          next.computedEvidence['row_total']!.state,
          FactState.unverified,
          reason: 'round $round',
        );
        expect(next.computations['row_total']!.value, '20');
        expect(
          find.text('row_total: 20 · unverified · CNY · 来源 s-p'),
          findsOneWidget,
        );
        expect(find.textContaining(_verifiedWord), findsNothing);
        expect(find.bySemanticsLabel(RegExp('成本 20（未核验）')), findsOneWidget);
      }
      semantics.dispose();
    });

    // Catches M3a/M3b for multi-input formulas, and an adapter that picks a
    // non-blocking state ahead of an unavailable dependency.
    test('mixed dependencies take the weakest state', () {
      final defs = {
        'sum': _sum('sum:ab', {'first': 'p1', 'second': 'p2'}),
      };
      ValidatedUiPlan withStates(FactState a, FactState b, Object? bValue) =>
          _base(
            facts: {
              'p1': _fact('p1', 'amount', '1', a, unit: 'CNY'),
              'p2': _fact('p2', 'amount', bValue, b, unit: 'CNY'),
            },
            defs: defs,
            oldValues: {'sum': '88'},
            nodes: [_metric('m', 'sum')],
          );
      final mixed = _prepare(
        withStates(FactState.verified, FactState.unverified, '2'),
        defs,
      );
      expect(mixed.result.errors, isEmpty);
      expect(mixed.evaluations['sum']!.unverifiedInputs, ['second']);
      expect(mixed.result.nextSnapshot!.computations['sum']!.value, '3');
      expect(
        mixed.result.nextSnapshot!.computedEvidence['sum']!.state,
        FactState.unverified,
      );
      final hidden = _prepare(
        withStates(FactState.unverified, FactState.notDisclosed, null),
        defs,
      );
      expect(hidden.result.errors, isEmpty);
      expect(hidden.result.nextSnapshot!.computations['sum']!.value, isNull);
      expect(
        hidden.result.nextSnapshot!.computedEvidence['sum']!.state,
        FactState.notDisclosed,
      );
    });
  });

  group('4 missing verified/unverified values reject with real diagnostics', () {
    // Catches (any one):
    //  M4a ui_recompute_adapter.dart:189-194 removed (candidate would be
    //      built with `unavailable.first` -> StateError, or a fabricated
    //      notApplicable/verified state).
    //  M4b ui_recompute_adapter.dart:189 replaced by a default
    //      FactState.notApplicable evidence.
    //  M4c ui_formula_registry.dart:293 diagnostic renamed/dropped.
    //  M4d surface.dart:182-186 publishing despite errors.
    for (final state in [FactState.verified, FactState.unverified]) {
      testWidgets('collection cell with ${state.name} null price is refused', (
        tester,
      ) async {
        final defs = {'row_total': _product('cost:a-row', 'price')};
        final base = _base(
          facts: {'price': _fact('a', 'price', null, state, unit: 'CNY/件')},
          defs: defs,
          oldValues: {'row_total': '88'},
          collections: {
            'costs': _costs({'a': 'row_total'}),
          },
          nodes: [_table('table', 'costs')],
        );
        final p = _prepare(base, defs, state: {'qty': '3'});
        expect(p.result.errors, ['recompute_unavailable_evidence:row_total']);
        expect(p.result.nextSnapshot, isNull);
        expect(p.result.nextIntent, isNull);
        expect(p.batch, isNull);
        expect(p.evaluations['row_total']!.status, UiFormulaStatus.unavailable);
        expect(p.evaluations['row_total']!.errors, [
          'missing_value:unit_price',
        ]);
        expect(p.result.errors.join(), isNot(contains('notApplicable')));

        final controller = await _mount(tester, base, defs);
        expect(await controller.recompute(), UiPublishOutcome.invalid);
        await tester.pump();
        expect(controller.current, same(base));
        expect(controller.outdated, isTrue);
        expect(controller.publicationErrors, ['recompute_failed']);
        expect(find.textContaining('notApplicable'), findsNothing);
      });
    }

    // Catches M4a/M4b on the tax path, and an evaluator that reports an
    // unsupported tax mode or a missing rate as an empty diagnostic.
    for (final sample in [
      ('unknown', '13', 'unsupported_tax_mode'),
      ('excluded', null, 'missing_tax_rate'),
    ]) {
      test('tax ${sample.$1}/${sample.$2} rejects with ${sample.$3}', () {
        UiFormulaSlot f(String id, String unit) =>
            UiFormulaSlot.fact(id, object: _obj('t'), field: id, unit: unit);
        final defs = {
          'tax': UiFormulaDefinition.taxPrice(
            computationId: 'tax:t',
            price: f('price', 'CNY/件'),
            currency: f('currency', 'currency'),
            taxMode: f('tax_mode', 'tax_mode'),
            taxRate: f('tax_rate', '%'),
            dealPrice: f('deal_price', 'CNY/件'),
            targetTaxMode: const UiFormulaSlot.uiState(
              'target',
              unit: 'tax_mode',
            ),
            targetCurrency: 'CNY',
            quoteUnit: '件',
          ),
        };
        SnapshotFact v(String id, Object? value, String unit) => SnapshotFact(
          object: _obj('t'),
          field: id,
          value: value,
          state: FactState.verified,
          unit: unit,
        );
        final base = _base(
          facts: {
            'price': v('price', '100', 'CNY/件'),
            'currency': v('currency', 'CNY', 'currency'),
            'tax_mode': v('tax_mode', sample.$1, 'tax_mode'),
            'tax_rate': v('tax_rate', sample.$2, '%'),
            'deal_price': v('deal_price', null, 'CNY/件'),
          },
          state: {'target': 'included'},
          specs: {'target': const UiStringEdit()},
          defs: defs,
          oldValues: {'tax': '88'},
          nodes: [_metric('m', 'tax')],
        );
        final p = _prepare(base, defs, keys: {'target'});
        expect(p.result.errors, ['recompute_unavailable_evidence:tax']);
        expect(p.batch, isNull);
        expect(p.evaluations['tax']!.errors, [sample.$3]);
      });
    }

    // KNOWN GAP (see report): when a verified input is missing its value but
    // another dependency is notDisclosed, the adapter accepts the candidate and
    // labels it notDisclosed; the verified input's missing value is only kept
    // in host diagnostics. Point 4 requires rejection. Production location:
    // ui_recompute_adapter.dart:184-194 (only rejects when *no* dependency has
    // an unavailable FactState). Catches, once fixed: masking a missing
    // verified value behind another dependency's state.
    test('verified null beside a notDisclosed dependency is refused', () {
      final defs = {
        'sum': _sum('sum:ab', {'first': 'p1', 'second': 'p2'}),
      };
      final base = _base(
        facts: {
          'p1': _fact('p1', 'amount', null, FactState.verified, unit: 'CNY'),
          'p2': _fact(
            'p2',
            'amount',
            null,
            FactState.notDisclosed,
            unit: 'CNY',
          ),
        },
        defs: defs,
        oldValues: {'sum': '88'},
        nodes: [_metric('m', 'sum')],
      );
      final p = _prepare(base, defs);
      expect(
        p.evaluations['sum']!.errors,
        containsAll(['missing_value:first', 'fact_unavailable:second']),
      );
      expect(p.result.errors, ['recompute_unavailable_evidence:sum']);
      expect(p.batch, isNull);
    });
  });

  group('5 stale/hidden results are not reused; authority stripped', () {
    final defs = {
      'total': _product('cost:a', 'price'),
      'hidden': _product('cost:hidden', 'price'),
    };
    ValidatedUiPlan authorityBase() => _base(
      facts: {
        'price': _fact(
          'a',
          'price',
          '2',
          FactState.verified,
          unit: 'CNY/件',
          sources: ['s-p'],
        ),
      },
      sources: {'s-p': _span('2')},
      defs: defs,
      oldValues: {'total': '88', 'hidden': '999'},
      nodes: [
        _metric('metric', 'total'),
        UiNode(
          id: 'chip',
          component: 'ObjectChip',
          properties: {'label': '报价行'},
          bindings: {'value': const BindingRef.fact('price')},
          events: {
            'tap': ActionBinding(actionRef: 'detail'),
            'back': ActionBinding(actionRef: 'back'),
          },
        ),
        UiNode(
          id: 'confirm',
          component: 'ConfirmCard',
          properties: {'label': '确认写入'},
          bindings: {'value': const BindingRef.fact('price')},
          events: {
            'confirm': ActionBinding(
              actionRef: 'confirm',
              inputRefs: ['qty'],
              operationKeyRef: 'op-confirm',
              expectedDraftRevision: 7,
            ),
            'cancel': ActionBinding(actionRef: 'cancel'),
          },
        ),
        UiNode(
          id: 'form',
          component: 'Form',
          properties: {'title': '旧写入'},
          events: {
            'submit': ActionBinding(
              actionRef: 'submit',
              inputRefs: ['qty'],
              operationKeyRef: 'op-submit',
              expectedDraftRevision: 7,
            ),
          },
        ),
      ],
      actions: {'edit', 'detail', 'back', 'submit', 'confirm', 'cancel'},
      actionContext: UiActionContext(
        draftRevision: 7,
        draft: {'qty': '2'},
        operations: {
          'op-submit': HostOperationRef(draftRevision: 7, inputRefs: {'qty'}),
          'op-confirm': HostOperationRef(draftRevision: 7, inputRefs: {'qty'}),
        },
      ),
    );

    // Catches (any one):
    //  M5a ui_recompute_adapter.dart:127-138 iterating `computations.keys`
    //      or previous.computations (hidden '999' would be re-emitted).
    //  M5b ui_recompute_adapter.dart:215 keeping previous.computedEvidence.
    //  M5c ui_recompute_adapter.dart:116-125 copying actionContext.
    //  M5d ui_recompute_adapter.dart:219-221 / :236-242 keeping business
    //      routes, or dropping local detail/back/cancel routes.
    test('adapter candidate drops hidden results and business authority', () {
      final base = authorityBase();
      final p = _prepare(base, defs, state: {'qty': '3'});
      expect(p.result.errors, isEmpty);
      final next = p.result.nextSnapshot!;
      expect(next.computations.keys, ['total']);
      expect(next.computedEvidence.keys, ['total']);
      expect(p.evaluations.keys, ['total']);
      expect(next.computations['total']!.value, '6');
      expect(next.computations['total']!.inputVersion, _nextRef);
      expect(
        next.computations['total'],
        isNot(same(base.snapshot.computations['total'])),
      );
      expect(next.computedEvidence['total']!.sourceRefs, ['s-p']);
      expect(next.actionContext, isNull);
      expect(p.result.nextIntent!.allowedActionRefs, {
        'edit',
        'detail',
        'back',
        'cancel',
      });
      final nodes = {for (final n in p.batch!.plan.nodes) n.id: n};
      final old = {for (final n in base.plan.nodes) n.id: n};
      expect(nodes['chip']!.events.keys, unorderedEquals(['tap', 'back']));
      expect(nodes['chip']!.events['tap'], same(old['chip']!.events['tap']));
      expect(nodes['chip']!.events['back'], same(old['chip']!.events['back']));
      expect(nodes['confirm']!.events.keys, ['cancel']);
      expect(nodes['form']!.events, isEmpty);
      expect(
        validateUiPlan(
          p.batch!.plan,
          next,
          p.batch!.intent,
          base.catalog,
        ).errors,
        isEmpty,
      );
    });

    // Catches: ui_recompute_adapter.dart:141-147 falling back to `prior`
    // when a displayed definition is missing or its computationId changed.
    test('displayed result without a matching definition is refused', () {
      final base = authorityBase();
      expect(_prepare(base, {'hidden': defs['hidden']!}).result.errors, [
        'recompute_computation_unregistered:total',
      ]);
      final renamed = {
        'total': _product('cost:a-v2', 'price'),
        'hidden': defs['hidden']!,
      };
      final p = _prepare(base, renamed);
      expect(p.result.errors, ['recompute_computation_unregistered:total']);
      expect(p.result.nextSnapshot, isNull);
    });

    // Catches: ui_recompute_adapter.dart:90-95 removed (an old base could
    // re-emit its result against a newer snapshot) and publication.dart:147-
    // 150 accepting a token for a superseded base.
    testWidgets('a superseded candidate cannot be published or rebuilt', (
      tester,
    ) async {
      final base = authorityBase();
      final controller = await _mount(tester, base, defs);
      final stale = _prepare(base, defs, state: {'qty': '9'});
      expect(stale.batch, isNotNull);
      expect(await controller.recompute(), UiPublishOutcome.published);
      final published = controller.current;
      // On this baseline the owner refuses it in the session rebase guard
      // (state.dart prepareRebase 'rebase_identity_or_revision' -> `invalid`)
      // before the coordinator token check; either way nothing is installed.
      expect(
        controller.publish(stale.batch!),
        isNot(UiPublishOutcome.published),
      );
      expect(controller.current, same(published));
      expect(published.snapshot.computations['total']!.value, '4');
      final crossed =
          UiFormulaRecomputeAdapter(
            basePlan: base,
            registry: _registry(defs),
            computations: defs,
            parameterStateKeys: {'qty'},
          ).prepare(
            UiRecomputeInput(
              previousSnapshot: published.snapshot,
              currentUiState: {'qty': '9'},
              token: _token(published.snapshot.ref, draftRevision: 7),
            ),
          );
      expect(crossed.result.errors, ['recompute_snapshot_mismatch']);

      // The bare coordinator names the reason: a token for a superseded base.
      final coordinator = UiPublicationCoordinator(base);
      final fresh = _prepare(base, defs, state: {'qty': '3'});
      expect(
        coordinator.publish(fresh.batch!, () => fresh.batch!.token),
        UiPublishOutcome.published,
      );
      expect(
        coordinator.publish(
          stale.batch!,
          () => _token(coordinator.current.snapshot.ref, draftRevision: 7),
        ),
        UiPublishOutcome.staleToken,
      );
      expect(coordinator.current.snapshot.computations['total']!.value, '6');
    });

    // Catches: surface.dart:193-201 / adapter :236-242 dropping local
    // navigation (detail/back would stop working after recompute) or keeping
    // the business submit (form would stay submittable; sink would fire).
    testWidgets('after recompute detail/back still navigate, submit is gone', (
      tester,
    ) async {
      final events = <UiEvent>[];
      final base = authorityBase();
      final controller = await _mount(
        tester,
        base,
        defs,
        onEvent: (e) async => events.add(e),
      );
      expect(
        base.plan.nodes.singleWhere((n) => n.id == 'form').events,
        contains('submit'),
      );
      expect(await controller.recompute(), UiPublishOutcome.published);
      await tester.pump();
      expect(controller.current.snapshot.actionContext, isNull);
      expect(
        controller.current.plan.nodes.singleWhere((n) => n.id == 'form').events,
        isEmpty,
      );
      expect(find.textContaining('88'), findsNothing);
      expect(find.textContaining('999'), findsNothing);
      expect(find.text('total: 4 · verified · CNY · 来源 s-p'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chip-detail')));
      await tester.pump();
      expect(controller.session.detailNode, 'chip');
      expect(find.text('Snapshot value: 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('detail-back')));
      await tester.pump();
      expect(controller.session.detailNode, isNull);
      expect(find.text('total: 4 · verified · CNY · 来源 s-p'), findsOneWidget);
      expect(events, isEmpty);
    });
  });
}
