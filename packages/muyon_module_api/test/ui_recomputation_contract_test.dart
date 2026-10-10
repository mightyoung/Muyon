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
}
