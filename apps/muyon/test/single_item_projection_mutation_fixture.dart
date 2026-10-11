import 'dart:io';

import 'package:muyon/assistant/single_item_projection.dart';
import 'package:muyon/app/adapters/inquiry/single_item_operations.dart';
import 'package:muyon_module_api/ui_contract.dart';

class ProjectionExpectationFailure implements Exception {
  const ProjectionExpectationFailure(this.name);
  final String name;
}

void verifyProjectionMutationFixture(String name) {
  SingleItemOperation operation(String id) => SingleItemOperation(
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
    newValues: const {'qty': '3'},
  );
  List<ProjectedSingleItem> project(List<String> ids) =>
      SingleItemProjector.project(
        parentTaskId: 'parent',
        presentationId: 'presentation',
        attemptId: 'attempt',
        draftRevision: 4,
        operations: ids.map(operation).toList(),
        declarations: inquiryIndependentItemOperations,
      )!.items;
  final items = project(['A', 'B']);
  final passed = switch (name) {
    'item_id_uses_array_index' =>
      items.first.itemId == project(['B', 'A']).last.itemId,
    'items_share_operation_key' =>
      items.first.operationKeyRef != items.last.operationKeyRef,
    _ => throw ArgumentError.value(name),
  };
  if (!passed) throw ProjectionExpectationFailure(name);
}

void main(List<String> args) {
  try {
    verifyProjectionMutationFixture(args.single);
    stdout.writeln('PASS:${args.single}');
  } on ProjectionExpectationFailure catch (failure) {
    stderr.writeln('EXPECTED_ASSERTION_FAILURE:${failure.name}');
    exitCode = 65;
  }
}
