import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

/// Canonical JSON: map keys sorted at every level. Stored receipt arguments
/// are compared as bytes, so this must not change.
Object? canonicalValue(Object? value) => switch (value) {
  Map value => {
    for (final key in (value.keys.cast<String>().toList()..sort()))
      key: canonicalValue(value[key]),
  },
  List value => value.map(canonicalValue).toList(),
  _ => value,
};

String canonicalJson(Object? value) => jsonEncode(canonicalValue(value));

/// The identity of one generic write under `reg4c:`: operation, parameters
/// and the resolved scope. The write tool stores [arguments] with its result;
/// a later lookup recomputes the same bytes to prove a receipt belongs to a
/// given request.
final class GenericWriteIdentity {
  GenericWriteIdentity({
    required this.operation,
    required this.parameters,
    required this.workspaceId,
    required List<ObjectRef> objects,
  }) : objects = List.unmodifiable(objects);

  final String operation;
  final Map<String, Object?> parameters;
  final String? workspaceId;
  final List<ObjectRef> objects;

  String get scopeKey => canonicalJson({
    'workspace': workspaceId,
    'objects': (objects
        .map(
          (r) => canonicalJson([
            r.moduleId,
            r.objectType,
            r.objectId,
            r.nativeProjectId,
          ]),
        )
        .toList()
      ..sort()),
  });

  String get arguments => canonicalJson({
    'operation': operation,
    'parameters': parameters,
    'scope': scopeKey,
  });

  String get receiptKey => 'reg4c:${parameters['operation_id']}';

  String get toolId => 'inquiry.$operation';

  /// Digest of [arguments]: the request identity a lookup must match.
  String get requestDigest => sha256.convert(utf8.encode(arguments)).toString();

  /// Digest of [scopeKey]: the scope identity a lookup must match.
  String get scopeDigest => sha256.convert(utf8.encode(scopeKey)).toString();
}
