import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'personal_agent.dart';
import '../platform/foundation_repository.dart';

class UiBusinessAction {
  const UiBusinessAction(this.toolId, this.parameters);
  final String toolId;
  final Map<String, Object?> Function(UiPendingAction) parameters;
}

class UiPlanningEventRouter {
  UiPlanningEventRouter({
    required this.agent,
    required this.taskId,
    required this.surface,
    this.businessActions = const {},
  }) {
    agent.repository.addListener(reconcile);
  }
  final PersonalAgent agent;
  final String taskId;
  final UiSurfaceController surface;
  final Map<String, UiBusinessAction> businessActions;
  final tasks = <String, String>{};
  final _pending = <String, UiPendingAction>{};
  final _seen = <String>{};
  bool _disposed = false;
  Future<void> dispatch(UiEvent event) async {
    if (_disposed || !_seen.add(event.eventId)) return;
    final task = agent.repository.task(taskId);
    if (task == null ||
        event.surfaceId != surface.current.plan.surfaceId ||
        event.observedRevision != surface.current.plan.revision) {
      throw StateError('stale_host_event');
    }
    final node = surface.current.plan.nodes.firstWhere(
      (n) => n.id == event.nodeId,
    );
    final binding = node.events[event.kind];
    if (binding == null) throw StateError('unknown_host_event');
    final route = surface.current.catalog.actions[binding.actionRef]?.route;
    if (route == UiActionRoute.local) return;
    if (route == UiActionRoute.business) {
      final pending = surface.pendingAction(event.eventId);
      final action = businessActions[binding.actionRef];
      if (pending == null ||
          action == null ||
          agent.tools.inspect(action.toolId)?.available != true) {
        throw StateError('business_port_unavailable');
      }
      _pending[event.eventId] = pending;
      final child = await agent.startTool(
        conversationId: task.conversationId,
        toolId: action.toolId,
        parameters: action.parameters(pending),
        previousAttemptId: task.id,
      );
      tasks[event.eventId] = child.id;
      await agent.repository.appendTaskEvent(task.id, {
        'type': 'ui_business_task',
        'data': {
          'surfaceId': event.surfaceId,
          'operationRef': pending.binding.operationKeyRef,
          'eventId': event.eventId,
          'taskId': child.id,
        },
      });
    } else if (route == UiActionRoute.semantic) {
      final child = await agent.startUiSemantic(
        task.id,
        'Explain the selected host presentation: ${node.id}, snapshot '
        '${surface.current.snapshot.ref.id}/${surface.current.snapshot.ref.revision}. '
        'Original question: ${task.prompt}\nOriginal answer: ${task.summary ?? ''}',
      );
      tasks[event.eventId] = child.id;
    } else {
      throw StateError('unsupported_host_route');
    }
    reconcile();
  }

  void reconcile() {
    if (_disposed) return;
    for (final entry in tasks.entries) {
      final task = agent.repository.task(entry.value);
      if (task == null) continue;
      final pending = _pending[entry.key];
      if (pending != null) {
        final calls =
            ((task.payload['step'] as Map?)?['calls'] as List?) ?? const [];
        for (final call in calls) {
          if (call is! Map || call['invocationId'] is! String) continue;
          final receipt = agent.tools.receiptFor(
            call['invocationId'] as String,
          );
          if (receipt == null || receipt.unknown) continue;
          surface.acceptReceipt(
            UiBusinessReceipt(
              eventId: entry.key,
              operationKeyRef: pending.binding.operationKeyRef!,
              draftRevision: pending.binding.expectedDraftRevision!,
              status: receipt.succeeded
                  ? UiReceiptStatus.succeeded
                  : UiReceiptStatus.failed,
              message: receipt.result?.summary ?? 'Host receipt',
              isSimulated: false,
            ),
          );
          _pending.remove(entry.key);
        }
      } else if (task.state == PersonalTaskState.succeeded) {
        final next = agent.uiPresentation(task.id)?.result.plan;
        if (next != null) {
          final current = surface.current;
          final validated = validateUiPlan(
            next,
            current.snapshot,
            current.intent,
            current.catalog,
          ).validatedPlan;
          if (validated != null) surface.acceptPlan(validated);
        }
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    agent.repository.removeListener(reconcile);
  }
}

Future<UiOperationRecovery> recoverUiPlanningOperation(
  PersonalAgent agent,
  String taskId,
  String surfaceId,
  String operationRef,
) async {
  for (final event in agent.repository.taskEvents(taskId).reversed) {
    if (event.type != 'ui_business_task' ||
        event.data['surfaceId'] != surfaceId ||
        event.data['operationRef'] != operationRef) {
      continue;
    }
    final child = agent.repository.task(event.data['taskId'] as String);
    if (child == null || child.previousAttemptId != taskId) {
      return UiOperationRecovery.unknown;
    }
    final calls =
        ((child.payload['step'] as Map?)?['calls'] as List?) ?? const [];
    for (final call in calls) {
      if (call is! Map || call['invocationId'] is! String) continue;
      final receipt = agent.tools.receiptFor(call['invocationId'] as String);
      if (receipt == null || receipt.unknown) continue;
      return receipt.succeeded
          ? UiOperationRecovery.succeeded
          : UiOperationRecovery.failed;
    }
    return UiOperationRecovery.unknown;
  }
  return UiOperationRecovery.unknown;
}
