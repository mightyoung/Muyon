import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

/// What a model handle is valid for: one task, its host scope and the host's
/// current snapshot/authority pin. A change of pin retires every older handle.
final class ModelReferenceBinding {
  const ModelReferenceBinding({
    required this.taskId,
    required this.scopeKey,
    required this.pin,
  });
  final String taskId, scopeKey, pin;
}

final class ModelReferenceRejected implements Exception {
  const ModelReferenceRejected(this.code);

  /// unknown | cross_task | wrong_scope | expired | revoked
  final String code;
  @override
  String toString() => 'ModelReferenceRejected($code)';
}

/// Host-private map from unpredictable handles to full object references. The
/// persistent identity, receipts and CAS keep the full digest; the model only
/// ever sees a handle. A handle is HMAC(host key, binding + object + digest):
/// not a fixed or public salt, stable for the same task and pin (so a preview
/// and the request it approves carry identical bytes), and not a permission:
/// it is never an input to authorization, only a way to name what was shown.
final class ModelReferenceMap {
  ModelReferenceMap(List<int> key, {this.maxHandles = 65536})
    : _key = List.unmodifiable(key) {
    if (key.length < 16) throw ArgumentError('Host key too short');
  }
  factory ModelReferenceMap.random() {
    final random = Random.secure();
    return ModelReferenceMap(List.generate(32, (_) => random.nextInt(256)));
  }
  final List<int> _key;
  final int maxHandles;
  final _entries = <String, _Entry>{};
  final _revoked = <String>{};

  String handleFor(ObjectRef ref, {required ModelReferenceBinding binding}) {
    if (ref.contentDigest == null) {
      throw ArgumentError('Only digest-bearing references need a handle');
    }
    if (_revoked.contains(binding.taskId)) {
      throw const ModelReferenceRejected('revoked');
    }
    final mac = Hmac(sha256, _key).convert(
      utf8.encode(
        jsonEncode([
          binding.taskId,
          binding.scopeKey,
          binding.pin,
          ref.toJson(),
        ]),
      ),
    );
    final handle =
        'mr1_${base64Url.encode(mac.bytes.sublist(0, 24)).replaceAll('=', '')}';
    if (!_entries.containsKey(handle)) {
      while (_entries.length >= maxHandles) {
        _entries.remove(_entries.keys.first);
      }
      _entries[handle] = _Entry(binding, ref);
    }
    return handle;
  }

  /// Returns the full reference only for a handle this instance minted for the
  /// same task, scope and pin; anything else is rejected without a fallback.
  ObjectRef resolve(String handle, {required ModelReferenceBinding current}) {
    final entry = _entries[handle];
    if (entry == null) throw const ModelReferenceRejected('unknown');
    if (_revoked.contains(entry.binding.taskId)) {
      throw const ModelReferenceRejected('revoked');
    }
    if (entry.binding.taskId != current.taskId) {
      throw const ModelReferenceRejected('cross_task');
    }
    if (entry.binding.scopeKey != current.scopeKey) {
      throw const ModelReferenceRejected('wrong_scope');
    }
    if (entry.binding.pin != current.pin) {
      throw const ModelReferenceRejected('expired');
    }
    return entry.ref;
  }

  void revokeTask(String taskId) => _revoked.add(taskId);
}

final class _Entry {
  const _Entry(this.binding, this.ref);
  final ModelReferenceBinding binding;
  final ObjectRef ref;
}

/// Replaces every object reference in [json] by its model form: locating fields
/// stay, `contentDigest` goes, a handle is added. Artifact digests are dropped.
/// Other keys, including a bare `contentDigest` in tool data, are untouched.
Object? projectModelJson(
  Object? json,
  ModelReferenceMap map,
  ModelReferenceBinding binding,
) {
  if (json is List) {
    return [for (final v in json) projectModelJson(v, map, binding)];
  }
  if (json is! Map) return json;
  final isObject =
      json['moduleId'] is String &&
      json['objectType'] is String &&
      json['objectId'] is String;
  final isArtifact =
      !isObject &&
      json['moduleId'] is String &&
      json['artifactId'] is String &&
      json.containsKey('contentDigest');
  if (isObject && json['contentDigest'] is String) {
    final ref = objectRefFromJson(Map<String, Object?>.from(json));
    final out = <String, Object?>{
      for (final e in json.entries)
        if (e.key != 'contentDigest')
          '${e.key}': projectModelJson(e.value, map, binding),
    };
    out['modelRef'] = map.handleFor(ref, binding: binding);
    return out;
  }
  return {
    for (final e in json.entries)
      if (!(isArtifact && e.key == 'contentDigest') &&
          !(isObject && e.key == 'contentDigest'))
        '${e.key}': projectModelJson(e.value, map, binding),
  };
}

/// A message body that is JSON is projected; any other text is left as it is.
String projectModelMessageContent(
  String content,
  ModelReferenceMap map,
  ModelReferenceBinding binding,
) {
  final trimmed = content.trimLeft();
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return content;
  try {
    return jsonEncode(projectModelJson(jsonDecode(content), map, binding));
  } on FormatException {
    return content;
  }
}
