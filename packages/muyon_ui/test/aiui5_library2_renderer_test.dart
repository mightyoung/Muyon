import 'dart:convert';

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
        ? BindingRef.fact(name == 'FileCard' ? 'label' : 'value')
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
  test(
    'all 33 real schemas compile through stream2 and shared end validation',
    () {
      for (final name in library2UiCatalog.components.keys) {
        final validated = componentCase(name).validatedPlan!;
        final compiler = UiStreamCompiler(
          session: UiStreamSession(
            surfaceId: validated.plan.surfaceId,
            revision: validated.plan.revision,
            snapshot: validated.snapshot,
            intent: validated.intent,
            catalog: library2UiCatalog,
            root: validated.plan.root,
            protocolVersion: 'aiui-stream/2',
          ),
        );
        for (final node in validated.plan.nodes) {
          final parents = validated.plan.nodes.where(
            (parent) => parent.children.contains(node.id),
          );
          compiler.addLine(
            jsonEncode({
              'op': 'node',
              'id': node.id,
              'component': node.component,
              if (parents.isNotEmpty) 'parent': parents.single.id,
              'props': node.properties,
              'bind': {
                for (final entry in node.bindings.entries)
                  entry.key: {
                    'kind': entry.value.kind.name,
                    'id': entry.value.id,
                  },
              },
            }),
          );
        }
        compiler.addLine('{"op":"end"}');
        expect(compiler.current.badLines, 0, reason: name);
        expect(compiler.current.complete, isTrue, reason: name);
        expect(compiler.current.finalPlan, isNotNull, reason: name);
      }
    },
  );

  Future<UiSurfaceController> mount(
    WidgetTester tester,
    UiValidationResult result, {
    UiObjectOpen? onOpenObject,
    UiEventSink? onEvent,
  }) async {
    expect(result.isValid, isTrue, reason: result.errors.join(','));
    final controller = UiSurfaceController(
      result.validatedPlan!,
      onOpenObject: onOpenObject,
      onEvent: onEvent,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.muyonTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: DynamicUiSurface(
              key: ObjectKey(controller),
              plan: result.validatedPlan!,
              controller: controller,
            ),
          ),
        ),
      ),
    );
    return controller;
  }

  testWidgets(
    'real typed controls dispatch numbers, bool, ISO dates and item IDs without truncation',
    (tester) async {
      for (final component in [
        'NumberStepper',
        'Slider',
        'Toggle',
        'DateField',
        'Choice',
        'Checklist',
      ]) {
        final ids = component == 'Choice' || component == 'Checklist';
        final slot = component == 'Choice'
            ? 'selected'
            : component == 'Checklist'
            ? 'checked'
            : 'value';
        final spec = switch (component) {
          'Choice' => UiItemIdsEdit(collectionId: 'options'),
          'Checklist' => UiItemIdsEdit(collectionId: 'items'),
          'Toggle' => const UiBoolEdit(),
          'DateField' => const UiDateEdit(
            first: '2020-01-01',
            last: '2030-01-01',
          ),
          _ => const UiNumberEdit(min: 0, max: 3, step: .5),
        };
        final result = fixture.check(
          component,
          props: component == 'Checklist' ? {} : {'label': component},
          spec: spec,
          initial: component == 'Toggle'
              ? true
              : component == 'DateField'
              ? '2026-10-10'
              : 1.5,
          bindings: {
            slot: const BindingRef.uiState('k'),
            if (ids)
              component == 'Choice'
                  ? 'options'
                  : 'items': BindingRef.collection(
                component == 'Choice' ? 'options' : 'items',
              ),
          },
          events: {
            'change': ActionBinding(actionRef: 'edit', inputRefs: ['k']),
          },
        );
        final controller = await mount(tester, result);
        switch (component) {
          case 'NumberStepper':
            tester
                .widget<ui.NumberStepper>(find.byType(ui.NumberStepper))
                .onChanged!(2.5);
          case 'Slider':
            tester
                .widget<ui.MuyonSlider>(find.byType(ui.MuyonSlider))
                .onChanged!(2.5);
          case 'Toggle':
            tester.widget<ui.Toggle>(find.byType(ui.Toggle)).onChanged!(false);
          case 'DateField':
            tester.widget<ui.DateField>(find.byType(ui.DateField)).onChanged!(
              DateTime(2026, 10, 11),
            );
          case 'Choice':
            tester.widget<ui.Choice>(find.byType(ui.Choice)).onChangedIds!({
              'a',
            });
          case 'Checklist':
            tester.widget<ui.Checklist>(find.byType(ui.Checklist)).onToggle!(
              0,
              true,
            );
        }
        await tester.pump();
        expect(controller.session.draftRevision, 1, reason: component);
        if (ids) {
          expect(controller.session.selections['k'], ['a']);
          expect(controller.session.userOverrides, isEmpty);
          expect(
            controller.session.resolve(const BindingRef.uiState('k')),
            isNull,
          );
        } else {
          expect(
            controller.session.userOverrides['k'],
            component == 'Toggle'
                ? false
                : component == 'DateField'
                ? '2026-10-11'
                : 2.5,
          );
        }
      }
    },
  );

  testWidgets(
    'Tabs and Disclosure use controlled view keys and do not increment draft',
    (tester) async {
      final tabs = fixture.check(
        'Tabs',
        bindings: {'selected': const BindingRef.uiState('k')},
        spec: const UiStringEdit(view: true),
        initial: 'first',
        events: {
          'change': ActionBinding(actionRef: 'edit', inputRefs: ['k']),
        },
        children: [
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
        ],
      );
      var controller = await mount(tester, tabs);
      final tabNode = controller.current.plan.nodes.firstWhere(
        (node) => node.id == 'target',
      );
      expect(
        await controller.dispatchCaptured(
          controller.captureRender(),
          tabNode,
          'change',
          'unknown',
        ),
        UiDispatchOutcome.invalid,
      );
      expect(controller.session.viewValues, isEmpty);
      tester.widget<ui.MuyonTabs>(find.byType(ui.MuyonTabs)).onChanged!(1);
      await tester.pump();
      expect(controller.session.viewValues['k'], 'second');
      expect(
        tester.widget<ui.MuyonTabs>(find.byType(ui.MuyonTabs)).selectedIndex,
        1,
      );
      expect(controller.session.draftRevision, 0);
      final disclosure = fixture.check(
        'Disclosure',
        props: {'title': 'Details'},
        bindings: {'expanded': const BindingRef.uiState('k')},
        spec: const UiBoolEdit(view: true),
        initial: true,
        events: {
          'change': ActionBinding(actionRef: 'edit', inputRefs: ['k']),
        },
      );
      controller = await mount(tester, disclosure);
      tester.widget<ui.Disclosure>(find.byType(ui.Disclosure)).onChanged!(
        false,
      );
      await tester.pump();
      expect(controller.session.viewValues['k'], false);
      expect(controller.session.draftRevision, 0);
      expect(
        tester.widget<ui.Disclosure>(find.byType(ui.Disclosure)).expanded,
        false,
      );
    },
  );

  testWidgets(
    'invalid decimal Field resets to accepted text and valid decimals retain precision',
    (tester) async {
      final result = fixture.check(
        'Field',
        props: {'label': 'Quantity'},
        initial: '1.5',
        spec: UiStringEdit(accepts: RegExp(r'^\d+(\.\d+)?$').hasMatch),
        bindings: {
          'value': const BindingRef.fact('value'),
          'draft': const BindingRef.uiState('k'),
        },
        events: {
          'change': ActionBinding(actionRef: 'edit', inputRefs: ['k']),
        },
      );
      final controller = await mount(tester, result);
      await tester.enterText(
        find.byKey(const ValueKey('target-field')),
        'oops',
      );
      await tester.pump();
      expect(controller.session.draftRevision, 0);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('target-field')))
            .controller!
            .text,
        '1.5',
      );
      await tester.enterText(
        find.byKey(const ValueKey('target-field')),
        '2.75',
      );
      await tester.pump();
      expect(controller.session.userOverrides['k'], '2.75');
      expect(controller.session.draftRevision, 1);
      expect(controller.current.snapshot.facts['value']!.value, 1.5);
    },
  );

  testWidgets(
    'stable row local navigation uses trusted object and stale closure dispatches nothing',
    (tester) async {
      final result = fixture.check(
        'CompareTable',
        props: {'label': 'Quotes'},
        bindings: {'rows': const BindingRef.collection('table')},
        events: {'tap': ActionBinding(actionRef: 'openRow')},
      );
      final opened = <ObjectRef>[];
      var sink = 0;
      final controller = await mount(
        tester,
        result,
        onOpenObject: (object, {required nodeId}) async {
          opened.add(object);
        },
        onEvent: (_) async {
          sink++;
        },
      );
      final old = tester
          .widget<TextButton>(find.byKey(const ValueKey('aiui2-target-row-a')))
          .onPressed!;
      final next = validateUiPlan(
        controller.current.plan.copyWith(revision: 2),
        controller.current.snapshot,
        controller.current.intent,
        controller.current.catalog,
      ).validatedPlan!;
      expect(controller.acceptPlan(next), isTrue);
      old();
      await tester.pump();
      expect(opened, isEmpty);
      tester
          .widget<TextButton>(find.byKey(const ValueKey('aiui2-target-row-a')))
          .onPressed!();
      await tester.pump();
      expect(
        opened.single,
        const ObjectRef(moduleId: 'm', objectType: 't', objectId: 'a'),
      );
      expect(sink, 0);
      expect(controller.session.draftRevision, 0);
      expect(controller.session.detailNode, isNull);
    },
  );

  testWidgets('same object from two tables retains each originating node ID', (
    tester,
  ) async {
    final initial = fixture
        .check(
          'CompareTable',
          props: {'label': 'Quotes'},
          bindings: {'rows': const BindingRef.collection('table')},
          events: {'tap': ActionBinding(actionRef: 'openRow')},
        )
        .validatedPlan!;
    final target = initial.plan.nodes.firstWhere((n) => n.id == 'target');
    final nodes = [
      for (final node in initial.plan.nodes)
        if (node.id == initial.plan.root)
          node.copyWith(children: [...node.children, 'second'])
        else
          node,
      UiNode(
        id: 'second',
        component: target.component,
        properties: target.properties,
        bindings: target.bindings,
        events: target.events,
      ),
    ];
    final result = validateUiPlan(
      initial.plan.copyWith(nodes: nodes),
      initial.snapshot,
      initial.intent,
      initial.catalog,
    );
    expect(result.isValid, isTrue, reason: result.errors.join(','));
    final opened = <(ObjectRef, String)>[];
    var businessCalls = 0;
    await mount(
      tester,
      result,
      onEvent: (_) async {
        businessCalls++;
      },
      onOpenObject: (object, {required nodeId}) async {
        opened.add((object, nodeId));
      },
    );
    for (final id in ['target', 'second']) {
      final button = find.byKey(ValueKey('aiui2-$id-row-a'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
    }
    expect(opened.map((value) => value.$2), ['target', 'second']);
    expect(opened[0].$1, opened[1].$1);
    expect(businessCalls, 0);
  });

  testWidgets(
    'Chart preserves null, conflict, units and same-source decimal text',
    (tester) async {
      final old = componentCase('Chart').validatedPlan!;
      for (final missing in [false, true]) {
        final snapshot = DataSnapshot(
          ref: old.snapshot.ref,
          facts: {
            'label': old.snapshot.facts['label']!,
            'value': SnapshotFact(
              object: old.snapshot.facts['value']!.object,
              field: 'amount',
              value: missing ? null : '1.250000',
              state: missing ? FactState.notDisclosed : FactState.conflict,
              unit: 'CNY',
              sourceRefs: ['source'],
            ),
          },
          sources: old.snapshot.sources,
          sourceDigests: old.snapshot.sourceDigests,
          collections: old.snapshot.collections,
          initialUiState: old.snapshot.initialUiState,
        );
        final result = validateUiPlan(
          old.plan,
          snapshot,
          old.intent,
          old.catalog,
        );
        await mount(tester, result);
        final chart = tester.widget<ui.Chart>(find.byType(ui.Chart));
        expect(chart.points.length, missing ? 0 : 1);
        if (!missing) expect(chart.points.single.value, 1.25);
        expect(
          find.textContaining(missing ? 'notDisclosed' : 'conflict'),
          findsWidgets,
        );
        expect(find.textContaining('CNY'), findsWidgets);
        expect(find.textContaining(missing ? '未提供' : '1.250000'), findsWidgets);
        expect(find.textContaining('来源 source'), findsWidgets);
        expect(find.textContaining('最优'), findsNothing);
      }
    },
  );

  testWidgets(
    'nullable controlled Disclosure does not fall back to model initial expansion',
    (tester) async {
      final result = fixture.check(
        'Disclosure',
        props: {'title': 'Details', 'initiallyExpanded': true},
        bindings: {'expanded': const BindingRef.uiState('k')},
        spec: const UiBoolEdit(view: true, nullable: true),
        initial: null,
        events: {
          'change': ActionBinding(actionRef: 'edit', inputRefs: ['k']),
        },
      );
      final controller = await mount(tester, result);
      expect(find.text('Details：未设置展开状态'), findsOneWidget);
      expect(find.byType(ui.Disclosure), findsNothing);
      expect(controller.session.viewValues, isEmpty);
      expect(controller.session.draftRevision, 0);
    },
  );

  testWidgets('old library1 remains a whole-surface fallback', (tester) async {
    final current = componentCase('Heading').validatedPlan!;
    final legacy = validateUiPlan(
      current.plan.copyWith(catalogVersion: libraryUiCatalog.version),
      current.snapshot,
      current.intent,
      libraryUiCatalog,
    );
    expect(legacy.isValid, isTrue);
    await mount(tester, legacy);
    expect(find.byKey(const ValueKey('aiui2-target')), findsNothing);
    expect(find.byType(ui.Heading), findsNothing);
  });

  testWidgets(
    'nullable bounded date opens within host bounds without inventing a draft value',
    (tester) async {
      final result = fixture.check(
        'DateField',
        props: {'label': 'Date'},
        bindings: {'value': const BindingRef.uiState('k')},
        spec: const UiDateEdit(
          first: '2030-01-01',
          last: '2040-01-01',
          nullable: true,
        ),
        initial: null,
        events: {
          'change': ActionBinding(actionRef: 'edit', inputRefs: ['k']),
        },
      );
      final controller = await mount(tester, result);
      await tester.tap(find.byKey(const ValueKey('date-field')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsOneWidget);
      expect(controller.session.draftRevision, 0);
      expect(controller.session.userOverrides, isEmpty);
    },
  );

  testWidgets(
    'all 33 components validate and render through the opted in library2 surface',
    (tester) async {
      const widgetTypes = <String, Type>{
        'PageScaffold': ui.PageScaffold,
        'MasterDetail': ui.MasterDetail,
        'Field': TextFormField,
        'Table': Table,
        'SourceList': TextButton,
        'ObjectChip': ui.ObjectChip,
        'StatusBadge': ui.StatusBadge,
        'ScopeChip': ui.ScopeChip,
        'WarnBanner': ui.WarnBanner,
        'SegmentedPill': ui.SegmentedPill,
        'ConfirmCard': ui.ConfirmCard,
        'BatchConfirmCard': ui.BatchConfirmCard,
        'Heading': ui.Heading,
        'Prose': ui.Prose,
        'Section': ui.Section,
        'Columns': ui.Columns,
        'Tabs': ui.MuyonTabs,
        'Disclosure': ui.Disclosure,
        'KeyValue': ui.KeyValue,
        'Metric': ui.Metric,
        'CompareTable': ui.CompareTable,
        'Chart': ui.Chart,
        'Choice': ui.Choice,
        'Form': ui.MuyonForm,
        'NumberStepper': ui.NumberStepper,
        'Slider': ui.MuyonSlider,
        'Toggle': ui.Toggle,
        'DateField': ui.DateField,
        'SourceCard': ui.SourceCard,
        'FileCard': ui.FileCard,
        'ProgressCard': ui.ProgressCard,
        'Checklist': ui.Checklist,
        'Timeline': ui.Timeline,
      };
      expect(
        library2UiCatalog.components.keys.toSet(),
        widgetTypes.keys.toSet(),
      );
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
          find.descendant(
            of: find.byKey(const ValueKey('aiui2-target')),
            matching: find.byType(widgetTypes[name]!),
          ),
          findsWidgets,
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
