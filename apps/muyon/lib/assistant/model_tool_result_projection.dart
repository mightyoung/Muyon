import 'dart:convert';

import 'package:muyon_module_api/muyon_module_api.dart';

import '../platform/inquiry_model_disclosure.dart';
import '../platform/foundation_repository.dart';
import '../platform/tool_registry.dart';
import '../app/adapters/inquiry_module.dart' show inquiryOntology;

/// A model projection, never a receipt. Registered fields do not grant access:
/// the invocation's existing scope and authorization checks still run first.
/// No output schema is registered for arbitrary provider data or summaries.
Map<String, Object?> modelToolResult(
  ToolCallResult result, {
  RegisteredToolInfo? producer,
}) {
  final data = <String, Object?>{};
  final refs = result.objectRefs;
  final record = result.data['record'];
  if (producer?.providerId == 'inquiry' &&
      producer?.descriptor.toolId == 'inquiry.object' &&
      producer?.descriptor.moduleId == 'inquiry' &&
      producer?.descriptor.effect == ToolEffect.read &&
      refs.length == 1 &&
      refs.single.moduleId == 'inquiry' &&
      record is Map) {
    data['record'] = <String, Object?>{
      for (final entry in record.entries)
        if (entry.key is String &&
            inquiryFieldDisclosedToModel(
              refs.single.objectType,
              entry.key as String,
              masked:
                  inquiryOntology
                      .type(refs.single.objectType)
                      ?.fields
                      .where((field) => field.name == entry.key)
                      .firstOrNull
                      ?.sensitivity !=
                  Sensitivity.none,
            ) &&
            (entry.value == null ||
                entry.value is String ||
                entry.value is num ||
                entry.value is bool))
          entry.key as String: entry.value,
    };
  }
  return {...result.toJson(), 'summary': '工具结果已记录；仅展示已登记可披露的字段', 'data': data};
}

// Fixed host outcomes emitted by AgentDispatch. Arbitrary checkpoint strings
// are not allowed to turn a non-executed outcome into a disclosure channel.
const _hostNonExecutionTexts = {
  '用户未批准此调用',
  '未执行：前一个操作失败',
  '未执行：只读参数需修正，请重新决定此操作',
  '未执行：已请求取消',
  '未执行：超出单步调用上限',
  '未执行：超出一张确认卡的调用上限',
  '未执行：任务在此之前中断，如仍需要请重新提出',
  '未执行：上一次尝试中该操作的结果未知，需先核实',
  '未执行',
};

bool _followsCompatibilityCall(List<Object?> messages, int index) {
  if (index == 0 || messages[index - 1] is! Map) return false;
  final prior = messages[index - 1] as Map;
  if (prior['role'] != 'assistant' || prior['content'] is! String) return false;
  try {
    final call = jsonDecode(prior['content'] as String);
    return call is Map && (call['type'] == 'tool' || call['calls'] is List);
  } on FormatException {
    return false;
  }
}

class ModelToolHistory {
  const ModelToolHistory(this.messages, {required this.hadLegacyResult});
  final List<Object?> messages;
  final bool hadLegacyResult;

  /// Old clearing placeholders and summaries may contain pre-policy results.
  /// Preserve them in the checkpoint, but never reuse them in a model request.
  Object? compaction(Object? stored) => hadLegacyResult ? null : stored;
}

/// Re-project persisted result messages before preview, send and summarization.
/// After a pre-policy result, assistant-derived prose/arguments have no safe
/// provenance. User-authored messages retain their separate disclosure policy.
ModelToolHistory modelToolHistory(
  List<Object?> messages, {
  Map<String, Object?>? Function(ToolCallResult, Object?)? projectedReceipt,
  bool Function(int, Map)? explicitUserMessage,
}) {
  var legacy = false;
  final projected = <Object?>[];
  for (var index = 0; index < messages.length; index++) {
    final message = messages[index];
    if (message is! Map) {
      projected.add(message);
      continue;
    }
    var output = Map<String, Object?>.from(message);
    final content = message['content'];
    final hostResult =
        message['role'] == 'tool' ||
        (message['role'] == 'user' &&
            explicitUserMessage?.call(index, message) != true &&
            _followsCompatibilityCall(messages, index));
    if (hostResult) {
      var recognized = false;
      if (content is String) {
        try {
          final body = jsonDecode(content);
          if (body is Map && body['trustedToolResult'] is Map) {
            final result = ToolCallResult.fromJson(
              Map<String, Object?>.from(body['trustedToolResult'] as Map),
            );
            final safe =
                projectedReceipt?.call(result, message['tool_call_id']) ??
                modelToolResult(result);
            if (body['modelDisclosurePolicy'] != 1 ||
                body['modelReferencePolicy'] != 1 ||
                jsonEncode(safe) != jsonEncode(body['trustedToolResult'])) {
              legacy = true;
            }
            output['content'] = jsonEncode({
              'trustedToolResult': safe,
              'modelDisclosurePolicy': 1,
              'modelReferencePolicy': 1,
              'citations': body['citations'] is List
                  ? body['citations']
                  : const [],
            });
            recognized = true;
          } else if (body is Map && body['notExecuted'] is String) {
            // This is an outcome placeholder, not a result field or summary.
            if (!_hostNonExecutionTexts.contains(body['notExecuted'])) {
              legacy = true;
            }
            output['content'] = jsonEncode({
              'notExecuted':
                  _hostNonExecutionTexts.contains(body['notExecuted'])
                  ? body['notExecuted']
                  : '未执行',
            });
            recognized = true;
          }
        } on Object {
          // Malformed old checkpoints are retained locally, never sent raw.
        }
      }
      if (!recognized) {
        legacy = true;
        output['content'] = jsonEncode({
          'modelToolResultUnavailable': 'unregistered_result',
        });
      }
    }
    if (legacy && message['role'] == 'assistant') {
      output['content'] = '此前工具派生内容未登记披露，已省略';
      if (message['tool_calls'] is List) {
        output['tool_calls'] = [
          for (final call in message['tool_calls'] as List)
            if (call is Map && call['function'] is Map)
              {
                ...Map<String, Object?>.from(call),
                'function': {
                  ...Map<String, Object?>.from(call['function'] as Map),
                  'arguments': '{}',
                },
              },
        ];
      }
    }
    projected.add(output);
  }
  return ModelToolHistory(projected, hadLegacyResult: legacy);
}

/// Only host-frozen execution metadata can associate a model message with a
/// registered producer. Result refs and result-supplied tags cannot grant it.
ModelToolHistory modelTaskToolHistory(PersonalTask task, ToolRegistry tools) =>
    modelToolHistory(
      task.payload['messages'] as List? ?? const [],
      explicitUserMessage: (index, message) =>
          message['role'] == 'user' &&
          ((task.payload['uiPlanningInternal'] != true &&
                  message['content'] == task.prompt) ||
              (task.payload['modelUserMessageIndices'] is List &&
                  (task.payload['modelUserMessageIndices'] as List).contains(
                    index,
                  ))),
      projectedReceipt: (serialized, callId) {
        final id = serialized.executionId;
        final sources = task.payload['modelResultProducers'];
        final metadata = sources is Map ? sources[id] : null;
        if (id == null || metadata is! Map || metadata['callId'] != callId) {
          return null;
        }
        final receipt = tools.receiptFor(id);
        if (receipt?.result == null ||
            receipt!.toolId != metadata['toolId'] ||
            receipt.identityDigest != metadata['identityDigest']) {
          return null;
        }
        final producer = tools.inspect(receipt.toolId);
        if (producer == null || producer.providerId != metadata['providerId']) {
          return null;
        }
        return modelToolResult(receipt.result!, producer: producer);
      },
    );

/// Host-only attribution of local tool-derived conversation answers. The
/// original message/receipt is retained; this copy is only for model requests.
List<AssistantMessage> modelConversationHistory(
  FoundationRepository repository,
  String conversationId, {
  ToolRegistry? tools,
}) {
  final withheldAnswers = <String>{
    for (final prior in repository.tasks(conversationId: conversationId))
      if ((prior.payload['toolCall'] != null && prior.profileId == null) ||
          (tools == null
                  ? modelToolHistory(
                      prior.payload['messages'] as List? ?? const [],
                    )
                  : modelTaskToolHistory(prior, tools))
              .hadLegacyResult)
        if (prior.summary != null) prior.summary!,
  };
  final withheldCommands = <String>{
    for (final prior in repository.tasks(conversationId: conversationId)) ...[
      if (prior.payload['modelHostToolRequestText'] is String)
        prior.payload['modelHostToolRequestText'] as String,
      if (prior.profileId == null && prior.payload['toolCall'] is Map)
        '运行工具 ${(prior.payload['toolCall'] as Map)['toolId']}：${jsonEncode((prior.payload['toolCall'] as Map)['parameters'] ?? const {})}',
    ],
  };
  return [
    for (final message in repository.messages(conversationId))
      if ((message.role == 'assistant' &&
              withheldAnswers.contains(message.content)) ||
          (message.role == 'user' &&
              withheldCommands.contains(message.content)))
        AssistantMessage(
          message.id,
          message.conversationId,
          message.role,
          '此前本机工具派生内容未登记披露，已省略',
          message.createdAt,
          message.references,
        )
      else
        message,
  ];
}
