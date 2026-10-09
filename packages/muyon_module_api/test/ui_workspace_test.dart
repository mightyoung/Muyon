import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';

void main() {
  test('manual override survives extraction refresh and explicit adoption', () {
    final draft = StoredUiWorkspace(
      taskId: 'task',
      surfaceId: 'surface',
      scopeKey: 'selected:a',
      revision: 1,
      schemaVersion: 1,
      catalogVersion: 'v1',
      snapshotRef: const SnapshotRef('snapshot', 4),
      intentRef: 'intent',
      planRevision: 4,
      draftRevision: 16,
      extracted: {'qty': '10'},
      userOverrides: {'qty': '12'},
      nodeIds: ['qty'],
      step: 'review',
      selectedRecords: ['a'],
      returnAnchor: 'qty',
      scrollOffset: 120,
    );
    final refreshed = draft.refreshExtraction({
      'qty': '11',
    }, const SnapshotRef('snapshot', 5));
    expect(refreshed.displayValues['qty'], '12');
    final restored = StoredUiWorkspace.fromJson(
      jsonDecode(jsonEncode(refreshed.toJson())) as Map<String, dynamic>,
    );
    expect(restored.displayValues['qty'], '12');
    expect(restored.scopeKey, 'selected:a');
    expect(restored.returnAnchor, 'qty');
    expect(restored.adoptExtracted('qty').displayValues['qty'], '11');
    expect(restored.adoptExtracted('qty').draftRevision, 17);
    expect(() => restored.userOverrides['qty'] = '999', throwsUnsupportedError);
  });
}
