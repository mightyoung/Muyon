import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

// CF-FIX-A T1: computed bindings must agree with their evidence state.
// GAP1 (CR-CF2-LIB2 review, C1): `verified` over a null value must be refused;
// `notDisclosed` over a null value stays accepted (control).

const _ref = SnapshotRef('s', 1);
const _object = ObjectRef(moduleId: 'm', objectType: 't', objectId: 'a');

/// A `price` fact that is not disclosed, plus a computed `total` whose value
/// and evidence state are supplied by the case.
DataSnapshot _snapshot({required Object? value, required FactState evidence}) =>
    DataSnapshot(
      ref: _ref,
      facts: {
        'price': SnapshotFact(
          object: _object,
          field: 'price',
          value: null,
          state: FactState.notDisclosed,
          unit: 'CNY/件',
        ),
      },
      computations: {
        'total': ComputedValue(
          value: value,
          inputVersion: _ref,
          computationId: 'review-total',
        ),
      },
      computedEvidence: {
        'total': UiComputedEvidence(
          state: evidence,
          unit: 'CNY',
          sourceRefs: const [],
        ),
      },
    );

UiValidationResult _validate(DataSnapshot snapshot) {
  final intent = InteractionIntent(
    id: 'i',
    purpose: 'review',
    snapshotRef: _ref,
    mandatoryStates: const {FactState.notDisclosed},
    allowedActionRefs: library2UiCatalog.actions.keys.toSet(),
  );
  final plan = UIPlan(
    surfaceId: 's',
    revision: 1,
    catalogVersion: 'library-2',
    snapshotRef: _ref,
    intentRef: 'i',
    root: 'root',
    nodes: [
      UiNode(
        id: 'root',
        component: 'PageScaffold',
        properties: {'title': 'review'},
        children: ['metric', 'kv'],
      ),
      UiNode(
        id: 'metric',
        component: 'Metric',
        properties: {'label': 'Total'},
        bindings: {'value': const BindingRef.computed('total')},
      ),
      UiNode(
        id: 'kv',
        component: 'KeyValue',
        bindings: {'value': const BindingRef.fact('price')},
      ),
    ],
  );
  return validateUiPlan(plan, snapshot, intent, library2UiCatalog);
}

void main() {
  group('T1: computed value and evidence agree', () {
    test(
      'a computed total claiming verified with a null value is rejected',
      () {
        final result = _validate(
          _snapshot(value: null, evidence: FactState.verified),
        );
        expect(result.isValid, isFalse, reason: '${result.errors}');
      },
    );

    test('control: a null value with notDisclosed evidence is still accepted', () {
      final result = _validate(
        _snapshot(value: null, evidence: FactState.notDisclosed),
      );
      expect(result.isValid, isTrue, reason: '${result.errors}');
    });
  });
}
