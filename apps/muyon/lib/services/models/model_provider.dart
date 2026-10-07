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

  ModelCapabilities copyWith({
    bool? nativeTools,
    bool? parallelToolCalls,
    bool? streaming,
    bool? jsonSchema,
    bool? jsonObject,
    bool? reportsUsage,
    int? contextTokens,
    int? maxOutputTokens,
    CapabilitySource? source,
  }) => ModelCapabilities(
    nativeTools: nativeTools ?? this.nativeTools,
    parallelToolCalls: parallelToolCalls ?? this.parallelToolCalls,
    streaming: streaming ?? this.streaming,
    jsonSchema: jsonSchema ?? this.jsonSchema,
    jsonObject: jsonObject ?? this.jsonObject,
    reportsUsage: reportsUsage ?? this.reportsUsage,
    contextTokens: contextTokens ?? this.contextTokens,
    maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
    source: source ?? this.source,
  );

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

/// What one probe observed (ADR-0005 §4.5). [unconfirmed] is a reply that was
/// accepted but did not show the behaviour (the model did not call the tool):
/// treated like "no", and said so. [undetermined] (timeout, 401/403, 5xx,
/// a dropped stream) and [notTested] never change a setting.
enum ProbeVerdict { yes, no, unconfirmed, undetermined, notTested }

/// The result of "测试连接", kept on the profile next to (never in place of)
/// [ModelCapabilities]. It takes effect only through [adoptedOver], which the
/// person triggers with "采用".
final class DetectedCapabilities {
  const DetectedCapabilities({
    this.nativeTools = ProbeVerdict.notTested,
    this.streaming = ProbeVerdict.notTested,
    this.reportsUsage = ProbeVerdict.notTested,
    this.jsonObject = ProbeVerdict.notTested,
    this.parallelToolCalls = ProbeVerdict.notTested,
    this.contextTokens,
    this.maxOutputTokens,
    this.presetNativeTools,
    required this.detectedAt,
    required this.payloadDigest,
    this.ledgerIds = const [],
  });

  final ProbeVerdict nativeTools,
      streaming,
      reportsUsage,
      jsonObject,
      parallelToolCalls;

  /// From the presets table, not from the probe (a probe cannot measure them).
  final int? contextTokens, maxOutputTokens;

  /// What the presets table suggests for native tools; shown, never adopted
  /// on its own.
  final bool? presetNativeTools;
  final DateTime detectedAt;

  /// Digest of the fixed probe content that was sent.
  final String payloadDigest;
  final List<String> ledgerIds;

  static bool? _flag(ProbeVerdict v) => switch (v) {
    ProbeVerdict.yes => true,
    ProbeVerdict.no || ProbeVerdict.unconfirmed => false,
    _ => null,
  };

  /// [current] with every definite finding applied; an undetermined or untested
  /// item, and a size the presets do not know, keep the current value.
  ModelCapabilities adoptedOver(ModelCapabilities current) => ModelCapabilities(
    nativeTools: _flag(nativeTools) ?? current.nativeTools,
    parallelToolCalls: _flag(parallelToolCalls) ?? current.parallelToolCalls,
    streaming: _flag(streaming) ?? current.streaming,
    jsonSchema: current.jsonSchema,
    jsonObject: _flag(jsonObject) ?? current.jsonObject,
    reportsUsage: _flag(reportsUsage) ?? current.reportsUsage,
    contextTokens: contextTokens ?? current.contextTokens,
    maxOutputTokens: maxOutputTokens ?? current.maxOutputTokens,
    source: CapabilitySource.detected,
  );

  /// Whether adopting would change anything.
  bool differsFrom(ModelCapabilities current) {
    final next = adoptedOver(current);
    return next.nativeTools != current.nativeTools ||
        next.parallelToolCalls != current.parallelToolCalls ||
        next.streaming != current.streaming ||
        next.jsonObject != current.jsonObject ||
        next.reportsUsage != current.reportsUsage ||
        next.contextTokens != current.contextTokens ||
        next.maxOutputTokens != current.maxOutputTokens;
  }

  static ProbeVerdict _verdict(Object? v) =>
      ProbeVerdict.values.asNameMap()[v] ?? ProbeVerdict.undetermined;

  /// A damaged value reads as "no result" rather than failing the profile.
  static DetectedCapabilities? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse('${json['detectedAt']}');
    final digest = json['payloadDigest'];
    if (at == null || digest is! String) return null;
    int? count(String key) {
      final v = json[key];
      return v is int && v > 0 ? v : null;
    }

    return DetectedCapabilities(
      nativeTools: _verdict(json['nativeTools']),
      streaming: _verdict(json['streaming']),
      reportsUsage: _verdict(json['reportsUsage']),
      jsonObject: _verdict(json['jsonObject']),
      parallelToolCalls: _verdict(json['parallelToolCalls']),
      contextTokens: count('contextTokens'),
      maxOutputTokens: count('maxOutputTokens'),
      presetNativeTools: json['presetNativeTools'] as bool?,
      detectedAt: at,
      payloadDigest: digest,
      ledgerIds: [
        for (final id in (json['ledgerIds'] as List?) ?? const [])
          if (id is String) id,
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'nativeTools': nativeTools.name,
    'streaming': streaming.name,
    'reportsUsage': reportsUsage.name,
    'jsonObject': jsonObject.name,
    'parallelToolCalls': parallelToolCalls.name,
    'contextTokens': contextTokens,
    'maxOutputTokens': maxOutputTokens,
    'presetNativeTools': presetNativeTools,
    'detectedAt': detectedAt.toUtc().toIso8601String(),
    'payloadDigest': payloadDigest,
    'ledgerIds': ledgerIds,
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
