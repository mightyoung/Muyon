import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';

/// C6-REDO: the generic model serialization sends no value that the host did
/// not register, never the raw row digest, and never source text.
void main() {
  const rawDigest =
      'f00dfeedf00dfeedf00dfeedf00dfeedf00dfeedf00dfeedf00dfeedf00dfeed';
  const object = ObjectRef(
    moduleId: 'inquiry',
    objectType: 'quotation',
    objectId: 'q1',
    nativeProjectId: 'p1',
    revisionRef: '3',
    contentDigest: rawDigest,
  );

  UiPlanningRequest request({
    UiModelDisclosure? disclosure,
    Map<String, SnapshotFact>? facts,
    Map<String, Object?> view = const {'v-secret': 'VIEW-CANARY'},
    Map<String, Object?> state = const {'s-secret': 'STATE-CANARY'},
    Map<String, ComputedValue> computed = const {},
    Map<String, SourceSpanRef> sources = const {},
    UiActionContext? action,
  }) {
    final allFacts =
        facts ??
        {
          'a': SnapshotFact(
            object: object,
            field: '名称',
            value: 'FACT-CANARY',
            state: FactState.verified,
          ),
        };
    final snapshot = DataSnapshot(
      ref: const SnapshotRef('raw-snapshot-id', 4),
      facts: allFacts,
      initialUiState: state,
      computations: computed,
      sources: sources,
      sourceDigests: const {'doc': rawDigest},
      actionContext: action,
    );
    return UiPlanningRequest(
      question: 'q',
      answer: 'a',
      conversationMessages: const [],
      conversationVersion: '1',
      coverage: 'c',
      taskId: 't',
      turnId: 't',
      snapshot: snapshot,
      intent: InteractionIntent(
        id: 'i',
        purpose: 'p',
        snapshotRef: snapshot.ref,
        requiredBindings: allFacts.keys.map(BindingRef.fact).toSet(),
      ),
      currentView: UiCurrentView(surfaceId: 's', revision: 1, values: view),
      catalog: UiCatalog(version: 'test', components: {}, actions: {}),
      allowedActionRefs: const {},
      mode: UiPlanningMode.motivation,
      disclosure: disclosure ?? UiModelDisclosure.none,
    );
  }

  String wire(UiPlanningRequest r) => jsonEncode(r.toJson());

  group('default (nothing registered)', () {
    test('no fact, state, view or computed value is sent; structure stays', () {
      final out = wire(
        request(
          computed: {
            'c': const ComputedValue(
              value: 'COMPUTED-CANARY',
              inputVersion: SnapshotRef('raw-snapshot-id', 4),
              computationId: 'sum',
            ),
          },
        ),
      );
      for (final canary in [
        'FACT-CANARY',
        'STATE-CANARY',
        'VIEW-CANARY',
        'COMPUTED-CANARY',
      ]) {
        expect(out, isNot(contains(canary)), reason: canary);
      }
      final json = jsonDecode(out) as Map;
      final fact = ((json['snapshot'] as Map)['facts'] as Map)['a'] as Map;
      expect(fact['field'], '名称');
      expect(fact['state'], 'verified');
      expect(fact['value'], isNull);
      expect(((json['snapshot'] as Map)['initialUiState'] as Map).keys, [
        's-secret',
      ]);
      expect((json['currentView'] as Map)['revision'], 1);
    });

    test('the raw row digest and the raw snapshot id never leave the host', () {
      final out = wire(request());
      expect(out, isNot(contains(rawDigest)));
      expect(out, isNot(contains('raw-snapshot-id')));
      expect(out, isNot(contains('contentDigest')));
    });

    test('source text is never sent, even with a registered snapshot', () {
      final out = wire(
        request(
          disclosure: UiModelDisclosure(factIds: {'a'}),
          sources: {
            'span': const SourceSpanRef(
              artifact: ArtifactRef(
                moduleId: 'inquiry',
                artifactId: 'a',
                contentDigest: rawDigest,
              ),
              originalText: 'SOURCE-CANARY',
              start: 0,
              end: 4,
            ),
          },
        ),
      );
      expect(out, isNot(contains('SOURCE-CANARY')));
      expect(out, contains('span'), reason: 'reference structure remains');
    });

    test('draft values in the action context are not sent', () {
      final out = wire(
        request(
          action: UiActionContext(
            draftRevision: 2,
            draft: const {'qty': 'DRAFT-CANARY'},
          ),
        ),
      );
      expect(out, isNot(contains('DRAFT-CANARY')));
      expect(out, contains('qty'));
    });
  });

  group('registered values', () {
    test('only registered ids carry values, and never when notDisclosed', () {
      final facts = {
        'a': SnapshotFact(
          object: object,
          field: '名称',
          value: 'FACT-CANARY',
          state: FactState.verified,
        ),
        'b': SnapshotFact(
          object: object,
          field: '价格',
          value: 'RESIDUAL-CANARY',
          state: FactState.notDisclosed,
        ),
        'c': SnapshotFact(
          object: object,
          field: '备注',
          value: 'UNREGISTERED-CANARY',
          state: FactState.verified,
        ),
      };
      final out = wire(
        request(
          facts: facts,
          disclosure: UiModelDisclosure(
            factIds: {'a', 'b'},
            stateKeys: {'s-secret'},
            viewKeys: {'v-secret'},
          ),
        ),
      );
      expect(out, contains('FACT-CANARY'));
      expect(out, contains('STATE-CANARY'));
      expect(out, contains('VIEW-CANARY'));
      expect(out, isNot(contains('RESIDUAL-CANARY')));
      expect(out, isNot(contains('UNREGISTERED-CANARY')));
    });

    test('computed values need registration and are otherwise null', () {
      ComputedValue c() => const ComputedValue(
        value: 'COMPUTED-CANARY',
        inputVersion: SnapshotRef('raw-snapshot-id', 4),
        computationId: 'sum',
      );
      expect(
        wire(request(computed: {'c': c()})),
        isNot(contains('COMPUTED-CANARY')),
      );
      expect(
        wire(
          request(
            computed: {'c': c()},
            disclosure: UiModelDisclosure(computedIds: {'c'}),
          ),
        ),
        contains('COMPUTED-CANARY'),
      );
    });
  });

  group('opaque handles', () {
    test('the object keeps its locating fields and gains the host handle', () {
      final out = jsonDecode(
        wire(
          request(
            disclosure: UiModelDisclosure(
              objectHandle: (ref) => 'mr1_handle_for_${ref.objectId}',
              snapshotAlias: 'ms1_alias',
            ),
          ),
        ),
      );
      final fact = ((out['snapshot'] as Map)['facts'] as Map)['a'] as Map;
      final ref = fact['object'] as Map;
      expect(ref['objectId'], 'q1');
      expect(ref['revisionRef'], '3');
      expect(ref['modelRef'], 'mr1_handle_for_q1');
      expect(ref.containsKey('contentDigest'), isFalse);
      expect((out['snapshot'] as Map)['id'], 'ms1_alias');
    });

    test('no handle function means no handle, and still no digest', () {
      final out = jsonDecode(wire(request())) as Map;
      final fact = ((out['snapshot'] as Map)['facts'] as Map)['a'] as Map;
      expect((fact['object'] as Map).containsKey('modelRef'), isFalse);
    });

    test('a digest-less object gets no handle', () {
      const bare = ObjectRef(
        moduleId: 'inquiry',
        objectType: 'quotation',
        objectId: 'q2',
      );
      final out = jsonDecode(
        wire(
          request(
            facts: {
              'a': SnapshotFact(
                object: bare,
                field: 'f',
                value: 1,
                state: FactState.verified,
              ),
            },
            disclosure: UiModelDisclosure(objectHandle: (_) => 'mr1_x'),
          ),
        ),
      );
      final ref =
          (((out['snapshot'] as Map)['facts'] as Map)['a'] as Map)['object']
              as Map;
      expect(ref.containsKey('modelRef'), isFalse);
    });
  });

  test('registration sets are frozen', () {
    final ids = {'a'};
    final disclosure = UiModelDisclosure(factIds: ids);
    ids.add('b');
    expect(disclosure.factIds, {'a'});
    expect(() => disclosure.factIds.add('c'), throwsUnsupportedError);
  });
}
