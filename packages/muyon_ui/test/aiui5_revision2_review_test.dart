import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_ui/muyon_ui.dart' as ui;

import 'aiui5_stateful_capture_test.dart' show CapturePort, tokenFor;
import 'workspace_controller_test.dart' show MemoryStore;

ValidatedUiPlan reviewPlan(
  String component, {
  int revision = 1,
  int draftRevision = 0,
  List<String> ids = const ['a'],
  bool view = false,
  double max = 10,
  bool multiColumn = false,
}) {
  final ref = SnapshotRef('s', revision);
  final idsKind = component == 'Choice' || component == 'Checklist';
  final snapshot = DataSnapshot(
    ref: ref,
    facts: {
      for (final id in ['a', 'b', 'c']) ...{
        'label-$id': SnapshotFact(
          object: ObjectRef(moduleId: 'm', objectType: 't', objectId: id),
          field: 'label',
          value: id.toUpperCase(),
          state: FactState.verified,
        ),
        'value-$id': SnapshotFact(
          object: ObjectRef(moduleId: 'm', objectType: 't', objectId: id),
          field: 'value',
          value: id == 'a' ? 2 : 1,
          state: id == 'b' ? FactState.conflict : FactState.verified,
        ),
      },
    },
    initialUiState: {'sort': 'original', if (!idsKind) 'k': 2.0},
    editSpecs: {
      'sort': const UiStringEdit(view: true),
      'k': idsKind
          ? UiItemIdsEdit(
              collectionId: 'items',
              multiple: true,
              initial: ids,
              view: view,
            )
          : UiNumberEdit(min: 0, max: max),
    },
    collections: {
      'items': UiCollection(
        id: 'items',
        columns: const [UiColumn('label', 'Label')],
        rows: [
          for (final id in ['a', 'b', 'c'])
            UiRow(itemId: id, cells: {'label': BindingRef.fact('label-$id')}),
        ],
      ),
      'table': UiCollection(
        id: 'table',
        columns: [
          const UiColumn('value', 'Value'),
          if (multiColumn) const UiColumn('label', 'Label'),
        ],
        rows: [
          for (final id in ['a', 'b', 'c'])
            UiRow(
              itemId: id,
              object: ObjectRef(moduleId: 'm', objectType: 't', objectId: id),
              cells: {
                'value': BindingRef.fact('value-$id'),
                if (multiColumn) 'label': BindingRef.fact('label-$id'),
              },
            ),
        ],
      ),
    },
    actionContext: idsKind && !view
        ? UiActionContext(
            draftRevision: draftRevision,
            draft: {'k': ids},
            operations: {
              'op': HostOperationRef(
                draftRevision: draftRevision,
                inputRefs: {'k'},
              ),
            },
          )
        : null,
  );
  final nodes = [
    UiNode(
      id: 'root',
      component: 'PageScaffold',
      properties: {'title': 'Review'},
      children: [
        'target',
        if (component == 'CompareTable') 'sorter',
        if (idsKind && !view) 'approval',
      ],
    ),
    UiNode(
      id: 'target',
      component: component,
      properties: component == 'Checklist'
          ? {}
          : component == 'Prose'
          ? {'text': 'First claim.\n\nSecond claim.'}
          : {'label': 'Review', if (component == 'Choice') 'multiple': true},
      bindings: switch (component) {
        'Prose' => {},
        'Choice' => {
          'options': const BindingRef.collection('items'),
          'selected': const BindingRef.uiState('k'),
        },
        'Checklist' => {
          'items': const BindingRef.collection('items'),
          'checked': const BindingRef.uiState('k'),
        },
        'CompareTable' => {
          'rows': const BindingRef.collection('table'),
          'sort': const BindingRef.uiState('sort'),
        },
        _ => {'value': const BindingRef.uiState('k')},
      },
      events: component == 'Prose'
          ? {}
          : component == 'CompareTable'
          ? {'tap': ActionBinding(actionRef: 'openRow')}
          : {
              'change': ActionBinding(actionRef: 'edit', inputRefs: ['k']),
            },
    ),
    if (component == 'CompareTable')
      UiNode(
        id: 'sorter',
        component: 'SegmentedPill',
        properties: {},
        bindings: {'selected': const BindingRef.uiState('sort')},
        events: {
          'change': ActionBinding(actionRef: 'sort', inputRefs: ['sort']),
        },
      ),
    if (idsKind && !view)
      UiNode(
        id: 'approval',
        component: 'Form',
        properties: {'title': 'Approve', 'submitLabel': 'Approve'},
        events: {
          'submit': ActionBinding(
            actionRef: 'submit',
            inputRefs: ['k'],
            operationKeyRef: 'op',
            expectedDraftRevision: draftRevision,
          ),
        },
      ),
  ];
  // Prose has only its declared model text property.
  final plan = UIPlan(
    surfaceId: 's',
    revision: revision,
    catalogVersion: 'library-2',
    snapshotRef: ref,
    intentRef: 'i',
    root: 'root',
    nodes: nodes,
  );
  final intent = InteractionIntent(
    id: 'i',
    purpose: 'review',
    snapshotRef: ref,
    allowedActionRefs: {'edit', 'submit', 'sort', 'openRow'},
  );
  final checked = validateUiPlan(plan, snapshot, intent, library2UiCatalog);
  expect(checked.isValid, isTrue, reason: checked.errors.join(','));
  return checked.validatedPlan!;
}

Future<void> mountReview(WidgetTester tester, UiSurfaceController c) =>
    tester.pumpWidget(
      MaterialApp(
        theme: ui.muyonTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: DynamicUiSurface(plan: c.current, controller: c),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'Prose model marker is visible announced and copied with each paragraph',
    (tester) async {
      final semantics = tester.ensureSemantics();

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final c = UiSurfaceController(reviewPlan('Prose'));
      addTearDown(c.dispose);
      await mountReview(tester, c);
      final prose = find.byType(ui.Prose);
      final visible = tester
          .widgetList<SelectableText>(
            find.descendant(of: prose, matching: find.byType(SelectableText)),
          )
          .map((w) => w.data!)
          .toList();
      expect(visible, ['模型所述：First claim.', '模型所述：Second claim.']);
      final semantic = tester
          .widgetList<Semantics>(
            find.descendant(of: prose, matching: find.byType(Semantics)),
          )
          .firstWhere(
            (w) => w.properties.customSemanticsActions?.isNotEmpty ?? false,
          );
      expect(semantic.properties.label, contains('模型所述'));
      expect(semantic.properties.label, contains('Second claim.'));
      semantic.properties.customSemanticsActions!.values.single();
      await tester.pump();
      expect(copied, '模型所述：First claim.\n\n模型所述：Second claim.');
      expect(
        tester
            .getSemantics(
              find
                  .descendant(of: prose, matching: find.byType(Semantics))
                  .first,
            )
            .label,
        contains('模型所述：Second claim.'),
      );
      semantics.dispose();
    },
  );
  testWidgets(
    'single column CompareTable sorts actual rows marks and row buttons with stable IDs',
    (tester) async {
      final opened = <String>[];
      final c = UiSurfaceController(
        reviewPlan('CompareTable'),
        onOpenObject: (object, {required nodeId}) async {
          opened.add(object.objectId);
        },
      );
      addTearDown(c.dispose);
      await mountReview(tester, c);
      expect(
        tester.widget<ui.CompareTable>(find.byType(ui.CompareTable)).rows,
        [
          ['2'],
          ['1'],
          ['1'],
        ],
      );
      final sorter = c.current.plan.nodes.firstWhere((n) => n.id == 'sorter');
      expect(
        await c.dispatch(c.eventFor(sorter, 'change', 'value')),
        UiDispatchOutcome.applied,
      );
      await tester.pump();
      final table = tester.widget<ui.CompareTable>(
        find.byType(ui.CompareTable),
      );
      expect(table.rows, [
        ['1'],
        ['1'],
        ['2'],
      ]);
      expect(table.marks[(0, 0)], ui.CompareMark.unverified);
      final buttons = find.descendant(
        of: find.byKey(const ValueKey('aiui2-target')),
        matching: find.byType(TextButton),
      );
      expect(tester.widgetList<TextButton>(buttons).map((w) => w.key), [
        const ValueKey('aiui2-target-row-b'),
        const ValueKey('aiui2-target-row-c'),
        const ValueKey('aiui2-target-row-a'),
      ]);
      await tester.tap(find.byKey(const ValueKey('aiui2-target-row-b')));
      await tester.pump();
      expect(opened, ['b']);
      expect(c.session.draftRevision, 0);
      expect(
        await c.dispatch(c.eventFor(sorter, 'change', 'original')),
        UiDispatchOutcome.applied,
      );
      await tester.pump();
      expect(
        tester.widget<ui.CompareTable>(find.byType(ui.CompareTable)).rows,
        [
          ['2'],
          ['1'],
          ['1'],
        ],
      );
    },
  );
  for (final component in ['Choice', 'Checklist']) {
    test(
      '$component accepted ID edit routes frozen business list after matching new host draft',
      () async {
        late UiSurfaceController c;
        var calls = 0;
        c = UiSurfaceController(
          reviewPlan(component),
          recomputePort: CapturePort(),
          publishTokenProbe: () => tokenFor(c),
          onEvent: (_) async {
            calls++;
          },
        );
        addTearDown(c.dispose);
        final target = c.current.plan.nodes.firstWhere((n) => n.id == 'target');
        expect(
          await c.dispatch(c.eventFor(target, 'change', ['c', 'b'])),
          UiDispatchOutcome.applied,
        );
        await Future<void>.delayed(Duration.zero);
        final next = reviewPlan(
          component,
          revision: 2,
          draftRevision: 1,
          ids: ['b', 'c'],
        );
        expect(
          c.publish(
            UiVersionBatch(
              token: tokenFor(c),
              snapshot: next.snapshot,
              intent: next.intent,
              plan: next.plan,
            ),
          ),
          UiPublishOutcome.published,
        );
        final submit = c.current.plan.nodes.firstWhere(
          (n) => n.id == 'approval',
        );
        final event = c.eventFor(submit, 'submit');
        expect(await c.dispatch(event), UiDispatchOutcome.routed);
        expect(calls, 1);
        expect(c.pendingAction(event.eventId)!.inputs['k'], ['b', 'c']);
        expect(
          () => (c.pendingAction(event.eventId)!.inputs['k'] as List).add('a'),
          throwsUnsupportedError,
        );
        expect(
          await c.dispatch(c.eventFor(submit, 'submit')),
          UiDispatchOutcome.duplicate,
        );
        expect(calls, 1);
      },
    );
    test(
      '$component selections survive a real in memory workspace close reopen',
      () async {
        final store = MemoryStore();
        final plan = reviewPlan(component);
        final c = await UiWorkspaceController.open(
          store: store,
          taskId: 'task',
          scopeKey: 'scope',
          plan: plan,
          schemaVersion: 2,
        );
        final target = c.surface.current.plan.nodes.firstWhere(
          (n) => n.id == 'target',
        );
        await c.surface.dispatch(c.surface.eventFor(target, 'change', ['b']));
        await c.flush();
        c.dispose();
        final reopened = await UiWorkspaceController.open(
          store: store,
          taskId: 'task',
          scopeKey: 'scope',
          plan: plan,
          schemaVersion: 2,
        );
        addTearDown(reopened.dispose);
        expect(reopened.surface.session.selections['k'], ['b']);
        expect(reopened.surface.session.selectionOverrides, contains('k'));
        expect(reopened.surface.session.draftRevision, 1);
        expect(reopened.readOnly, isFalse);
      },
    );
  }
  test('library2 collection checkpoint JSON roundtrip reopens without activating stored capabilities', () async {
    final store = MemoryStore();
    final plan = reviewPlan('Choice');
    final c = await UiWorkspaceController.open(
      store: store,
      taskId: 'task',
      scopeKey: 'scope',
      plan: plan,
      schemaVersion: 2,
    );
    await c.flush();
    c.dispose();
    store.value = StoredUiWorkspace.fromJson(
      jsonDecode(jsonEncode(store.value!.toJson())) as Map<String, dynamic>,
    );
    final reopened = await UiWorkspaceController.open(
      store: store,
      taskId: 'task',
      scopeKey: 'scope',
      plan: plan,
      schemaVersion: 2,
    );
    addTearDown(reopened.dispose);
    expect(reopened.readOnly, isFalse);
    expect(
      reopened.surface.current.plan.nodes
          .firstWhere((n) => n.id == 'target')
          .bindings['options'],
      const BindingRef.collection('items'),
    );
  });
  test('typed restore quarantines old number outside new bound and keeps original durable bytes', () async {
    final store = MemoryStore();
    final old = reviewPlan('NumberStepper');
    final c = await UiWorkspaceController.open(
      store: store,
      taskId: 'task',
      scopeKey: 'scope',
      plan: old,
      schemaVersion: 2,
    );
    final target = c.surface.current.plan.nodes.firstWhere(
      (n) => n.id == 'target',
    );
    expect(
      await c.surface.dispatch(c.surface.eventFor(target, 'change', 9.0)),
      UiDispatchOutcome.applied,
    );
    await c.flush();
    c.dispose();
    final before = jsonEncode(store.value!.toJson());
    final reopened = await UiWorkspaceController.open(
      store: store,
      taskId: 'task',
      scopeKey: 'scope',
      plan: reviewPlan('NumberStepper', revision: 2, max: 5),
      schemaVersion: 2,
    );
    addTearDown(reopened.dispose);
    expect(
      reopened.surface.session.resolve(const BindingRef.uiState('k')),
      2.0,
    );
    expect(reopened.surface.session.readableDraft['k'], 9.0);
    expect(reopened.surface.session.unreadableReasons['k'], 'range');
    expect(reopened.readOnly, isTrue);
    await expectLater(reopened.flush(), throwsStateError);
    expect(jsonEncode(store.value!.toJson()), before);
  });
  test(
    'view ID selections restore separately without draft or manual override',
    () async {
      final store = MemoryStore();
      final plan = reviewPlan('Checklist', view: true);
      final c = await UiWorkspaceController.open(
        store: store,
        taskId: 'task',
        scopeKey: 'scope',
        plan: plan,
      );
      final node = c.surface.current.plan.nodes.firstWhere(
        (n) => n.id == 'target',
      );
      expect(
        await c.surface.dispatch(c.surface.eventFor(node, 'change', ['b'])),
        UiDispatchOutcome.applied,
      );
      await c.flush();
      c.dispose();
      final restored = await UiWorkspaceController.open(
        store: store,
        taskId: 'task',
        scopeKey: 'scope',
        plan: plan,
      );
      addTearDown(restored.dispose);
      expect(store.value!.schemaVersion, 2);
      expect(restored.surface.session.viewSelections['k'], ['b']);
      expect(restored.surface.session.selections['k'], ['b']);
      expect(restored.surface.session.selectionOverrides, isEmpty);
      expect(restored.surface.session.draftRevision, 0);
    },
  );
  test(
    'restored removed item remains readable and cannot become business input',
    () async {
      final store = MemoryStore();
      final plan = reviewPlan('Choice');
      final c = await UiWorkspaceController.open(
        store: store,
        taskId: 'task',
        scopeKey: 'scope',
        plan: plan,
      );
      c.surface.session.edit('k', ['b']);
      await c.flush();
      c.dispose();
      final raw =
          jsonDecode(jsonEncode(store.value!.toJson())) as Map<String, dynamic>;
      raw['selections']['k'] = ['removed'];
      store.value = StoredUiWorkspace.fromJson(raw);
      final restored = await UiWorkspaceController.open(
        store: store,
        taskId: 'task',
        scopeKey: 'scope',
        plan: plan,
      );
      addTearDown(restored.dispose);
      expect(restored.surface.session.selections['k'], ['a']);
      expect(restored.surface.session.readableDraft['k'], ['removed']);
      expect(restored.surface.session.unreadableReasons['k'], 'unknown_item');
      expect(restored.readOnly, isTrue);
      final submit = restored.surface.current.plan.nodes.firstWhere(
        (n) => n.id == 'approval',
      );
      expect(
        await restored.surface.dispatch(
          restored.surface.eventFor(submit, 'submit'),
        ),
        UiDispatchOutcome.stale,
      );
    },
  );
  testWidgets(
    'multi column CompareTable retains original rows without invented sort key',
    (tester) async {
      final c = UiSurfaceController(
        reviewPlan('CompareTable', multiColumn: true),
      );
      addTearDown(c.dispose);
      await mountReview(tester, c);
      final sorter = c.current.plan.nodes.firstWhere((n) => n.id == 'sorter');
      await c.dispatch(c.eventFor(sorter, 'change', 'value'));
      await tester.pump();
      expect(
        tester.widget<ui.CompareTable>(find.byType(ui.CompareTable)).rows,
        [
          ['2', 'A'],
          ['1', 'B'],
          ['1', 'C'],
        ],
      );
    },
  );
}
