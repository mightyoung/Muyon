import 'package:flutter/widgets.dart';

import 'files.dart';
import 'module.dart';
import 'references.dart';
import 'tools.dart';

/// Declared by `ModuleFeature.importPipeline`. The members are the v1 import
/// trio on [ModuleRuntime], unchanged.
abstract interface class ImportCapable {
  Future<ImportReceipt?> receipt(String operationId);
  Future<PreparedImport> prepareImport(
    SelectedInput input,
    ImportTarget target,
  );
  Future<ImportReceipt> commitImport(PreparedImport input, ImportIntent intent);
}

/// Device-exchange item kind, such as `research-task`.
class ExchangeKind {
  const ExchangeKind(this.id);
  final String id;
  @override
  bool operator ==(Object other) => other is ExchangeKind && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// Host-independent description of a received exchange item. The final shape
/// is settled with the research migration (REG-3).
class ExchangeEnvelope {
  const ExchangeEnvelope({
    required this.kind,
    required this.id,
    required this.filePath,
    this.header = const {},
  });
  final ExchangeKind kind;
  final String id;
  final String filePath;
  final Map<String, Object?> header;
}

class ExchangeVerdict {
  const ExchangeVerdict.accept() : accepted = true, reason = null;
  const ExchangeVerdict.reject(String this.reason) : accepted = false;
  final bool accepted;
  final String? reason;
}

/// Declared by `ModuleFeature.exchange`. Transport, pairing and verification
/// stay in the host; the module only parses and imports.
abstract interface class ExchangeCapable {
  Set<ExchangeKind> get exchangeKinds;

  /// Verifies; writes nothing.
  Future<ExchangeVerdict> inspect(ExchangeEnvelope envelope);

  /// Called after the host verified and stored the item. Idempotent.
  Future<void> accept(ExchangeEnvelope envelope, ModuleSession session);
}

class ObjectPageLease {
  const ObjectPageLease({
    required this.title,
    required this.page,
    required this.dispose,
  });
  final String title;
  final Widget page;
  final Future<void> Function() dispose;
}

/// Declared by `ModuleFeature.objectPages`. Needs no workspace binding.
abstract interface class ObjectPages {
  /// Null means this module has no page for [ref].
  Future<ObjectPageLease?> open(BuildContext context, ObjectRef ref);
}

class IndexScope {
  const IndexScope({this.nativeProjectId});
  final String? nativeProjectId;
}

class IndexableItem {
  const IndexableItem({
    required this.ref,
    this.filePath,
    this.text,
    required this.contentDigest,
  });
  final ObjectRef ref;
  final String? filePath;
  final String? text;
  final String contentDigest;
}

abstract interface class SearchSource {
  String get id;
  Set<String> get objectTypes;
  Future<List<IndexableItem>> list(IndexScope scope);

  /// Pre-retrieval check; null means gone or digest mismatch.
  Future<ObjectView?> confirm(ObjectRef ref);
}

typedef ToolResultRenderer = Widget Function(
  BuildContext context,
  ToolCallResult result,
);

/// Declared by `ModuleFeature.resultRenderers`. Defined, not consumed, in the
/// second phase.
abstract interface class ResultRenderers {
  Map<String, ToolResultRenderer> get renderers;
}

class PublishContext {
  const PublishContext({required this.moduleId});
  final String moduleId;
}

class PublishCheckResult {
  const PublishCheckResult({
    required this.id,
    required this.passed,
    this.fixHint,
  });
  final String id;
  final bool passed;
  final String? fixHint;
}

/// Declared by `ModuleFeature.publishChecks`.
abstract interface class PublishChecks {
  Future<List<PublishCheckResult>> run(PublishContext context);
}
