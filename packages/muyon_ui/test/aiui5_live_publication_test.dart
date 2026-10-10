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

class ReentrantGetterController extends UiSurfaceController {
  ReentrantGetterController(
    super.plan, {
    super.recomputePort,
    super.publishTokenProbe,
  });
  bool armed = false;
  int afterPublicationReads = 0;
  @override
  ValidatedUiPlan get current {
    final value = super.current;
    if (armed && value.snapshot.ref.revision == 2) {
      afterPublicationReads++;
      session.selectView('sort', 'value');
    }
    return value;
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
  test(
    'no overridable host getter runs between publication and session install',
    () async {
      final port = DeferredPort();
      late ReentrantGetterController c;
      c = ReentrantGetterController(
        mountedPlan(),
        recomputePort: port,
        publishTokenProbe: () => liveToken(c),
      );
      addTearDown(c.dispose);
      c.armed = true;
      final result = c.recompute();
      port.pending.single.complete(
        candidate(port.inputs.single, c.current.intent, '180'),
      );
      expect(await result, UiPublishOutcome.published);
      expect(c.afterPublicationReads, 0);
      c.armed = false;
      expect(c.session.snapshot, same(c.current.snapshot));
      expect(c.session.currentPlan, same(c.current));
      expect(c.session.resolve(const BindingRef.computed('total')), '180');
    },
  );

  test('incomplete recomputation injection fails closed', () {
    expect(
      () => UiSurfaceController(mountedPlan(), recomputePort: DeferredPort()),
      throwsArgumentError,
    );
  });

  test(
    'read-only admission reaches both controller and direct session events',
    () async {
      var calls = 0;
      final c = UiSurfaceController(
        mountedPlan(),
        readOnlyProbe: () => true,
        onEvent: (_) async {
          calls++;
        },
      );
      addTearDown(c.dispose);
      final edit = event('readonly-edit', 'quantity', 'change', payload: '18');
      expect(
        c.session.dispatch(edit, c.current, c.current.catalog),
        UiEventOutcome.invalid,
      );
      expect(await c.dispatch(edit), UiDispatchOutcome.stale);
      expect(
        await c.dispatch(event('readonly-business', 'confirm', 'confirm')),
        UiDispatchOutcome.stale,
      );
      expect(c.session.userOverrides, isEmpty);
      expect(c.session.draftRevision, 0);
      expect(c.operationRefs, isEmpty);
      expect(calls, 0);
    },
  );

  test('reverse host completion publishes only the latest request', () async {
    final port = DeferredPort();
    late UiSurfaceController c;
    c = UiSurfaceController(
      mountedPlan(),
      recomputePort: port,
      publishTokenProbe: () => liveToken(c),
    );
    addTearDown(c.dispose);
    final first = c.recompute(), latest = c.recompute();
    port.pending.last.complete(
      candidate(port.inputs.last, c.current.intent, '180'),
    );
    expect(await latest, UiPublishOutcome.published);
    final published = c.current;
    port.pending.first.complete(
      candidate(port.inputs.first, published.intent, '999'),
    );
    expect(await first, UiPublishOutcome.staleToken);
    expect(c.current, same(published));
    expect(c.session.snapshot, same(published.snapshot));
    expect(c.session.resolve(const BindingRef.computed('total')), '180');
  });

  test(
    'final probe view and source mutations reject both-object installation',
    () {
      for (final source in [false, true]) {
        final port = DeferredPort();
        late UiSurfaceController c;
        var reads = 0;
        c = UiSurfaceController(
          mountedPlan(),
          recomputePort: port,
          publishTokenProbe: () {
            if (++reads == 2) {
              if (source) {
                c.session.updateSourceDigest('text', 'changed');
              } else {
                c.session.selectView('sort', 'value');
              }
            }
            return liveToken(c);
          },
        );
        addTearDown(c.dispose);
        final base = c.current;
        final input = UiRecomputeInput(
          previousSnapshot: base.snapshot,
          currentUiState: base.snapshot.initialUiState,
          token: liveToken(c),
        );
        final result = candidate(input, base.intent, '180');
        final plan = base.plan.copyWith(
          revision: base.plan.revision + 1,
          snapshotRef: result.nextSnapshot!.ref,
          nodes: [
            for (final n in base.plan.nodes)
              n.copyWith(
                events: {
                  for (final entry in n.events.entries)
                    if (result.nextIntent!.allowedActionRefs.contains(
                      entry.value.actionRef,
                    ))
                      entry.key: entry.value,
                },
              ),
          ],
        );
        expect(
          c.publish(
            UiVersionBatch(
              token: input.token,
              snapshot: result.nextSnapshot!,
              intent: result.nextIntent!,
              plan: plan,
            ),
          ),
          UiPublishOutcome.staleToken,
        );
        expect(c.current, same(base));
        expect(c.session.snapshot, same(base.snapshot));
        expect(c.session.resolve(const BindingRef.computed('total')), 120);
        expect(c.outdated, isTrue);
      }
    },
  );

  test(
    'publication retains pending operation and correlates its original receipt',
    () async {
      final port = DeferredPort(), sink = Completer<void>();
      late UiSurfaceController c;
      var calls = 0;
      c = UiSurfaceController(
        mountedPlan(),
        recomputePort: port,
        publishTokenProbe: () => liveToken(c),
        onEvent: (_) {
          calls++;
          return sink.future;
        },
      );
      addTearDown(c.dispose);
      final sent = c.dispatch(event('pending', 'confirm', 'confirm'));
      final pending = c.pendingAction('pending');
      expect(pending, isNotNull);
      expect(
        await c.dispatch(event('edit', 'quantity', 'change', payload: '18')),
        UiDispatchOutcome.applied,
      );
      expect(
        c.session.dispatch(
          event('direct-business', 'confirm', 'confirm'),
          c.current,
          c.current.catalog,
        ),
        UiEventOutcome.invalid,
      );
      port.pending.single.complete(
        candidate(port.inputs.single, c.current.intent, '180'),
      );
      await Future<void>.value();
      expect(c.current.snapshot.ref.revision, 2);
      expect(c.session.resolve(const BindingRef.computed('total')), '180');
      expect(c.pendingAction('pending'), same(pending));
      expect(c.operationRefs, contains('public-qty'));
      expect(
        c.acceptReceipt(
          const UiBusinessReceipt(
            eventId: 'pending',
            operationKeyRef: 'public-qty',
            draftRevision: 0,
            status: UiReceiptStatus.succeeded,
            message: 'host result',
            isSimulated: true,
          ),
        ),
        isTrue,
      );
      expect(c.receipts['confirm']!.draftRevision, 0);
      expect(c.operationRefs, contains('public-qty'));
      sink.complete();
      expect(await sent, UiDispatchOutcome.routed);
      expect(calls, 1);
    },
  );

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
