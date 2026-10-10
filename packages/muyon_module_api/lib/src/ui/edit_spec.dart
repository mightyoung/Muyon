import 'dart:convert';

import 'collection.dart';
import 'plan.dart';

/// Typed edit specs only take effect under this catalog version; every older
/// catalog keeps the string-only gate even when a snapshot registers specs.
const typedEditCatalogVersion = 'library-2';
bool usesTypedEdits(UiCatalog catalog) =>
    catalog.version == typedEditCatalogVersion;

/// Hard ceiling for [UiStringEdit.maxLength] (UTF-8 bytes); hosts may not raise it.
const uiStringEditMaxBytes = 4096;
const _maxSafeInteger = 9007199254740991;

/// Collections visible to membership checks (itemIds).
class UiEditContext {
  UiEditContext({Map<String, UiCollection> collections = const {}})
    : collections = Map.unmodifiable(collections);
  final Map<String, UiCollection> collections;
}

/// Host-declared edit rule for one state key. Never converts, rounds or clamps:
/// every check returns null (accept) or a stable error code.
sealed class UiEditSpec {
  const UiEditSpec({this.nullable = false, this.view = false});

  /// A null payload is legal (clearing the value).
  final bool nullable;

  /// Writes view state only: no draftRevision bump, never a business input.
  final bool view;
  UiValueType get payloadType;

  /// Pure type/range/format check, including the null decision.
  String? rejectPayload(Object? payload);

  /// Checks that need host data (itemIds membership).
  String? rejectInContext(Object? payload, UiEditContext context) => null;

  /// Host metadata sanity; the host must not build a snapshot when non-null.
  String? validateSpec();

  /// Both layers; null means accepted.
  String? reject(Object? payload, UiEditContext context) =>
      rejectPayload(payload) ??
      (payload == null ? null : rejectInContext(payload, context));

  String? _nullDecision(Object? payload) =>
      payload == null ? (nullable ? null : 'null_not_allowed') : _kContinue;
}

const _kContinue = '\u0000continue';

final class UiStringEdit extends UiEditSpec {
  const UiStringEdit({
    this.maxLength = uiStringEditMaxBytes,
    this.accepts,
    super.nullable,
    super.view,
  });
  final int maxLength;
  final bool Function(String)? accepts;
  @override
  UiValueType get payloadType => UiValueType.string;
  @override
  String? rejectPayload(Object? payload) {
    final decision = _nullDecision(payload);
    if (decision != _kContinue) return decision;
    if (payload is! String) return 'type';
    if (utf8.encode(payload).length > maxLength) return 'max_length';
    if (accepts != null && !accepts!(payload)) return 'format';
    return null;
  }

  @override
  String? validateSpec() => maxLength < 1 || maxLength > uiStringEditMaxBytes
      ? 'max_length_invalid'
      : null;
}

final class UiBoolEdit extends UiEditSpec {
  const UiBoolEdit({super.nullable, super.view});
  @override
  UiValueType get payloadType => UiValueType.boolean;
  @override
  String? rejectPayload(Object? payload) {
    final decision = _nullDecision(payload);
    if (decision != _kContinue) return decision;
    return payload is bool ? null : 'type';
  }

  @override
  String? validateSpec() => null;
}

final class UiNumberEdit extends UiEditSpec {
  const UiNumberEdit({
    required this.min,
    required this.max,
    this.step,
    this.integer = false,
    super.nullable,
    super.view,
  });
  final double min, max;
  final double? step;
  final bool integer;
  @override
  UiValueType get payloadType => UiValueType.number;
  @override
  String? rejectPayload(Object? payload) {
    final decision = _nullDecision(payload);
    if (decision != _kContinue) return decision;
    if (payload is! num) return 'type';
    if (!payload.isFinite) return 'not_finite';
    if (integer &&
        (payload != payload.truncate() || payload.abs() > _maxSafeInteger)) {
      return 'not_integer';
    }
    if (payload < min || payload > max) return 'range';
    final s = step;
    if (s != null) {
      final cells = (payload - min) / s;
      // A ratio that overflows cannot be proven on-grid: reject, never convert.
      if (!cells.isFinite || (cells - cells.roundToDouble()).abs() > 1e-9) {
        return 'off_grid';
      }
    }
    return null;
  }

  @override
  String? validateSpec() {
    if (!min.isFinite || !max.isFinite || min > max) return 'range_invalid';
    final s = step;
    if (s != null && (!s.isFinite || s <= 0)) return 'step_invalid';
    return null;
  }
}

/// Strict `YYYY-MM-DD`, year 0001-9999, real Gregorian day, no time or zone.
bool isStrictIsoDate(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return false;
  }
  final y = int.parse(value.substring(0, 4));
  final m = int.parse(value.substring(5, 7));
  final d = int.parse(value.substring(8, 10));
  if (y < 1) return false;
  final parsed = DateTime.utc(y, m, d);
  return parsed.year == y && parsed.month == m && parsed.day == d;
}

final class UiDateEdit extends UiEditSpec {
  const UiDateEdit({
    required this.first,
    required this.last,
    super.nullable,
    super.view,
  });
  final String first, last; // 'YYYY-MM-DD', inclusive
  @override
  UiValueType get payloadType => UiValueType.string;
  @override
  String? rejectPayload(Object? payload) {
    final decision = _nullDecision(payload);
    if (decision != _kContinue) return decision;
    if (payload is! String) return 'type';
    if (!isStrictIsoDate(payload)) return 'date_format';
    // Same fixed-width format: lexicographic order is date order.
    if (payload.compareTo(first) < 0 || payload.compareTo(last) > 0) {
      return 'range';
    }
    return null;
  }

  @override
  String? validateSpec() =>
      !isStrictIsoDate(first) ||
          !isStrictIsoDate(last) ||
          first.compareTo(last) > 0
      ? 'range_invalid'
      : null;
}

final class UiItemIdsEdit extends UiEditSpec {
  UiItemIdsEdit({
    required this.collectionId,
    this.multiple = false,
    List<String> initial = const [],
    super.view,
  }) : initial = List.unmodifiable(initial);
  final String collectionId;
  final bool multiple;
  final List<String> initial;
  @override
  UiValueType get payloadType => UiValueType.stringList;

  /// Canonical stored form: de-duplicated, `String.compareTo` ascending.
  static List<String> normalize(Iterable<String> ids) =>
      List.unmodifiable(ids.toSet().toList()..sort());

  @override
  String? rejectPayload(Object? payload) {
    if (payload == null) return 'null_not_allowed';
    if (payload is! List || payload.any((e) => e is! String)) return 'type';
    final ids = payload.cast<String>();
    if (ids.toSet().length != ids.length) return 'duplicate';
    if (ids.length > UiCollectionLimits.rows) return 'too_many';
    if (!multiple && ids.length > 1) return 'single_select';
    return null;
  }

  @override
  String? rejectInContext(Object? payload, UiEditContext context) {
    if (payload is! List || payload.any((e) => e is! String)) return 'type';
    final collection = context.collections[collectionId];
    if (collection == null) return 'unknown_collection';
    final known = {for (final row in collection.rows) row.itemId};
    return payload.every(known.contains) ? null : 'unknown_item';
  }

  @override
  String? validateSpec() {
    if (collectionId.isEmpty) return 'collection_id';
    return rejectPayload(initial);
  }
}
