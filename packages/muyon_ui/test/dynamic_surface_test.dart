import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'dynamic_fixtures.dart';

void main() {
  testWidgets('mandatory_unknown_survives_fallback', (tester) async {
    final snapshot = DataSnapshot(
      ref: const SnapshotRef('public', 1),
      facts: {
        'noise': SnapshotFact(
          object: const ObjectRef(
            moduleId: 'public',
            objectType: 'quote',
            objectId: 'c',
          ),
          field: 'noise',
          value: null,
          state: FactState.notDisclosed,
          sourceRefs: ['source'],
        ),
      },
      sources: {
        'source': const SourceSpanRef(
          artifact: ArtifactRef(
            moduleId: 'public',
            artifactId: 'original',
            contentDigest: 'v1',
          ),
          originalText: 'Public source: noise not provided.',
          start: 0,
          end: 34,
        ),
      },
      sourceDigests: {'original': 'v1'},
    );
    final intent = InteractionIntent(
      id: 'compare',
      purpose: 'Public comparison',
      snapshotRef: snapshot.ref,
      requiredBindings: {const BindingRef.fact('noise')},
      mandatoryStates: {FactState.notDisclosed},
    );
    final plan = UIPlan(
      surfaceId: 'public',
      revision: 1,
      catalogVersion: minimalUiCatalog.version,
      snapshotRef: snapshot.ref,
      intentRef: intent.id,
      root: 'root',
      nodes: [
        UiNode(
          id: 'root',
          component: 'Unsupported',
          bindings: {'value': const BindingRef.fact('noise')},
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: muyonTheme(Brightness.light),
        home: Scaffold(
          body: SemanticUiSurface(
            snapshot: snapshot,
            intent: intent,
            result: UiPlanningResult(
              decision: UiDisplayDecision.supplement,
              reasonCode: 'fixture',
              plan: plan,
            ),
            originalAnswer: 'Complete original answer.',
          ),
        ),
      ),
    );
    expect(find.text('Complete original answer.'), findsOneWidget);
    expect(find.textContaining('notDisclosed'), findsOneWidget);
    expect(find.text('Public source: noise not provided.'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });

  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    testWidgets('local_events_patch_and_back_preserve_actual_current $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var calls = 0;
      final controller = UiSurfaceController(
        actionPlan(),
        onEvent: (_) async {
          calls++;
        },
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: muyonTheme(Brightness.dark),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(1.8),
                ),
                child: renderUiPlan(
                  controller.current,
                  onEvent: (_) async {},
                  controller: controller,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('quantity-field')),
        '14',
      );
      await tester.tap(find.byKey(const ValueKey('source-expand')));
      await tester.pump();
      expect(find.text('Public original: 10 pieces.'), findsOneWidget);
      final p = controller.current.plan;
      final patch = UiPatch(
        patchId: 'p5',
        surfaceId: p.surfaceId,
        baseRevision: 4,
        nextRevision: 5,
        snapshotRevision: controller.current.snapshot.ref,
        ops: [
          UiPatchOperation.replace(
            p.nodes.first.copyWith(properties: {'title': 'Actual current 5'}),
          ),
        ],
      );
      expect(controller.applyPatch(patch).isValid, isTrue);
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('detail-detail')));
      await tester.tap(find.byKey(const ValueKey('detail-detail')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('detail-back')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('quantity-field')))
            .controller!
            .text,
        '14',
      );
      expect(controller.current.plan.revision, 5);
      expect(
        controller.session.resolve(const BindingRef.uiState('quantity')),
        '14',
      );
      expect(find.text('Actual current 5'), findsOneWidget);
      expect(calls, 0);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('confirm_and_cancel_show_only_port_receipts', (tester) async {
    late UiSurfaceController controller;
    var quantity = 10, calls = 0;
    controller = UiSurfaceController(
      actionPlan(),
      onEvent: (e) async {
        calls++;
        quantity = 12;
        controller.acceptReceipt(
          UiBusinessReceipt(
            eventId: e.eventId,
            operationKeyRef: 'public-qty',
            draftRevision: 0,
            status: UiReceiptStatus.succeeded,
            message: 'Public memory quantity: $quantity',
            isSimulated: true,
          ),
        );
      },
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: muyonTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: renderUiPlan(
              controller.current,
              onEvent: (_) async {},
              controller: controller,
            ),
          ),
        ),
      ),
    );
    expect(quantity, 10);
    expect(find.text('更多'), findsNothing);
    await tester.ensureVisible(find.text('仅这一次'));
    await tester.tap(find.text('仅这一次'));
    await tester.pumpAndSettle();
    expect(quantity, 12);
    expect(calls, 1);
    expect(find.textContaining('Simulated receipt'), findsOneWidget);
    expect(find.textContaining('Public memory quantity: 12'), findsOneWidget);
    expect(controller.current.snapshot.facts['qty']!.value, 10);
  });

  testWidgets('unimplemented_catalog_keeps_mandatory_snapshot_projection', (
    tester,
  ) async {
    final s = publicSnapshot(), i = publicIntent(publicSnapshot());
    final catalog = UiCatalog(
      version: 'unimplemented',
      components: {
        'Unsupported': UiComponentSchema(
          bindings: {
            'qty': {BindingKind.fact},
            'noise': {BindingKind.fact},
            'source': {BindingKind.sourceSpan},
          },
        ),
      },
      actions: {},
    );
    final plan = UIPlan(
      surfaceId: 'unimplemented',
      revision: 1,
      catalogVersion: catalog.version,
      snapshotRef: s.ref,
      intentRef: i.id,
      root: 'root',
      nodes: [
        UiNode(
          id: 'root',
          component: 'Unsupported',
          bindings: {
            'qty': const BindingRef.fact('qty'),
            'noise': const BindingRef.fact('noise'),
            'source': const BindingRef.sourceSpan('source'),
          },
        ),
      ],
    );
    final checked = validateUiPlan(plan, s, i, catalog).validatedPlan!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: renderUiPlan(checked, onEvent: (_) async {})),
      ),
    );
    expect(find.textContaining('notDisclosed'), findsOneWidget);
    expect(find.text('Public original: 10 pieces.'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });
  testWidgets('local_sort_changes_rows_without_calling_port', (tester) async {
    final initial = actionPlan();
    var calls = 0;
    final p = initial.plan.copyWith(
      nodes: [
        initial.plan.nodes.first.copyWith(
          children: [...initial.plan.nodes.first.children, 'table', 'sort'],
        ),
        ...initial.plan.nodes.skip(1),
        UiNode(
          id: 'table',
          component: 'Table',
          properties: {
            'label': 'Total',
            'alternateLabel': 'Comparison quantity',
          },
          bindings: {
            'value': const BindingRef.computed('total'),
            'alternate': const BindingRef.fact('qty'),
            'sort': const BindingRef.uiState('sort'),
          },
        ),
        UiNode(
          id: 'sort',
          component: 'SegmentedPill',
          bindings: {'selected': const BindingRef.uiState('sort')},
          events: {
            'change': ActionBinding(actionRef: 'sort', inputRefs: ['sort']),
          },
        ),
      ],
    );
    final checked = validateUiPlan(
      p,
      initial.snapshot,
      initial.intent,
      dynamicUiCatalog,
    ).validatedPlan!;
    final controller = UiSurfaceController(
      checked,
      onEvent: (_) async {
        calls++;
      },
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: muyonTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: renderUiPlan(
              checked,
              onEvent: (_) async {},
              controller: controller,
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.text('Total: 120')).dy,
      lessThan(tester.getTopLeft(find.text('Comparison quantity: 10')).dy),
    );
    await tester.ensureVisible(find.text('Sort by value'));
    await tester.tap(find.text('Sort by value'));
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('Comparison quantity: 10')).dy,
      lessThan(tester.getTopLeft(find.text('Total: 120')).dy),
    );
    expect(calls, 0);
  });

  testWidgets('stable_node_reorder_preserves_focus', (tester) async {
    final c = UiSurfaceController(actionPlan());
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: muyonTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: renderUiPlan(
              c.current,
              onEvent: (_) async {},
              controller: c,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('quantity-field')));
    await tester.pump();
    final focus = tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode;
    expect(focus.hasFocus, isTrue);
    final p = c.current.plan;
    expect(
      c
          .applyPatch(
            UiPatch(
              patchId: 'reorder',
              surfaceId: p.surfaceId,
              baseRevision: 4,
              nextRevision: 5,
              snapshotRevision: p.snapshotRef,
              ops: [
                UiPatchOperation.replace(
                  p.nodes.first.copyWith(
                    children: [
                      'noise',
                      'quantity',
                      'source',
                      'detail',
                      'confirm',
                      'warning',
                    ],
                  ),
                ),
              ],
            ),
          )
          .isValid,
      isTrue,
    );
    await tester.pump();
    expect(
      identical(
        tester.widget<EditableText>(find.byType(EditableText)).focusNode,
        focus,
      ),
      isTrue,
    );
    expect(focus.hasFocus, isTrue);
  });
  testWidgets('confirmation_expansion_survives_unrelated_local_event', (
    tester,
  ) async {
    final c = UiSurfaceController(actionPlan(), onEvent: (_) async {});
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: muyonTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: renderUiPlan(
              c.current,
              onEvent: (_) async {},
              controller: c,
            ),
          ),
        ),
      ),
    );
    final payload = tester
        .widget<ConfirmCard>(find.byType(ConfirmCard))
        .item
        .payload;
    await tester.ensureVisible(find.text('展开内容'));
    await tester.tap(find.text('展开内容'));
    await tester.pump();
    expect(find.text(payload), findsOneWidget);
    await c.dispatch(event('expand-source', 'source', 'tap'));
    await tester.pump();
    expect(find.text(payload), findsOneWidget);
  });
  testWidgets('batch_pending_and_cancelled_are_not_called_decided', (
    tester,
  ) async {
    final initial = actionPlan();
    final p = initial.plan.copyWith(
      nodes: [
        for (final n in initial.plan.nodes)
          if (n.id == 'confirm')
            n.copyWith(component: 'BatchConfirmCard')
          else
            n,
      ],
    );
    final checked = validateUiPlan(
      p,
      initial.snapshot,
      initial.intent,
      dynamicUiCatalog,
    ).validatedPlan!;
    final c = UiSurfaceController(checked, onEvent: (_) async {});
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: muyonTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: renderUiPlan(checked, onEvent: (_) async {}, controller: c),
          ),
        ),
      ),
    );
    await c.dispatch(event('cancel', 'confirm', 'cancel'));
    await tester.pump();
    expect(find.text('已拒绝'), findsOneWidget);
    expect(find.text('已决定'), findsNothing);
  });

  testWidgets(
    'single_confirmation_uses_actual_cancel_pending_and_failed_state',
    (tester) async {
      final cancelled = UiSurfaceController(
        actionPlan(),
        onEvent: (_) async {},
      );
      addTearDown(cancelled.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: muyonTheme(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: renderUiPlan(
                cancelled.current,
                onEvent: (_) async {},
                controller: cancelled,
              ),
            ),
          ),
        ),
      );
      await cancelled.dispatch(event('cancel', 'confirm', 'cancel'));
      await tester.pump();
      expect(
        tester.widget<ConfirmCard>(find.byType(ConfirmCard)).status,
        BusinessStatus.rejected,
      );
      final pending = UiSurfaceController(actionPlan(), onEvent: (_) async {});
      addTearDown(pending.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: muyonTheme(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: renderUiPlan(
                pending.current,
                onEvent: (_) async {},
                controller: pending,
              ),
            ),
          ),
        ),
      );
      await pending.dispatch(event('request', 'confirm', 'confirm'));
      await tester.pump();
      expect(
        tester.widget<ConfirmCard>(find.byType(ConfirmCard)).status,
        BusinessStatus.running,
      );
      expect(
        pending.acceptReceipt(
          const UiBusinessReceipt(
            eventId: 'request',
            operationKeyRef: 'public-qty',
            draftRevision: 0,
            status: UiReceiptStatus.failed,
            message: 'Public fixture rejected write',
            isSimulated: true,
          ),
        ),
        isTrue,
      );
      await tester.pump();
      expect(
        tester.widget<ConfirmCard>(find.byType(ConfirmCard)).status,
        BusinessStatus.failed,
      );
    },
  );
}
