import 'package:flutter/foundation.dart';

@immutable
class PrototypePage {
  const PrototypePage({
    required this.id,
    required this.title,
    required this.createdAt,
    this.latestVersionId,
  });
  final String id;
  final String title;
  final DateTime createdAt;
  final String? latestVersionId;
}

@immutable
class PrototypeVersion {
  const PrototypeVersion({
    required this.id,
    required this.pageId,
    required this.label,
    required this.digest,
    required this.directory,
    required this.fileCount,
    required this.createdAt,
  });
  final String id;
  final String pageId;
  final String label;

  /// SHA-256 over every file path and content in the imported build.
  final String digest;

  /// Absolute directory holding the copied build; the WebView root.
  final String directory;
  final int fileCount;
  final DateTime createdAt;
}

@immutable
class PrototypeFeedback {
  const PrototypeFeedback({
    required this.id,
    required this.pageId,
    required this.versionId,
    required this.text,
    required this.createdAt,
  });
  final String id;
  final String pageId;
  final String versionId;
  final String text;
  final DateTime createdAt;
}
