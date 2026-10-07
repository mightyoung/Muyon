/// The messages a model request is built from, and their size (ADR-0005
/// §6.6). A task keeps every message it ever had; what is sent, previewed and
/// digested is `f(full messages, compaction state)`, one deterministic
/// function, so the person confirms exactly what leaves.
library;

import 'dart:convert';

import '../services/models/token_estimate.dart';

/// The messages to send for [messages]. With no compaction state, exactly the
/// stored list: nothing about the request changes.
///
/// With a state: the system message (instructions, memories) as stored; then
/// the host's summary of everything before `summary.upTo`, if there is one;
/// then the remaining messages, those whose result was cleared showing their
/// placeholder instead. The calls of an assistant message and their results
/// stay paired. [references] are the task's citations: after a compaction the
/// newest tool result carries the whole table again, so `[rN]` stays valid.
List<Object?> buildRequestView(
  List<Object?> messages, {
  Object? compactionState,
  List<Object?> references = const [],
}) {
  if (compactionState is! Map || messages.isEmpty) return messages;
  final cleared = compactionState['cleared'] is Map
      ? compactionState['cleared'] as Map
      : const {};
  final summary = compactionState['summary'] as Map?;
  if (cleared.isEmpty && summary == null) return messages;
  final upTo = summary == null ? 1 : (summary['upTo'] as int);
  final view = <Object?>[
    messages.first,
    if (summary != null) {'role': 'user', 'content': summary['content']},
  ];
  for (var i = upTo.clamp(1, messages.length); i < messages.length; i++) {
    final change = cleared['$i'];
    final message = messages[i] as Map;
    if (change is! Map) {
      view.add(message);
      continue;
    }
    view.add(<String, Object?>{
      ..._typed(message),
      if (change['content'] != null) 'content': change['content'],
      if (change['arguments'] == true && message['tool_calls'] is List)
        'tool_calls': [
          for (final call in message['tool_calls'] as List)
            <String, Object?>{
              ..._typed(call as Map),
              'function': <String, Object?>{
                ..._typed(call['function'] as Map),
                'arguments': '{}',
              },
            },
        ],
    });
  }
  return _replayCitations(view, references);
}

/// A payload takes only `Map<String, Object?>`; a raw `Map` copied with a
/// spread would not be one.
Map<String, Object?> _typed(Map m) => Map<String, Object?>.from(m);

/// The newest tool result is the one the model reads the citation table from.
/// If it does not list every reference the task has (older results were
/// cleared or summarized), the host puts the full table back, from the task's
/// own references.
List<Object?> _replayCitations(List<Object?> view, List<Object?> references) {
  if (references.isEmpty) return view;
  for (var i = view.length - 1; i > 0; i--) {
    final m = view[i] as Map;
    final content = m['content'];
    if (content is! String || !content.startsWith('{"trustedToolResult"')) {
      continue;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException {
      return view;
    }
    if (decoded is! Map || decoded['citations'] is! List) return view;
    if ((decoded['citations'] as List).length == references.length) return view;
    return [
      ...view.take(i),
      <String, Object?>{
        ..._typed(m),
        'content': jsonEncode({
          ...decoded,
          'citations': [
            for (var n = 0; n < references.length; n++)
              {'citationId': 'r${n + 1}', 'reference': references[n]},
          ],
        }),
      },
      ...view.skip(i + 1),
    ];
  }
  return view;
}

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
