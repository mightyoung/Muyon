/// The messages a model request is built from, and their size (ADR-0005
/// §6.6-8). Today the view is the stored conversation unchanged; context
/// compaction (K-3) will replace the `compactionState` seam with `f(full
/// messages, state)` without touching what is stored or confirmed.
library;

import 'dart:convert';

import '../services/models/token_estimate.dart';

/// The messages to send for [messages]. With no compaction state, exactly the
/// stored list: nothing about the request changes.
List<Object?> buildRequestView(
  List<Object?> messages, {
  Object? compactionState,
}) => messages;

/// Reserved for K-3 (compaction trigger); not used by K-2a.
///
/// Estimated tokens of [messages]. When the provider reported the prompt size
/// of an earlier request, [reportedPromptTokens] stands for the first
/// [reportedMessageCount] messages and only the rest is estimated; a report
/// always wins over an estimate of the same content.
int estimateMessageTokens(
  List<Object?> messages, {
  int? reportedPromptTokens,
  int reportedMessageCount = 0,
}) {
  final known = reportedPromptTokens != null && reportedMessageCount > 0
      ? reportedMessageCount.clamp(0, messages.length)
      : 0;
  final rest = messages.skip(known);
  final estimate = estimateTokens(jsonEncode(rest.toList()));
  return known > 0 ? reportedPromptTokens! + estimate : estimate;
}
