import 'package:muyon_module_api/ui_contract.dart';

// Compilation scaffold for the RED commit. Not a usable evaluator.
enum UiFormulaStatus { ready, unavailable, invalid, stale }
enum _Formula { sum, product, tax, margin, budgetUnitPrice }

class UiFormulaSlot {
  const UiFormulaSlot.fact(String id, {required this.object, required this.field, required this.unit})
    : binding = BindingRef.fact(id);
  const UiFormulaSlot.uiState(String id, {required this.unit})
    : binding = BindingRef.uiState(id), object = null, field = null;
  final BindingRef binding;
  final ObjectRef? object;
  final String? field;
  final String unit;
}

class UiFormulaDefinition {
  UiFormulaDefinition._(this.computationId, this.formulaId, this._formula, Map<String, UiFormulaSlot> slots, this.outputUnit, {this.allowEmpty = false})
    : slots = Map.unmodifiable(slots);
  factory UiFormulaDefinition.sum({required String computationId, required Map<String, UiFormulaSlot> amounts, required String unit, bool allowEmpty = false}) =>
    UiFormulaDefinition._(computationId, 'ui.sum_decimal', _Formula.sum, amounts, unit, allowEmpty: allowEmpty);
  factory UiFormulaDefinition.product({required String computationId, required UiFormulaSlot quantity, required UiFormulaSlot unitPrice, required String currency, required String quantityUnit}) =>
    UiFormulaDefinition._(computationId, 'ui.product_decimal', _Formula.product, {'quantity': quantity, 'unit_price': unitPrice}, currency);
  factory UiFormulaDefinition.taxPrice({required String computationId, required UiFormulaSlot price, required UiFormulaSlot currency, required UiFormulaSlot taxMode, required UiFormulaSlot taxRate, required UiFormulaSlot dealPrice, required UiFormulaSlot targetTaxMode, required String targetCurrency, required String quoteUnit}) =>
    UiFormulaDefinition._(computationId, 'inquiry.tax_price', _Formula.tax, {'price': price, 'currency': currency, 'tax_mode': taxMode, 'tax_rate': taxRate, 'deal_price': dealPrice, 'target_tax_mode': targetTaxMode}, '$targetCurrency/$quoteUnit');
  factory UiFormulaDefinition.marginAmount({required String computationId, required UiFormulaSlot sales, required UiFormulaSlot cost, required String currency}) =>
    UiFormulaDefinition._(computationId, 'inquiry.margin_amount', _Formula.margin, {'sales': sales, 'cost': cost}, currency);
  factory UiFormulaDefinition.budgetUnitPrice({required String computationId, required UiFormulaSlot unitPrice, required String unit}) =>
    UiFormulaDefinition._(computationId, 'inquiry.markup_unit_price', _Formula.budgetUnitPrice, {'budget_unit_price': unitPrice}, unit);
  final String computationId, formulaId, outputUnit;
  final int formulaVersion = 1;
  final _Formula _formula;
  final Map<String, UiFormulaSlot> slots;
  final bool allowEmpty;
}

class UiFormulaInvocation {
  UiFormulaInvocation({required this.formulaId, required this.formulaVersion, required this.computationId, required this.inputVersion, required Map<String, BindingRef> inputs}) : inputs = Map.unmodifiable(inputs);
  factory UiFormulaInvocation.forDefinition(UiFormulaDefinition definition, SnapshotRef version) => UiFormulaInvocation(formulaId: definition.formulaId, formulaVersion: definition.formulaVersion, computationId: definition.computationId, inputVersion: version, inputs: {for (final e in definition.slots.entries) e.key: e.value.binding});
  final String formulaId, computationId;
  final int formulaVersion;
  final SnapshotRef inputVersion;
  final Map<String, BindingRef> inputs;
}

class UiFormulaEvaluation {
  UiFormulaEvaluation({required this.status, required this.value, required this.unit, required this.inputVersion, required this.computationId, required this.inputFingerprint, List<String> errors = const [], List<String> unverifiedInputs = const []}) : errors = List.unmodifiable(errors), unverifiedInputs = List.unmodifiable(unverifiedInputs);
  final UiFormulaStatus status;
  final Object? value;
  final String? unit;
  final SnapshotRef inputVersion;
  final String computationId, inputFingerprint;
  final List<String> errors, unverifiedInputs;
}

class UiFormulaRegistry {
  UiFormulaRegistry({required List<UiFormulaDefinition> definitions}) : definitions = List.unmodifiable(definitions);
  final List<UiFormulaDefinition> definitions;
  UiFormulaEvaluation evaluate(UiFormulaInvocation invocation, DataSnapshot snapshot, Map<String, Object?> currentUiState) => UiFormulaEvaluation(status: UiFormulaStatus.invalid, value: null, unit: null, inputVersion: snapshot.ref, computationId: invocation.computationId, inputFingerprint: '', errors: ['not_implemented']);
}
