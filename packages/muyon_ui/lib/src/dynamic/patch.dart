import 'dart:convert';

import 'package:muyon_module_api/ui_contract.dart';

enum UiPatchOperationKind { add, replace, remove }

class UiPatchOperation {
  const UiPatchOperation.add(UiNode value)
    : kind = UiPatchOperationKind.add,
      node = value,
      nodeId = null;
  const UiPatchOperation.replace(UiNode value)
    : kind = UiPatchOperationKind.replace,
      node = value,
      nodeId = null;
  const UiPatchOperation.remove(String id)
    : kind = UiPatchOperationKind.remove,
      node = null,
      nodeId = id;
  final UiPatchOperationKind kind;
  final UiNode? node;
  final String? nodeId;
}

class UiPatch {
  UiPatch({
    required this.patchId,
    required this.surfaceId,
    required this.baseRevision,
    required this.nextRevision,
    required this.snapshotRevision,
    required List<UiPatchOperation> ops,
    this.complete = true,
  }) : ops = List.unmodifiable(ops);
  final String patchId, surfaceId;
  final int baseRevision, nextRevision;
  final SnapshotRef snapshotRevision;
  final List<UiPatchOperation> ops;
  final bool complete;
}

/// Node-only, complete-message patch. No operation can modify business facts.
UiValidationResult applyUiPatch(
  ValidatedUiPlan current,
  UiPatch patch,
  DataSnapshot snapshot,
  InteractionIntent intent,
  UiCatalog catalog,
) {
  UiValidationResult reject(String reason) =>
      UiValidationResult.rejected([reason]);
  if (!patch.complete) return reject('incomplete_patch');
  if (patch.patchId.isEmpty || patch.ops.isEmpty || patch.ops.length > 200) {
    return reject('invalid_patch');
  }
  if (!identical(snapshot, current.snapshot) ||
      !identical(catalog, current.catalog) ||
      !identical(intent, current.intent) ||
      patch.snapshotRevision != snapshot.ref ||
      patch.surfaceId != current.plan.surfaceId) {
    return reject('patch_context');
  }
  late String fingerprint;
  try {
    fingerprint = jsonEncode([
      patch.surfaceId,
      patch.baseRevision,
      patch.nextRevision,
      patch.snapshotRevision.id,
      patch.snapshotRevision.revision,
      for (final op in patch.ops)
        [
          op.kind.name,
          op.nodeId,
          if (op.node != null)
            [
              op.node!.id,
              op.node!.component,
              op.node!.properties,
              {
                for (final e in op.node!.bindings.entries)
                  e.key: [e.value.kind.name, e.value.id],
              },
              op.node!.children,
              {
                for (final e in op.node!.events.entries)
                  e.key: [
                    e.value.actionRef,
                    e.value.inputRefs,
                    e.value.expectedDraftRevision,
                    e.value.operationKeyRef,
                  ],
              },
            ],
        ],
    ]);
  } catch (_) {
    return reject('patch_value');
  }
  final prior = current.appliedPatches[patch.patchId];
  if (prior != null) {
    return prior == fingerprint
        ? UiValidationResult.unchanged(current)
        : reject('patch_id_reused');
  }
  if (patch.baseRevision != current.plan.revision ||
      patch.nextRevision <= patch.baseRevision) {
    return reject('patch_revision');
  }
  final nodes = {for (final node in current.plan.nodes) node.id: node};
  final touched = <String>{};
  for (final op in patch.ops) {
    final id = op.node?.id ?? op.nodeId!;
    if (id.isEmpty || !touched.add(id)) return reject('patch_node');
    switch (op.kind) {
      case UiPatchOperationKind.add:
        if (nodes.containsKey(id)) return reject('patch_existing_node');
        nodes[id] = op.node!;
      case UiPatchOperationKind.replace:
        if (!nodes.containsKey(id)) return reject('patch_missing_node');
        nodes[id] = op.node!;
      case UiPatchOperationKind.remove:
        if (nodes.remove(id) == null) return reject('patch_missing_node');
    }
  }
  var result = validateUiPlan(
    current.plan.copyWith(
      revision: patch.nextRevision,
      nodes: nodes.values.toList(),
    ),
    snapshot,
    intent,
    catalog,
  );
  if (!result.isValid) return result;
  for (final e in current.appliedPatches.entries) {
    result = result.recordPatch(e.key, e.value);
  }
  return result.recordPatch(patch.patchId, fingerprint);
}
