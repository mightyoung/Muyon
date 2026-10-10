import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/ui_formula_registry.dart';
import 'package:muyon/platform/ui_recompute_adapter.dart';
// H2 public export is owner-controlled and absent from pinned PR21.
// ignore: implementation_imports
import 'package:muyon_module_api/src/ui/recomputation.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:supplier_core/supplier_core.dart';

import '../../../packages/supplier_core/test/fixtures.dart' as business;

// Test-first acceptance on current interfaces. The widget cases intentionally
// require the missing edit -> recompute -> publication behavior. No production
// publication shim, replacement evaluator, skip, or business write is used.
// Adapter cases exercise only candidate preparation through the fixed F5c port.
void main() {
  late Directory root;
  late Store store;
  late String projectId;
  late String itemId;
  late DataSnapshot snapshot;
  late UiFormulaDefinition definition;
  late UiFormulaRegistry registry;

  setUp(() {
    root = Directory.systemTemp.createTempSync('aiui-edit-recompute-');
    business.tmp = root;
    store = business.device('aiui-edit-recompute');
    addTearDown(() {
      store.close();
      root.deleteSync(recursive: true);
    });
    projectId = store.save('project', business.project('AIUI-RED'));
    itemId = store.save(
      'project_item',
      business.item(projectId, 'labor', name: '预算行 A', qty: '2', cost: '10'),
    );
    final item = store.get('project_item', itemId)!;
    final object = ObjectRef(
      moduleId: 'inquiry',
      objectType: 'project_item',
      objectId: item.id,
      revisionRef: item.version.toString(),
    );
    final unit = item.data['unit']! as String;
    final currency = store.get('project', projectId)!.data['currency']! as String;
    snapshot = DataSnapshot(
      ref: const SnapshotRef('budget-line-preview', 7),
      facts: {
        'qty_fact': SnapshotFact(
          object: object,
          field: 'qty',
          value: item.data['qty'],
          state: FactState.verified,
          unit: unit,
        ),
        'unit_cost': SnapshotFact(
          object: object,
          field: 'unit_cost',
          value: item.data['unit_cost'],
          state: FactState.verified,
          unit: '$currency/$unit',
        ),
      },
      initialUiState: {'qty': item.data['qty']},
    );
    definition = UiFormulaDefinition.product(
      computationId: 'budget-line-cost:$itemId',
      quantity: UiFormulaSlot.uiState('qty', unit: unit),
      unitPrice: UiFormulaSlot.fact(
        'unit_cost',
        object: object,
        field: 'unit_cost',
        unit: '$currency/$unit',
      ),
      currency: currency,
      quantityUnit: unit,
      decimalPolicy: UiFormulaDecimalPolicy.supplierCoreUnsigned,
    );
    registry = UiFormulaRegistry(
      definitions: [definition],
      limits: const UiFormulaLimits(
        maxInputs: 32,
        maxDecimalBytes: 256,
        maxInputBytes: 16384,
      ),
    );
    final initial = registry.evaluate(
      UiFormulaInvocation.forDefinition(definition, snapshot.ref),
      snapshot,
      snapshot.initialUiState,
    );
    expect(initial.status, UiFormulaStatus.ready);
    expect(initial.errors, isEmpty);
    expect(initial.value, '20'); // Independent fixed business example.
    snapshot = snapshot.copyWith(
      computations: {
        'total': ComputedValue(
          value: initial.value,
          inputVersion: initial.inputVersion,
          computationId: initial.computationId,
        ),
      },
    );
  });

  UiFormulaEvaluation evaluate(String quantity) => registry.evaluate(
    UiFormulaInvocation.forDefinition(definition, snapshot.ref),
    snapshot,
    Map<String, Object?>.unmodifiable({'qty': quantity}),
  );

  ValidatedUiPlan plan() {
    final intent = InteractionIntent(
      id: 'budget-line-preview-intent',
      purpose: '预览预算行成本；不写入业务',
      snapshotRef: snapshot.ref,
      requiredBindings: {const BindingRef.computed('total')},
      allowedActionRefs: {'edit'},
    );
    final result = validateUiPlan(
      UIPlan(
        surfaceId: 'budget-line-preview-surface',
        revision: 11,
        catalogVersion: minimalUiCatalog.version,
        snapshotRef: snapshot.ref,
        intentRef: intent.id,
        root: 'root',
        nodes: [
          UiNode(
            id: 'root',
            component: 'PageScaffold',
            properties: {'title': '预算行 A'},
            children: ['quantity', 'total'],
          ),
          UiNode(
            id: 'quantity',
            component: 'Field',
            properties: {'label': '数量'},
            bindings: {
              'value': const BindingRef.fact('qty_fact'),
              'draft': const BindingRef.uiState('qty'),
            },
            events: {
              'change': ActionBinding(actionRef: 'edit', inputRefs: ['qty']),
            },
          ),
          UiNode(
            id: 'total',
            component: 'Table',
            properties: {'label': '行成本'},
            bindings: {'value': const BindingRef.computed('total')},
          ),
        ],
      ),
      snapshot,
      intent,
      minimalUiCatalog,
    );
    expect(result.errors, isEmpty);
    return result.validatedPlan!;
  }

  test('real_f3a_has_fixed_20_30_40_business_results', () {
    // Constants remain independent of both evaluator and Store.budget.
    final fingerprints = <String>{};
    for (final sample in [('2', '20'), ('3', '30'), ('4', '40')]) {
      final result = evaluate(sample.$1);
      expect(result.status, UiFormulaStatus.ready);
      expect(result.errors, isEmpty);
      expect(result.value, sample.$2);
      expect(result.inputVersion, snapshot.ref);
      expect(result.computationId, definition.computationId);
      expect(result.inputFingerprint, isNotEmpty);
      fingerprints.add(result.inputFingerprint);
    }
    expect(fingerprints, hasLength(3));
    expect(store.budget(projectId, withWarnings: false).lines.single.cost, '20');
    expect(store.get('project_item', itemId)!.data['qty'], '2');
  });

  UiPublishToken token({SnapshotRef? base}) => UiPublishToken(
    baseSnapshotRef: base ?? snapshot.ref,
    draftRevision: 1,
    hostGeneration: 11,
    sourceGeneration: 12,
    permissionGeneration: 13,
    scopeKey: 'fixture-selected-item:$itemId',
  );

  UiFormulaRecomputeAdapter adapter({
    ValidatedUiPlan? base,
    UiFormulaRegistry? evaluator,
    Map<String, UiFormulaDefinition>? definitions,
    Set<String> parameterKeys = const {'qty'},
  }) => UiFormulaRecomputeAdapter(
    basePlan: base ?? plan(),
    registry: evaluator ?? registry,
    computations: definitions ?? {'total': definition},
    parameterStateKeys: parameterKeys,
  );

  UiRecomputeInput input(String qty, {UiPublishToken? captured}) =>
      UiRecomputeInput(
        previousSnapshot: snapshot,
        currentUiState: {'qty': qty},
        token: captured ?? token(),
      );

  test('adapter_prepares_fixed_30_40_with_new_ref_and_extracted_2', () async {
    final hostAdapter = adapter();
    final initialFingerprint = evaluate('2').inputFingerprint;
    for (final sample in [('3', '30'), ('4', '40')]) {
      final frozen = input(sample.$1);
      final prepared = hostAdapter.prepare(frozen);
      final next = prepared.result.nextSnapshot!;
      final batch = prepared.batch!;
      expect(prepared.result.errors, isEmpty);
      expect(prepared.result.token, same(frozen.token));
      expect(batch.token, same(frozen.token));
      expect(next.ref, const SnapshotRef('budget-line-preview', 8));
      expect(next.initialUiState['qty'], '2');
      expect(frozen.currentUiState['qty'], sample.$1);
      expect(next.computations['total']!.value, sample.$2);
      expect(next.computations['total']!.inputVersion, next.ref);
      expect(next.computations['total']!.computationId, definition.computationId);
      expect(prepared.evaluations['total']!.inputFingerprint, isNotEmpty);
      expect(prepared.evaluations['total']!.inputFingerprint, isNot(initialFingerprint));
      expect(batch.snapshot, same(next));
      expect(batch.intent, same(prepared.result.nextIntent));
      expect(batch.plan.revision, 12);
      expect(batch.plan.snapshotRef, next.ref);
      expect(batch.intent.snapshotRef, next.ref);
      expect(validateUiPlan(batch.plan, next, batch.intent, minimalUiCatalog).errors, isEmpty);
      final throughPort = await hostAdapter.rebuild(frozen);
      expect(throughPort.nextSnapshot!.computations['total']!.value, sample.$2);
      expect(throughPort.token, same(frozen.token));
      expect(snapshot.computations['total']!.value, '20');
      expect(store.get('project_item', itemId)!.data['qty'], '2');
    }
  });

  test('adapter_recomputes_all_displayed_instances_even_without_qty_dependency', () {
    final original = snapshot;
    final fixed = UiFormulaDefinition.product(
      computationId: 'fixed-original-cost:$itemId',
      quantity: UiFormulaSlot.fact(
        'qty_fact', object: original.facts['qty_fact']!.object,
        field: 'qty', unit: '件',
      ),
      unitPrice: definition.slots['unit_price']!,
      currency: 'CNY', quantityUnit: '件',
      decimalPolicy: UiFormulaDecimalPolicy.supplierCoreUnsigned,
    );
    snapshot = original.copyWith(computations: {
      ...original.computations,
      'fixed': ComputedValue(
        value: '999', // Deliberately poisoned old cache, not the business oracle.
        inputVersion: original.ref,
        computationId: fixed.computationId,
      ),
    });
    final base = plan();
    final raw = base.plan.copyWith(nodes: [
      base.plan.nodes.first.copyWith(children: ['quantity', 'total', 'fixed']),
      ...base.plan.nodes.skip(1),
      UiNode(
        id: 'fixed', component: 'Table', properties: {'label': '原始行成本'},
        bindings: {'value': const BindingRef.computed('fixed')},
      ),
    ]);
    final checked = validateUiPlan(raw, snapshot, base.intent, base.catalog);
    expect(checked.errors, isEmpty);
    final prepared = adapter(
      base: checked.validatedPlan!,
      evaluator: UiFormulaRegistry(definitions: [definition, fixed], limits: registry.limits),
      definitions: {'total': definition, 'fixed': fixed},
    ).prepare(input('3'));
    final next = prepared.result.nextSnapshot!;
    expect(next.computations['total']!.value, '30');
    expect(next.computations['fixed']!.value, '20'); // Fixed independent oracle.
    expect(next.computations.values.every((value) => value.inputVersion == next.ref), isTrue);
    expect(prepared.evaluations.keys, unorderedEquals(['total', 'fixed']));
    expect(prepared.evaluations['fixed']!.status, UiFormulaStatus.ready);
    expect(prepared.evaluations['fixed']!.inputFingerprint, isNotEmpty);
    expect(snapshot.computations['fixed']!.value, '999');
  });

  test('adapter_rejects_wrong_base_token_and_unregistered_instance', () {
    final prepared = adapter().prepare(input('3', captured: token(base: const SnapshotRef('other', 7))));
    expect(prepared.result.errors, ['recompute_token_snapshot_mismatch']);
    expect(prepared.batch, isNull);
    expect(prepared.evaluations, isEmpty);
    final missing = adapter(definitions: {}).prepare(input('3'));
    expect(missing.result.errors, ['recompute_computation_unregistered:total']);
    expect(missing.result.nextSnapshot, isNull);
    expect(snapshot.computations['total']!.value, '20');
  });

  test('adapter_blocks_view_or_nonstring_formula_state_before_evaluation', () {
    final view = adapter(parameterKeys: {}).prepare(input('3'));
    expect(view.result.errors, ['formula_view_or_undeclared_parameter:qty']);
    expect(view.evaluations, isEmpty);
    final number = adapter().prepare(UiRecomputeInput(
      previousSnapshot: snapshot, currentUiState: {'qty': 3}, token: token(),
    ));
    expect(number.result.errors, ['formula_state_not_string:qty']);
    expect(number.result.nextSnapshot, isNull);
    expect(number.evaluations, isEmpty);
  });

  test('adapter_real_unit_mismatch_keeps_legal_manual_qty_and_no_candidate', () {
    final price = snapshot.facts['unit_cost']!;
    snapshot = DataSnapshot(
      ref: snapshot.ref,
      facts: {
        ...snapshot.facts,
        'unit_cost': SnapshotFact(
          object: price.object, field: price.field, value: price.value,
          state: price.state, unit: 'USD/件',
        ),
      },
      initialUiState: snapshot.initialUiState,
      computations: snapshot.computations,
    );
    final frozen = input('3');
    final prepared = adapter().prepare(frozen);
    expect(prepared.result.errors, contains('total:unit_mismatch:unit_price'));
    expect(prepared.result.nextSnapshot, isNull);
    expect(prepared.batch, isNull);
    expect(prepared.evaluations['total']!.status, UiFormulaStatus.invalid);
    expect(frozen.currentUiState['qty'], '3');
    expect(snapshot.initialUiState['qty'], '2');
    expect(snapshot.computations['total']!.value, '20');
  });

  test('adapter_unavailable_prepares_null_candidate_without_old_success', () {
    final price = snapshot.facts['unit_cost']!;
    snapshot = DataSnapshot(
      ref: snapshot.ref,
      facts: {
        ...snapshot.facts,
        'unit_cost': SnapshotFact(
          object: price.object, field: price.field, value: null,
          state: FactState.notDisclosed, unit: price.unit,
        ),
      },
      initialUiState: snapshot.initialUiState,
      computations: snapshot.computations,
    );
    final prepared = adapter().prepare(input('3'));
    expect(prepared.result.errors, isEmpty);
    expect(prepared.result.nextSnapshot!.computations['total']!.value, isNull);
    expect(prepared.result.nextSnapshot!.facts['unit_cost']!.state, FactState.notDisclosed);
    expect(prepared.evaluations['total']!.status, UiFormulaStatus.unavailable);
    expect(prepared.evaluations['total']!.errors, contains('fact_unavailable:unit_price'));
    expect(prepared.result.nextSnapshot!.initialUiState['qty'], '2');
    expect(snapshot.computations['total']!.value, '20');
  });

  for (final sample in [('3', '30'), ('4', '40')]) {
    testWidgets('edit_qty_${sample.$1}_publishes_fixed_total_${sample.$2}', (
      tester,
    ) async {
      final controller = UiSurfaceController(plan());
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      });
      final businessChanges = store.db.select('SELECT total_changes() AS n').single['n'];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DynamicUiSurface(
                key: const ValueKey('mounted-budget-preview'),
                plan: controller.current,
                controller: controller,
              ),
            ),
          ),
        ),
      );
      expect(find.text('行成本: 20'), findsOneWidget);
      expect(controller.session.resolve(const BindingRef.computed('total')), '20');
      await tester.enterText(
        find.byKey(const ValueKey('quantity-field')),
        sample.$1,
      );
      await tester.pump();

      // Preconditions establish a real renderer event, an accepted parameter
      // edit, and no business effect before the missing publication assertion.
      expect(controller.session.userOverrides['qty'], sample.$1);
      expect(controller.session.resolve(const BindingRef.uiState('qty')), sample.$1);
      expect(controller.session.draftRevision, 1);
      expect(
        tester.widget<DynamicUiSurface>(find.byType(DynamicUiSurface)).controller,
        same(controller),
      );
      expect(store.get('project_item', itemId)!.data['qty'], '2');
      expect(store.budget(projectId, withWarnings: false).lines.single.cost, '20');
      expect(store.db.select('SELECT total_changes() AS n').single['n'], businessChanges);
      final frozenState = Map<String, Object?>.unmodifiable({
        for (final key in snapshot.initialUiState.keys)
          key: controller.session.resolve(BindingRef.uiState(key)),
      });
      final candidate = registry.evaluate(
        UiFormulaInvocation.forDefinition(definition, snapshot.ref),
        snapshot,
        frozenState,
      );
      expect(candidate.status, UiFormulaStatus.ready);
      expect(candidate.value, sample.$2); // Fixed 30/40, not another evaluator.
      expect(tester.takeException(), isNull);

      // Expected RED on the baseline: actual remains '20'. This is a desired
      // behavior assertion, never an assertion that the missing feature works.
      expect(
        controller.session.resolve(const BindingRef.computed('total')),
        sample.$2,
        reason: 'Accepted quantity edit must publish the recomputed total on '
            'the mounted surface; evaluating a detached candidate is insufficient.',
      );
      expect(find.text('行成本: ${sample.$2}'), findsOneWidget);
    });
  }
}
