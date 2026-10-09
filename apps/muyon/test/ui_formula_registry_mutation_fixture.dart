// Pure Dart fixtures shared by normal tests and isolated source mutants.
import 'dart:io';

import 'package:muyon/platform/ui_formula_registry.dart';
import 'package:muyon_module_api/ui_contract.dart';

const _object = ObjectRef(moduleId: 'fixture', objectType: 'quote', objectId: 'q', revisionRef: 'r1');
const _version = SnapshotRef('mutation-fixture', 1);
const _limits = UiFormulaLimits(maxInputs: 32, maxDecimalBytes: 256, maxInputBytes: 16384);
class FormulaExpectationFailure implements Exception {
  FormulaExpectationFailure(this.name);
  final String name;
}
void _check(bool condition, String name) {
  if (!condition) throw FormulaExpectationFailure(name);
}
void verifyFormulaMutationFixture(String name) {
  final definition = UiFormulaDefinition.sum(computationId: 'total', amounts: {
    'a': const UiFormulaSlot.fact('a', object: _object, field: 'amount', unit: 'CNY'),
    'b': const UiFormulaSlot.fact('b', object: _object, field: 'amount', unit: 'CNY'),
  }, unit: 'CNY', decimalPolicy: UiFormulaDecimalPolicy.supplierCoreUnsigned);
  final registry = UiFormulaRegistry(definitions: [definition], limits: _limits);
  DataSnapshot inputs(String a, String b, {SnapshotRef ref = _version, bool missing = false}) => DataSnapshot(ref: ref, facts: {
    if (!missing) 'a': SnapshotFact(object: _object, field: 'amount', value: a, state: FactState.verified, unit: 'CNY'),
    'b': SnapshotFact(object: _object, field: 'amount', value: b, state: FactState.verified, unit: 'CNY'),
  });
  final invocation = UiFormulaInvocation.forDefinition(definition, _version);
  switch (name) {
    case 'sum_decimal_exact_and_unit_checked':
      for (final values in [['0.1', '0.2', '0.3'], ['999999999999.000001', '0', '999999999999.000001']]) {
        final result = registry.evaluate(invocation, inputs(values[0], values[1]), {});
        _check(result.status == UiFormulaStatus.ready && result.value == values[2], name);
      }
    case 'stale_input_version_not_published':
      final s = inputs('1', '2', ref: const SnapshotRef('mutation-fixture', 2));
      final result = registry.evaluate(invocation, s, {});
      _check(result.status == UiFormulaStatus.stale && result.value == null && result.inputVersion == s.ref && result.errors.contains('stale_input_version'), name);
    case 'unknown_formula_rejected':
      final unknown = UiFormulaInvocation(formulaId: 'arbitrary.expression', formulaVersion: 1, computationId: 'total', inputVersion: _version, inputs: invocation.inputs);
      final result = registry.evaluate(unknown, inputs('1', '2'), {});
      _check(result.status == UiFormulaStatus.invalid && result.value == null && result.errors.contains('unknown_formula'), name);
    case 'unknown_ref_rejected':
      final result = registry.evaluate(invocation, inputs('1', '2', missing: true), {});
      _check(result.status == UiFormulaStatus.invalid && result.value == null && result.errors.contains('unknown_ref:a'), name);
    default:
      throw ArgumentError.value(name);
  }
}
void main(List<String> args) {
  try {
    verifyFormulaMutationFixture(args.single);
    stdout.writeln('PASS:${args.single}');
  } on FormulaExpectationFailure catch (failure) {
    stderr.writeln('EXPECTED_ASSERTION_FAILURE:${failure.name}');
    exitCode = 65;
  }
}
