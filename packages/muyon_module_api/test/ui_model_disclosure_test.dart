import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'ui/fixtures.dart';

const object = ObjectRef(
  moduleId: 'inquiry',
  objectType: 'project_item',
  objectId: 'item',
);
const ref = SnapshotRef('safe-ref', 1);
UiPlanningRequest request(
  DataSnapshot snapshot, {
  Set<String> facts = const {},
  Set<String> computed = const {},
  Set<String> uiState = const {},
}) => UiPlanningRequest(
  modelDisclosedFactRefs: facts,
  modelDisclosedComputedRefs: computed,
  modelDisclosedUiStateRefs: uiState,
  question: 'display',
  answer: '',
  conversationMessages: const [],
  conversationVersion: '1',
  coverage: 'selected',
  taskId: 'task',
  turnId: 'turn',
  snapshot: snapshot,
  intent: InteractionIntent(
    id: 'intent',
    purpose: 'display',
    snapshotRef: snapshot.ref,
  ),
  currentView: UiCurrentView(surfaceId: 'surface', revision: 1),
  catalog: ContractFixture().catalog,
  allowedActionRefs: const {},
  mode: UiPlanningMode.intelligent,
);

void main() {
  for (final state in [
    FactState.notDisclosed,
    FactState.readFailed,
    FactState.notApplicable,
    FactState.verified,
  ]) {
    test(
      'direct serializer denies unregistered residual value for ${state.name}',
      () {
        final canary = 'RESIDUAL-SECRET-${state.name}-84e16';
        final snapshot = DataSnapshot(
          ref: ref,
          facts: {
            'secret': SnapshotFact(
              object: object,
              field: 'unknown_field',
              value: canary,
              state: state,
            ),
          },
          computations: {
            'sum': ComputedValue(
              value: canary,
              inputVersion: ref,
              computationId: 'sum',
            ),
          },
          computedEvidence: {'sum': UiComputedEvidence(state: state)},
        );
        expect(jsonEncode(request(snapshot).toJson()), isNot(contains(canary)));
        expect(
          snapshot.facts['secret']!.value,
          canary,
          reason: 'local snapshot remains untouched',
        );
      },
    );
  }
  test(
    'source original text never serialized without disclosure authority',
    () {
      final snapshot = DataSnapshot(
        ref: ref,
        facts: {},
        sources: {
          's': const SourceSpanRef(
            artifact: ArtifactRef(
              moduleId: 'inquiry',
              artifactId: 'a',
              contentDigest: 'digest',
            ),
            originalText: 'ORIGINAL-SECRET-93baf',
            start: 0,
            end: 3,
          ),
        },
      );
      final text = jsonEncode(request(snapshot).toJson());
      expect(text, isNot(contains('ORIGINAL-SECRET-93baf')));
      expect(text, contains('digest'));
      expect(snapshot.sources['s']!.originalText, 'ORIGINAL-SECRET-93baf');
    },
  );
  for (final state in [
    FactState.notDisclosed,
    FactState.readFailed,
    FactState.notApplicable,
    FactState.conflict,
  ]) {
    test('registration cannot override unavailable ${state.name} evidence', () {
      const canary = 'REGISTERED-BUT-HIDDEN-6812';
      final snapshot = DataSnapshot(
        ref: ref,
        facts: {
          'secret': SnapshotFact(
            object: object,
            field: 'price',
            value: canary,
            state: state,
          ),
        },
        computations: {
          'sum': const ComputedValue(
            value: canary,
            inputVersion: ref,
            computationId: 'sum',
          ),
        },
        computedEvidence: {'sum': UiComputedEvidence(state: state)},
      );
      expect(
        jsonEncode(
          request(snapshot, facts: {'secret'}, computed: {'sum'}).toJson(),
        ),
        isNot(contains(canary)),
      );
    });
  }
  test('registered ordinary values preserved but missing or old computed provenance withheld', () {
    final snapshot = DataSnapshot(
      ref: ref,
      facts: {
        'qty': SnapshotFact(
          object: object,
          field: 'qty',
          value: 'NORMAL-QTY-2',
          state: FactState.unverified,
        ),
      },
      computations: {
        'good': const ComputedValue(
          value: 'NORMAL-SUM-4',
          inputVersion: ref,
          computationId: 'good',
        ),
        'missing': const ComputedValue(
          value: 'MISSING-EVIDENCE-9da',
          inputVersion: ref,
          computationId: 'missing',
        ),
        'old': const ComputedValue(
          value: 'OLD-EVIDENCE-9da',
          inputVersion: SnapshotRef('old', 0),
          computationId: 'old',
        ),
      },
      computedEvidence: {
        'good': UiComputedEvidence(state: FactState.verified),
        'old': UiComputedEvidence(state: FactState.verified),
      },
    );
    final text = jsonEncode(
      request(
        snapshot,
        facts: {'qty'},
        computed: {'good', 'missing', 'old'},
      ).toJson(),
    );
    expect(text, contains('NORMAL-QTY-2'));
    expect(text, contains('NORMAL-SUM-4'));
    expect(text, isNot(contains('MISSING-EVIDENCE-9da')));
    expect(text, isNot(contains('OLD-EVIDENCE-9da')));
  });
  test(
    'checkpoint drafts and current view require separate host registration',
    () {
      const canary = 'RESTORED-WORKSPACE-RAW-829f';
      final snapshot = DataSnapshot(
        ref: ref,
        facts: {},
        initialUiState: {'unknown': canary, 'safe': 'SAFE-DRAFT'},
        actionContext: UiActionContext(
          draftRevision: 1,
          draft: {'unknown': canary, 'safe': 'SAFE-DRAFT'},
        ),
      );
      final text = jsonEncode(request(snapshot, uiState: {'safe'}).toJson());
      expect(text, isNot(contains(canary)));
      expect(text, contains('SAFE-DRAFT'));
      final view = UiPlanningRequest(
        question: 'q',
        answer: '',
        conversationMessages: [],
        conversationVersion: '1',
        coverage: 'selected',
        taskId: 't',
        turnId: 't',
        snapshot: snapshot,
        intent: InteractionIntent(
          id: 'i',
          purpose: 'display',
          snapshotRef: ref,
        ),
        currentView: UiCurrentView(
          surfaceId: 's',
          revision: 1,
          values: {'unknown': canary},
        ),
        catalog: ContractFixture().catalog,
        allowedActionRefs: {},
        mode: UiPlanningMode.intelligent,
      );
      expect(jsonEncode(view.toJson()), isNot(contains(canary)));
      expect(snapshot.initialUiState['unknown'], canary);
    },
  );
}
