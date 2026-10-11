import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/single_item_projection.dart';
import 'package:muyon/app/adapters/inquiry/single_item_operations.dart';
import 'package:muyon_module_api/ui_contract.dart';

SingleItemOperation qty(String id, {String to = '3'}) => SingleItemOperation(
  target: ObjectRef(
    moduleId: 'inquiry',
    objectType: 'project_item',
    objectId: id,
    nativeProjectId: 'project',
    revisionRef: '7',
    contentDigest: 'digest-$id',
  ),
  operation: 'set_item_qty',
  oldValues: const {'qty': '2'},
  newValues: {'qty': to},
);

SingleItemProjection? project(
  List<SingleItemOperation> operations, {
  String attempt = 'attempt-1',
  String parent = 'parent',
  String presentation = 'presentation',
  List<IndependentItemOperation> declarations =
      inquiryIndependentItemOperations,
  bool atomic = false,
}) => SingleItemProjector.project(
  parentTaskId: parent,
  presentationId: presentation,
  attemptId: attempt,
  draftRevision: 4,
  operations: operations,
  declarations: declarations,
  atomicBatch: atomic,
);

void main() {
  test(
    'A and B freeze only their target, values, records and fixed tool binding',
    () {
      final result = project([qty('A'), qty('B', to: '5')]);
      expect(result, isNotNull);
      final items = result!.items;
      expect(items, hasLength(2));
      expect(items.map((i) => i.itemId).toSet(), hasLength(2));
      expect(items.map((i) => i.operationKeyRef).toSet(), hasLength(2));
      expect(items.map((i) => i.surfaceId).toSet(), hasLength(2));
      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        final id = index == 0 ? 'A' : 'B';
        final to = index == 0 ? '3' : '5';
        expect(item.parentTaskId, 'parent');
        expect(item.presentationId, 'presentation');
        expect(item.target.objectId, id);
        expect(item.oldValues, {'qty': '2'});
        expect(item.newValues, {'qty': to});
        expect(item.toolId, 'inquiry.set_item_qty');
        expect(item.parameters, {'item_id': id, 'from_qty': '2', 'to_qty': to});
        final snapshot = item.snapshot;
        final context = snapshot.actionContext!;
        expect(snapshot.ref.revision, 4);
        expect(snapshot.facts.values.map((f) => f.object).toSet(), {
          item.target,
        });
        expect(
          snapshot.facts.values.map((f) => f.value),
          containsAll(['2', to]),
        );
        expect(context.draft, item.parameters);
        expect(context.draftRevision, 4);
        expect(context.confirmedRecordRefs, {item.recordRef});
        expect(context.operations.keys.toList(), [item.operationKeyRef]);
        expect(context.operations[item.operationKeyRef]!.inputRefs, {
          item.recordRef,
        });
        expect(context.operations[item.operationKeyRef]!.draftRevision, 4);
        expect(identical(snapshot, items[1 - index].snapshot), isFalse);
        expect(
          identical(context, items[1 - index].snapshot.actionContext),
          isFalse,
        );
      }
      expect(() => items.clear(), throwsUnsupportedError);
      expect(
        () => items.first.parameters['item_id'] = 'B',
        throwsUnsupportedError,
      );
    },
  );

  test(
    'input reorder preserves each item identity and operation and surface keys',
    () {
      final before = project([qty('A'), qty('B')])!.items;
      final after = project([qty('B'), qty('A')])!.items.reversed.toList();
      for (var i = 0; i < before.length; i++) {
        expect(after[i].itemId, before[i].itemId);
        expect(after[i].operationKeyRef, before[i].operationKeyRef);
        expect(after[i].surfaceId, before[i].surfaceId);
        expect(after[i].snapshot.ref, before[i].snapshot.ref);
      }
    },
  );

  test('same target with distinct operations has distinct identities', () {
    final operation = qty('A');
    final update = SingleItemOperation(
      target: operation.target,
      operation: 'update_record',
      oldValues: const {'name': 'before'},
      newValues: const {'name': 'after'},
    );
    final items = project(
      [operation, update],
      declarations: [
        ...inquiryIndependentItemOperations,
        const IndependentItemOperation(
          moduleId: 'inquiry',
          objectType: 'project_item',
          operation: 'update_record',
        ),
      ],
    )!.items;
    expect(items[0].itemId, isNot(items[1].itemId));
    expect(items[0].operationKeyRef, isNot(items[1].operationKeyRef));
    expect(items[1].toolId, 'inquiry.update_record');
    expect(items[1].parameters, {
      'operation_id': items[1].operationKeyRef,
      'type': 'project_item',
      'id': 'A',
      'expected_version': 7,
      'values': {'name': 'after'},
    });
  });

  test(
    'reconstruction preserves keys and a new attempt isolates every key',
    () {
      final first = project([qty('A')])!.items.single;
      final restored = project([qty('A')])!.items.single;
      final next = project([qty('A')], attempt: 'attempt-2')!.items.single;
      expect(restored.itemId, first.itemId);
      expect(restored.operationKeyRef, first.operationKeyRef);
      expect(restored.surfaceId, first.surfaceId);
      expect(next.itemId, first.itemId);
      expect(next.operationKeyRef, isNot(first.operationKeyRef));
      expect(next.surfaceId, isNot(first.surfaceId));
      expect(next.snapshot.ref, isNot(first.snapshot.ref));
      expect(
        project([qty('A')], parent: 'other')!.items.single.operationKeyRef,
        isNot(first.operationKeyRef),
      );
      expect(
        project([qty('A')], presentation: 'other')!.items.single.surfaceId,
        isNot(first.surfaceId),
      );
    },
  );

  test('undeclared and incomplete independent lifecycle declarations refuse whole batch', () {
    expect(project([qty('A'), qty('B')], declarations: []), isNull);
    for (final declaration in [
      const IndependentItemOperation(
        moduleId: 'inquiry',
        objectType: 'project_item',
        operation: 'set_item_qty',
        independentPrepare: false,
      ),
      const IndependentItemOperation(
        moduleId: 'inquiry',
        objectType: 'project_item',
        operation: 'set_item_qty',
        independentCommit: false,
      ),
      const IndependentItemOperation(
        moduleId: 'inquiry',
        objectType: 'project_item',
        operation: 'set_item_qty',
        independentReceipt: false,
      ),
      const IndependentItemOperation(
        moduleId: 'inquiry',
        objectType: 'project_item',
        operation: 'set_item_qty',
        atomic: true,
      ),
    ]) {
      expect(project([qty('A')], declarations: [declaration]), isNull);
    }
    expect(
      project([
        qty('A'),
        SingleItemOperation(
          target: qty('B').target,
          operation: 'unknown',
          oldValues: const {},
          newValues: const {},
        ),
      ]),
      isNull,
    );
    expect(
      project(
        [qty('A')],
        declarations: [
          const IndependentItemOperation(
            moduleId: 'other',
            objectType: 'project_item',
            operation: 'set_item_qty',
          ),
        ],
      ),
      isNull,
    );
  });

  test(
    'atomic batches are not split even when a single-row operation is declared',
    () {
      expect(project([qty('A'), qty('B')], atomic: true), isNull);
    },
  );

  test(
    'ambiguous duplicate identities and changed payload in one attempt refuse',
    () {
      expect(project([qty('A'), qty('A')]), isNull);
      expect(project([qty('A'), qty('A', to: '9')]), isNull);
      // A reconstructed attempt whose payload changed gets a different operation key.
      expect(
        project([qty('A', to: '9')])!.items.single.operationKeyRef,
        isNot(project([qty('A')])!.items.single.operationKeyRef),
      );
    },
  );

  test('unpinned target, malformed quantity and extra draft fields refuse', () {
    final target = qty('A').target;
    for (final operation in [
      SingleItemOperation(
        target: const ObjectRef(
          moduleId: 'inquiry',
          objectType: 'project_item',
          objectId: 'A',
        ),
        operation: 'set_item_qty',
        oldValues: const {'qty': '2'},
        newValues: const {'qty': '3'},
      ),
      SingleItemOperation(
        target: target,
        operation: 'set_item_qty',
        oldValues: const {'qty': '2'},
        newValues: const {'qty': 'NaN'},
      ),
      SingleItemOperation(
        target: target,
        operation: 'set_item_qty',
        oldValues: const {'qty': '2'},
        newValues: const {'qty': '3', 'item_id': 'B'},
      ),
    ]) {
      expect(project([qty('B'), operation]), isNull);
    }
    expect(project([]), isNull);
    expect(project([qty('A')], attempt: ''), isNull);
  });

  test('host inputs are frozen before projection and nested update values stay frozen', () {
    final changes = <String, Object?>{'qty': '3'};
    final operation = SingleItemOperation(
      target: qty('A').target,
      operation: 'set_item_qty',
      oldValues: const {'qty': '2'},
      newValues: changes,
    );
    changes['qty'] = '999';
    expect(project([operation])!.items.single.parameters['to_qty'], '3');
  });
}
