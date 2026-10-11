import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import 'dynamic_fixtures.dart';

// Copied from aiui5_live_publication_test.dart: one validated, mounted plan.
ValidatedUiPlan mountedPlan() {
  final base = actionPlan();
  final p = base.plan.copyWith(
    nodes: [
      base.plan.nodes.first.copyWith(
        children: [...base.plan.nodes.first.children, 'total'],
      ),
      ...base.plan.nodes.skip(1),
      UiNode(
        id: 'total',
        component: 'Table',
        properties: {'label': 'Total'},
        bindings: {'value': const BindingRef.computed('total')},
      ),
    ],
  );
  return validateUiPlan(
    p,
    base.snapshot,
    base.intent,
    base.catalog,
  ).validatedPlan!;
}

void main() {
  test('surface_without_probe_treats_content_as_external', () {
    final controller = UiSurfaceController(mountedPlan());
    addTearDown(controller.dispose);
    expect(controller.externalContent, isTrue);
  });

  test('surface_with_clean_probe_is_not_external', () {
    final controller = UiSurfaceController(
      mountedPlan(),
      externalContentProbe: () => false,
    );
    addTearDown(controller.dispose);
    expect(controller.externalContent, isFalse);
  });

  test('surface_probe_that_throws_treats_content_as_external', () {
    final controller = UiSurfaceController(
      mountedPlan(),
      externalContentProbe: () => throw StateError('probe failed'),
    );
    addTearDown(controller.dispose);
    expect(controller.externalContent, isTrue);
  });

  test('surface_probe_recovering_to_clean_reads_clean_again', () {
    var throwing = true;
    final controller = UiSurfaceController(
      mountedPlan(),
      externalContentProbe: () {
        if (throwing) throw StateError('probe failed');
        return false;
      },
    );
    addTearDown(controller.dispose);
    expect(controller.externalContent, isTrue);
    throwing = false;
    expect(controller.externalContent, isFalse);
  });
}
