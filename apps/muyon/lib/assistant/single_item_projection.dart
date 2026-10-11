import 'package:muyon_module_api/ui_contract.dart';

import '../app/adapters/inquiry/single_item_operations.dart';

class SingleItemOperation {
  SingleItemOperation({
    required this.target,
    required this.operation,
    required Map<String, Object?> oldValues,
    required Map<String, Object?> newValues,
  }) : oldValues = Map.unmodifiable(oldValues),
       newValues = Map.unmodifiable(newValues);
  final ObjectRef target;
  final String operation;
  final Map<String, Object?> oldValues, newValues;
}

class SingleItemProjection {
  SingleItemProjection(List<ProjectedSingleItem> items)
    : items = List.unmodifiable(items);
  final List<ProjectedSingleItem> items;
}

class ProjectedSingleItem {
  ProjectedSingleItem({
    required this.itemId,
    required this.operationKeyRef,
    required this.surfaceId,
    required this.parentTaskId,
    required this.presentationId,
    required this.target,
    required this.recordRef,
    required this.oldValues,
    required this.newValues,
    required this.toolId,
    required this.parameters,
    required this.snapshot,
  });
  final String itemId, operationKeyRef, surfaceId, parentTaskId, presentationId;
  final ObjectRef target;
  final String recordRef, toolId;
  final Map<String, Object?> oldValues, newValues, parameters;
  final DataSnapshot snapshot;
}

/// Host-only pure projection. Deliberately disconnected from router and UI.
abstract final class SingleItemProjector {
  static SingleItemProjection? project({
    required String parentTaskId,
    required String presentationId,
    required String attemptId,
    required int draftRevision,
    required List<SingleItemOperation> operations,
    required List<IndependentItemOperation> declarations,
    bool atomicBatch = false,
  }) {
    return null; // RED: no projection implemented yet.
  }
}
