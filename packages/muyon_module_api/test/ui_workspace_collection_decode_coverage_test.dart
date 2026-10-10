import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';

// Schema1 stored presentations reject collection bindings.
// This tests that boundary independently of collection rendering/admission.
Map<String, dynamic> persistedPresentation({String kind = 'fact'}) => {
  'surfaceId': 'surface',
  'revision': 4,
  'catalogVersion': 'library-2',
  'snapshotId': 'snapshot',
  'snapshotRevision': 4,
  'intentRef': 'intent',
  'root': 'qty',
  'nodes': [
    {
      'id': 'qty',
      'component': 'Text',
      'properties': {'text': 'Quantity'},
      'children': <String>[],
      'bindings': {
        'value': {'kind': kind, 'id': 'quantity'},
      },
      'events': {
        'edit': {
          'actionRef': 'editQuantity',
          'inputRefs': ['quantity'],
          'expectedDraftRevision': 16,
          'operationKeyRef': 'edit-operation',
        },
      },
    },
  ],
};

Map<String, dynamic> persistedWorkspace({
  String kind = 'fact',
  int schemaVersion = 1,
}) => {
  'taskId': 'task',
  'surfaceId': 'surface',
  'scopeKey': 'selected:a',
  'revision': 1,
  'schemaVersion': schemaVersion,
  'catalogVersion': 'library-2',
  'snapshotId': 'snapshot',
  'snapshotRevision': 4,
  'intentRef': 'intent',
  'planRevision': 4,
  'draftRevision': 16,
  'extracted': {'quantity': '2'},
  'userOverrides': {'quantity': '3'},
  'nodeIds': ['qty'],
  'step': 'review',
  'selectedRecords': ['a'],
  'returnAnchor': 'qty',
  'scrollOffset': 120,
  'presentation': persistedPresentation(kind: kind),
};

Matcher rejectsCollectionKind() => throwsA(
  isA<ArgumentError>()
      .having((error) => error.name, 'name', 'kind')
      .having((error) => error.invalidValue, 'invalidValue', 'collection'),
);

void main() {
  test('stored presentation rejects a known collection binding kind', () {
    final payload = persistedPresentation(kind: 'collection');
    final before = jsonDecode(jsonEncode(payload));
    expect(BindingKind.values, contains(BindingKind.collection));

    expect(() => decodeUiPresentation(payload), rejectsCollectionKind());
    expect(payload, before);
  });

  test('workspace restore propagates collection codec rejection', () {
    final payload = persistedWorkspace(kind: 'collection');
    final before = jsonDecode(jsonEncode(payload));

    expect(() => StoredUiWorkspace.fromJson(payload), rejectsCollectionKind());
    expect(payload, before);
  });

  test('library-2 workspace rejects schema1 even with fact binding', () {
    final payload = persistedWorkspace();
    final before = jsonDecode(jsonEncode(payload));
    expect(
      () => StoredUiWorkspace.fromJson(payload),
      throwsA(isA<ArgumentError>().having(
        (error) => error.message, 'message', 'workspace_selection_schema',
      )),
    );
    expect(payload, before);
  });

  test('schema2 fact presentation restores draft and binding metadata', () {
    final payload = persistedWorkspace(schemaVersion: 2);
    final before = jsonDecode(jsonEncode(payload));
    final restored = StoredUiWorkspace.fromJson(payload);

    expect(restored.displayValues['quantity'], '3');
    expect(restored.extracted['quantity'], '2');
    expect(restored.draftRevision, 16);
    expect(restored.presentation, isNotNull);
    final snapshotNames = {const SnapshotRef('snapshot', 4): 'original'};
    expect(snapshotNames[restored.snapshotRef], 'original');
    expect(snapshotNames[restored.presentation!.snapshotRef], 'original');
    final node = restored.presentation!.nodes.single;
    expect(node.bindings['value'], const BindingRef.fact('quantity'));
    expect(node.events['edit']!.actionRef, 'editQuantity');
    expect(node.events['edit']!.inputRefs, ['quantity']);
    expect(node.events['edit']!.expectedDraftRevision, 16);
    expect(node.events['edit']!.operationKeyRef, 'edit-operation');
    final roundTrip = StoredUiWorkspace.fromJson(
      jsonDecode(jsonEncode(restored.toJson())) as Map<String, dynamic>,
    );
    expect(roundTrip.toJson(), restored.toJson());
    expect(payload, before);
  });
}
