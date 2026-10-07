import 'dart:async';
import 'dart:convert';

import 'model_gateway.dart';
import 'model_provider.dart';

/// OpenAI Chat Completions compatible endpoints (ADR-0005 §4.2): request
/// mapping, SSE parsing and the non-streaming response, as [ModelEvent]s.
/// Text that merely looks like tool-call markup (`<｜｜DSML｜｜ …>`) is text.
class OpenAiCompatProvider implements ModelProvider {
  const OpenAiCompatProvider();

  @override
  ModelCapabilities capabilities(ModelProfile profile) => profile.capabilities;

  @override
  Map<String, Object?> encode(ModelRequest request) {
    final streaming = request.profile.capabilities.streaming;
    return {
      'model': request.profile.modelId,
      'messages': [for (final m in request.messages) m.toJson()],
      if (request.tools.isNotEmpty) ...{
        'tools': [
          for (final t in request.tools)
            {
              'type': 'function',
              'function': {
                'name': t.name,
                'description': t.description,
                'parameters': t.parameters,
              },
            },
        ],
        'tool_choice': request.toolChoice.name == 'none' ? 'none' : 'auto',
      },
      'stream': streaming,
      if (streaming) 'stream_options': const {'include_usage': true},
      'max_tokens': ?request.maxOutputTokens,
      if (request.jsonObject) 'response_format': const {'type': 'json_object'},
    };
  }

  @override
  Stream<ModelEvent> decode(ModelRequest request, Stream<List<int>> body) =>
      request.profile.capabilities.streaming
      ? _decodeStream(request, body)
      : _decodeWhole(request, body);

  static FinishReason _reason(Object? value) => switch (value) {
    'stop' => FinishReason.stop,
    // `function_call` is the legacy spelling; the call itself is reported as
    // a problem, so the reply is a protocol violation, not an "other" end.
    'tool_calls' || 'function_call' => FinishReason.toolCalls,
    'length' => FinishReason.length,
    'content_filter' => FinishReason.contentFilter,
    _ => FinishReason.other,
  };

  static int? _count(Object? value) =>
      value is num && value.isFinite && value >= 0 ? value.toInt() : null;

  static Usage? _usage(Object? raw) => raw is Map
      ? Usage(
          promptTokens: _count(raw['prompt_tokens']),
          completionTokens: _count(raw['completion_tokens']),
        )
      : null;

  static ToolCallComplete _complete(
    ModelRequest request,
    Set<String> seenIds, {
    required String id,
    required String name,
    required String arguments,
  }) {
    String? problem;
    Map<String, Object?>? parsed;
    if (id.isEmpty || name.isEmpty) {
      problem = 'tool_call_incomplete';
    } else if (!seenIds.add(id)) {
      problem = 'tool_call_duplicate_id';
    } else if (!request.tools.any((t) => t.name == name)) {
      problem = 'tool_call_unknown_name';
    } else {
      try {
        // A function without parameters may come back with no arguments.
        final decoded = arguments.trim().isEmpty ? {} : jsonDecode(arguments);
        if (decoded is Map) {
          parsed = Map<String, Object?>.from(decoded);
        } else {
          problem = 'tool_call_arguments_invalid';
        }
      } on FormatException {
        problem = 'tool_call_arguments_invalid';
      }
    }
    return ToolCallComplete(
      callId: id,
      name: name,
      arguments: problem == null ? parsed : null,
      problem: problem,
    );
  }

  Stream<ModelEvent> _decodeWhole(
    ModelRequest request,
    Stream<List<int>> body,
  ) async* {
    final bytes = <int>[];
    await for (final chunk in body) {
      bytes.addAll(chunk);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      yield const ModelError('response_not_json');
      return;
    }
    if (decoded is! Map) {
      yield const ModelError('response_not_object');
      return;
    }
    if (decoded['error'] != null) {
      yield const ModelError('provider_error');
      return;
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      yield const ModelError('empty_choices');
      return;
    }
    final choice = choices.first as Map;
    final message = choice['message'];
    if (message is! Map) {
      yield const ModelError('choice_without_message');
      return;
    }
    final reason = _reason(choice['finish_reason']);
    final content = message['content'];
    if (content is String && content.isNotEmpty) yield TextDelta(content);
    final calls = message['tool_calls'];
    if (calls != null && calls is! List) {
      yield const ModelError('tool_calls_not_list');
      return;
    }
    final seen = <String>{};
    if (calls is List && calls.isNotEmpty) {
      if (reason != FinishReason.length) {
        for (final call in calls) {
          final function = call is Map ? call['function'] : null;
          final name = function is Map ? function['name'] : null;
          final args = function is Map ? function['arguments'] : null;
          final id = call is Map ? call['id'] : null;
          yield _complete(
            request,
            seen,
            id: id is String ? id : '',
            name: name is String ? name : '',
            arguments: args is String ? args : '',
          );
        }
      }
    } else if (message['function_call'] != null) {
      yield const ToolCallComplete(
        callId: '',
        name: '',
        problem: 'legacy_function_call',
      );
    }
    final usage = _usage(decoded['usage']);
    if (usage != null) yield usage;
    yield Done(reason);
  }

  Stream<ModelEvent> _decodeStream(
    ModelRequest request,
    Stream<List<int>> body,
  ) async* {
    final calls = <int, _CallBuffer>{};
    var legacy = false;
    var sawOutput = false;
    FinishReason? finish;
    var done = false;

    Iterable<ModelEvent> handle(Map<Object?, Object?> chunk) sync* {
      if (chunk['error'] != null) {
        yield ModelError('provider_error', partialOutput: sawOutput);
        return;
      }
      final choices = chunk['choices'];
      if (choices is List && choices.isNotEmpty && choices.first is Map) {
        final choice = choices.first as Map;
        final delta = choice['delta'];
        if (delta is Map) {
          final content = delta['content'];
          if (content is String && content.isNotEmpty) {
            sawOutput = true;
            yield TextDelta(content);
          }
          if (delta['function_call'] != null) legacy = true;
          final fragments = delta['tool_calls'];
          if (fragments is List) {
            for (final f in fragments) {
              if (f is! Map) continue;
              final index = f['index'] is int ? f['index'] as int : 0;
              final function = f['function'];
              final buffer = calls.putIfAbsent(index, _CallBuffer.new);
              final id = f['id'];
              final name = function is Map ? function['name'] : null;
              final args = function is Map ? function['arguments'] : null;
              if (id is String && id.isNotEmpty) buffer.id = id;
              if (name is String && name.isNotEmpty) buffer.name = name;
              if (args is String) buffer.arguments.write(args);
              sawOutput = true;
              yield ToolCallDelta(
                index: index,
                callId: id is String ? id : null,
                name: name is String ? name : null,
                argsFragment: args is String ? args : '',
              );
            }
          }
        }
        final reason = choice['finish_reason'];
        if (reason is String) finish = _reason(reason);
      }
      final usage = _usage(chunk['usage']);
      if (usage != null) yield usage;
    }

    Iterable<ModelEvent> finishUp() sync* {
      final reason = finish;
      if (reason == null) {
        // [DONE] without a finish reason: the reply is not known complete.
        yield ModelError('stream_truncated', partialOutput: sawOutput);
        return;
      }
      if (reason != FinishReason.length) {
        final seen = <String>{};
        for (final index in calls.keys.toList()..sort()) {
          final b = calls[index]!;
          yield _complete(
            request,
            seen,
            id: b.id,
            name: b.name,
            arguments: b.arguments.toString(),
          );
        }
        if (legacy && calls.isEmpty) {
          yield const ToolCallComplete(
            callId: '',
            name: '',
            problem: 'legacy_function_call',
          );
        }
      }
      yield Done(reason);
    }

    await for (final data in parseSse(body)) {
      if (data == '[DONE]') {
        done = true;
        break;
      }
      final Object? chunk;
      try {
        chunk = jsonDecode(data);
      } on FormatException {
        // Never quote the chunk: an endpoint may echo a credential in it.
        yield ModelError('stream_malformed', partialOutput: sawOutput);
        return;
      }
      if (chunk is! Map) {
        yield ModelError('stream_malformed', partialOutput: sawOutput);
        return;
      }
      var failed = false;
      for (final event in handle(chunk)) {
        yield event;
        if (event is ModelError) failed = true;
      }
      if (failed) return;
    }
    // A reply that ended with its finish reason is complete even when the
    // endpoint closes without [DONE]; without a finish reason it is not.
    if (done || finish != null) {
      yield* Stream.fromIterable(finishUp());
    }
  }

  /// `data:` payloads of a Server-Sent Events body, one per event. Comment
  /// lines and other fields are ignored; multi-line data joins with `\n`.
  static Stream<String> parseSse(Stream<List<int>> body) async* {
    final data = <String>[];
    await for (final line
        in body
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (data.isNotEmpty) {
          yield data.join('\n');
          data.clear();
        }
      } else if (line.startsWith('data:')) {
        final value = line.substring(5);
        data.add(value.startsWith(' ') ? value.substring(1) : value);
      }
    }
    if (data.isNotEmpty) yield data.join('\n');
  }
}

class _CallBuffer {
  String id = '';
  String name = '';
  final arguments = StringBuffer();
}
