import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import 'dynamic_fixtures.dart';

void main() {
  test(
    'three_event_routes_preserve_draft_and_port_receipt_authority',
    () async {
      final requests = <UiEvent>[];
      final controller = UiSurfaceController(
        actionPlan(),
        onEvent: (e) async {
          requests.add(e);
        },
      );
      addTearDown(controller.dispose);
      expect(
        await controller.dispatch(event('source', 'source', 'tap')),
        UiDispatchOutcome.applied,
      );
      expect(requests, isEmpty);
      expect(
        await controller.dispatch(event('business', 'confirm', 'confirm')),
        UiDispatchOutcome.routed,
      );
      expect(requests.single.kind, 'confirm');
      expect(
        controller.receipts,
        isEmpty,
        reason: 'Calling a sink does not prove success',
      );
      expect(
        controller.acceptReceipt(
          const UiBusinessReceipt(
            eventId: 'business',
            operationKeyRef: 'other',
            draftRevision: 0,
            status: UiReceiptStatus.succeeded,
            message: 'Forged',
            isSimulated: true,
          ),
        ),
        isFalse,
      );
      expect(
        controller.acceptReceipt(
          const UiBusinessReceipt(
            eventId: 'business',
            operationKeyRef: 'public-qty',
            draftRevision: 0,
            status: UiReceiptStatus.succeeded,
            message: 'Public memory quantity is now 12',
            isSimulated: true,
          ),
        ),
        isTrue,
      );
      expect(controller.receipts['confirm']!.isSimulated, isTrue);
      expect(
        await controller.dispatch(event('explain', 'warning', 'tap')),
        UiDispatchOutcome.routed,
      );
      expect(requests.length, 2);
      expect(controller.current.snapshot.facts['qty']!.value, 10);
    },
  );
  test('cancel_and_changed_draft_never_reach_business_port', () async {
    var calls = 0;
    final cancelled = UiSurfaceController(
      actionPlan(),
      onEvent: (_) async {
        calls++;
      },
    );
    addTearDown(cancelled.dispose);
    expect(
      await cancelled.dispatch(event('cancel', 'confirm', 'cancel')),
      UiDispatchOutcome.applied,
    );
    expect(
      await cancelled.dispatch(event('confirm', 'confirm', 'confirm')),
      UiDispatchOutcome.stale,
    );
    final edited = UiSurfaceController(
      actionPlan(),
      onEvent: (_) async {
        calls++;
      },
    );
    addTearDown(edited.dispose);
    expect(
      await edited.dispatch(event('edit', 'quantity', 'change', payload: '14')),
      UiDispatchOutcome.applied,
    );
    expect(
      await edited.dispatch(event('confirm2', 'confirm', 'confirm')),
      UiDispatchOutcome.stale,
    );
    expect(calls, 0);
  });
  test('in_flight_duplicate_and_old_revision_are_not_sent_twice', () async {
    final barrier = Completer<void>();
    var calls = 0;
    final controller = UiSurfaceController(
      actionPlan(),
      onEvent: (_) {
        calls++;
        return barrier.future;
      },
    );
    addTearDown(controller.dispose);
    final first = controller.dispatch(event('one', 'confirm', 'confirm'));
    expect(
      await controller.dispatch(event('two', 'confirm', 'confirm')),
      UiDispatchOutcome.duplicate,
    );
    expect(
      await controller.dispatch(event('old', 'warning', 'tap', revision: 3)),
      UiDispatchOutcome.stale,
    );
    barrier.complete();
    expect(await first, UiDispatchOutcome.routed);
    expect(calls, 1);
  });

  test('full_replanning_preserves_patch_id_history', () {
    final initial = actionPlan(),
        controller = UiSurfaceController(actionPlan());
    addTearDown(controller.dispose);
    final p = controller.current.plan;
    final patch = UiPatch(
      patchId: 'stable-id',
      surfaceId: p.surfaceId,
      baseRevision: 4,
      nextRevision: 5,
      snapshotRevision: p.snapshotRef,
      ops: [
        UiPatchOperation.replace(
          p.nodes.first.copyWith(properties: {'title': 'First patch'}),
        ),
      ],
    );
    expect(controller.applyPatch(patch).isValid, isTrue);
    final next = validateUiPlan(
      controller.current.plan.copyWith(revision: 6),
      controller.current.snapshot,
      controller.current.intent,
      controller.current.catalog,
    ).validatedPlan!;
    expect(controller.acceptPlan(next), isTrue);
    final reused = UiPatch(
      patchId: 'stable-id',
      surfaceId: initial.plan.surfaceId,
      baseRevision: 6,
      nextRevision: 7,
      snapshotRevision: p.snapshotRef,
      ops: [
        UiPatchOperation.replace(
          p.nodes.first.copyWith(properties: {'title': 'Reused ID'}),
        ),
      ],
    );
    expect(controller.applyPatch(reused).isValid, isFalse);
    expect(controller.current.plan.revision, 6);
  });
  test(
    'view_sort_preserves_business_draft_revision_and_confirmation',
    () async {
      final initial = actionPlan();
      var calls = 0;
      final p = initial.plan.copyWith(
        nodes: [
          initial.plan.nodes.first.copyWith(
            children: [...initial.plan.nodes.first.children, 'sort'],
          ),
          ...initial.plan.nodes.skip(1),
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
      expect(
        await controller.dispatch(
          event('sort', 'sort', 'change', payload: 'value'),
        ),
        UiDispatchOutcome.applied,
      );
      expect(controller.session.draftRevision, 0);
      expect(
        await controller.dispatch(event('confirm', 'confirm', 'confirm')),
        UiDispatchOutcome.routed,
      );
      expect(calls, 1);
    },
  );
  test(
    'failed_port_does_not_forge_receipt_or_unlock_unknown_operation',
    () async {
      final controller = UiSurfaceController(
        actionPlan(),
        onEvent: (_) async {
          throw StateError('fixture transport failed');
        },
      );
      addTearDown(controller.dispose);
      expect(
        await controller.dispatch(event('one', 'confirm', 'confirm')),
        UiDispatchOutcome.routed,
      );
      expect(controller.receipts, isEmpty);
      expect(controller.pendingAction('one'), isNotNull);
      expect(
        await controller.dispatch(event('two', 'confirm', 'confirm')),
        UiDispatchOutcome.duplicate,
      );
    },
  );
  test('next_semantic_event_observes_actual_patched_current', () async {
    late UiSurfaceController controller;
    final observed = <int>[];
    controller = UiSurfaceController(
      actionPlan(),
      onEvent: (e) async {
        observed.add(e.observedRevision);
        observed.add(controller.current.plan.revision);
      },
    );
    addTearDown(controller.dispose);
    final p = controller.current.plan;
    expect(
      controller
          .applyPatch(
            UiPatch(
              patchId: 'p5',
              surfaceId: p.surfaceId,
              baseRevision: 4,
              nextRevision: 5,
              snapshotRevision: p.snapshotRef,
              ops: [
                UiPatchOperation.replace(
                  p.nodes.first.copyWith(properties: {'title': 'Current5'}),
                ),
              ],
            ),
          )
          .isValid,
      isTrue,
    );
    final node = controller.current.plan.nodes.singleWhere(
      (n) => n.id == 'warning',
    );
    expect(
      await controller.dispatch(controller.eventFor(node, 'tap')),
      UiDispatchOutcome.routed,
    );
    expect(observed, [5, 5]);
  });
}
