// Post-review regressions. Fixture helpers adapted from PR57; its file is preserved.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/ui_formula_registry.dart';
import 'package:muyon/platform/ui_recompute_adapter.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_ui/muyon_ui.dart' as ui;

const _ref = SnapshotRef('lib2-provenance', 4);
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
  UiCatalog? catalog,
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
      catalogVersion: (catalog ?? library2UiCatalog).version,
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
    catalog ?? library2UiCatalog,
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
  Completer<void>? release,
  bool Function()? readOnlyProbe,
  int pauseAfter = 0,
}) async {
  late UiSurfaceController controller;
  controller = UiSurfaceController(
    base,
    onEvent: onEvent,
    readOnlyProbe: readOnlyProbe,
    recomputePort: _PausedPort(
      release,
      UiLiveFormulaRecomputePort(
        currentPlan: () => controller.current,
        registry: _registry(defs),
        computations: defs,
        parameterStateKeys: keys,
      ),
      pauseAfter,
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

final class _PausedPort implements UiRecomputePort {
  _PausedPort(this.release, this.delegate, [this.pauseAfter = 0]);
  final Completer<void>? release;
  final UiRecomputePort delegate;
  final int pauseAfter;
  int calls = 0;
  @override
  Future<UiRecomputeResult> rebuild(UiRecomputeInput input) async {
    if (++calls > pauseAfter && release != null) await release!.future;
    return delegate.rebuild(input);
  }
}

ValidatedUiPlan _recoveryBase() {
  final defs = {'total': _product('cost:a', 'price')};
  return _base(
    facts: {
      'price': _fact('a', 'price', '7', FactState.verified, unit: 'CNY/件'),
    },
    defs: defs,
    oldValues: {'total': '88'},
    state: {'qty': '', 'sort': 'original', 'expanded': false},
    specs: {
      'qty': const UiStringEdit(),
      'sort': const UiStringEdit(view: true),
      'expanded': const UiBoolEdit(view: true),
    },
    actions: {'edit', 'submit', 'sort', 'detail', 'back'},
    actionContext: UiActionContext(
      draftRevision: 0,
      draft: {'qty': ''},
      operations: {
        'old': HostOperationRef(draftRevision: 0, inputRefs: {'qty'}),
      },
    ),
    nodes: [
      _metric('metric', 'total'),
      UiNode(
        id: 'toggle',
        component: 'Toggle',
        properties: {'label': 'Expanded'},
        bindings: {'value': const BindingRef.uiState('expanded')},
        events: {
          'change': ActionBinding(actionRef: 'edit', inputRefs: ['expanded']),
        },
      ),
      UiNode(
        id: 'qty',
        component: 'Field',
        properties: {'label': 'Quantity'},
        bindings: {
          'value': const BindingRef.fact('price'),
          'draft': const BindingRef.uiState('qty'),
        },
        events: {
          'change': ActionBinding(actionRef: 'edit', inputRefs: ['qty']),
        },
      ),
      UiNode(
        id: 'sort',
        component: 'SegmentedPill',
        bindings: {'selected': const BindingRef.uiState('sort')},
        events: {
          'change': ActionBinding(actionRef: 'sort', inputRefs: ['sort']),
        },
      ),
      UiNode(
        id: 'submit',
        component: 'Form',
        properties: {'title': 'Submit'},
        events: {
          'submit': ActionBinding(
            actionRef: 'submit',
            inputRefs: ['qty'],
            operationKeyRef: 'old',
            expectedDraftRevision: 0,
          ),
        },
      ),
    ],
  );
}

void main() {
  testWidgets(
    'host-owned pending cancel is reachable in actual UI and labels retained results cancelled',
    (tester) async {
      var business = 0;
      var readonly = false;
      final release = Completer<void>();
      final defs = {'total': _product('cost:a', 'price')};
      final base = _recoveryBase();
      final controller = await _mount(
        tester,
        base,
        defs,
        release: release,
        readOnlyProbe: () => readonly,
        onEvent: (_) async {
          business++;
        },
      );
      final pending = controller.recompute();
      await tester.pump();
      final cancel = find.byKey(const ValueKey('ui-host-cancel-recompute'));
      expect(cancel, findsOneWidget);
      readonly = true;
      controller.notifyListeners();
      await tester.pump();
      expect(tester.widget<OutlinedButton>(cancel).onPressed, isNull);
      controller.cancelRecompute();
      expect(controller.recomputing,isTrue);
      readonly = false;
      controller.notifyListeners();
      await tester.pump();
      await tester.tap(cancel);
      await tester.pump();
      expect(find.textContaining('已取消重算'), findsOneWidget);
      expect(cancel, findsNothing);
      expect(controller.outdated, isTrue);
      final submit = controller.current.plan.nodes.singleWhere(
        (n) => n.id == 'submit',
      );
      expect(
        await controller.dispatchCaptured(
          controller.captureRender(),
          submit,
          'submit',
        ),
        UiDispatchOutcome.stale,
      );
      release.complete();
      expect(await pending, UiPublishOutcome.staleToken);
      await tester.pump();
      expect(controller.current, same(base));
      expect(find.textContaining('已取消重算'), findsOneWidget);
      expect(business, 0);
    },
  );

  testWidgets(
    'cancelled candidate cannot publish or clear visible stale results',
    (tester) async {
      final release = Completer<void>();
      final defs = {'total': _product('cost:a', 'price')};
      final base = _base(
        facts: {
          'price': _fact('a', 'price', '7', FactState.verified, unit: 'CNY/件'),
        },
        defs: defs,
        oldValues: {'total': '88'},
        nodes: [_metric('metric', 'total')],
      );
      final controller = await _mount(tester, base, defs, release: release);
      final pending = controller.recompute();
      await tester.pump();
      controller.cancelRecompute();
      await tester.pump();
      expect(find.textContaining('已取消重算'), findsOneWidget);
      release.complete();
      expect(await pending, UiPublishOutcome.staleToken);
      await tester.pump();
      expect(controller.current, same(base));
      expect(controller.outdated, isTrue);
      expect(find.textContaining('上次结果：88'), findsWidgets);
    },
  );

  testWidgets(
    'permission withdrawn while pending cannot publish even with unchanged token',
    (tester) async {
      var readonly = false;
      final release = Completer<void>();
      final defs = {'total': _product('cost:a', 'price')};
      final base = _base(
        facts: {
          'price': _fact('a', 'price', '7', FactState.verified, unit: 'CNY/件'),
        },
        defs: defs,
        oldValues: {'total': '88'},
        nodes: [_metric('metric', 'total')],
      );
      final controller = await _mount(
        tester,
        base,
        defs,
        release: release,
        readOnlyProbe: () => readonly,
      );
      final pending = controller.recompute();
      await tester.pump();
      readonly = true;
      release.complete();
      expect(await pending, UiPublishOutcome.invalid);
      await tester.pump();
      expect(controller.current, same(base));
      expect(controller.outdated, isTrue);
    },
  );
  testWidgets(
    'continuous safe edits keep newest result and reject late prior candidate',
    (tester) async {
      var business = 0;
      final release = Completer<void>();
      final defs = {'total': _product('cost:a', 'price')};
      final controller = await _mount(
        tester,
        _recoveryBase(),
        defs,
        release: release,
        pauseAfter: 1,
        onEvent: (_) async {
          business++;
        },
      );
      expect(await controller.recompute(), UiPublishOutcome.invalid);
      await tester.pump();
      final capture = controller.captureRender();
      final node = controller.current.plan.nodes.singleWhere(
        (n) => n.id == 'qty',
      );
      expect(
        await controller.dispatchCaptured(capture, node, 'change', '3'),
        UiDispatchOutcome.applied,
      );
      expect(
        await controller.dispatchCaptured(capture, node, 'change', '4'),
        UiDispatchOutcome.applied,
      );
      final submit = controller.current.plan.nodes.singleWhere(
        (n) => n.id == 'submit',
      );
      expect(
        await controller.dispatchCaptured(capture, submit, 'submit'),
        UiDispatchOutcome.stale,
      );
      controller.adoptExtracted('qty');
      expect(controller.session.userOverrides['qty'], '4');
      await tester.pump();
      expect(find.textContaining('正在重算'), findsOneWidget);
      release.complete();
      await tester.pumpAndSettle();
      expect(controller.current.snapshot.computations['total']!.value, '28');
      expect(controller.outdated, isFalse);
      expect(business, 0);
    },
  );

  testWidgets(
    'stale result permits only valid local edit recovery and no business or view dispatch',
    (tester) async {
      var business = 0;
      var readonly = false;
      final defs = {'total': _product('cost:a', 'price')};
      final base = _recoveryBase();
      final controller = await _mount(
        tester,
        base,
        defs,
        onEvent: (_) async {
          business++;
        },
        readOnlyProbe: () => readonly,
      );
      expect(await controller.recompute(), UiPublishOutcome.invalid);
      await tester.pump();
      final capture = controller.captureRender();
      UiNode node(String id) =>
          controller.current.plan.nodes.singleWhere((n) => n.id == id);
      final initial = controller.session.draftRevision;
      expect(controller.allowsInteraction(node('qty'), 'change'), isTrue);
      expect(controller.allowsInteraction(node('toggle'), 'change'), isFalse);
      expect(
        await controller.dispatchCaptured(
          capture,
          node('toggle'),
          'change',
          true,
        ),
        UiDispatchOutcome.stale,
      );
      expect(
        controller.session.resolve(const BindingRef.uiState('expanded')),
        false,
      );
      expect(
        await controller.dispatchCaptured(capture, node('submit'), 'submit'),
        UiDispatchOutcome.stale,
      );
      expect(
        await controller.dispatchCaptured(
          capture,
          node('sort'),
          'change',
          'value',
        ),
        UiDispatchOutcome.stale,
      );
      controller.adoptExtracted('qty');
      expect(controller.session.draftRevision, initial);
      expect(
        await controller.dispatchCaptured(capture, node('qty'), 'change', 3),
        UiDispatchOutcome.invalid,
      );
      expect(controller.session.draftRevision, initial);
      expect(controller.outdated, isTrue);
      readonly = true;
      expect(
        await controller.dispatchCaptured(capture, node('qty'), 'change', '3'),
        UiDispatchOutcome.stale,
      );
      readonly = false;
      expect(
        await controller.dispatchCaptured(capture, node('qty'), 'change', '3'),
        UiDispatchOutcome.applied,
      );
      await tester.pumpAndSettle();
      expect(controller.current.snapshot.computations['total']!.value, '21');
      expect(controller.outdated, isFalse);
      expect(controller.recomputing, isFalse);
      expect(find.textContaining('上次发布版本'), findsNothing);
      expect(business, 0);
    },
  );
  testWidgets(
    'stale computed metric and collection cell each identify their prior result',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final defs = {
        'total': _product('cost:a', 'price'),
        'row_total': _product('cost:row', 'price'),
      };
      final base = _base(
        facts: {
          'price': _fact('a', 'price', null, FactState.verified, unit: 'CNY/件'),
        },
        defs: defs,
        oldValues: {'total': '88', 'row_total': '88'},
        collections: {
          'costs': _costs({'a': 'row_total'}),
        },
        nodes: [_metric('metric', 'total'), _table('table', 'costs')],
      );
      final controller = await _mount(tester, base, defs);
      expect(await controller.recompute(), UiPublishOutcome.invalid);
      await tester.pump();
      expect(find.textContaining('上次结果：88'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('aiui2-table')),
          matching: find.bySemanticsLabel(RegExp('第 1 行.*上次结果：88')),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('上次来源：verified'), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('上次结果：88')), findsWidgets);
      expect(
        controller.current.snapshot.computedEvidence['total']!.state,
        FactState.verified,
      );
      expect(
        controller.session.resolve(const BindingRef.computed('total')),
        '88',
      );
      semantics.dispose();
    },
  );
  testWidgets('host error diagnostics are not displayed verbatim', (
    tester,
  ) async {
    final defs = {'total': _product('cost:a', 'price')};
    final controller = await _mount(tester, _recoveryBase(), defs);
    controller.portError = 'RAW_HOST_ERROR_CANARY_9481';
    controller.notifyListeners();
    await tester.pump();
    expect(find.textContaining('RAW_HOST_ERROR_CANARY_9481'), findsNothing);
    expect(find.textContaining('操作未完成'), findsOneWidget);
  });

  testWidgets(
    'pending calculation marks old results and successful publication clears notice',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final defs = {'total': _product('cost:a', 'price')};
      final base = _base(
        facts: {
          'price': _fact('a', 'price', '7', FactState.verified, unit: 'CNY/件'),
        },
        defs: defs,
        oldValues: {'total': '88'},
        nodes: [_metric('metric', 'total')],
      );
      final release = Completer<void>();
      final controller = await _mount(tester, base, defs, release: release);
      final pending = controller.recompute();
      await tester.pump();
      expect(controller.recomputing, isTrue);
      expect(find.textContaining('正在重算'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('正在重算')), findsWidgets);
      release.complete();
      expect(await pending, UiPublishOutcome.published);
      await tester.pump();
      expect(find.textContaining('上次发布版本'), findsNothing);
      expect(controller.current.snapshot.computations['total']!.value, '14');
      semantics.dispose();
    },
  );

  test(
    'collection missing row rejects whole batch even with ready sibling',
    () {
      final defs = {
        'total': _product('cost:a', 'ready'),
        'row_total': _product('cost:row', 'missing'),
      };
      final base = _base(
        facts: {
          'ready': _fact('a', 'price', '7', FactState.verified, unit: 'CNY/件'),
          'missing': _fact(
            'a',
            'price',
            null,
            FactState.verified,
            unit: 'CNY/件',
          ),
        },
        defs: defs,
        oldValues: {'total': '88', 'row_total': '88'},
        collections: {
          'costs': _costs({'a': 'row_total'}),
        },
        nodes: [_metric('metric', 'total'), _table('table', 'costs')],
      );
      final prepared = _prepare(base, defs);
      expect(prepared.result.errors, [
        'recompute_unavailable_evidence:row_total',
      ]);
      expect(prepared.result.nextSnapshot, isNull);
      expect(prepared.batch, isNull);
      expect(base.snapshot.computations['total']!.value, '88');
    },
  );
  test(
    'unknown target tax mode with verified facts rejects domain evidence',
    () {
      final fields = {
        'price': ('107', 'CNY/件'),
        'currency': ('CNY', 'currency'),
        'tax_mode': ('included', 'tax_mode'),
        'tax_rate': ('7', '%'),
        'deal_price': ('107', 'CNY/件'),
      };
      UiFormulaSlot slot(String name) => UiFormulaSlot.fact(
        name,
        object: _obj('a'),
        field: name,
        unit: fields[name]!.$2,
      );
      final def = UiFormulaDefinition.taxPrice(
        computationId: 'tax',
        price: slot('price'),
        currency: slot('currency'),
        taxMode: slot('tax_mode'),
        taxRate: slot('tax_rate'),
        dealPrice: slot('deal_price'),
        targetTaxMode: const UiFormulaSlot.uiState('target', unit: 'tax_mode'),
        targetCurrency: 'CNY',
        quoteUnit: '件',
      );
      final defs = {'total': def};
      final base = _base(
        facts: {
          for (final entry in fields.entries)
            entry.key: _fact(
              'a',
              entry.key,
              entry.value.$1,
              FactState.verified,
              unit: entry.value.$2,
            ),
        },
        defs: defs,
        oldValues: {'total': '88'},
        state: {'target': 'unknown'},
        specs: {'target': const UiStringEdit()},
        nodes: [_metric('metric', 'total')],
      );
      expect(_prepare(base, defs, keys: {'target'}).result.errors, [
        'recompute_unavailable_evidence:total',
      ]);
    },
  );
  test('empty collection does not recompute undisplayed historical result', () {
    final defs = {'total': _product('cost:a', 'price')};
    final base = _base(
      facts: {
        'price': _fact('a', 'price', '7', FactState.verified, unit: 'CNY/件'),
      },
      defs: defs,
      oldValues: {'total': '88'},
      collections: {'costs': _costs({})},
      nodes: [_table('table', 'costs')],
    );
    final prepared = _prepare(base, defs);
    expect(prepared.result.errors, isEmpty);
    expect(prepared.result.nextSnapshot!.computations, isEmpty);
    expect(prepared.result.nextSnapshot!.computedEvidence, isEmpty);
  });

  for (final version in ['minimal-1', 'dynamic-1', 'library-2']) {
    test(
      'same-name forged catalog $version cannot obtain recompute support',
      () {
        final defs = {'total': _product('cost:a', 'price')};
        final base = _base(
          catalog: UiCatalog(
            version: version,
            components: library2UiCatalog.components,
            actions: library2UiCatalog.actions,
          ),
          facts: {
            'price': _fact(
              'a',
              'price',
              '7',
              FactState.verified,
              unit: 'CNY/件',
            ),
          },
          defs: defs,
          oldValues: {'total': '88'},
          nodes: [_metric('metric', 'total')],
        );
        expect(_prepare(base, defs).result.errors, [
          'recompute_catalog_unavailable',
        ]);
      },
    );
  }
  ValidatedUiPlan sumBase(
    Map<String, SnapshotFact> facts,
    Map<String, UiFormulaDefinition> defs,
  ) => _base(
    facts: facts,
    defs: defs,
    oldValues: {'sum': '88'},
    nodes: [_metric('metric', 'sum')],
  );
  test(
    'missing verified value cannot be masked by notDisclosed dependency',
    () {
      final defs = {
        'sum': _sum('sum', {'a': 'a', 'b': 'b'}),
      };
      final base = sumBase({
        'a': _fact('a', 'amount', null, FactState.verified, unit: 'CNY'),
        'b': _fact('b', 'amount', null, FactState.notDisclosed, unit: 'CNY'),
      }, defs);
      final prepared = _prepare(base, defs);
      expect(prepared.evaluations['sum']!.errors, contains('missing_value:a'));
      expect(prepared.result.errors, ['recompute_unavailable_evidence:sum']);
      expect(prepared.result.nextSnapshot, isNull);
      expect(prepared.batch, isNull);
    },
  );
  test(
    'read failure dominates non-applicability independently of slot ordering',
    () {
      for (final swap in [false, true]) {
        final defs = {
          'sum': _sum('sum', {
            'a': swap ? 'failed' : 'na',
            'b': swap ? 'na' : 'failed',
          }),
        };
        final base = sumBase({
          'na': _fact(
            'na',
            'amount',
            null,
            FactState.notApplicable,
            unit: 'CNY',
          ),
          'failed': _fact(
            'failed',
            'amount',
            null,
            FactState.readFailed,
            unit: 'CNY',
          ),
        }, defs);
        expect(
          _prepare(
            base,
            defs,
          ).result.nextSnapshot!.computedEvidence['sum']!.state,
          FactState.readFailed,
        );
      }
    },
  );
  test('undeclared state key is rejected before evaluation', () {
    final defs = {'total': _product('cost:a', 'price')};
    final base = _base(
      facts: {
        'price': _fact('a', 'price', '7', FactState.verified, unit: 'CNY/件'),
      },
      defs: defs,
      oldValues: {'total': '88'},
      nodes: [_metric('metric', 'total')],
    );
    expect(
      () =>
          _prepare(base, defs, state: {'undeclared': 'CANARY_EXTRA_STATE_617'}),
      throwsArgumentError,
    );
  });
  testWidgets(
    'failed batch visibly and semantically marks old verified result stale',
    (tester) async {
      final semantics = tester.ensureSemantics();

      final defs = {
        'total': _product('cost:a', 'price'),
        'row_total': _product('cost:row', 'price'),
      };
      final base = _base(
        facts: {
          'price': _fact('a', 'price', null, FactState.verified, unit: 'CNY/件'),
        },
        defs: defs,
        oldValues: {'total': '88', 'row_total': '88'},
        collections: {
          'costs': _costs({'a': 'row_total'}),
        },
        nodes: [_metric('metric', 'total'), _table('table', 'costs')],
      );
      final controller = await _mount(tester, base, defs);
      expect(find.textContaining('88'), findsWidgets);
      expect(await controller.recompute(), UiPublishOutcome.invalid);
      await tester.pump();
      expect(controller.current, same(base));
      expect(controller.outdated, isTrue);
      expect(find.textContaining('结果已过期'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('结果已过期')), findsWidgets);
      // Prior evidence remains inspectable, explicitly qualified by the stale notice.
      expect(find.textContaining('上次发布版本'), findsOneWidget);
      semantics.dispose();
    },
  );
}
