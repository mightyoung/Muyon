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
  test('opaque references are scoped, stable, private and fail closed', () {
    const object = ObjectRef(
      moduleId: 'inquiry',
      objectType: 'project_item',
      objectId: 'row',
      nativeProjectId: 'project',
      revisionRef: '2',
      contentDigest: 'PRIVATE-ROW-HASH-212dc',
    );
    const artifact = ArtifactRef(
      moduleId: 'inquiry',
      artifactId: 'paper',
      contentDigest: 'PRIVATE-ARTIFACT-HASH-818a',
    );
    var current = true;
    final map = ModelReferenceMap(
      taskId: 'task',
      scopeKey: 'PRIVATE-SCOPE',
      snapshotKey: 'PRIVATE-SNAPSHOT',
      objects: {object},
      artifacts: [artifact],
      isCurrent: () => current,
    );
    final wire = map.projectObject(object);
    final token = wire['modelRef']! as String;
    expect(wire, map.projectObject(object));
    final text = jsonEncode(
      map.projectJson({
        'scope': {
          'objects': [object.toJson()],
        },
        'artifact': {
          'moduleId': artifact.moduleId,
          'artifactId': artifact.artifactId,
          'contentDigest': artifact.contentDigest,
        },
      }),
    );
    for (final secret in [
      'PRIVATE-ROW-HASH-212dc',
      'PRIVATE-ARTIFACT-HASH-818a',
      'PRIVATE-SCOPE',
      'PRIVATE-SNAPSHOT',
    ]) {
      expect(text, isNot(contains(secret)));
    }
    expect(
      map.resolveObject(
        token,
        taskId: 'task',
        scopeKey: 'PRIVATE-SCOPE',
        snapshotKey: 'PRIVATE-SNAPSHOT',
        locators: wire,
      ),
      same(object),
    );
    for (final context in [
      ('foreign', 'PRIVATE-SCOPE', 'PRIVATE-SNAPSHOT'),
      ('task', 'other', 'PRIVATE-SNAPSHOT'),
      ('task', 'PRIVATE-SCOPE', 'old'),
    ]) {
      expect(
        map.resolveObject(
          token,
          taskId: context.$1,
          scopeKey: context.$2,
          snapshotKey: context.$3,
        ),
        isNull,
      );
    }
    expect(
      map.resolveObject(
        'mr1_forged',
        taskId: 'task',
        scopeKey: 'PRIVATE-SCOPE',
        snapshotKey: 'PRIVATE-SNAPSHOT',
      ),
      isNull,
    );
    expect(
      map.resolveObject(
        token,
        taskId: 'task',
        scopeKey: 'PRIVATE-SCOPE',
        snapshotKey: 'PRIVATE-SNAPSHOT',
        locators: {...wire, 'objectId': 'foreign'},
      ),
      isNull,
    );
    expect(
      map.resolveObject(
        token,
        taskId: 'task',
        scopeKey: 'PRIVATE-SCOPE',
        snapshotKey: 'PRIVATE-SNAPSHOT',
        locators: {...wire, 'contentDigest': object.contentDigest},
      ),
      isNull,
    );
    expect(
      () => map.projectObject(
        const ObjectRef(
          moduleId: 'inquiry',
          objectType: 'project_item',
          objectId: 'foreign',
        ),
      ),
      throwsStateError,
    );
    expect(
      () => map.projectJson({'contentDigest': 'UNKNOWN-HASH'}),
      throwsStateError,
    );
    final artifactWire = map.projectArtifact(artifact);
    final artifactToken = artifactWire['modelRef']! as String;
    expect(
      map.resolveArtifact(
        artifactToken,
        taskId: 'task',
        scopeKey: 'PRIVATE-SCOPE',
        snapshotKey: 'PRIVATE-SNAPSHOT',
        locators: artifactWire,
      ),
      same(artifact),
    );
    expect(
      map.resolveArtifact(
        'forged',
        taskId: 'task',
        scopeKey: 'PRIVATE-SCOPE',
        snapshotKey: 'PRIVATE-SNAPSHOT',
      ),
      isNull,
    );
    expect(
      map.resolveArtifact(
        artifactToken,
        taskId: 'task',
        scopeKey: 'PRIVATE-SCOPE',
        snapshotKey: 'PRIVATE-SNAPSHOT',
        locators: {...artifactWire, 'artifactId': 'foreign'},
      ),
      isNull,
    );
    expect(
      map.resolveArtifact(
        artifactToken,
        taskId: 'foreign',
        scopeKey: 'PRIVATE-SCOPE',
        snapshotKey: 'PRIVATE-SNAPSHOT',
      ),
      isNull,
    );
    expect(
      () => map.projectArtifact(
        const ArtifactRef(
          moduleId: 'inquiry',
          artifactId: 'foreign',
          contentDigest: 'unknown',
        ),
      ),
      throwsStateError,
    );
    current = false;
    expect(
      map.resolveObject(
        token,
        taskId: 'task',
        scopeKey: 'PRIVATE-SCOPE',
        snapshotKey: 'PRIVATE-SNAPSHOT',
      ),
      isNull,
    );
    expect(() => map.projectObject(object), throwsStateError);
    current = true;
    map.expire();
    expect(
      map.resolveObject(
        token,
        taskId: 'task',
        scopeKey: 'PRIVATE-SCOPE',
        snapshotKey: 'PRIVATE-SNAPSHOT',
      ),
      isNull,
    );
    expect(() => map.projectArtifact(artifact), throwsStateError);
    final other = ModelReferenceMap(
      taskId: 'other-task',
      scopeKey: 'PRIVATE-SCOPE',
      snapshotKey: 'PRIVATE-SNAPSHOT',
      objects: {object},
    );
    expect(other.projectObject(object)['modelRef'], isNot(token));
    expect(
      other.resolveObject(
        token,
        taskId: 'other-task',
        scopeKey: 'PRIVATE-SCOPE',
        snapshotKey: 'PRIVATE-SNAPSHOT',
      ),
      isNull,
    );
  });

  test('model reference metadata does not disclose the host row digest', () {
    const pinned = ObjectRef(
      moduleId: 'inquiry',
      objectType: 'project_item',
      objectId: 'row',
      revisionRef: '3',
      contentDigest: 'ROW-DIGEST-SECRET-941bd',
    );
    final snapshot = DataSnapshot(
      ref: ref,
      facts: {
        'name': SnapshotFact(
          object: pinned,
          field: 'name',
          value: 'ordinary',
          state: FactState.verified,
        ),
      },
    );
    final text = jsonEncode(request(snapshot, facts: {'name'}).toJson());
    expect(text, isNot(contains('ROW-DIGEST-SECRET-941bd')));
    expect(
      snapshot.facts['name']!.object.contentDigest,
      'ROW-DIGEST-SECRET-941bd',
    );
  });

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
      expect(text, contains('modelRef'));
      expect(text, isNot(contains('"contentDigest"')));
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
