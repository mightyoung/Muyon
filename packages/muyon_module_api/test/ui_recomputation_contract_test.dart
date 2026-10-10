import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/src/ui/recomputation.dart';
import 'package:muyon_module_api/ui_contract.dart';

UiPublishToken token({
  SnapshotRef baseSnapshotRef = const SnapshotRef('budget', 7),
  int draftRevision = 3,
  int hostGeneration = 1,
  int sourceGeneration = 2,
  int permissionGeneration = 4,
  String scopeKey = 'inquiry:budget',
}) => UiPublishToken(
  baseSnapshotRef: baseSnapshotRef,
  draftRevision: draftRevision,
  hostGeneration: hostGeneration,
  sourceGeneration: sourceGeneration,
  permissionGeneration: permissionGeneration,
  scopeKey: scopeKey,
);

void main() {
  test('token compares every frozen component by value', () {
    final frozen = token();
    final equal = token(baseSnapshotRef: SnapshotRef('budget', 7));
    expect(identical(frozen, equal), isFalse);
    expect(frozen, equal);
    expect(frozen.hashCode, equal.hashCode);
    expect({frozen, equal}, hasLength(1));
    for (final changed in [
      token(baseSnapshotRef: const SnapshotRef('other', 7)),
      token(baseSnapshotRef: const SnapshotRef('budget', 8)),
      token(draftRevision: 4),
      token(hostGeneration: 2),
      token(sourceGeneration: 3),
      token(permissionGeneration: 5),
      token(scopeKey: 'other'),
    ]) {
      expect(changed, isNot(frozen));
    }
    expect(frozen == Object(), isFalse);
  });

  test('input copies state and exposes an unmodifiable map', () {
    final snapshot = DataSnapshot(
      ref: const SnapshotRef('budget', 7),
      facts: {},
      initialUiState: {'qty': '2'},
    );
    final values = <String, Object?>{'qty': '3'};
    final frozen = token();
    final input = UiRecomputeInput(
      previousSnapshot: snapshot,
      currentUiState: values,
      token: frozen,
    );
    values['qty'] = '9';
    expect(input.currentUiState, {'qty': '3'});
    expect(input.previousSnapshot, same(snapshot));
    expect(input.token, same(frozen));
    expect(snapshot.initialUiState, {'qty': '2'});
    expect(() => input.currentUiState['qty'] = '4', throwsUnsupportedError);
  });

  test('input preserves exact scalars, nulls and extracted values', () {
    final snapshot = DataSnapshot(
      ref: const SnapshotRef('budget', 7),
      facts: {},
      initialUiState: {
        'qty': '2',
        'empty': '',
        'unset': null,
        'count': 1,
        'ratio': 0.5,
        'flag': false,
      },
    );
    final input = UiRecomputeInput(
      previousSnapshot: snapshot,
      currentUiState: {...snapshot.initialUiState, 'qty': '3.00'},
      token: token(),
    );
    expect(input.currentUiState['qty'], '3.00');
    expect(input.currentUiState['qty'], isA<String>());
    expect(input.currentUiState['empty'], '');
    expect(input.currentUiState.containsKey('unset'), isTrue);
    expect(input.currentUiState['unset'], isNull);
    expect(input.currentUiState['count'], isA<int>());
    expect(input.currentUiState['ratio'], 0.5);
    expect(input.currentUiState['flag'], isFalse);
    expect(snapshot.initialUiState['qty'], '2');
    expect(() => input.currentUiState.clear(), throwsUnsupportedError);
  });

  test('input rejects partial, extra or non-scalar state before freezing', () {
    final snapshot = DataSnapshot(
      ref: const SnapshotRef('budget', 7),
      facts: {},
      initialUiState: {'qty': '2'},
    );
    for (final values in <Map<String, Object?>>[
      {},
      {'qty': '3', 'unknown': '4'},
      {'other': '3'},
      {'qty': <String>['3']},
      {'qty': <String, Object?>{'nested': '3'}},
      {'qty': <String>{'3'}},
      {'qty': Object()},
      {'qty': double.nan},
      {'qty': double.infinity},
      {'qty': double.negativeInfinity},
    ]) {
      expect(
        () => UiRecomputeInput(
          previousSnapshot: snapshot,
          currentUiState: values,
          token: token(),
        ),
        throwsArgumentError,
      );
    }
  });

  test('empty declared state remains a valid frozen input', () {
    final input = UiRecomputeInput(
      previousSnapshot: DataSnapshot(
        ref: const SnapshotRef('budget', 7),
        facts: {},
      ),
      currentUiState: {},
      token: token(),
    );
    expect(input.currentUiState, isEmpty);
    expect(() => input.currentUiState['qty'] = '3', throwsUnsupportedError);
  });

  test('result freezes failure diagnostics and keeps the original token', () {
    final frozen = token();
    final errors = ['formula_invalid'];
    final result = UiRecomputeResult(token: frozen, errors: errors);
    errors[0] = 'changed';
    errors.add('added');
    expect(result.token, same(frozen));
    expect(result.nextSnapshot, isNull);
    expect(result.nextIntent, isNull);
    expect(result.errors, ['formula_invalid']);
    expect(() => result.errors.add('other'), throwsUnsupportedError);
    expect(() => result.errors[0] = 'other', throwsUnsupportedError);
  });

  test('result candidate retains snapshot and intent identities', () {
    final snapshot = DataSnapshot(
      ref: const SnapshotRef('budget', 8),
      facts: {},
      initialUiState: {'qty': '2'},
      computations: {
        'total': ComputedValue(
          value: '30',
          inputVersion: const SnapshotRef('budget', 8),
          computationId: 'budget.total',
        ),
      },
    );
    final intent = InteractionIntent(
      id: 'budget-intent',
      purpose: 'budget',
      snapshotRef: snapshot.ref,
    );
    final frozen = token();
    final result = UiRecomputeResult(
      token: frozen,
      nextSnapshot: snapshot,
      nextIntent: intent,
    );
    expect(result.token, same(frozen));
    expect(result.nextSnapshot, same(snapshot));
    expect(result.nextIntent, same(intent));
    expect(result.errors, isEmpty);
    expect(() => result.errors.add('error'), throwsUnsupportedError);
    expect(result.nextSnapshot!.initialUiState['qty'], '2');
    expect(result.nextSnapshot!.computations['total']!.value, '30');
  });

  test('result requires either a complete candidate or failure diagnostics', () {
    final snapshot = DataSnapshot(ref: const SnapshotRef('budget', 8), facts: {});
    final intent = InteractionIntent(
      id: 'budget-intent',
      purpose: 'budget',
      snapshotRef: snapshot.ref,
    );
    expect(() => UiRecomputeResult(token: token()), throwsArgumentError);
    expect(
      () => UiRecomputeResult(token: token(), nextSnapshot: snapshot),
      throwsArgumentError,
    );
    expect(
      () => UiRecomputeResult(token: token(), nextIntent: intent),
      throwsArgumentError,
    );
    expect(
      () => UiRecomputeResult(
        token: token(),
        nextSnapshot: snapshot,
        nextIntent: intent,
        errors: ['invalid'],
      ),
      throwsArgumentError,
    );
  });

  test('batch retains raw candidate identity and leaves admission to publish', () {
    final snapshot = DataSnapshot(ref: const SnapshotRef('budget', 8), facts: {});
    final intent = InteractionIntent(
      id: 'budget-intent',
      purpose: 'budget',
      snapshotRef: snapshot.ref,
    );
    final nodes = [UiNode(id: 'root', component: 'Section')];
    final plan = UIPlan(
      surfaceId: 'budget-surface',
      revision: 12,
      catalogVersion: 'library-2',
      snapshotRef: const SnapshotRef('mismatched', 8),
      intentRef: intent.id,
      root: 'root',
      nodes: nodes,
    );
    final frozen = token();
    final batch = UiVersionBatch(
      token: frozen,
      snapshot: snapshot,
      intent: intent,
      plan: plan,
    );
    nodes.clear();
    expect(batch.token, same(frozen));
    expect(batch.snapshot, same(snapshot));
    expect(batch.intent, same(intent));
    expect(batch.plan, same(plan));
    expect(batch.plan.nodes, hasLength(1));
    expect(() => batch.plan.nodes.clear(), throwsUnsupportedError);
    expect(batch.plan.snapshotRef, isNot(batch.snapshot.ref));
  });

  test('synchronous probe exposes changes to every token component', () {
    var current = token();
    final frozen = current;
    final UiPublishTokenProbe probe = () => current;
    expect(probe(), frozen);
    for (final changed in [
      token(baseSnapshotRef: const SnapshotRef('budget', 8)),
      token(draftRevision: 4),
      token(hostGeneration: 2),
      token(sourceGeneration: 3),
      token(permissionGeneration: 5),
      token(scopeKey: 'other'),
    ]) {
      current = changed;
      expect(probe(), same(changed));
      expect(probe(), isNot(frozen));
    }
    expect(UiPublishOutcome.values, [
      UiPublishOutcome.published,
      UiPublishOutcome.staleToken,
      UiPublishOutcome.invalid,
      UiPublishOutcome.disposed,
    ]);
  });
}
