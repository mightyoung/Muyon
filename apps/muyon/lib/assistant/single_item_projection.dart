import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:uuid/uuid.dart';

import 'package:muyon/app/adapters/inquiry/single_item_operations.dart';

class SingleItemOperation {
  SingleItemOperation({
    required this.target,
    required this.operation,
    required Map<String, Object?> oldValues,
    required Map<String, Object?> newValues,
  }) : oldValues = _freezeMap(oldValues),
       newValues = _freezeMap(newValues);
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
  ProjectedSingleItem._({
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
    if (atomicBatch ||
        operations.isEmpty ||
        draftRevision < 0 ||
        [
          parentTaskId,
          presentationId,
          attemptId,
        ].any((id) => id.trim().isEmpty)) {
      return null;
    }
    final namespace = [parentTaskId, presentationId, attemptId];
    final items = <ProjectedSingleItem>[];
    final identities = <String>{};
    for (final operation in operations) {
      final target = operation.target;
      if (target.moduleId != 'inquiry' ||
          target.objectType != 'project_item' ||
          [
            target.objectId,
            target.nativeProjectId,
            target.revisionRef,
            target.contentDigest,
          ].any((value) => value == null || value.isEmpty)) {
        return null;
      }
      final matching = declarations
          .where(
            (declaration) =>
                declaration.moduleId == target.moduleId &&
                declaration.objectType == target.objectType &&
                declaration.operation == operation.operation,
          )
          .toList();
      // No implicit splitting from generic writeForms or coverage entries.
      if (matching.length != 1) return null;
      final declaration = matching.single;
      if (declaration.atomic ||
          !declaration.independentPrepare ||
          !declaration.independentCommit ||
          !declaration.independentReceipt) {
        return null;
      }
      final identity = [
        target.moduleId,
        target.objectType,
        target.nativeProjectId,
        target.objectId,
        operation.operation,
      ];
      final itemId = 'item-${_digest(identity)}'; // stable_item_identity
      if (!identities.add(itemId)) return null;
      final recordRef = 'record-${_digest(target.toJson())}';
      final operationKeyRef = const Uuid().v5(
        Namespace.url.value,
        _canonical([
          namespace,
          identity,
          target.toJson(),
          draftRevision,
          operation.oldValues,
          operation.newValues,
        ]),
      ); // independent_operation_key
      final parameters = _parameters(operation, operationKeyRef);
      if (parameters == null) return null;
      final surfaceId = 'surface-${_digest([namespace, itemId])}';
      final context = UiActionContext(
        draftRevision: draftRevision,
        draft: parameters,
        confirmedRecordRefs: {recordRef},
        operations: {
          operationKeyRef: HostOperationRef(
            draftRevision: draftRevision,
            inputRefs: {recordRef},
          ),
        },
      );
      items.add(
        ProjectedSingleItem._(
          itemId: itemId,
          operationKeyRef: operationKeyRef,
          surfaceId: surfaceId,
          parentTaskId: parentTaskId,
          presentationId: presentationId,
          target: target,
          recordRef: recordRef,
          oldValues: operation.oldValues,
          newValues: operation.newValues,
          toolId: 'inquiry.${operation.operation}',
          parameters: parameters,
          snapshot: DataSnapshot(
            ref: SnapshotRef(
              'snapshot-${_digest([surfaceId, operationKeyRef])}',
              draftRevision,
            ),
            actionContext: context,
            facts: {
              for (final entry in operation.oldValues.entries)
                'old.${entry.key}': SnapshotFact(
                  object: target,
                  field: entry.key,
                  value: entry.value,
                  state: FactState.verified,
                ),
              for (final entry in operation.newValues.entries)
                'new.${entry.key}': SnapshotFact(
                  object: target,
                  field: entry.key,
                  value: entry.value,
                  state: FactState.unverified,
                ),
            },
          ),
        ),
      );
    }
    return SingleItemProjection(items);
  }
}

// Fixed host mappings; declarations cannot supply tool names or parameter
// builders. Unsupported operations fail closed even if falsely declared.
Map<String, Object?>? _parameters(SingleItemOperation operation, String key) {
  final target = operation.target;
  switch (operation.operation) {
    case 'set_item_qty':
      final before = operation.oldValues['qty'];
      final after = operation.newValues['qty'];
      bool decimal(Object? value) =>
          value is String &&
          value.length <= 40 &&
          RegExp(r'^\d+(?:\.\d+)?$').hasMatch(value);
      if (operation.oldValues.length != 1 ||
          operation.newValues.length != 1 ||
          !decimal(before) ||
          !decimal(after) ||
          target.objectId.length > 64) {
        return null;
      }
      return _freezeMap({
        'item_id': target.objectId,
        'from_qty': before,
        'to_qty': after,
      });
    case 'update_record':
      final version = int.tryParse(target.revisionRef!);
      if (version == null ||
          version < 1 ||
          operation.newValues.isEmpty ||
          operation.oldValues.keys.toSet().length !=
              operation.newValues.length ||
          !operation.newValues.keys.every(operation.oldValues.containsKey)) {
        return null;
      }
      return _freezeMap({
        'operation_id': key,
        'type': target.objectType,
        'id': target.objectId,
        'expected_version': version,
        'values': operation.newValues,
      });
    default:
      return null;
  }
}

Map<String, Object?> _freezeMap(Map<String, Object?> value) => Map.unmodifiable(
  {for (final entry in value.entries) entry.key: _freeze(entry.value)},
);

Object? _freeze(Object? value) {
  if (value is Map<String, Object?>) return _freezeMap(value);
  if (value is List<Object?>) return List.unmodifiable(value.map(_freeze));
  if (value == null ||
      value is String ||
      value is bool ||
      value is int ||
      (value is double && value.isFinite)) {
    return value;
  }
  throw ArgumentError('Single item values must be JSON data');
}

String _canonical(Object? value) {
  Object? sort(Object? value) {
    if (value is Map<String, Object?>) {
      final keys = value.keys.toList()..sort();
      return {for (final key in keys) key: sort(value[key])};
    }
    if (value is List<Object?>) return value.map(sort).toList();
    return value;
  }

  return jsonEncode(sort(value));
}

String _digest(Object? value) =>
    sha256.convert(utf8.encode(_canonical(value))).toString();
