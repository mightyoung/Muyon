import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'ui/fixtures.dart';

void main() {
  // Removing any lookup/version check must let an invalid plan through.
  test('unknown_binding_and_action_are_rejected', () {
    final f = ContractFixture();
    expect(f.validate(f.plan).isValid, isTrue);
    for (final plan in [
      f.withNode(bindings: {'value': const BindingRef.fact('missing')}),
      f.withNode(events: {'tap': ActionBinding(actionRef: 'missing')}),
      f.plan.copyWith(snapshotRef: const SnapshotRef('comparison', 3)),
      f.plan.copyWith(catalogVersion: 'unknown'),
      f.plan.copyWith(intentRef: 'unknown'),
      f.plan.copyWith(nodes: [f.plan.nodes.first]),
    ]) {
      final result = f.validate(plan);
      expect(result.isValid, isFalse);
      expect(result.validatedPlan, isNull);
      expect(result.errors, isNotEmpty);
    }
  });

  test('display_decision_union_is_consistent', () {
    final f = ContractFixture();
    expect(
      UiPlanningResult(
        decision: UiDisplayDecision.textOnly,
        reasonCode: 'plain',
        plan: f.plan,
      ).errors,
      isNotEmpty,
    );
    expect(
      const UiPlanningResult(
        decision: UiDisplayDecision.supplement,
        reasonCode: 'compare',
      ).errors,
      isNotEmpty,
    );
    expect(
      UiPlanningResult(
        decision: UiDisplayDecision.replacePresentation,
        reasonCode: 'compare',
        plan: f.plan,
      ).errors,
      isEmpty,
    );
  });

  // A resolver that conflates draft/fact or substitutes a paraphrase fails here.
  test('state_computation_and_original_span_remain_distinct', () {
    final f = ContractFixture();
    final state = UiSessionState(f.snapshot);
    expect(state.resolve(const BindingRef.fact('qty')), 10);
    expect(state.resolve(const BindingRef.computed('total')), 120);
    state.edit('quantity', '12');
    expect(state.resolve(const BindingRef.uiState('quantity')), '12');
    expect(state.resolve(const BindingRef.fact('qty')), 10);
    expect(state.resolve(const BindingRef.computed('total')), 120);
    expect(
      state.resolve(const BindingRef.sourceSpan('quote')),
      'Public fixture: quantity 10, unit price 12.',
    );
    state.updateSourceDigest('document', 'changed');
    expect(state.resolve(const BindingRef.sourceSpan('quote')), isNull);
    expect(state.staleSources, contains('quote'));
  });

  test(
    'tree_cycles_duplicates_unreachable_nodes_and_bad_properties_rejected',
    () {
      final f = ContractFixture();
      for (final nodes in [
        [
          f.plan.nodes.first.copyWith(children: ['root']),
          f.plan.nodes.last,
        ],
        [...f.plan.nodes, f.plan.nodes.last],
        [...f.plan.nodes, UiNode(id: 'orphan', component: 'Text')],
        [
          f.plan.nodes.first.copyWith(properties: {'title': 7}),
          f.plan.nodes.last,
        ],
        [f.plan.nodes.first, f.plan.nodes.last.copyWith(component: 'Unknown')],
      ]) {
        expect(f.validate(f.plan.copyWith(nodes: nodes)).isValid, isFalse);
      }
    },
  );

  test('source_digest_and_computation_input_revision_are_checked', () {
    final f = ContractFixture();
    final stale = f.snapshot.copyWith(sourceDigests: {'document': 'changed'});
    expect(validateUiPlan(f.plan, stale, f.intent, f.catalog).isValid, isFalse);
    final wrong = f.snapshot.copyWith(
      computations: {
        'total': const ComputedValue(
          value: 120,
          inputVersion: SnapshotRef('comparison', 3),
          computationId: 'fixture-total',
        ),
      },
    );
    expect(validateUiPlan(f.plan, wrong, f.intent, f.catalog).isValid, isFalse);
  });

  // Removing the host-owned operation check would permit fabricated commits.
  test('current_view_and_commit_refs_are_real', () {
    final f = ContractFixture();
    final state = UiSessionState(f.snapshot);
    expect(state.accept(f.validate(f.plan).validatedPlan!), isTrue);
    expect(
      state.accept(f.validate(f.plan.copyWith(revision: 3)).validatedPlan!),
      isFalse,
    );
    expect(
      state.accept(f.validate(f.plan.copyWith(revision: 5)).validatedPlan!),
      isTrue,
    );
    expect(state.currentPlan!.plan.revision, 5);
    final commit = f.withNode(
      events: {
        'tap': ActionBinding(
          actionRef: 'commit',
          inputRefs: ['quantity', 'record-a'],
          expectedDraftRevision: 15,
          operationKeyRef: 'host-operation-1',
        ),
      },
    );
    expect(f.validate(commit).isValid, isTrue);
    expect(
      f
          .validate(commit)
          .validatedPlan!
          .plan
          .nodes
          .last
          .events['tap']!
          .operationKeyRef,
      'host-operation-1',
    );
    expect(
      f
          .validate(
            f.withNode(
              events: {
                'tap': ActionBinding(
                  actionRef: 'commit',
                  inputRefs: ['quantity', 'record-a'],
                  expectedDraftRevision: 15,
                  operationKeyRef: 'invented',
                ),
              },
            ),
          )
          .isValid,
      isFalse,
    );
    final commitState = UiSessionState(f.snapshot);
    final checkedCommit = f.validate(commit).validatedPlan!;
    expect(commitState.accept(checkedCommit), isTrue);
    const commitEvent = UiEvent(
      eventId: 'commit',
      surfaceId: 'comparison',
      nodeId: 'qty',
      observedRevision: 4,
      kind: 'tap',
    );
    expect(
      commitState.dispatch(commitEvent, checkedCommit, f.catalog),
      UiEventOutcome.unsupported,
    );
    expect(
      commitState.dispatch(commitEvent, checkedCommit, f.catalog),
      UiEventOutcome.unsupported,
    );
    commitState.edit('quantity', '12');
    expect(
      commitState.dispatch(
        const UiEvent(
          eventId: 'e',
          surfaceId: 'comparison',
          nodeId: 'qty',
          observedRevision: 4,
          kind: 'tap',
        ),
        checkedCommit,
        f.catalog,
      ),
      UiEventOutcome.stale,
    );
  });

  test('events_require_current_surface_node_revision_and_typed_payload', () {
    final f = ContractFixture();
    final state = UiSessionState(f.snapshot);
    final plan = f.validate(f.plan).validatedPlan!;
    state.accept(plan);
    for (final event in [
      const UiEvent(
        eventId: 'e1',
        surfaceId: 'other',
        nodeId: 'qty',
        observedRevision: 4,
        kind: 'change',
        payload: '12',
      ),
      const UiEvent(
        eventId: 'e2',
        surfaceId: 'comparison',
        nodeId: 'absent',
        observedRevision: 4,
        kind: 'change',
        payload: '12',
      ),
      const UiEvent(
        eventId: 'e3',
        surfaceId: 'comparison',
        nodeId: 'qty',
        observedRevision: 3,
        kind: 'change',
        payload: '12',
      ),
      const UiEvent(
        eventId: 'e4',
        surfaceId: 'comparison',
        nodeId: 'qty',
        observedRevision: 4,
        kind: 'change',
        payload: 12,
      ),
    ]) {
      expect(
        state.dispatch(event, plan, f.catalog),
        isNot(UiEventOutcome.applied),
      );
    }
    expect(state.resolve(const BindingRef.uiState('quantity')), '10');
    expect(
      state.dispatch(
        const UiEvent(
          eventId: 'ok',
          surfaceId: 'comparison',
          nodeId: 'qty',
          observedRevision: 4,
          kind: 'change',
          payload: '12',
        ),
        plan,
        f.catalog,
      ),
      UiEventOutcome.applied,
    );
    expect(state.resolve(const BindingRef.uiState('quantity')), '12');
  });
  test('same_version_foreign_catalog_cannot_change_validated_event_routes', () {
    final f = ContractFixture();
    final checked = f.validate(f.plan).validatedPlan!;
    final state = UiSessionState(f.snapshot)..accept(checked);
    final foreign = UiCatalog(
      version: f.catalog.version,
      components: f.catalog.components,
      actions: {
        'edit': const UiActionDefinition(
          route: UiActionRoute.local,
          localAction: UiLocalAction.openDetail,
        ),
      },
    );
    expect(
      state.dispatch(
        const UiEvent(
          eventId: 'e',
          surfaceId: 'comparison',
          nodeId: 'qty',
          observedRevision: 4,
          kind: 'change',
          payload: '12',
        ),
        checked,
        foreign,
      ),
      UiEventOutcome.stale,
    );
    expect(state.detailNode, isNull);
  });
}
