import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/ui_formula_registry.dart';
import 'package:muyon_module_api/ui_contract.dart';

const _ref = SnapshotRef('fingerprint-redaction', 1);
const _object = ObjectRef(
  moduleId: 'inquiry',
  objectType: 'quotation_line',
  objectId: 'a',
  revisionRef: '1',
);
final _sum = UiFormulaDefinition.sum(
  computationId: 'price-sum',
  amounts: {
    'amount': const UiFormulaSlot.fact(
      'price',
      object: _object,
      field: 'amount',
      unit: 'CNY',
    ),
  },
  unit: 'CNY',
  decimalPolicy: UiFormulaDecimalPolicy.supplierCoreUnsigned,
);
final _registry = UiFormulaRegistry(
  definitions: [_sum],
  limits: const UiFormulaLimits(
    maxInputs: 32,
    maxDecimalBytes: 256,
    maxInputBytes: 16384,
  ),
);
UiFormulaEvaluation _evaluate(FactState state, Object? raw) =>
    _registry.evaluate(
      UiFormulaInvocation.forDefinition(_sum, _ref),
      DataSnapshot(
        ref: _ref,
        facts: {
          'price': SnapshotFact(
            object: _object,
            field: 'amount',
            value: raw,
            state: state,
            unit: 'CNY',
            sourceRefs: ['source'],
          ),
        },
      ),
      const {},
    );

void main() {
  for (final state in [
    FactState.notDisclosed,
    FactState.readFailed,
    FactState.notApplicable,
    FactState.conflict,
  ]) {
    test(
      '${state.name} residual values never influence fingerprint, byte count or diagnostics',
      () {
        final first = _evaluate(state, 'HIDDEN_COMMERCIAL_CANARY_A_904');
        final second = _evaluate(
          state,
          'HIDDEN_COMMERCIAL_CANARY_B_LONGER_7172',
        );
        final absent = _evaluate(state, null);
        final nonScalar = _evaluate(state, {'secret': 'HIDDEN_MAP_CANARY_826'});
        for (final evaluation in [first, second, absent, nonScalar]) {
          expect(evaluation.status, UiFormulaStatus.unavailable);
          expect(evaluation.value, isNull);
          expect(evaluation.errors, ['fact_unavailable:amount']);
          expect(evaluation.inputFingerprint, absent.inputFingerprint);
          expect(evaluation.inputBytes, absent.inputBytes);
          final diagnostic = jsonEncode({
            'fingerprint': evaluation.inputFingerprint,
            'errors': evaluation.errors,
            'value': evaluation.value,
            'unverified': evaluation.unverifiedInputs,
          });
          expect(diagnostic, isNot(contains('HIDDEN_')));
        }
      },
    );
  }
  for (final state in [FactState.verified, FactState.unverified]) {
    test(
      '${state.name} legitimate numeric values and diagnostic inputs remain compatible',
      () {
        final first = _evaluate(state, '7');
        final second = _evaluate(state, '8');
        expect(first.status, UiFormulaStatus.ready);
        expect(first.value, '7');
        expect(second.value, '8');
        expect(first.inputFingerprint, isNot(second.inputFingerprint));
        expect(
          first.unverifiedInputs,
          state == FactState.unverified ? ['amount'] : isEmpty,
        );
        expect(
          first.inputFingerprint,
          state == FactState.verified
              ? '1915492fdd13d282d66ae3e1b1cb244f838c07365603ede0ad117e8215d7ee76'
              : '5506221f7b61414f5ff7195e3612228e569bd7b0b81e1f25b1ee49d5daa37f20',
        );
      },
    );
  }
  test(
    'accepted manual parameters still affect arithmetic and fingerprints',
    () {
      final def = UiFormulaDefinition.product(
        computationId: 'cost:a',
        quantity: const UiFormulaSlot.uiState('qty', unit: '件'),
        unitPrice: const UiFormulaSlot.fact(
          'price',
          object: _object,
          field: 'amount',
          unit: 'CNY/件',
        ),
        currency: 'CNY',
        quantityUnit: '件',
        decimalPolicy: UiFormulaDecimalPolicy.supplierCoreUnsigned,
      );
      final registry = UiFormulaRegistry(
        definitions: [def],
        limits: const UiFormulaLimits(
          maxInputs: 32,
          maxDecimalBytes: 256,
          maxInputBytes: 16384,
        ),
      );
      final snapshot = DataSnapshot(
        ref: _ref,
        facts: {
          'price': SnapshotFact(
            object: _object,
            field: 'amount',
            value: '7',
            state: FactState.verified,
            unit: 'CNY/件',
          ),
        },
        initialUiState: {'qty': '2'},
      );
      UiFormulaEvaluation evaluate(String qty) => registry.evaluate(
        UiFormulaInvocation.forDefinition(def, _ref),
        snapshot,
        {'qty': qty},
      );
      final first = evaluate('2');
      final second = evaluate('3');
      expect(first.value, '14');
      expect(second.value, '21');
      expect(first.inputFingerprint, isNot(second.inputFingerprint));
    },
  );
}
