import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import 'aiui5_stateful_capture_test.dart' show CapturePort, tokenFor;

ValidatedUiPlan approvalPlan(int revision) {
  final ref = SnapshotRef('s', revision);
  final snapshot = DataSnapshot(
    ref: ref,
    facts: {
      'qty': SnapshotFact(
        object: const ObjectRef(
          moduleId: 'm',
          objectType: 'item',
          objectId: 'a',
        ),
        field: 'qty',
        value: '2',
        state: FactState.verified,
      ),
    },
    initialUiState: const {'qty': '2'},
    editSpecs: {
      'qty': revision == 1
          ? const UiStringEdit()
          : UiStringEdit(accepts: (value) => value == '2' || value == '4'),
    },
    actionContext: UiActionContext(
      draftRevision: revision == 1 ? 0 : 1,
      draft: const {'qty': '2'},
      operations: {
        'op': HostOperationRef(
          draftRevision: revision == 1 ? 0 : 1,
          inputRefs: {'qty'},
        ),
      },
    ),
  );
  final intent = InteractionIntent(
    id: 'i',
    purpose: 'approval',
    snapshotRef: ref,
    allowedActionRefs: {'edit', 'submit'},
  );
  final plan = UIPlan(
    surfaceId: 's',
    revision: revision,
    catalogVersion: 'library-2',
    snapshotRef: ref,
    intentRef: 'i',
    root: 'root',
    nodes: [
      UiNode(
        id: 'root',
        component: 'PageScaffold',
        properties: {'title': 'Approval'},
        children: ['qty', 'approval'],
      ),
      UiNode(
        id: 'qty',
        component: 'Field',
        properties: {'label': 'Quantity'},
        bindings: {
          'value': const BindingRef.fact('qty'),
          'draft': const BindingRef.uiState('qty'),
        },
        events: {
          'change': ActionBinding(actionRef: 'edit', inputRefs: ['qty']),
        },
      ),
      UiNode(
        id: 'approval',
        component: 'Form',
        properties: {'title': 'Approve', 'submitLabel': 'Approve'},
        events: {
          'submit': ActionBinding(
            actionRef: 'submit',
            inputRefs: ['qty'],
            operationKeyRef: 'op',
            expectedDraftRevision: revision == 1 ? 0 : 1,
          ),
        },
      ),
    ],
  );
  final checked = validateUiPlan(plan, snapshot, intent, library2UiCatalog);
  expect(checked.isValid, isTrue, reason: checked.errors.join(','));
  return checked.validatedPlan!;
}

void main() {
  test('retained invalid quantity rejects business despite matching active draft and repairs only legal String', () async {
    final old = approvalPlan(1), next = approvalPlan(2);
    var businessCalls = 0;
    late UiSurfaceController controller;
    controller = UiSurfaceController(
      old,
      recomputePort: CapturePort(),
      publishTokenProbe: () => tokenFor(controller),
      onEvent: (_) async {
        businessCalls++;
      },
    );
    addTearDown(controller.dispose);
    controller.session.edit('qty', '3');
    expect(controller.session.draftRevision, 1);
    expect(
      controller.publish(
        UiVersionBatch(
          token: tokenFor(controller),
          snapshot: next.snapshot,
          intent: next.intent,
          plan: next.plan,
        ),
      ),
      UiPublishOutcome.published,
    );
    expect(controller.session.readableDraft['qty'], '3');
    expect(controller.session.unreadableReasons['qty'], 'format');
    expect(controller.session.resolve(const BindingRef.uiState('qty')), '2');
    expect(controller.current.snapshot.actionContext!.draft['qty'], '2');
    expect(
      controller.current.snapshot.actionContext!.draftRevision,
      controller.session.draftRevision,
    );
    final submit = UiEvent(
      eventId: 'submit',
      surfaceId: 's',
      nodeId: 'approval',
      observedRevision: 2,
      kind: 'submit',
    );
    expect(
      controller.session.dispatch(
        submit,
        controller.current,
        library2UiCatalog,
      ),
      UiEventOutcome.invalid,
    );
    expect(await controller.dispatch(submit), UiDispatchOutcome.invalid);
    expect(businessCalls, 0);
    for (final invalid in ['3', 4]) {
      expect(
        await controller.dispatch(
          UiEvent(
            eventId: 'invalid-$invalid',
            surfaceId: 's',
            nodeId: 'qty',
            observedRevision: 2,
            kind: 'change',
            payload: invalid,
          ),
        ),
        UiDispatchOutcome.invalid,
      );
      expect(controller.session.readableDraft['qty'], '3');
      expect(controller.session.draftRevision, 1);
    }
    expect(
      await controller.dispatch(
        UiEvent(
          eventId: 'repair',
          surfaceId: 's',
          nodeId: 'qty',
          observedRevision: 2,
          kind: 'change',
          payload: '4',
        ),
      ),
      UiDispatchOutcome.applied,
    );
    expect(controller.session.userOverrides['qty'], '4');
    expect(controller.session.readableDraft, isEmpty);
    expect(controller.session.unreadableReasons, isEmpty);
    expect(controller.session.draftRevision, 2);
    expect(
      await controller.dispatch(
        UiEvent(
          eventId: 'old-approval',
          surfaceId: 's',
          nodeId: 'approval',
          observedRevision: 2,
          kind: 'submit',
        ),
      ),
      UiDispatchOutcome.stale,
    );
    expect(businessCalls, 0);
  });
}
