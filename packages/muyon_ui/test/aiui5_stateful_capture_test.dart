import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'aiui5_library2_catalog_test.dart' as fixture;

class CapturePort implements UiRecomputePort {
  int calls = 0;
  @override
  Future<UiRecomputeResult> rebuild(UiRecomputeInput input) async {
    calls++;
    return UiRecomputeResult(
      token: input.token,
      errors: ['fixture_unavailable'],
    );
  }
}

class StatefulCaptureController extends UiSurfaceController {
  StatefulCaptureController(
    super.plan, {
    super.onEvent,
    super.recomputePort,
    super.publishTokenProbe,
  });
  int dispatches = 0;
  @override
  Future<UiDispatchOutcome> dispatch(UiEvent event) {
    dispatches++;
    return super.dispatch(event);
  }
}

DataSnapshot snapshotWith(
  DataSnapshot old,
  SnapshotRef ref, {
  bool reverse = false,
}) {
  final options = UiCollection(
    id: 'options',
    columns: const [UiColumn('label', 'Label')],
    rows: [
      for (final id in reverse ? ['b', 'a'] : ['a', 'b'])
        UiRow(itemId: id, cells: const {'label': BindingRef.fact('label')}),
    ],
  );
  return DataSnapshot(
    ref: ref,
    facts: old.facts,
    initialUiState: old.initialUiState,
    editSpecs: old.editSpecs,
    collections: {...old.collections, 'options': options},
    sources: old.sources,
    sourceDigests: old.sourceDigests,
    computations: old.computations,
    computedEvidence: old.computedEvidence,
  );
}

InteractionIntent intentWith(InteractionIntent old, SnapshotRef ref) =>
    InteractionIntent(
      id: old.id,
      purpose: old.purpose,
      snapshotRef: ref,
      requiredBindings: old.requiredBindings,
      mandatoryStates: old.mandatoryStates,
      allowedActionRefs: old.allowedActionRefs,
    );

ValidatedUiPlan componentPlan(String component, {String tabInitial = 'first'}) {
  final result = fixture.check(
    component,
    props: component == 'Choice'
        ? {'label': 'Choice', 'multiple': true}
        : component == 'Disclosure'
        ? {'title': 'Details'}
        : {},
    bindings: component == 'Choice'
        ? {
            'options': const BindingRef.collection('options'),
            'selected': const BindingRef.uiState('k'),
          }
        : {
            component == 'Tabs' ? 'selected' : 'expanded':
                const BindingRef.uiState('k'),
          },
    initial: component == 'Tabs' ? tabInitial : false,
    spec: component == 'Choice'
        ? UiItemIdsEdit(collectionId: 'options', multiple: true, initial: ['a'])
        : component == 'Tabs'
        ? const UiStringEdit(view: true)
        : const UiBoolEdit(view: true),
    events: {
      'change': ActionBinding(actionRef: 'edit', inputRefs: ['k']),
    },
    children: component == 'Tabs'
        ? [
            UiNode(
              id: 'first',
              component: 'Section',
              properties: {'title': 'First'},
            ),
            UiNode(
              id: 'second',
              component: 'Section',
              properties: {'title': 'Second'},
            ),
          ]
        : [],
  );
  expect(result.isValid, isTrue, reason: result.errors.join(','));
  final original = result.validatedPlan!;
  final snapshot = snapshotWith(original.snapshot, original.snapshot.ref);
  return validateUiPlan(
    original.plan,
    snapshot,
    original.intent,
    original.catalog,
  ).validatedPlan!;
}

UiPublishToken tokenFor(UiSurfaceController c) => UiPublishToken(
  baseSnapshotRef: c.current.snapshot.ref,
  draftRevision: c.session.draftRevision,
  hostGeneration: 1,
  sourceGeneration: 1,
  permissionGeneration: 1,
  scopeKey: 'fixture',
);

Finder componentFinder(String component) => switch (component) {
  'Choice' => find.byType(Choice),
  'Tabs' => find.byType(MuyonTabs),
  _ => find.byType(Disclosure),
};

VoidCallback bottomCallback(
  WidgetTester tester,
  String component,
  bool semantics,
) {
  if (!semantics) {
    final key = switch (component) {
      'Choice' => 'choice-a',
      'Tabs' => 'tab-0',
      _ => 'disclosure-toggle',
    };
    return tester.widget<InkWell>(find.byKey(ValueKey(key))).onTap!;
  }
  final label = switch (component) {
    'Choice' => 'A',
    'Tabs' => 'First',
    _ => 'Details',
  };
  return tester
      .widgetList<Semantics>(
        find.descendant(
          of: componentFinder(component),
          matching: find.byType(Semantics),
        ),
      )
      .firstWhere(
        (s) =>
            s.properties.onTap != null &&
            (s.properties.label?.startsWith(label) ?? false),
      )
      .properties
      .onTap!;
}

Future<void> mount(WidgetTester tester, UiSurfaceController c) =>
    tester.pumpWidget(
      MaterialApp(
        theme: muyonTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: DynamicUiSurface(
              key: const ValueKey('same-surface'),
              plan: c.current,
              controller: c,
            ),
          ),
        ),
      ),
    );

void main() {
  for (final component in ['Choice', 'Tabs', 'Disclosure']) {
    for (final semantics in [false, true]) {
      testWidgets(
        'old $component ${semantics ? 'Semantics' : 'InkWell'} callback cannot acquire rebuilt capture',
        (tester) async {
          final port = CapturePort();
          var businessCalls = 0;
          late StatefulCaptureController c;
          c = StatefulCaptureController(
            componentPlan(component),
            recomputePort: port,
            publishTokenProbe: () => tokenFor(c),
            onEvent: (_) async {
              businessCalls++;
            },
          );
          addTearDown(c.dispose);
          await mount(tester, c);
          final state = tester.state(componentFinder(component));
          final old = bottomCallback(tester, component, semantics);
          final base = c.current;
          final snapshot = snapshotWith(
            base.snapshot,
            const SnapshotRef('s', 2),
            reverse: true,
          );
          final intent = intentWith(base.intent, snapshot.ref);
          final plan = base.plan.copyWith(
            revision: 2,
            snapshotRef: snapshot.ref,
            nodes: [
              for (final node in base.plan.nodes)
                if (component == 'Tabs' && node.id == 'target')
                  node.copyWith(children: node.children.reversed.toList())
                else
                  node,
            ],
          );
          expect(
            c.publish(
              UiVersionBatch(
                token: tokenFor(c),
                snapshot: snapshot,
                intent: intent,
                plan: plan,
              ),
            ),
            UiPublishOutcome.published,
          );
          await mount(tester, c);
          expect(tester.state(componentFinder(component)), same(state));
          old();
          await tester.pump();
          expect(c.dispatches, 0);
          expect(c.session.draftRevision, 0);
          expect(c.session.viewValues, isEmpty);
          expect(c.session.selectionOverrides, isEmpty);
          if (component == 'Choice') expect(c.session.selections['k'], ['a']);
          expect(port.calls, 0);
          expect(businessCalls, 0);
          bottomCallback(tester, component, semantics)();
          await tester.pump();
          expect(c.dispatches, 1);
          expect(
            component == 'Choice'
                ? c.session.selectionOverrides.contains('k')
                : c.session.viewValues.containsKey('k'),
            isTrue,
          );
          expect(port.calls, component == 'Choice' ? 1 : 0);
          expect(businessCalls, 0);
        },
      );
    }
  }

  testWidgets(
    'unknown initial Tabs selection renders home but unknown runtime child is rejected',
    (tester) async {
      final c = UiSurfaceController(
        componentPlan('Tabs', tabInitial: 'missing'),
      );
      addTearDown(c.dispose);
      await mount(tester, c);
      expect(find.byKey(const ValueKey('aiui2-first')), findsOneWidget);
      expect(find.byKey(const ValueKey('aiui2-second')), findsNothing);
      expect(c.session.resolve(const BindingRef.uiState('k')), 'missing');
      final node = c.current.plan.nodes.firstWhere((n) => n.id == 'target');
      expect(
        await c.dispatch(c.eventFor(node, 'change', 'missing')),
        UiDispatchOutcome.invalid,
      );
      expect(c.session.viewValues, isEmpty);
      expect(c.session.draftRevision, 0);
      tester.widget<InkWell>(find.byKey(const ValueKey('tab-1'))).onTap!();
      await tester.pump();
      expect(c.session.viewValues['k'], 'second');
      expect(find.byKey(const ValueKey('aiui2-second')), findsOneWidget);
      expect(c.session.draftRevision, 0);
    },
  );
}
