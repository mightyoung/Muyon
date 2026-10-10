import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import 'dynamic_fixtures.dart';

// Protocol boundary fixture only. F3b owns actual registry evaluation tests.
class DeferredPort implements UiRecomputePort {
  final inputs = <UiRecomputeInput>[];
  final pending = <Completer<UiRecomputeResult>>[];
  @override
  Future<UiRecomputeResult> rebuild(UiRecomputeInput input) {
    inputs.add(input);
    final result = Completer<UiRecomputeResult>();
    pending.add(result);
    return result.future;
  }
}

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

UiPublishToken liveToken(UiSurfaceController c) => UiPublishToken(
  baseSnapshotRef: c.current.snapshot.ref,
  draftRevision: c.session.draftRevision,
  hostGeneration: 1,
  sourceGeneration: 1,
  permissionGeneration: 1,
  scopeKey: 'fixture',
);

UiRecomputeResult candidate(
  UiRecomputeInput input,
  InteractionIntent old,
  String value,
) {
  final ref = SnapshotRef(
    input.previousSnapshot.ref.id,
    input.previousSnapshot.ref.revision + 1,
  );
  return UiRecomputeResult(
    token: input.token,
    nextSnapshot: DataSnapshot(
      ref: ref,
      facts: input.previousSnapshot.facts,
      initialUiState: input.previousSnapshot.initialUiState,
      editSpecs: input.previousSnapshot.editSpecs,
      collections: input.previousSnapshot.collections,
      computedEvidence: input.previousSnapshot.computedEvidence,
      sources: input.previousSnapshot.sources,
      sourceDigests: input.previousSnapshot.sourceDigests,
      computations: {
        'total': ComputedValue(
          value: value,
          inputVersion: ref,
          computationId: 'public-total',
        ),
      },
    ),
    nextIntent: InteractionIntent(
      id: old.id,
      purpose: old.purpose,
      snapshotRef: ref,
      requiredBindings: old.requiredBindings,
      mandatoryStates: old.mandatoryStates,
      allowedActionRefs: old.allowedActionRefs.difference({'confirm'}),
    ),
  );
}

void main() {
  testWidgets(
    'edit publishes into the same mounted session and preserves field focus',
    (tester) async {
      final port = DeferredPort();
      late UiSurfaceController c;
      c = UiSurfaceController(
        mountedPlan(),
        recomputePort: port,
        publishTokenProbe: () => liveToken(c),
      );
      addTearDown(c.dispose);
      final session = c.session;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DynamicUiSurface(plan: c.current, controller: c),
            ),
          ),
        ),
      );
      final field = find.byKey(const ValueKey('quantity-field'));
      await tester.tap(field);
      await tester.enterText(field, '18');
      await tester.pump();
      expect(port.inputs, hasLength(1));
      expect(port.inputs.single.currentUiState['quantity'], '18');
      expect(c.recomputing, isTrue);
      final textController = tester.widget<TextFormField>(field).controller;
      final editable = tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      final focus = editable.focusNode;
      expect(focus.hasFocus, isTrue);
      var sawPublished = false;
      c.addListener(() {
        if (c.current.snapshot.ref.revision == 2) {
          sawPublished = true;
          expect(c.session.snapshot, same(c.current.snapshot));
          expect(c.session.currentPlan, same(c.current));
        }
      });
      port.pending.single.complete(
        candidate(port.inputs.single, c.current.intent, '180'),
      );
      await tester.pump();
      expect(sawPublished, isTrue);
      expect(c.session, same(session));
      expect(c.session.snapshot.initialUiState['quantity'], '12');
      expect(c.session.userOverrides['quantity'], '18');
      expect(c.session.resolve(const BindingRef.computed('total')), '180');
      expect(find.text('Total: 180'), findsOneWidget);
      expect(c.recomputing, isFalse);
      // A host rebuild with the newly published plan must not discard field state.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DynamicUiSurface(plan: c.current, controller: c),
            ),
          ),
        ),
      );
      expect(
        tester.widget<TextFormField>(field).controller,
        same(textController),
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: field, matching: find.byType(EditableText)),
            )
            .focusNode,
        same(focus),
      );
      expect(focus.hasFocus, isTrue);
      await tester.enterText(field, '24');
      await tester.pump();
      expect(port.inputs, hasLength(2));
      expect(port.inputs.last.previousSnapshot, same(c.current.snapshot));
      port.pending.last.complete(
        candidate(port.inputs.last, c.current.intent, '240'),
      );
      await tester.pump();
      expect(c.session.resolve(const BindingRef.computed('total')), '240');
      expect(c.session.draftRevision, 2);
    },
  );
}
