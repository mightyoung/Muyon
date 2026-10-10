import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_ui/muyon_ui.dart' as ui;

import 'aiui5_library2_catalog_test.dart' as fixture;

UiValidationResult componentCase(String name) {
  final schema = library2UiCatalog.components[name]!;
  final properties = <String, Object?>{
    for (final key in schema.requiredProperties)
      key: key == 'kind'
          ? 'bar'
          : key == 'text'
          ? 'source text'
          : 'host label',
  };
  final bindings = <String, BindingRef>{};
  UiEditSpec? spec;
  Object? initial = 'a';
  for (final slot in schema.requiredBindings) {
    bindings[slot] = schema.bindings[slot]!.contains(BindingKind.collection)
        ? BindingRef.collection(switch (name) {
            'Chart' => 'series',
            'CompareTable' => 'table',
            'Choice' => 'options',
            'Checklist' => 'items',
            _ => 'timeline',
          })
        : schema.bindings[slot]!.contains(BindingKind.uiState)
        ? const BindingRef.uiState('k')
        : schema.bindings[slot]!.contains(BindingKind.fact)
        ? const BindingRef.fact('value')
        : schema.bindings[slot]!.contains(BindingKind.sourceSpan)
        ? const BindingRef.sourceSpan('source')
        : throw StateError('unhandled required binding $name/$slot');
  }
  switch (name) {
    case 'Choice':
      spec = UiItemIdsEdit(collectionId: 'options');
    case 'NumberStepper':
    case 'Slider':
      spec = const UiNumberEdit(min: 0, max: 3, step: .5);
      initial = 1.5;
    case 'Toggle':
      spec = const UiBoolEdit();
      initial = true;
    case 'DateField':
      spec = const UiDateEdit(first: '2020-01-01', last: '2030-01-01');
      initial = '2026-10-10';
  }
  return fixture.check(
    name,
    props: properties,
    bindings: bindings,
    spec: spec,
    initial: initial,
    children: name == 'Tabs'
        ? [
            UiNode(
              id: 'section',
              component: 'Section',
              properties: {'title': 'Section'},
            ),
          ]
        : [],
  );
}

void main() {
  testWidgets(
    'all 33 components validate and render through the opted in library2 surface',
    (tester) async {
      expect(library2UiCatalog.components.length, 33);
      for (final name in library2UiCatalog.components.keys) {
        final result = componentCase(name);
        expect(result.isValid, isTrue, reason: '$name: ${result.errors}');
        await tester.pumpWidget(
          MaterialApp(
            theme: ui.muyonTheme(Brightness.light),
            home: Scaffold(
              body: SingleChildScrollView(
                child: DynamicUiSurface(
                  key: ValueKey(name),
                  plan: result.validatedPlan!,
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: name);
        expect(
          find.byKey(const ValueKey('aiui2-target')),
          findsOneWidget,
          reason: name,
        );
        expect(
          find.text('Interactive component unavailable.'),
          findsNothing,
          reason: name,
        );
        expect(
          find.text('AI-generated interface unavailable.'),
          findsNothing,
          reason: name,
        );
      }
    },
  );
}
