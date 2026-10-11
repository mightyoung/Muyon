import 'package:collection/collection.dart';

import 'context.dart';
import 'write_forms.dart';

/// Stable conflict codes (ADR-0004 §4.5, W3). A conflict stays `failed`; the
/// code travels in trusted `ToolCallResult.data`, never in the summary text.
const writeConflictCodes = {
  'version_conflict',
  'scope_changed',
  'referencing_changed',
  'operation_id_reuse',
};

/// Structured conflict for a failed write. Host-built data, not model input.
class WriteConflict {
  WriteConflict({
    required this.code,
    required this.currentVersion,
    List<String> fieldPaths = const [],
    Map<String, Object?> details = const {},
  }) : fieldPaths = List.unmodifiable(fieldPaths),
       details = freezeJsonMap(details) {
    if (!writeConflictCodes.contains(code)) {
      throw ArgumentError.value(code, 'code', 'not a stable conflict code');
    }
    if (currentVersion is! int && currentVersion is! String) {
      throw ArgumentError.value(
        currentVersion,
        'currentVersion',
        'expected an int or a string',
      );
    }
    for (final path in this.fieldPaths) {
      if (!isStableFieldPath(path)) {
        throw ArgumentError.value(path, 'fieldPaths', 'expected a stable path');
      }
    }
  }

  final String code;

  /// The stored version (int) or revision digest (string) the caller must
  /// reconcile against.
  final Object currentVersion;
  final List<String> fieldPaths;
  final Map<String, Object?> details;

  /// Keys are part of the contract: `error_code`, `current_version`, and the
  /// optional `field_paths` and `details`.
  Map<String, Object?> toTrustedData() => freezeJsonMap({
    'error_code': code,
    'current_version': currentVersion,
    if (fieldPaths.isNotEmpty) 'field_paths': fieldPaths,
    if (details.isNotEmpty) 'details': details,
  });

  @override
  bool operator ==(Object other) =>
      other is WriteConflict &&
      other.code == code &&
      other.currentVersion == currentVersion &&
      const ListEquality<String>().equals(other.fieldPaths, fieldPaths) &&
      const DeepCollectionEquality().equals(other.details, details);

  @override
  int get hashCode => Object.hash(
    code,
    currentVersion,
    const ListEquality<String>().hash(fieldPaths),
    const DeepCollectionEquality().hash(details),
  );
}
