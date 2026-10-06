import 'cards/canonical_json.dart';

class ObjectKey implements Comparable<ObjectKey> {
  ObjectKey({
    required this.originProjectKey,
    required this.objectType,
    required this.objectUuid,
  }) {
    if (![
      originProjectKey,
      objectType,
      objectUuid,
    ].every((value) => RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value))) {
      throw const FormatException('Invalid canonical object identity');
    }
  }
  final String originProjectKey;
  final String objectType;
  final String objectUuid;
  Map<String, Object?> toJson() => {
    'originProjectKey': originProjectKey,
    'objectType': objectType,
    'objectUuid': objectUuid,
  };
  factory ObjectKey.fromJson(Map<String, Object?> json) => ObjectKey(
    originProjectKey: json['originProjectKey'] as String,
    objectType: json['objectType'] as String,
    objectUuid: json['objectUuid'] as String,
  );
  String get token => canonicalJson(toJson());
  @override
  int compareTo(ObjectKey other) {
    for (final pair in [
      (originProjectKey, other.originProjectKey),
      (objectType, other.objectType),
      (objectUuid, other.objectUuid),
    ]) {
      final compared = pair.$1.compareTo(pair.$2);
      if (compared != 0) return compared;
    }
    return 0;
  }

  @override
  bool operator ==(Object other) => other is ObjectKey && token == other.token;
  @override
  int get hashCode => token.hashCode;
}

class SourceRef {
  SourceRef({
    required this.documentRef,
    required this.contentDigest,
    required this.pageIndex,
    required this.quote,
    this.contextBefore,
    this.contextAfter,
    this.parserVersion,
    List<SourceBox>? coordinates,
  }) : coordinates = coordinates == null
           ? null
           : List.unmodifiable(coordinates) {
    if (documentRef.objectType != 'document' ||
        pageIndex < 0 ||
        pageIndex > 9007199254740991 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(contentDigest)) {
      throw const FormatException('Invalid source reference');
    }
    validateUnicode(quote);
    if (contextBefore != null) validateUnicode(contextBefore!);
    if (contextAfter != null) validateUnicode(contextAfter!);
    if (parserVersion != null) validateUnicode(parserVersion!);
  }
  final ObjectKey documentRef;
  final String contentDigest;
  final int pageIndex;
  final String quote;
  final String? contextBefore;
  final String? contextAfter;
  final String? parserVersion;

  /// Fractions of the physical page, from its top-left corner.
  /// Evidence only: the resolver never trusts stored boxes as parser proof.
  final List<SourceBox>? coordinates;
  Map<String, Object?> toJson() => {
    'documentRef': documentRef.toJson(),
    'contentDigest': contentDigest,
    'pageIndex': pageIndex,
    'quote': quote,
    'contextBefore': contextBefore,
    'contextAfter': contextAfter,
    'parserVersion': parserVersion,
    if (coordinates != null)
      'coordinates': coordinates!.map((box) => box.toJson()).toList(),
  };
  factory SourceRef.fromJson(Map<String, Object?> json) => SourceRef(
    documentRef: ObjectKey.fromJson(
      Map<String, Object?>.from(json['documentRef'] as Map),
    ),
    contentDigest: json['contentDigest'] as String,
    pageIndex: json['pageIndex'] as int,
    quote: json['quote'] as String,
    contextBefore: json['contextBefore'] as String?,
    contextAfter: json['contextAfter'] as String?,
    parserVersion: json['parserVersion'] as String?,
    coordinates: json['coordinates'] == null
        ? null
        : (json['coordinates'] as List)
              .map(
                (box) =>
                    SourceBox.fromJson(Map<String, Object?>.from(box as Map)),
              )
              .toList(),
  );
  SourceAvailability availability({
    required bool exists,
    required String? currentDigest,
  }) => !exists
      ? SourceAvailability.missing
      : currentDigest != contentDigest
      ? SourceAvailability.replaced
      : SourceAvailability.pageLevel;
}

enum SourceAvailability { missing, replaced, pageLevel }

/// A finite, positive-area rectangle in normalized physical page coordinates.
class SourceBox {
  SourceBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  }) {
    if (![
          left,
          top,
          right,
          bottom,
        ].every((v) => v.isFinite && v >= 0 && v <= 1) ||
        left >= right ||
        top >= bottom) {
      throw const FormatException('Invalid normalized source coordinates');
    }
  }
  final double left, top, right, bottom;
  Map<String, Object?> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };
  factory SourceBox.fromJson(Map<String, Object?> json) {
    const fields = {'left', 'top', 'right', 'bottom'};
    if (json.length != fields.length ||
        json.keys.toSet().difference(fields).isNotEmpty ||
        fields.any((key) => json[key] is! num)) {
      throw const FormatException(
        'Invalid normalized source coordinate fields',
      );
    }
    return SourceBox(
      left: (json['left'] as num).toDouble(),
      top: (json['top'] as num).toDouble(),
      right: (json['right'] as num).toDouble(),
      bottom: (json['bottom'] as num).toDouble(),
    );
  }
}
