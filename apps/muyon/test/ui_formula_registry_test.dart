import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/ui_formula_registry.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:supplier_core/src/pricing.dart' as pricing;
import 'package:supplier_core/supplier_core.dart';

import '../../../packages/supplier_core/test/fixtures.dart' as fixtures;
import 'ui_formula_registry_mutation_fixture.dart' as mutation_fixture;

const object = ObjectRef(moduleId: 'inquiry', objectType: 'quotation', objectId: 'q1', revisionRef: 'r1');
const limits = UiFormulaLimits(maxInputs: 32, maxDecimalBytes: 256, maxInputBytes: 16384);
const domainDecimal = UiFormulaDecimalPolicy.supplierCoreUnsigned;
const version = SnapshotRef('formula-fixture', 1);
UiFormulaSlot fact(String id, String unit) => UiFormulaSlot.fact(id, object: object, field: id, unit: unit);
SnapshotFact value(String id, Object? v, String unit, {FactState state = FactState.verified, ObjectRef identity = object}) => SnapshotFact(object: identity, field: id, value: v, state: state, unit: unit);
DataSnapshot snapshot(Map<String, SnapshotFact> facts, {Map<String, Object?> state = const {}, SnapshotRef ref = version}) => DataSnapshot(ref: ref, facts: facts, initialUiState: state);
UiFormulaEvaluation evaluate(UiFormulaDefinition d, DataSnapshot s, {Map<String, Object?>? state, UiFormulaInvocation? invocation}) => UiFormulaRegistry(definitions: [d], limits: limits).evaluate(invocation ?? UiFormulaInvocation.forDefinition(d, s.ref), s, state ?? s.initialUiState);
UiFormulaDefinition sum({int n = 2, String unit = 'CNY', bool allowEmpty = false}) => UiFormulaDefinition.sum(computationId: 'total', amounts: {for (var i = 0; i < n; i++) 'a$i': fact('a$i', unit)}, unit: unit, decimalPolicy: domainDecimal, allowEmpty: allowEmpty);
UiFormulaDefinition product() => UiFormulaDefinition.product(computationId: 'line', quantity: const UiFormulaSlot.uiState('qty', unit: '件'), unitPrice: fact('price', 'CNY/件'), currency: 'CNY', quantityUnit: '件', decimalPolicy: domainDecimal);
UiFormulaDefinition tax({String currency = 'CNY'}) => UiFormulaDefinition.taxPrice(computationId: 'tax', price: fact('price', '$currency/件'), currency: fact('currency', 'currency'), taxMode: fact('tax_mode', 'tax_mode'), taxRate: fact('tax_rate', '%'), dealPrice: fact('deal_price', '$currency/件'), targetTaxMode: const UiFormulaSlot.uiState('target', unit: 'tax_mode'), targetCurrency: 'CNY', quoteUnit: '件');
DataSnapshot quote({String price = '100', String currency = 'CNY', String mode = 'excluded', Object? rate = '13', Object? deal, String target = 'included'}) => snapshot({'price': value('price', price, '$currency/件'), 'currency': value('currency', currency, 'currency'), 'tax_mode': value('tax_mode', mode, 'tax_mode'), 'tax_rate': value('tax_rate', rate, '%'), 'deal_price': value('deal_price', deal, '$currency/件')}, state: {'target': target});
void ready(UiFormulaEvaluation result, String expected, String unit) {
  expect(result.status, UiFormulaStatus.ready);
  expect(result.value, expected);
  expect(result.unit, unit);
  expect(result.errors, isEmpty);
  expect(result.inputVersion, version);
}
void rejected(UiFormulaEvaluation result, UiFormulaStatus status, String code) {
  expect(result.status, status);
  expect(result.value, isNull);
  expect(result.errors, contains(code));
}

void main() {
  for (final name in ['sum_decimal_exact_and_unit_checked', 'stale_input_version_not_published', 'unknown_formula_rejected', 'unknown_ref_rejected']) {
    test('shared mutation fixture: $name', () => mutation_fixture.verifyFormulaMutationFixture(name));
  }
  test('sum_decimal_exact_and_unit_checked', () {
    final s = snapshot({'a0': value('a0', '0.1', 'CNY'), 'a1': value('a1', '0.2', 'CNY')});
    ready(evaluate(sum(), s), '0.3', 'CNY');
    ready(evaluate(sum(), snapshot({'a0': value('a0', '999999999999.000001', 'CNY'), 'a1': value('a1', '0', 'CNY')})), '999999999999.000001', 'CNY');
    rejected(evaluate(sum(), snapshot({...s.facts, 'a1': value('a1', '0.2', 'USD')})), UiFormulaStatus.invalid, 'unit_mismatch:a1');
    rejected(evaluate(sum(), snapshot({...s.facts, 'a1': value('a1', null, 'CNY')})), UiFormulaStatus.unavailable, 'missing_value:a1');
    ready(evaluate(sum(n: 0, allowEmpty: true), snapshot({})), '0', 'CNY');
    rejected(evaluate(sum(n: 0), snapshot({})), UiFormulaStatus.invalid, 'empty_group');
  });
  test('product_decimal_rounds_once', () {
    for (final row in [['3', '0.1', '0.3'], ['0.000001', '0.5', '0.000001'], ['0', '999', '0']]) {
      ready(evaluate(product(), snapshot({'price': value('price', row[1], 'CNY/件')}, state: {'qty': row[0]})), row[2], 'CNY');
    }
    rejected(evaluate(product(), snapshot({'price': value('price', '1', 'USD/件')}, state: {'qty': '3'})), UiFormulaStatus.invalid, 'unit_mismatch:unit_price');
    rejected(evaluate(product(), snapshot({'price': value('price', '1', 'CNY/件')}, state: {'qty': '-1'})), UiFormulaStatus.invalid, 'invalid_decimal:quantity');
  });
  test('tax_price_matches_supplier_core', () {
    final cases = <DataSnapshot>[
      quote(), quote(price: '1', mode: 'included', target: 'excluded'),
      quote(price: '0.000001', rate: '50'), quote(mode: 'excluded', target: 'excluded', rate: null),
      quote(rate: null), quote(mode: 'unknown'), quote(currency: 'USD'), quote(deal: '10'), quote(price: '0'),
    ];
    final expected = ['113', '0.884956', '0.000002', '100', null, null, null, '11.3', '0'];
    for (var i = 0; i < cases.length; i++) {
      final s = cases[i];
      final raw = {for (final e in s.facts.entries) e.key: e.value.value};
      final before = Map<String, Object?>.of(raw);
      final result = evaluate(tax(currency: raw['currency']! as String), s);
      expect(result.value, pricing.priceInTaxMode(raw, currency: 'CNY', taxMode: s.initialUiState['target']! as String));
      expect(result.value, expected[i]);
      expect(result.status, expected[i] == null ? UiFormulaStatus.unavailable : UiFormulaStatus.ready);
      expect(raw, before);
      expect({for (final e in s.facts.entries) e.key: e.value.value}, before);
      expect(s.initialUiState, {'target': s.initialUiState['target']});
    }
  });
  test('tax_rate_domain_precision_and_range_are_not_relaxed', () {
    for (final rate in ['-1', '100.0001', '1.00001', '0.13e2', 13]) {
      rejected(evaluate(tax(), quote(rate: rate)), UiFormulaStatus.invalid, rate is String ? 'invalid_decimal:tax_rate' : 'wrong_type:tax_rate');
    }
    ready(evaluate(tax(), quote(rate: '100')), '200', 'CNY/件');
    ready(evaluate(tax(), quote(rate: '0.13')), '100.13', 'CNY/件');
  });
  test('margin_is_amount_not_percentage', () {
    final d = UiFormulaDefinition.marginAmount(computationId: 'margin', sales: fact('sales', 'CNY'), cost: fact('cost', 'CNY'), currency: 'CNY', decimalPolicy: domainDecimal);
    ready(evaluate(d, snapshot({'sales': value('sales', '29.5875', 'CNY'), 'cost': value('cost', '25.966666', 'CNY')})), '3.620834', 'CNY');
    ready(evaluate(d, snapshot({'sales': value('sales', '1', 'CNY'), 'cost': value('cost', '2', 'CNY')})), '-1', 'CNY');
    rejected(evaluate(d, snapshot({'sales': value('sales', null, 'CNY'), 'cost': value('cost', '2', 'CNY')})), UiFormulaStatus.unavailable, 'missing_value:sales');
  });
  test('markup_preview_matches_budget_unit_price', () {
    // Fixture Store only. Production evaluator never looks up business records.
    final dir = Directory.systemTemp.createTempSync('formula-budget-');
    fixtures.tmp = dir;
    final store = fixtures.device('formula-fixture');
    try {
      final project = store.save('project', fixtures.project('F3a', markup: '12.5'));
      store.save('project_item', fixtures.item(project, 'labor', name: 'a', qty: '3', cost: '0.1'));
      store.save('project_item', fixtures.item(project, 'labor', name: 'b', qty: '2', cost: '10.333333'));
      store.save('project_item', fixtures.item(project, 'other', name: 'c', cost: '5', price: '6'));
      final budget = store.budget(project, withWarnings: false);
      expect(budget.lines.map((line) => line.unitPrice), ['0.1125', '11.625', '6']);
      expect([budget.cost, budget.price, budget.margin], ['25.966666', '29.5875', '3.620834']);
      final d = UiFormulaDefinition.budgetUnitPrice(computationId: 'markup', unitPrice: fact('budget_unit_price', 'CNY/件'), unit: 'CNY/件');
      for (final line in budget.lines) {
        ready(evaluate(d, snapshot({'budget_unit_price': value('budget_unit_price', line.unitPrice, 'CNY/件')})), line.unitPrice, 'CNY/件');
      }
    } finally {
      store.close();
      dir.deleteSync(recursive: true);
    }
  });
  test('unknown_formula_version_instance_slot_and_reference_are_rejected', () {
    final d = sum(n: 1);
    final s = snapshot({'a0': value('a0', '1', 'CNY')});
    UiFormulaInvocation request({String? formula, int v = 1, String id = 'total', Map<String, BindingRef>? refs}) => UiFormulaInvocation(formulaId: formula ?? d.formulaId, formulaVersion: v, computationId: id, inputVersion: version, inputs: refs ?? {'a0': const BindingRef.fact('a0')});
    rejected(evaluate(d, s, invocation: request(formula: 'eval')), UiFormulaStatus.invalid, 'unknown_formula');
    rejected(evaluate(d, s, invocation: request(v: 2)), UiFormulaStatus.invalid, 'unknown_formula_version');
    rejected(evaluate(d, s, invocation: request(id: 'ui.sum_decimal')), UiFormulaStatus.invalid, 'unknown_computation');
    rejected(evaluate(d, s, invocation: request(refs: {'expr': const BindingRef.fact('a0')})), UiFormulaStatus.invalid, 'slot_mismatch');
    rejected(evaluate(d, s, invocation: request(refs: {'a0': const BindingRef.fact('missing')})), UiFormulaStatus.invalid, 'ref_mismatch:a0');
    rejected(evaluate(d, snapshot({})), UiFormulaStatus.invalid, 'unknown_ref:a0');
    for (final binding in [const BindingRef.computed('a0'), const BindingRef.sourceSpan('a0')]) {
      rejected(evaluate(d, s, invocation: request(refs: {'a0': binding})), UiFormulaStatus.invalid, 'wrong_kind:a0');
    }
  });
  test('fact_identity_and_state_do_not_gain_trust', () {
    final d = sum(n: 1);
    rejected(evaluate(d, snapshot({'a0': value('a0', '1', 'CNY', identity: const ObjectRef(moduleId: 'inquiry', objectType: 'quotation', objectId: 'other'))})), UiFormulaStatus.invalid, 'identity_mismatch:a0');
    for (final state in [FactState.readFailed, FactState.conflict, FactState.notDisclosed, FactState.notApplicable]) {
      rejected(evaluate(d, snapshot({'a0': value('a0', '1', 'CNY', state: state)})), UiFormulaStatus.unavailable, 'fact_unavailable:a0');
    }
    final r = evaluate(d, snapshot({'a0': value('a0', '1', 'CNY', state: FactState.unverified)}));
    ready(r, '1', 'CNY');
    expect(r.unverifiedInputs, ['a0']);
  });
  test('ui_state_must_be_predeclared_complete_and_cannot_rebind_metadata', () {
    final d = product();
    final facts = {'price': value('price', '1', 'CNY/件')};
    rejected(evaluate(d, snapshot(facts), state: {'qty': '3'}), UiFormulaStatus.invalid, 'unknown_ref:quantity');
    rejected(evaluate(d, snapshot(facts, state: {'qty': '3'}), state: {}), UiFormulaStatus.invalid, 'state_projection_mismatch');
    rejected(evaluate(d, snapshot(facts, state: {'qty': '3'}), state: {'qty': '3', 'formula': 'eval'}), UiFormulaStatus.invalid, 'state_projection_mismatch');
    final s = snapshot(facts, state: {'qty': '3'});
    final state = {'qty': '4'};
    ready(evaluate(d, s, state: state), '4', 'CNY');
    expect(s.initialUiState['qty'], '3');
    expect(state, {'qty': '4'});
  });
  test('decimal_format_is_checked_before_micros', () {
    for (final bad in ['', ' 1', '+1', '-1', '.1', '1.', '1.2.3', '1e2', 'NaN', 'Infinity', '1.0000001', '1000000000000', 1, double.nan, [], {}]) {
      final r = evaluate(sum(n: 1), snapshot({'a0': value('a0', bad, 'CNY')}));
      expect(r.status, UiFormulaStatus.invalid, reason: '$bad');
      expect(r.value, isNull);
    }
    ready(evaluate(sum(n: 1), snapshot({'a0': value('a0', '0001.200000', 'CNY')})), '1.2', 'CNY');
  });
  test('invalid_inputs_take_priority_over_missing_values', () {
    rejected(evaluate(sum(), snapshot({'a0': value('a0', null, 'CNY'), 'a1': value('a1', 'oops', 'CNY')})), UiFormulaStatus.invalid, 'invalid_decimal:a1');
  });
  test('input_version_and_fingerprint_track_edits_and_new_snapshots', () {
    final d = product();
    final s = snapshot({'price': value('price', '0.1', 'CNY/件')}, state: {'qty': '3'});
    final a = evaluate(d, s);
    final b = evaluate(d, s, state: {'qty': '4'});
    ready(a, '0.3', 'CNY'); ready(b, '0.4', 'CNY');
    expect(a.inputFingerprint, isNotEmpty);
    expect(a.inputFingerprint, isNot(b.inputFingerprint));
    expect(evaluate(d, s).inputFingerprint, a.inputFingerprint);
    final next = snapshot(s.facts, state: s.initialUiState, ref: const SnapshotRef('formula-fixture', 2));
    rejected(evaluate(d, next, invocation: UiFormulaInvocation.forDefinition(d, version)), UiFormulaStatus.stale, 'stale_input_version');
    final fresh = evaluate(d, next);
    expect(fresh.status, UiFormulaStatus.ready);
    expect(fresh.inputVersion, next.ref);
    expect(fresh.inputFingerprint, isNot(a.inputFingerprint));
  });
  test('fingerprint_is_typed_order_independent_and_keeps_provenance', () {
    final d = sum();
    final a = value('a0', '1', 'CNY'); final b = value('a1', '2', 'CNY');
    final r = evaluate(d, snapshot({'a0': a, 'a1': b}));
    expect(evaluate(d, snapshot({'a1': b, 'a0': a})).inputFingerprint, r.inputFingerprint);
    expect(evaluate(d, snapshot({'a0': value('a0', '1', 'CNY', state: FactState.unverified), 'a1': b})).inputFingerprint, isNot(r.inputFingerprint));
  });
  test('slot_and_decimal_byte_limits_include_the_boundary', () {
    for (final n in [31, 32, 33]) {
      final r = evaluate(sum(n: n), snapshot({for (var i = 0; i < n; i++) 'a$i': value('a$i', '1', 'CNY')}));
      if (n <= 32) { ready(r, '$n', 'CNY'); } else { rejected(r, UiFormulaStatus.invalid, 'too_many_inputs'); }
    }
    for (final n in [255, 256, 257]) {
      final r = evaluate(sum(n: 1), snapshot({'a0': value('a0', '${'0' * (n - 1)}1', 'CNY')}));
      if (n <= 256) { ready(r, '1', 'CNY'); } else { rejected(r, UiFormulaStatus.invalid, 'input_too_large:a0'); }
    }
  });

  test('fact_field_and_revision_are_fixed_host_identity', () {
    final d = sum(n: 1);
    final wrongField = SnapshotFact(object: object, field: 'other', value: '1', state: FactState.verified, unit: 'CNY');
    rejected(evaluate(d, snapshot({'a0': wrongField})), UiFormulaStatus.invalid, 'identity_mismatch:a0');
    final otherRevision = ObjectRef(moduleId: object.moduleId, objectType: object.objectType, objectId: object.objectId, revisionRef: 'r2');
    rejected(evaluate(d, snapshot({'a0': value('a0', '1', 'CNY', identity: otherRevision)})), UiFormulaStatus.invalid, 'identity_mismatch:a0');
  });
  test('fingerprint_records_slot_order_and_source_provenance', () {
    final d = sum();
    final reverse = UiFormulaDefinition.sum(computationId: 'total', amounts: {'a1': fact('a1', 'CNY'), 'a0': fact('a0', 'CNY')}, unit: 'CNY', decimalPolicy: domainDecimal);
    final s = snapshot({'a0': value('a0', '1', 'CNY'), 'a1': value('a1', '2', 'CNY')});
    final a = evaluate(d, s);
    expect(evaluate(reverse, s).inputFingerprint, a.inputFingerprint);
    final sourced = SnapshotFact(object: object, field: 'a0', value: '1', state: FactState.verified, unit: 'CNY', sourceRefs: ['source1']);
    expect(evaluate(d, snapshot({...s.facts, 'a0': sourced})).inputFingerprint, isNot(a.inputFingerprint));
  });
  test('host_limits_are_explicit_and_aggregate_utf8_boundary_is_inclusive', () {
    final d = sum(n: 1);
    DataSnapshot withSource(String source) => snapshot({'a0': SnapshotFact(object: object, field: 'a0', value: '1', state: FactState.verified, unit: 'CNY', sourceRefs: [source])});
    final base = evaluate(d, withSource(''));
    expect(base.status, UiFormulaStatus.ready);
    expect(base.inputBytes, greaterThan(0));
    final pad = 'x' * (limits.maxInputBytes - base.inputBytes);
    final unicode = evaluate(d, withSource('汉'));
    expect(unicode.inputBytes, base.inputBytes + 3);
    final atUtf8Boundary = evaluate(d, withSource('汉${pad.substring(3)}'));
    ready(atUtf8Boundary, '1', 'CNY');
    expect(atUtf8Boundary.inputBytes, limits.maxInputBytes);
    for (final suffix in [-1, 0, 1]) {
      final s = withSource(suffix < 0 ? pad.substring(1) : '$pad${'x' * suffix}');
      final r = evaluate(d, s);
      expect(r.inputBytes, limits.maxInputBytes + suffix);
      if (suffix <= 0) { ready(r, '1', 'CNY'); } else { rejected(r, UiFormulaStatus.invalid, 'inputs_too_large'); }
    }
    final small = UiFormulaRegistry(definitions: [d], limits: const UiFormulaLimits(maxInputs: 1, maxDecimalBytes: 1, maxInputBytes: 1000));
    rejected(small.evaluate(UiFormulaInvocation.forDefinition(d, version), snapshot({'a0': value('a0', '12', 'CNY')}), {}), UiFormulaStatus.invalid, 'input_too_large:a0');
  });
  test('definition_dimension_and_metadata_cannot_be_inferred', () {
    final d = UiFormulaDefinition.product(computationId: 'bad', quantity: const UiFormulaSlot.uiState('qty', unit: 'kg'), unitPrice: fact('price', 'CNY/件'), currency: 'CNY', quantityUnit: '件', decimalPolicy: domainDecimal);
    rejected(evaluate(d, snapshot({'price': value('price', '1', 'CNY/件')}, state: {'qty': '1'})), UiFormulaStatus.invalid, 'invalid_definition');
  });
  test('evaluation_does_not_mutate_inputs_or_accept_new_literal_slots', () {
    final d = product();
    final s = snapshot({'price': value('price', '0.1', 'CNY/件')}, state: {'qty': '3'});
    final refs = {'quantity': const BindingRef.uiState('qty'), 'unit_price': const BindingRef.fact('price')};
    final inv = UiFormulaInvocation(formulaId: d.formulaId, formulaVersion: 1, computationId: d.computationId, inputVersion: version, inputs: refs);
    refs['expr'] = const BindingRef.fact('price');
    final state = {'qty': '4'};
    ready(evaluate(d, s, state: state, invocation: inv), '0.4', 'CNY');
    expect(inv.inputs.keys, ['quantity', 'unit_price']);
    expect(d.slots.keys, ['quantity', 'unit_price']);
    expect(s.facts['price']!.value, '0.1');
    expect(s.initialUiState, {'qty': '3'}); expect(state, {'qty': '4'});
    expect(() => inv.inputs['value'] = const BindingRef.fact('price'), throwsUnsupportedError);
    expect(() => d.slots.clear(), throwsUnsupportedError);
  });

  test('registry_refuses_duplicate_instance_and_nonpositive_host_limits', () {
    final d = sum(n: 1);
    expect(() => UiFormulaRegistry(definitions: [d, d], limits: limits), throwsArgumentError);
    expect(() => UiFormulaRegistry(definitions: [d], limits: const UiFormulaLimits(maxInputs: 0, maxDecimalBytes: 256, maxInputBytes: 16384)), throwsArgumentError);
  });
  test('tax_metadata_stays_fact_only_and_belongs_to_one_quote', () {
    final d = UiFormulaDefinition.taxPrice(computationId: 'tax', price: fact('price', 'CNY/件'), currency: const UiFormulaSlot.uiState('currency', unit: 'currency'), taxMode: fact('tax_mode', 'tax_mode'), taxRate: fact('tax_rate', '%'), dealPrice: fact('deal_price', 'CNY/件'), targetTaxMode: const UiFormulaSlot.uiState('target', unit: 'tax_mode'), targetCurrency: 'CNY', quoteUnit: '件');
    rejected(evaluate(d, quote()), UiFormulaStatus.invalid, 'invalid_definition');
    final mixed = UiFormulaDefinition.taxPrice(computationId: 'tax', price: fact('price', 'CNY/件'), currency: fact('currency', 'currency'), taxMode: fact('tax_mode', 'tax_mode'), taxRate: const UiFormulaSlot.fact('tax_rate', object: ObjectRef(moduleId: 'inquiry', objectType: 'quotation', objectId: 'other'), field: 'tax_rate', unit: '%'), dealPrice: fact('deal_price', 'CNY/件'), targetTaxMode: const UiFormulaSlot.uiState('target', unit: 'tax_mode'), targetCurrency: 'CNY', quoteUnit: '件');
    rejected(evaluate(mixed, quote()), UiFormulaStatus.invalid, 'invalid_definition');
  });
}
