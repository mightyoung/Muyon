import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:muyon_module_api/muyon_module_api.dart';

/// Fixed failures are the only errors this private protocol exposes.
final class CoreAgentFailure implements Exception {
  const CoreAgentFailure(this.code);
  final String code;
}

bool coreSame(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && coreSame(a[key], b[key]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(a.length, (i) => i).every((i) => coreSame(a[i], b[i]));
  }
  return a == b;
}

Object? coreStrictJson(String text) {
  try {
    _StrictJson(text).check();
    return jsonDecode(text);
  } catch (_) {
    throw const CoreAgentFailure('host_protocol');
  }
}

/// Role, call identity and pairing are exact. JSON inside arguments/tool
/// content is compared structurally, since the two runtimes serialize object
/// keys in different orders. The actual received messages are still what the
/// host constructs, authorizes and sends in its ModelRequest.
bool coreHistoryMatches(Object? actual, List<Map<String, Object?>> expected) {
  Object? normalized(Object? input) {
    if (input is! List) return null;
    return [for (final message in input) _normalizeMessage(message)];
  }

  return coreSame(normalized(actual), normalized(expected));
}

Object? _normalizeMessage(Object? input) {
  if (input is! Map) return null;
  final message = Map<Object?, Object?>.from(input);
  final keys = switch (message['role']) {
    'user' => {'role', 'content'},
    'assistant' => {'role', 'content', 'tool_calls'},
    'tool' => {'role', 'content', 'tool_call_id'},
    _ => throw const CoreAgentFailure('host_protocol'),
  };
  coreKeys(message, keys);
  if (message['content'] is! String)
    throw const CoreAgentFailure('host_protocol');
  if (message['role'] == 'tool') {
    message['content'] = coreStrictJson(message['content'] as String);
  }
  if (message['tool_calls'] case final List calls) {
    message['tool_calls'] = [for (final call in calls) _normalizeCall(call)];
  }
  return message;
}

Object? _normalizeCall(Object? input) {
  if (input is! Map) return null;
  final call = Map<Object?, Object?>.from(input);
  coreKeys(call, {'id', 'type', 'function'});
  if (call['function'] case final Map raw) {
    final function = Map<Object?, Object?>.from(raw);
    coreKeys(function, {'name', 'arguments'});
    if (function['arguments'] is! String) {
      throw const CoreAgentFailure('host_protocol');
    }
    function['arguments'] = coreStrictJson(function['arguments'] as String);
    call['function'] = function;
  }
  return call;
}

void coreKeys(Map value, Set<String> keys) {
  if (value.length != keys.length || !value.keys.every(keys.contains)) {
    throw const CoreAgentFailure('host_protocol');
  }
}

bool coreValidCallId(String value) {
  if (value.isEmpty ||
      utf8.encode(value).length > 128 ||
      value.runes.any((r) => r < 32 || (r >= 127 && r <= 159))) {
    return false;
  }
  // Reject unpaired UTF16 surrogates instead of allowing the encoder to change
  // identity into a replacement character. Other Unicode remains valid.
  final units = value.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff)
        return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

String coreMetadata(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 128 ||
      !RegExp(r'^[A-Za-z0-9._:/-]+$').hasMatch(value)) {
    throw const CoreAgentFailure('projection_rejected');
  }
  return value;
}

/// The original result stays in the registry. Only these five typed reference
/// fields may cross into the child or subsequent model context.
Map<String, Object?> projectCoreInquiryResult(
  ToolCallResult result,
  ResolvedAssistantScope scope,
  Map<String, Object?> arguments,
) {
  if (result.status != ToolCallStatus.succeeded ||
      result.objectRefs.length != 1) {
    throw const CoreAgentFailure('projection_rejected');
  }
  final ref = result.objectRefs.single;
  if (ref.moduleId != 'inquiry' ||
      ref.objectType != arguments['type'] ||
      ref.objectId != arguments['id'] ||
      !scope.contains(ref)) {
    throw const CoreAgentFailure('projection_rejected');
  }
  String? optional(String? value) => value == null ? null : coreMetadata(value);
  return {
    'found': true,
    'objectRefs': [
      {
        'moduleId': 'inquiry',
        'objectType': coreMetadata(ref.objectType),
        'objectId': coreMetadata(ref.objectId),
        'revisionRef': optional(ref.revisionRef),
        'contentDigest': optional(ref.contentDigest),
      },
    ],
  };
}

/// Incremental bounded framing. JSON is checked for duplicate keys before the
/// standard decoder can silently discard them; depth is checked before growth.
Stream<Map<String, Object?>> coreFrames(
  Stream<List<int>> source, {
  void Function(int count)? onBytes,
}) async* {
  var buffer = <int>[];
  var total = 0;
  await for (final chunk in source) {
    total += chunk.length;
    onBytes?.call(chunk.length);
    if (total > 262144) throw const CoreAgentFailure('host_budget');
    buffer.addAll(chunk);
    while (buffer.length >= 4) {
      final size = ByteData.sublistView(
        Uint8List.fromList(buffer),
        0,
        4,
      ).getUint32(0);
      if (size == 0) throw const CoreAgentFailure('host_protocol');
      if (size > 65536) {
        throw const CoreAgentFailure('host_budget');
      }
      if (buffer.length < size + 4) break;
      Object? value;
      try {
        final text = utf8.decode(buffer.sublist(4, size + 4));
        value = coreStrictJson(text);
      } catch (_) {
        throw const CoreAgentFailure('host_protocol');
      }
      if (value is! Map<String, dynamic>) {
        throw const CoreAgentFailure('host_protocol');
      }
      yield Map<String, Object?>.from(value);
      buffer = buffer.sublist(size + 4);
    }
  }
  if (buffer.isNotEmpty) throw const CoreAgentFailure('host_protocol');
}

final class _StrictJson {
  _StrictJson(this.text);
  final String text;
  int at = 0;
  Never bad() => throw const CoreAgentFailure('host_protocol');
  void ws() {
    while (at < text.length && ' \n\r\t'.contains(text[at])) {
      at++;
    }
  }

  String string() {
    final start = at++;
    while (at < text.length) {
      final c = text[at++];
      if (c == '\\') {
        at++;
      } else if (c == '"') {
        return jsonDecode(text.substring(start, at)) as String;
      }
    }
    return bad();
  }

  void value(int depth) {
    if (depth > 32) bad();
    ws();
    if (at >= text.length) bad();
    final c = text[at];
    if (c == '"') {
      string();
      return;
    }
    if (c == '{' || c == '[') {
      at++;
      ws();
      final end = c == '{' ? '}' : ']';
      final keys = <String>{};
      if (at < text.length && text[at] == end) {
        at++;
        return;
      }
      while (true) {
        ws();
        if (c == '{') {
          if (at >= text.length || text[at] != '"') bad();
          if (!keys.add(string())) bad();
          ws();
          if (at >= text.length || text[at++] != ':') bad();
        }
        value(depth + 1);
        ws();
        if (at >= text.length) bad();
        final next = text[at++];
        if (next == end) return;
        if (next != ',') bad();
      }
    }
    final start = at;
    while (at < text.length && !',]} \n\r\t'.contains(text[at])) {
      at++;
    }
    if (at == start) bad();
    jsonDecode(text.substring(start, at));
  }

  void check() {
    value(0);
    ws();
    if (at != text.length) bad();
  }
}
