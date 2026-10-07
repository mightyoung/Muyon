/// Where the agent loop writes what happened (ADR-0005 §6.5). The loop only
/// calls [AgentEventSink.append] (or, for an event that goes with a state
/// change, hands it to the same transaction as the change); K-4 keeps them in
/// the `task_events` table. An event
/// never carries a request or response body, a key or the model's own words:
/// digests, sizes, ids and fixed codes only.
library;

import '../platform/foundation_repository.dart';

/// `type` values; the first group follows the research report §6.4.4, the
/// rest are ADR-0005's additions.
abstract final class AgentEventType {
  static const wait = 'wait';
  static const approval = 'approval';
  static const modelRequest = 'model_request';
  static const modelResponse = 'model_response';
  static const toolProposed = 'tool_proposed';
  static const toolResult = 'tool_result';
  static const compaction = 'compaction';
  static const compactionFailed = 'compaction_failed';
  static const error = 'error';
  static const cancel = 'cancel';
  static const done = 'done';

  /// A new attempt took over what an earlier one left (K-4): counts and a
  /// fixed outcome code only.
  static const resume = 'resume';
}

final class AgentEvent {
  const AgentEvent(this.type, {this.step, this.data = const {}});
  final String type;

  /// Steps used when it happened.
  final int? step;
  final Map<String, Object?> data;
}

abstract interface class AgentEventSink {
  /// Append only; `seq` is increasing within one task.
  Future<void> append(String taskId, AgentEvent event);
}

/// A sink whose events live in the same database as the task state, so an
/// event that goes with a state change can be written in the very transaction
/// that changes the state (`FoundationRepository.updateTask(events: ...)`).
/// Any other sink receives such events one by one, after the change.
abstract interface class TransactionalEventSink implements AgentEventSink {}

/// Events in the `task_events` table (ADR-0005 §6.5, K-4). The repository
/// owns the numbering, so `seq` goes up by one per task whoever appends.
class TaskEventTableSink implements TransactionalEventSink {
  const TaskEventTableSink(this.repository);
  final FoundationRepository repository;

  @override
  Future<void> append(String taskId, AgentEvent event) =>
      repository.appendTaskEvent(taskId, {
        'type': event.type,
        'step': ?event.step,
        if (event.data.isNotEmpty) 'data': event.data,
      });
}
