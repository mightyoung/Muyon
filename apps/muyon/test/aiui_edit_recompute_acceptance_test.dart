import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/ui_formula_registry.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:supplier_core/supplier_core.dart';

import '../../../packages/supplier_core/test/fixtures.dart' as business;

// Test-first acceptance on current interfaces. The widget cases intentionally
// require the missing edit -> recompute -> publication behavior. No production
// adapter, future API, replacement evaluator, skip, or business write is used.
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
