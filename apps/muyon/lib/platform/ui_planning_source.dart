import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import '../assistant/ui_planning.dart';
import 'foundation_repository.dart';
import 'tool_registry.dart';
import 'ui_workspace_store.dart';

/// Conservative initial host adapter: display recorded scalar results whose
/// actual registry receipt names one object. It does not invent domain facts,
/// document spans or business-action mappings; V2 domain adapters follow REG4a.
class TaskReceiptUiPlanningSource {
  const TaskReceiptUiPlanningSource(this.repository, this.tools);
  final FoundationRepository repository;
  final ToolRegistry tools;
  Future<UiPlanningHostState?> read(PersonalTask supplied) async {
    final task = repository.task(supplied.id);
    if (task == null || task.payload['uiPlanningInternal'] == true) return null;
    final store = HostUiWorkspaceStore(repository, taskId: task.id);
    final surfaceId = 'task-${task.id}';
    final workspace = await store.load(surfaceId);
    final facts = <String, SnapshotFact>{};
    final receiptData = <Object?>[];
    for (final event in repository.taskEvents(task.id)) {
      final id = event.data['invocationId'];
      if (id is! String) continue;
      final receipt = tools.receiptFor(id);
      if (receipt == null ||
          !receipt.succeeded ||
          receipt.result!.objectRefs.length != 1) {
        continue;
      }
      final result = receipt.result!;
      receiptData.add([id, result.toJson()]);
      for (final entry in result.data.entries) {
        if (!isUiScalar(entry.value)) continue;
        facts['$id:${entry.key}'] = SnapshotFact(
          object: result.objectRefs.single,
          field: entry.key,
          value: entry.value,
          state: FactState.unverified,
        );
      }
    }
    if (facts.isEmpty) return null;
    final digest = sha256
        .convert(utf8.encode(jsonEncode(receiptData)))
        .toString();
    final snapshot = DataSnapshot(
      ref: SnapshotRef(
        'receipts-${task.id}',
        int.parse(digest.substring(0, 12), radix: 16),
      ),
      facts: facts,
      initialUiState: workspace?.displayValues ?? const {},
    );
    const allowed = {'detail', 'back'};
    return UiPlanningHostState(
      snapshot: snapshot,
      intent: InteractionIntent(
        id: 'receipt-presentation-${task.id}',
        purpose:
            'Display recorded host results; unverified fields remain labelled',
        snapshotRef: snapshot.ref,
        requiredBindings: facts.keys.map(BindingRef.fact).toSet(),
        mandatoryStates: {FactState.unverified},
        allowedActionRefs: allowed,
      ),
      currentView: UiCurrentView(
        surfaceId: surfaceId,
        revision: workspace?.planRevision ?? 0,
        values: workspace?.displayValues ?? const {},
      ),
      catalog: dynamicUiCatalog,
      allowedActionRefs: allowed,
    );
  }
}
