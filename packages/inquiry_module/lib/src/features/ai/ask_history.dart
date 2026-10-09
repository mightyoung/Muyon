import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:supplier_core/supplier_core.dart';

/// Local conversation history, including the task and its actual tool receipts.
class AskHistoryMessage {
  AskHistoryMessage(
    this.fromUser,
    this.text, {
    this.error = false,
    this.evidence,
    this.appliedActions = const [],
    this.jobId,
    this.evidencePacket,
    String? id,
  }) : id =
           id ??
           'message-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';
  static int _nextId = 0;
  final String id;
  final bool fromUser, error;
  final String text;
  final AssistantAnswer? evidence;
  final List<Map<String, Object?>> appliedActions;
  final String? jobId;
  // Keep the original packet: its text was already normalized, so rebuilding
  // from observations alone cannot recover the original unverified count.
  final Map<String, Object?>? evidencePacket;
  List<String> get evidenceWarnings => {
    ...?evidence?.warnings,
    if (evidencePacket?['warnings'] case final List warnings)
      ...warnings.whereType<String>(),
  }.toList();

  AskHistoryMessage withJob(String id) => AskHistoryMessage(
    fromUser,
    text,
    error: error,
    evidence: evidence,
    appliedActions: appliedActions,
    jobId: id,
    evidencePacket: evidencePacket,
    id: this.id,
  );
}

List<AskHistoryMessage> readAskHistory(String? saved) {
  final messages = <AskHistoryMessage>[];
  try {
    final decoded = jsonDecode(saved ?? '[]');
    if (decoded is! List) return messages;
    final legacyOccurrences = <String, int>{};
    for (final row in decoded.skip(
      decoded.length > 100 ? decoded.length - 100 : 0,
    )) {
      if (row is! List ||
          row.length < 3 ||
          row[0] is! bool ||
          row[1] is! String ||
          row[2] is! bool) {
        continue;
      }
      final metadata = row.length == 4 && row[3] is Map
          ? row[3] as Map
          : const {};
      AssistantAnswer? evidence;
      try {
        final packet = metadata['evidence'];
        if (packet is Map) {
          evidence = AssistantAnswer.fromRun(
            packet['text'] as String,
            [
              for (final o in packet['observations'] as List)
                AssistantObservation(
                  callId: o['call_id'] as String,
                  tool: o['tool'] as String,
                  arguments: o['arguments'] as String,
                  result: o['result'] as String,
                  round: o['round'] as int,
                  providedToModel: o['provided_to_model'] as bool? ?? true,
                ),
            ],
            modelCalls: packet['model_calls'] as int,
            elapsed: Duration(milliseconds: packet['elapsed_ms'] as int),
            contextCompactions: packet['context_compactions'] as int? ?? 0,
          );
        }
      } catch (_) {
        // A damaged packet must not hide the original question or answer.
      }
      final legacyKey = sha256.convert(utf8.encode(jsonEncode(row))).toString();
      final occurrence = legacyOccurrences.update(
        legacyKey,
        (n) => n + 1,
        ifAbsent: () => 0,
      );
      messages.add(
        AskHistoryMessage(
          row[0] as bool,
          row[1] as String,
          error: row[2] as bool,
          evidence: evidence,
          evidencePacket: evidence != null
              ? Map<String, Object?>.from(metadata['evidence'] as Map)
              : null,
          id: metadata['message_id'] is String
              ? metadata['message_id'] as String
              : 'legacy-$legacyKey-$occurrence',
          jobId: metadata['job_id'] is String
              ? metadata['job_id'] as String
              : null,
          appliedActions: metadata['applied_actions'] is List
              ? [
                  for (final action in metadata['applied_actions'] as List)
                    if (action is Map &&
                        action.keys.every((key) => key is String))
                      Map<String, Object?>.from(action),
                ]
              : const [],
        ),
      );
    }
  } on FormatException {
    // Invalid legacy JSON starts an empty history.
  }
  return messages;
}

String writeAskHistory(List<AskHistoryMessage> messages) => jsonEncode([
  for (final m in messages.skip(
    messages.length > 100 ? messages.length - 100 : 0,
  ))
    [
      m.fromUser,
      m.text,
      m.error,
      if (!m.id.startsWith('legacy-') ||
          m.jobId != null ||
          m.evidence != null ||
          m.appliedActions.isNotEmpty)
        {
          'message_id': m.id,
          if (m.jobId != null) 'job_id': m.jobId,
          if (m.evidence != null)
            'evidence': m.evidencePacket ?? m.evidence!.toJson(),
          if (m.appliedActions.isNotEmpty) 'applied_actions': m.appliedActions,
        },
    ],
]);

/// Merge only this writer's changed messages into the latest persisted history.
/// A disposed page may finish after its replacement has taken a snapshot.
List<AskHistoryMessage> mergeAskHistory(
  List<AskHistoryMessage> base,
  List<AskHistoryMessage> local,
  List<AskHistoryMessage> latest,
) {
  final old = {
    for (final m in base) m.id: writeAskHistory([m]),
  };
  final merged = [...latest];
  for (final message in local) {
    if (old[message.id] == writeAskHistory([message])) continue;
    final index = merged.indexWhere((m) => m.id == message.id);
    if (index >= 0) {
      merged[index] = message;
    } else {
      final question = message.fromUser || message.jobId == null
          ? -1
          : merged.lastIndexWhere(
              (m) => m.fromUser && m.jobId == message.jobId,
            );
      if (question < 0) {
        merged.add(message);
      } else {
        var end = question + 1;
        while (end < merged.length && !merged[end].fromUser) {
          end++;
        }
        merged.insert(end, message);
      }
    }
  }
  return merged;
}
