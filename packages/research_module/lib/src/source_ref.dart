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
  }) {
    if (documentRef.objectType != 'document' ||
        pageIndex < 0 ||
        pageIndex > 9007199254740991 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(contentDigest)) {
      throw const FormatException('Invalid source reference');
    }
    validateUnicode(quote);
  }
  final ObjectKey documentRef;
  final String contentDigest;
  final int pageIndex;
  final String quote;
  final String? contextBefore;
  final String? contextAfter;
  final String? parserVersion;
  Map<String, Object?> toJson() => {
    'documentRef': documentRef.toJson(),
    'contentDigest': contentDigest,
    'pageIndex': pageIndex,
    'quote': quote,
    'contextBefore': contextBefore,
    'contextAfter': contextAfter,
    'parserVersion': parserVersion,
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
