import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

// These are explicit integration blockers, not claims that the gallery is
// already stream-compatible. Keep the scalar and local-action gates intact.
void main() {
  const ref = SnapshotRef('snapshot', 1);
  const object = ObjectRef(
    moduleId: 'test',
    objectType: 'item',
    objectId: 'one',
  );
  UiValidationResult check(
    String component,
    String slot,
    BindingKind kind,
    Object? value, {
    Map<String, Object?> properties = const {},
    Map<String, ActionBinding> events = const {},
  }) {
    final snapshot = DataSnapshot(
      ref: ref,
      facts: {
        if (kind == BindingKind.fact)
          'data': SnapshotFact(
            object: object,
            field: 'data',
            value: value,
            state: FactState.verified,
          ),
      },
      computations: {
        if (kind == BindingKind.computed)
          'data': ComputedValue(
            value: value,
            inputVersion: ref,
            computationId: 'host-computation',
          ),
      },
      initialUiState: {if (kind == BindingKind.uiState) 'data': value},
    );
    final intent = InteractionIntent(
      id: 'intent',
      purpose: 'offline contract check',
      snapshotRef: ref,
      allowedActionRefs: {'edit', 'detail'},
    );
    return validateUiPlan(
      UIPlan(
        surfaceId: 'surface',
        revision: 1,
        catalogVersion: libraryUiCatalog.version,
        snapshotRef: ref,
        intentRef: intent.id,
        root: 'root',
        nodes: [
          UiNode(
            id: 'root',
            component: component,
            properties: properties,
            bindings: {slot: BindingRef(kind, 'data')},
            events: events,
          ),
        ],
      ),
      snapshot,
      intent,
      libraryUiCatalog,
    );
  }

  test('Toggle boolean edit remains a declared typed-action blocker', () {
    final result = check(
      'Toggle', 'value', BindingKind.uiState, false,
      properties: {'label': '开关'},
      events: {
        'change': ActionBinding(actionRef: 'edit', inputRefs: ['data']),
      },
    );
    expect(result.errors, ['edit_input']);
    expect(result.validatedPlan, isNull);
  });

  test('CompareTable detail remains blocked without object identity', () {
    final result = check(
      'CompareTable', 'rows', BindingKind.computed, 'host rows reference',
      properties: {'label': '对比'},
      events: {'tap': ActionBinding(actionRef: 'detail')},
    );
    expect(result.errors, ['detail_input']);
    expect(result.validatedPlan, isNull);
  });

  test('Checklist facts cannot be edited as local UI state', () {
    final result = check(
      'Checklist', 'items', BindingKind.fact, 'host items reference',
      events: {
        'change': ActionBinding(actionRef: 'edit', inputRefs: ['data']),
      },
    );
    expect(result.errors, ['edit_input']);
    expect(result.validatedPlan, isNull);
  });

  for (final (component, slot, kind, properties, error) in [
    ('Chart', 'data', BindingKind.fact, {'kind': 'bar'}, 'unknown_fact:data'),
    ('Chart', 'data', BindingKind.computed, {'kind': 'bar'},
      'unknown_or_stale_computation:data'),
    ('Table', 'value', BindingKind.computed, {'label': '表格'},
      'unknown_or_stale_computation:data'),
    ('CompareTable', 'rows', BindingKind.computed, {'label': '对比'},
      'unknown_or_stale_computation:data'),
    ('Checklist', 'items', BindingKind.uiState, <String, Object?>{},
      'unknown_state:data'),
    ('Timeline', 'events', BindingKind.fact, <String, Object?>{},
      'unknown_fact:data'),
  ]) {
    test('$component $kind rejects raw collections pending host adapter', () {
      final result = check(
        component, slot, kind, const [1, 2], properties: properties,
      );
      expect(result.errors, [error]);
      expect(result.validatedPlan, isNull);
      // This control isolates collection shape from tree/catalog failures.
      expect(
        check(component, slot, kind, 'host reference', properties: properties)
            .errors,
        isEmpty,
      );
    });
  }
}
