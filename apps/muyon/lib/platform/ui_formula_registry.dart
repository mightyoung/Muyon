import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:supplier_core/supplier_core.dart' as pricing;

/// Host-only F3a interfaces. Not a stream codec, runtime or publication API.
enum UiFormulaStatus { ready, unavailable, invalid, stale }

/// Explicit opt-in to existing supplier field rules, not general signed math.
enum UiFormulaDecimalPolicy {
  supplierCoreUnsigned,
  // Explicit projection policy for already computed budget totals: unsigned
  // <=6 fractional digits, bounded by host byte limits rather than field width.
  supplierCoreProjectedUnsigned,
}

/// Required host safety configuration; these are not formal schema defaults.
final class UiFormulaLimits {
  const UiFormulaLimits({
    required this.maxInputs,
    required this.maxDecimalBytes,
    required this.maxInputBytes,
  });
  final int maxInputs, maxDecimalBytes, maxInputBytes;
}

enum _Formula { sum, product, tax, margin, budgetUnitPrice }

final class UiFormulaSlot {
  const UiFormulaSlot.fact(
    String id, {
    required this.object,
    required this.field,
    required this.unit,
  }) : _id = id, _kind = BindingKind.fact;
  const UiFormulaSlot.uiState(String id, {required this.unit})
    : _id = id, _kind = BindingKind.uiState, object = null, field = null;
  final String _id;
  final BindingKind _kind;
  BindingRef get binding => BindingRef(_kind, _id);
  final ObjectRef? object;
  final String? field;
  final String unit;
}

/// Fixed functions and input references constructed by trusted host code only.
/// No user/model callbacks, custom formulas, literal decoder or recursive DAG.
final class UiFormulaDefinition {
  UiFormulaDefinition._(
    this.computationId,
    this.formulaId,
    this._formula,
    Map<String, UiFormulaSlot> slots,
    this.outputUnit, {
    this.allowEmpty = false,
    this.decimalPolicy,
    this.quantityUnit,
    this.targetCurrency,
    this.quoteUnit,
  }) : slots = Map.unmodifiable(slots);

  factory UiFormulaDefinition.sum({
    required String computationId,
    required Map<String, UiFormulaSlot> amounts,
    required String unit,
    required UiFormulaDecimalPolicy decimalPolicy,
    bool allowEmpty = false,
  }) => UiFormulaDefinition._(
    computationId, 'ui.sum_decimal', _Formula.sum, amounts, unit,
    allowEmpty: allowEmpty, decimalPolicy: decimalPolicy,
  );
  factory UiFormulaDefinition.product({
    required String computationId,
    required UiFormulaSlot quantity,
    required UiFormulaSlot unitPrice,
    required String currency,
    required String quantityUnit,
    required UiFormulaDecimalPolicy decimalPolicy,
  }) => UiFormulaDefinition._(
    computationId, 'ui.product_decimal', _Formula.product,
    {'quantity': quantity, 'unit_price': unitPrice}, currency,
    quantityUnit: quantityUnit, targetCurrency: currency,
    decimalPolicy: decimalPolicy,
  );
  factory UiFormulaDefinition.taxPrice({
    required String computationId,
    required UiFormulaSlot price,
    required UiFormulaSlot currency,
    required UiFormulaSlot taxMode,
    required UiFormulaSlot taxRate,
    required UiFormulaSlot dealPrice,
    required UiFormulaSlot targetTaxMode,
    required String targetCurrency,
    required String quoteUnit,
  }) => UiFormulaDefinition._(
    computationId, 'inquiry.tax_price', _Formula.tax,
    {
      'price': price, 'currency': currency, 'tax_mode': taxMode,
      'tax_rate': taxRate, 'deal_price': dealPrice,
      'target_tax_mode': targetTaxMode,
    }, '$targetCurrency/$quoteUnit',
    targetCurrency: targetCurrency, quoteUnit: quoteUnit,
  );
  factory UiFormulaDefinition.marginAmount({
    required String computationId,
    required UiFormulaSlot sales,
    required UiFormulaSlot cost,
    required String currency,
    required UiFormulaDecimalPolicy decimalPolicy,
  }) => UiFormulaDefinition._(
    computationId, 'inquiry.margin_amount', _Formula.margin,
    {'sales': sales, 'cost': cost}, currency,
    targetCurrency: currency, decimalPolicy: decimalPolicy,
  );

  /// Reference to host-projected BudgetLine.unitPrice, not a markup preview.
  /// The shared markup helper remains a supplier_core owner dependency.
  factory UiFormulaDefinition.budgetUnitPrice({
    required String computationId,
    required UiFormulaSlot unitPrice,
    required String unit,
  }) => UiFormulaDefinition._(
    computationId, 'inquiry.markup_unit_price', _Formula.budgetUnitPrice,
    {'budget_unit_price': unitPrice}, unit,
  );

  final String computationId, formulaId, outputUnit;
  final int formulaVersion = 1;
  final UiValueType outputType = UiValueType.string;
  final bool nullableOutput = true;
  final _Formula _formula;
  final Map<String, UiFormulaSlot> slots;
  final bool allowEmpty;
  final UiFormulaDecimalPolicy? decimalPolicy;
  final String? quantityUnit, targetCurrency, quoteUnit;
}

final class UiFormulaInvocation {
  UiFormulaInvocation({
    required this.formulaId,
    required this.formulaVersion,
    required this.computationId,
    required this.inputVersion,
    required Map<String, BindingRef> inputs,
  }) : inputs = Map.unmodifiable(inputs);
  factory UiFormulaInvocation.forDefinition(
    UiFormulaDefinition definition, SnapshotRef version,
  ) => UiFormulaInvocation(
    formulaId: definition.formulaId,
    formulaVersion: definition.formulaVersion,
    computationId: definition.computationId,
    inputVersion: version,
    inputs: {for (final e in definition.slots.entries) e.key: e.value.binding},
  );
  final String formulaId, computationId;
  final int formulaVersion;
  final SnapshotRef inputVersion;
  final Map<String, BindingRef> inputs;
}

final class UiFormulaEvaluation {
  UiFormulaEvaluation({
    required this.status,
    required this.value,
    required this.unit,
    required this.inputVersion,
    required this.computationId,
    required this.inputFingerprint,
    this.inputBytes = 0,
    List<String> errors = const [],
    List<String> unverifiedInputs = const [],
  }) : errors = List.unmodifiable(errors),
       unverifiedInputs = List.unmodifiable(unverifiedInputs);
  final UiFormulaStatus status;
  final Object? value;
  final String? unit;
  final SnapshotRef inputVersion;
  final String computationId;

  /// Opaque diagnostic only; no adopted persistence/cache/authority semantics.
  final String inputFingerprint;
  final int inputBytes;
  final List<String> errors, unverifiedInputs;
}

final class UiFormulaRegistry {
  UiFormulaRegistry({
    required List<UiFormulaDefinition> definitions,
    required this.limits,
  }) : definitions = List.unmodifiable(definitions),
       _byId = Map.unmodifiable({for (final d in definitions) d.computationId: d}) {
    if (limits.maxInputs <= 0 || limits.maxDecimalBytes <= 0 || limits.maxInputBytes <= 0) {
      throw ArgumentError('host limits must be positive');
    }
    if (_byId.length != definitions.length) {
      throw ArgumentError('duplicate host computation id');
    }
  }
  final List<UiFormulaDefinition> definitions;
  final UiFormulaLimits limits;
  final Map<String, UiFormulaDefinition> _byId;

  UiFormulaEvaluation evaluate(
    UiFormulaInvocation invocation,
    DataSnapshot snapshot,
    Map<String, Object?> currentUiState,
  ) {
    final definition = _byId[invocation.computationId];
    var fingerprint = '';
    var inputBytes = 0;
    final unverified = <String>[];
    UiFormulaEvaluation result(UiFormulaStatus status, {
      Object? value, List<String> errors = const [],
    }) => UiFormulaEvaluation(
      status: status, value: value, errors: errors,
      unit: definition?.outputUnit, inputVersion: snapshot.ref,
      computationId: invocation.computationId,
      inputFingerprint: fingerprint, inputBytes: inputBytes,
      unverifiedInputs: unverified,
    );
    UiFormulaEvaluation reject(String error) => result(
      UiFormulaStatus.invalid, errors: [error],
    );
    if (definition == null) return reject('unknown_computation');
    if (invocation.inputVersion != snapshot.ref) {
      return result(UiFormulaStatus.stale, errors: ['stale_input_version']);
    }
    if (invocation.formulaId != definition.formulaId) {
      return reject('unknown_formula');
    }
    if (invocation.formulaVersion != definition.formulaVersion) {
      return reject('unknown_formula_version');
    }
    if (definition.slots.length > limits.maxInputs || invocation.inputs.length > limits.maxInputs) {
      return reject('too_many_inputs');
    }
    if (!_sameKeys(definition.slots, invocation.inputs)) return reject('slot_mismatch');
    if (!_validDefinition(definition)) return reject('invalid_definition');
    if (definition._formula == _Formula.sum && definition.slots.isEmpty && !definition.allowEmpty) {
      return reject('empty_group');
    }
    final stateKeys = currentUiState.keys.toList()..sort();
    final invalid = <String>[];
    final missing = <String>[];
    final values = <String, Object?>{};
    final records = <Object?>[];
    final names = definition.slots.keys.toList()..sort();
    for (final name in names) {
      final slot = definition.slots[name]!;
      final binding = invocation.inputs[name]!;
      if (binding.kind != BindingKind.fact && binding.kind != BindingKind.uiState) {
        invalid.add('wrong_kind:$name');
        continue;
      }
      if (binding != slot.binding) {
        invalid.add('ref_mismatch:$name');
        continue;
      }
      final exists = binding.kind == BindingKind.fact
          ? snapshot.facts.containsKey(binding.id)
          : snapshot.initialUiState.containsKey(binding.id);
      if (!exists) {
        invalid.add('unknown_ref:$name');
        continue;
      }
      final fact = binding.kind == BindingKind.fact ? snapshot.facts[binding.id] : null;
      final raw = fact == null ? currentUiState[binding.id] : fact.value;
      if (fact != null) {
        if (fact.object != slot.object || fact.field != slot.field) invalid.add('identity_mismatch:$name');
        if (fact.unit != slot.unit) invalid.add('unit_mismatch:$name');
        if (fact.state == FactState.unverified) unverified.add(name);
      }
      if (!isUiScalar(raw)) {
        invalid.add(raw is num ? 'nonfinite:$name' : 'wrong_type:$name');
        continue;
      }
      final sources = fact?.sourceRefs.toList() ?? <String>[];
      sources.sort();
      records.add([
        name, binding.kind.name, binding.id, slot.unit,
        fact?.object.toJson(), fact?.field, fact?.unit, fact?.state.name, sources,
        _typed(raw),
      ]);
      if (fact != null && fact.state != FactState.verified && fact.state != FactState.unverified) {
        missing.add('fact_unavailable:$name');
        continue;
      }
      if (raw == null) {
        if (definition._formula == _Formula.tax && (name == 'tax_rate' || name == 'deal_price')) {
          values[name] = null;
        } else {
          missing.add('missing_value:$name');
        }
        continue;
      }
      if (raw is! String) {
        invalid.add('wrong_type:$name');
        continue;
      }
      if (definition._formula == _Formula.tax && name == 'currency') {
        if (!_currency(raw)) invalid.add('invalid_currency:$name');
        values[name] = raw;
      } else if (definition._formula == _Formula.tax && name.endsWith('tax_mode')) {
        if (!const ['included', 'excluded', 'unknown'].contains(raw)) invalid.add('invalid_tax_mode:$name');
        values[name] = raw;
      } else {
        if (utf8.encode(raw).length > limits.maxDecimalBytes) {
          invalid.add('input_too_large:$name');
          continue;
        }
        try {
          final rate = definition._formula == _Formula.tax && name == 'tax_rate';
          // BudgetLine.unitPrice is a computed output, not a project input field:
          // markup and aggregation can increase integer width. Still unsigned, <=6 decimals
          // and host byte-bounded; do not reject a valid existing budget result.
          final projectedBudget = definition._formula == _Formula.budgetUnitPrice ||
              (definition._formula == _Formula.margin &&
               definition.decimalPolicy == UiFormulaDecimalPolicy.supplierCoreProjectedUnsigned);
          final decimal = pricing.ExactDecimal.parse(raw,
            maxIntegerDigits: rate ? 3 : (projectedBudget ? limits.maxDecimalBytes : 12),
            maxFractionDigits: rate ? 4 : 6,
          );
          if (rate && decimal.compareTo(pricing.ExactDecimal.parse('100')) > 0) {
            invalid.add('invalid_decimal:$name');
          }
          values[name] = decimal.canonical;
        } on FormatException {
          invalid.add('invalid_decimal:$name');
        }
      }
    }
    // Report undeclared bound references specifically, while rejecting every
    // incomplete/extra/non-scalar state projection before any computation.
    if (!_sameKeys(snapshot.initialUiState, currentUiState)) {
      invalid.add('state_projection_mismatch');
    }
    for (final key in stateKeys) {
      if (!isUiScalar(currentUiState[key])) invalid.add('invalid_state_value:$key');
    }
    if (invalid.isNotEmpty) return result(UiFormulaStatus.invalid, errors: invalid);

    // Private diagnostic encoding. No runtime cache or persisted format adoption.
    final bytes = utf8.encode(jsonEncode([
      'f3a-local-diagnostic', definition.formulaId, definition.formulaVersion,
      definition.computationId, definition.outputUnit, definition.decimalPolicy?.name,
      snapshot.ref.id, snapshot.ref.revision, records,
      [for (final key in stateKeys) [key, _typed(currentUiState[key])]],
    ]));
    inputBytes = bytes.length;
    if (inputBytes > limits.maxInputBytes) return reject('inputs_too_large');
    fingerprint = sha256.convert(bytes).toString();
    if (missing.isNotEmpty) return result(UiFormulaStatus.unavailable, errors: missing);

    String? value;
    switch (definition._formula) {
      case _Formula.sum:
        var total = BigInt.zero;
        for (final item in values.values) {
          total += pricing.micros(item! as String);
        }
        value = pricing.fromMicros(total); // exact_sum
      case _Formula.product:
        value = pricing.fromMicros(pricing.multiply(
          pricing.micros(values['quantity']! as String),
          pricing.micros(values['unit_price']! as String),
        ));
      case _Formula.margin:
        value = pricing.fromMicros(
          pricing.micros(values['sales']! as String) - pricing.micros(values['cost']! as String),
        );
      case _Formula.budgetUnitPrice:
        value = values['budget_unit_price']! as String;
      case _Formula.tax:
        final currency = values['currency']! as String;
        for (final name in ['price', 'deal_price']) {
          if (definition.slots[name]!.unit != '$currency/${definition.quoteUnit}') {
            return reject('unit_mismatch:$name');
          }
        }
        value = pricing.priceInTaxMode({
          'price': values['price'], 'currency': currency,
          'tax_mode': values['tax_mode'], 'tax_rate': values['tax_rate'],
          'deal_price': values['deal_price'],
        }, currency: definition.targetCurrency!, taxMode: values['target_tax_mode']! as String);
        if (value == null) {
          final reason = currency != definition.targetCurrency ? 'unsupported_currency'
              : (values['tax_mode'] == 'unknown' || values['target_tax_mode'] == 'unknown')
              ? 'unsupported_tax_mode' : 'missing_tax_rate';
          return result(UiFormulaStatus.unavailable, errors: [reason]);
        }
    }
    return result(UiFormulaStatus.ready, value: value);
  }
}

bool _sameKeys(Map<String, Object?> a, Map<String, Object?> b) =>
    a.length == b.length && a.keys.every(b.containsKey);
bool _currency(String? value) => value != null && RegExp(r'^[A-Z]{3}$').hasMatch(value);
bool _nonempty(String? value) => value != null && value.isNotEmpty && value.trim() == value;
Object _typed(Object? value) => [
  value == null ? 'null' : value is String ? 'string' : value is bool ? 'bool'
      : value is int ? 'int' : 'double',
  value,
];

bool _validDefinition(UiFormulaDefinition d) {
  if (!_nonempty(d.computationId) || !_nonempty(d.outputUnit)) return false;
  for (final entry in d.slots.entries) {
    final slot = entry.value;
    if (!_nonempty(entry.key) || !_nonempty(slot.binding.id) || !_nonempty(slot.unit)) return false;
    if (slot.binding.kind == BindingKind.fact) {
      final object = slot.object;
      if (object == null || !_nonempty(slot.field) || !_nonempty(object.moduleId) ||
          !_nonempty(object.objectType) || !_nonempty(object.objectId)) {
        return false;
      }
    }
  }
  switch (d._formula) {
    case _Formula.sum:
      return d.decimalPolicy == UiFormulaDecimalPolicy.supplierCoreUnsigned &&
          d.slots.values.every((s) => s.binding.kind == BindingKind.fact && s.unit == d.outputUnit);
    case _Formula.product:
      return d.decimalPolicy == UiFormulaDecimalPolicy.supplierCoreUnsigned &&
          _currency(d.targetCurrency) && _nonempty(d.quantityUnit) &&
          d.slots['quantity']!.unit == d.quantityUnit &&
          d.slots['unit_price']!.unit == '${d.targetCurrency}/${d.quantityUnit}';
    case _Formula.margin:
      return (d.decimalPolicy == UiFormulaDecimalPolicy.supplierCoreUnsigned ||
              d.decimalPolicy == UiFormulaDecimalPolicy.supplierCoreProjectedUnsigned) &&
          _currency(d.targetCurrency) && d.slots.values.every((s) => s.unit == d.outputUnit);
    case _Formula.budgetUnitPrice:
      return d.slots.values.every((s) => s.binding.kind == BindingKind.fact && s.unit == d.outputUnit);
    case _Formula.tax:
      if (!_currency(d.targetCurrency) || !_nonempty(d.quoteUnit)) return false;
      final price = d.slots['price']!;
      for (final name in ['price', 'currency', 'tax_mode', 'tax_rate', 'deal_price']) {
        final slot = d.slots[name]!;
        if (slot.binding.kind != BindingKind.fact || slot.object != price.object) {
          return false;
        }
      }
      return d.slots['target_tax_mode']!.binding.kind == BindingKind.uiState &&
          d.slots['currency']!.unit == 'currency' &&
          d.slots['tax_mode']!.unit == 'tax_mode' &&
          d.slots['target_tax_mode']!.unit == 'tax_mode' &&
          d.slots['tax_rate']!.unit == '%' &&
          price.unit == d.slots['deal_price']!.unit;
  }
}
