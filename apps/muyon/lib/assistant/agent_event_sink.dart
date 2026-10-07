/// Where the agent loop writes what happened (ADR-0005 §6.5). The loop only
/// calls [AgentEventSink.append]; today's implementation keeps the events in
/// the task payload, K-4 replaces it with the `task_events` table. An event
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

/// Events in the task payload (`events`). The repository owns the list, so a
/// task update made from an older snapshot cannot drop or rewrite one.
class PayloadEventSink implements AgentEventSink {
  const PayloadEventSink(this.repository);
  final FoundationRepository repository;

  @override
  Future<void> append(String taskId, AgentEvent event) =>
      repository.appendTaskEvent(taskId, {
        'type': event.type,
        'step': ?event.step,
        if (event.data.isNotEmpty) 'data': event.data,
      });
}
