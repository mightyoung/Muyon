import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/ui_formula_registry.dart';
import 'package:muyon/platform/ui_recompute_adapter.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

void main() {
  const ref = SnapshotRef('readonly', 4);
  const object = ObjectRef(moduleId: 'inquiry', objectType: 'item', objectId: 'a', revisionRef: '1');
  final definition = UiFormulaDefinition.product(computationId: 'cost:a', quantity: const UiFormulaSlot.uiState('qty', unit: '件'), unitPrice: const UiFormulaSlot.fact('price', object: object, field: 'price', unit: 'CNY/件'), currency: 'CNY', quantityUnit: '件', decimalPolicy: UiFormulaDecimalPolicy.supplierCoreUnsigned);
  final registry = UiFormulaRegistry(definitions: [definition], limits: const UiFormulaLimits(maxInputs: 32, maxDecimalBytes: 256, maxInputBytes: 16384));
  const token = UiPublishToken(baseSnapshotRef: ref, draftRevision: 7, hostGeneration: 8, sourceGeneration: 9, permissionGeneration: 10, scopeKey: 'selected:a');
  ValidatedUiPlan base({UiCatalog? catalog, UiEditSpec qtySpec = const UiStringEdit(), FactState state = FactState.verified, Object? price = '10', bool collection = true}) {
    final snapshot = DataSnapshot(ref: ref, facts: {'price': SnapshotFact(object: object, field: 'price', value: price, state: state, unit: 'CNY/件')}, initialUiState: {'qty': '2', 'scale': 2, 'expanded': false}, editSpecs: {'qty': qtySpec, 'scale': const UiNumberEdit(min: 0, max: 10, step: 1), 'expanded': const UiBoolEdit(view: true)}, computations: {'total': const ComputedValue(value: '20', inputVersion: ref, computationId: 'cost:a')}, computedEvidence: {'total': UiComputedEvidence(state: FactState.verified, unit: 'WRONG')}, actionContext: UiActionContext(draftRevision: 7, operations: {'old': HostOperationRef(draftRevision: 7, inputRefs: {'qty'})}), collections: {'costs': UiCollection(id: 'costs', columns: [const UiColumn('cost', 'Cost')], rows: [UiRow(itemId: 'a', cells: {'cost': const BindingRef.computed('total')})])});
    final intent = InteractionIntent(id: 'preview', purpose: 'readonly', snapshotRef: ref, requiredBindings: {const BindingRef.computed('total')}, allowedActionRefs: {'edit', 'submit', 'detail', 'back'});
    final cat = catalog ?? library2UiCatalog;
    final checked = validateUiPlan(UIPlan(surfaceId: 'preview', revision: 6, catalogVersion: cat.version, snapshotRef: ref, intentRef: intent.id, root: 'root', nodes: [UiNode(id: 'root', component: 'PageScaffold', properties: {'title': 'Preview'}, children: ['total']), UiNode(id: 'total', component: collection ? 'CompareTable' : 'Metric', properties: {'label': 'Cost'}, bindings: collection ? {'rows': const BindingRef.collection('costs')} : {'value': const BindingRef.computed('total')})]), snapshot, intent, cat);
    expect(checked.errors, isEmpty);
    return checked.validatedPlan!;
  }
  UiPreparedFormulaRecompute prepare(ValidatedUiPlan b, {Object? qty = '3', Object? scale = 3, Set<String> keys = const {'qty'}}) => UiFormulaRecomputeAdapter(basePlan: b, registry: registry, computations: {'total': definition}, parameterStateKeys: keys).prepare(UiRecomputeInput(previousSnapshot: b.snapshot, currentUiState: {'qty': qty, 'scale': scale, 'expanded': true}, token: token));
  test('library2 collection recomputes real value evidence and strips authority', () {
    final b = base(state: FactState.unverified);
    final p = prepare(b);
    expect(p.result.errors, isEmpty);
    final next = p.result.nextSnapshot!;
    expect(next.computations['total']!.value, '30');
    expect(next.computations['total']!.inputVersion, const SnapshotRef('readonly', 5));
    expect(p.evaluations['total']!.inputFingerprint, isNotEmpty);
    expect(p.evaluations['total']!.unverifiedInputs, ['unit_price']);
    expect(next.computedEvidence['total']!.state, FactState.unverified);
    expect(next.computedEvidence['total']!.unit, 'CNY');
    expect(next.collections['costs'], same(b.snapshot.collections['costs']));
    expect(next.editSpecs['scale'], same(b.snapshot.editSpecs['scale']));
    expect(next.initialUiState['qty'], '2');
    expect(next.actionContext, isNull);
    expect(p.result.nextIntent!.allowedActionRefs, {'edit', 'detail', 'back'});
    expect(p.result.token, same(token));
    expect(validateUiPlan(p.batch!.plan, next, p.batch!.intent, b.catalog).errors, isEmpty);
  });
  test('direct unavailable computation has fresh dependency evidence', () {
    final p = prepare(base(collection: false, state: FactState.readFailed, price: null));
    expect(p.result.errors, isEmpty);
    expect(p.result.nextSnapshot!.computations['total']!.value, isNull);
    expect(p.result.nextSnapshot!.computedEvidence['total']!.state, FactState.readFailed);
    expect(p.evaluations['total']!.errors, contains('fact_unavailable:unit_price'));
  });
  test('frozen typed state is validated before evaluator', () {
    final p = prepare(base(), scale: 11);
    expect(p.result.errors, ['recompute_state_rejected:scale:range']);
    expect(p.evaluations, isEmpty);
  });
  test('invalid string buffer is not an accepted input', () {
    final p = prepare(base(qtySpec: UiStringEdit(accepts: (v) => RegExp(r'^\d+$').hasMatch(v))), qty: 'oops');
    expect(p.result.errors, ['recompute_state_rejected:qty:format']);
    expect(p.evaluations, isEmpty);
  });
  test('catalog name alone cannot grant library2 support', () {
    final cat = UiCatalog(version: 'library-2', components: library2UiCatalog.components, actions: library2UiCatalog.actions);
    expect(prepare(base(catalog: cat)).result.errors, ['recompute_catalog_unavailable']);
  });
  test('view and undeclared formula parameters are refused', () {
    expect(prepare(base(), keys: {}).result.errors, ['formula_view_or_undeclared_parameter:qty']);
    expect(prepare(base(qtySpec: const UiStringEdit(view: true))).result.errors, ['formula_state_not_parameter_string_spec:qty']);
  });
}
