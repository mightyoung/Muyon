/// Provider-neutral model interface (ADR-0005 §4.1). An adapter only maps a
/// [ModelRequest] to a wire payload and a response body to [ModelEvent]s. It
/// has no `HttpClient` and no ledger: every byte leaves through the gateway's
/// one [OutboundChannel], so "no ledger row, no send" holds in one place.
library;

import 'model_gateway.dart';

enum CapabilitySource { unknown, userDeclared, preset, migrated, detected }

/// What an endpoint is declared to support. Unset fields take the
/// conservative value; [compat] (the default) means the JSON protocol over a
/// non-streaming request.
final class ModelCapabilities {
  const ModelCapabilities({
    this.nativeTools = false,
    this.parallelToolCalls = false,
    this.streaming = false,
    this.jsonSchema = false,
    this.jsonObject = false,
    this.reportsUsage = false,
    this.contextTokens,
    this.maxOutputTokens,
    this.source = CapabilitySource.unknown,
  });

  static const compat = ModelCapabilities();

  final bool nativeTools;
  final bool parallelToolCalls;
  final bool streaming;

  /// `response_format: json_schema`.
  final bool jsonSchema;

  /// `response_format: json_object`.
  final bool jsonObject;

  /// Whether a response carries `usage`.
  final bool reportsUsage;

  /// null = unknown.
  final int? contextTokens;
  final int? maxOutputTokens;
  final CapabilitySource source;

  /// Missing, mistyped or unknown values fall back to the conservative
  /// default instead of failing: a damaged setting must not lock the profile.
  factory ModelCapabilities.fromJson(Object? json) {
    if (json is! Map) return compat;
    bool flag(String key) => json[key] == true;
    int? count(String key) {
      final v = json[key];
      return v is int && v > 0 ? v : null;
    }

    return ModelCapabilities(
      nativeTools: flag('nativeTools'),
      parallelToolCalls: flag('parallelToolCalls'),
      streaming: flag('streaming'),
      jsonSchema: flag('jsonSchema'),
      jsonObject: flag('jsonObject'),
      reportsUsage: flag('reportsUsage'),
      contextTokens: count('contextTokens'),
      maxOutputTokens: count('maxOutputTokens'),
      source:
          CapabilitySource.values.asNameMap()[json['source']] ??
          CapabilitySource.unknown,
    );
  }

  Map<String, Object?> toJson() => {
    'nativeTools': nativeTools,
    'parallelToolCalls': parallelToolCalls,
    'streaming': streaming,
    'jsonSchema': jsonSchema,
    'jsonObject': jsonObject,
    'reportsUsage': reportsUsage,
    'contextTokens': contextTokens,
    'maxOutputTokens': maxOutputTokens,
    'source': source.name,
  };
}

enum ToolChoice { auto, none }

/// A call the assistant made, as stored in a conversation.
final class ModelToolCall {
  const ModelToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
  final String id;

  /// Wire (encoded) function name.
  final String name;

  /// JSON text, exactly as the model produced it.
  final String arguments;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': 'function',
    'function': {'name': name, 'arguments': arguments},
  };
}

/// `system` / `user` / `assistant` (+[toolCalls]) / `tool` (+[toolCallId]).
final class ModelMessage {
  const ModelMessage({
    required this.role,
    this.content = '',
    this.toolCalls = const [],
    this.toolCallId,
  });
  final String role;
  final String content;
  final List<ModelToolCall> toolCalls;
  final String? toolCallId;

  /// Reads a stored message map (`{role, content, tool_calls?,
  /// tool_call_id?}`), the same shape the wire uses.
  factory ModelMessage.fromJson(Map<Object?, Object?> json) => ModelMessage(
    role: json['role'] as String,
    content: json['content'] as String? ?? '',
    toolCalls: [
      for (final c in (json['tool_calls'] as List?) ?? const [])
        ModelToolCall(
          id: (c as Map)['id'] as String,
          name: (c['function'] as Map)['name'] as String,
          arguments: (c['function'] as Map)['arguments'] as String,
        ),
    ],
    toolCallId: json['tool_call_id'] as String?,
  );

  Map<String, Object?> toJson() => {
    'role': role,
    'content': content,
    if (toolCalls.isNotEmpty)
      'tool_calls': [for (final c in toolCalls) c.toJson()],
    'tool_call_id': ?toolCallId,
  };
}

final class ModelToolSpec {
  const ModelToolSpec({
    required this.name,
    required this.description,
    required this.parameters,
  });

  /// Encoded function name (see tool_names.dart).
  final String name;
  final String description;

  /// JSON Schema subset, object at the root.
  final Map<String, Object?> parameters;
}

final class ModelRequest {
  const ModelRequest({
    required this.profile,
    required this.messages,
    this.tools = const [],
    this.toolChoice = ToolChoice.auto,
    this.maxOutputTokens,
    this.jsonObject = false,
    required this.caller,
    this.requestDigest,
  });
  final ModelProfile profile;
  final List<ModelMessage> messages;
  final List<ModelToolSpec> tools;
  final ToolChoice toolChoice;
  final int? maxOutputTokens;

  /// Ask for `response_format: json_object` (the compatibility protocol).
  /// The gateway resends once without it when the endpoint answers 400/422,
  /// as `chat` does.
  final bool jsonObject;

  /// Written to the ledger.
  final String caller;

  /// Digest of the request the person confirmed (ADR-0005 §5.4); recorded in
  /// the ledger next to the wire digest.
  final String? requestDigest;

  ModelRequest withoutJsonObject() => ModelRequest(
    profile: profile,
    messages: messages,
    tools: tools,
    toolChoice: toolChoice,
    maxOutputTokens: maxOutputTokens,
    caller: caller,
    requestDigest: requestDigest,
  );
}

enum FinishReason { stop, toolCalls, length, contentFilter, other }

sealed class ModelEvent {
  const ModelEvent();
}

final class TextDelta extends ModelEvent {
  const TextDelta(this.text);
  final String text;
}

/// Display only: a tool call is acted on after [ToolCallComplete] and [Done].
final class ToolCallDelta extends ModelEvent {
  const ToolCallDelta({
    required this.index,
    this.callId,
    this.name,
    this.argsFragment = '',
  });
  final int index;
  final String? callId, name;
  final String argsFragment;
}

final class ToolCallComplete extends ModelEvent {
  const ToolCallComplete({
    required this.callId,
    required this.name,
    this.arguments,
    this.problem,
  });
  final String callId;

  /// Wire function name exactly as returned.
  final String name;

  /// null when [problem] is set.
  final Map<String, Object?>? arguments;

  /// Fixed code when this must not run: no id or name, repeated id, a name
  /// that was not sent in `tools`, arguments that are not a JSON object, or
  /// the legacy `function_call` shape. The host discards such a reply.
  final String? problem;
  bool get valid => problem == null && arguments != null;
}

/// null = the provider did not report it (not zero).
final class Usage extends ModelEvent {
  const Usage({this.promptTokens, this.completionTokens});
  final int? promptTokens, completionTokens;
}

final class Done extends ModelEvent {
  const Done(this.reason);
  final FinishReason reason;
}

final class ModelError extends ModelEvent {
  const ModelError(this.code, {this.partialOutput = false});

  /// Fixed and redacted; never the model's or the endpoint's own text.
  final String code;
  final bool partialOutput;
}

/// The single way bytes leave the host (ADR-0005 §4.4). Opening one has
/// already passed the credential check and `beforeSend`, written the ledger
/// row, sent the request and checked for HTTP 200.
abstract interface class OutboundChannel {
  /// Response bytes. Idle and absolute timeouts, the size cap and
  /// cancellation are enforced here and surface as errors on the stream.
  Stream<List<int>> get body;
  int get bytesReceived;
  Future<void> finish(OutboundOutcome outcome);
}

enum OutboundStatus { succeeded, failed, cancelled, timeout }

final class OutboundOutcome {
  const OutboundOutcome(
    this.status, {
    this.error,
    this.promptTokens,
    this.completionTokens,
  });
  final OutboundStatus status;
  final String? error;
  final int? promptTokens, completionTokens;
}

abstract interface class ModelProvider {
  /// Reserved for K-3/AUTH-1 (capability-driven choices); not used by K-2a.
  ///
  /// Pure: no request is sent.
  ModelCapabilities capabilities(ModelProfile profile);

  /// The JSON body for [request].
  Map<String, Object?> encode(ModelRequest request);

  /// Events for one response body. Ends with [Done] or [ModelError]; the
  /// gateway adds `stream_truncated` when the body ends with neither.
  Stream<ModelEvent> decode(ModelRequest request, Stream<List<int>> body);
}
