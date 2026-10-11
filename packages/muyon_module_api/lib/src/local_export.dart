import 'dart:typed_data';

import 'context.dart';
import 'references.dart';
import 'tool_registrar.dart';

/// Optional platform capability (ADR-0004 §4.5 style). Declaring it, or a
/// [DestinationRule.localExport] target, grants no save permission: the host
/// facade still needs a per-export approval and a target the person picks.
const localExportsCapabilityId = 'local_exports';

/// One declared external target, for the cross-check below.
class LocalExportDeclaration {
  const LocalExportDeclaration(this.name, this.effect, this.destination);
  final String name;
  final ToolEffect effect;
  final DestinationRule destination;
}

/// Problems with a [DestinationRule] on its own (no module context). Shared by
/// the spec constructors and [localExportDeclarationProblems].
List<String> localExportRuleProblems(ToolEffect effect, DestinationRule rule) {
  if (!rule.localExport) return const [];
  return [
    if (rule.fixedHosts.isNotEmpty || rule.publicWeb)
      'localExport cannot be combined with a network rule',
    if (effect != ToolEffect.export) 'localExport requires the export effect',
  ];
}

/// Cross-checks local-export targets against the module's declared
/// capabilities. One message per violation; empty means compliant. Pure.
List<String> localExportDeclarationProblems({
  required Set<String> capabilityIds,
  required Iterable<LocalExportDeclaration> declarations,
}) {
  final problems = <String>[];
  for (final d in declarations) {
    if (!d.destination.localExport) continue;
    if (!capabilityIds.contains(localExportsCapabilityId)) {
      problems.add(
        '${d.name}: localExport target without the $localExportsCapabilityId capability',
      );
    }
    problems.addAll(
      localExportRuleProblems(
        d.effect,
        d.destination,
      ).map((m) => '${d.name}: $m'),
    );
  }
  return List.unmodifiable(problems);
}

enum LocalExportKind { report, claimDrafts }

class LocalExportExclusion {
  const LocalExportExclusion(this.id, this.reason);
  final String id, reason;
}

final _hex64 = RegExp(r'^[0-9a-f]{64}$');

/// The frozen content of one export, produced once before any approval. All
/// collections and source/exclusion values are copied and unmodifiable;
/// later changes by the caller do not
/// reach it, so what is approved is what is written.
class LocalExportPreparation {
  LocalExportPreparation({
    required this.kind,
    required this.formatVersion,
    required this.mimeType,
    required this.generatedAt,
    required List<int> bytes,
    required this.sha256,
    required List<ObjectRef> sources,
    required this.dedupedObjectCount,
    required List<LocalExportExclusion> exclusions,
    required List<String> warnings,
    required this.preparationVersion,
    required this.manifestDigest,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView(),
       sources = List.unmodifiable(
         sources.map(
           (source) => ObjectRef(
             moduleId: source.moduleId,
             objectType: source.objectType,
             objectId: source.objectId,
             nativeProjectId: source.nativeProjectId,
             revisionRef: source.revisionRef,
             contentDigest: source.contentDigest,
           ),
         ),
       ),
       exclusions = List.unmodifiable(
         exclusions.map(
           (exclusion) => LocalExportExclusion(exclusion.id, exclusion.reason),
         ),
       ),
       warnings = List.unmodifiable(warnings) {
    if (bytes.isEmpty) throw ArgumentError('An export has content');
    if (!_hex64.hasMatch(sha256) || !_hex64.hasMatch(manifestDigest)) {
      throw ArgumentError('Digests are lowercase SHA-256 hex');
    }
    if (dedupedObjectCount < 0) throw ArgumentError('Negative object count');
    if (preparationVersion < 1) throw ArgumentError('Preparation version');
    if (formatVersion.isEmpty || mimeType.isEmpty) {
      throw ArgumentError('Format and MIME type are required');
    }
  }
  final LocalExportKind kind;
  final String formatVersion, mimeType;
  final DateTime generatedAt;
  final Uint8List bytes;
  int get byteCount => bytes.length;
  final String sha256;

  /// Source objects with their revisions / digests as read.
  final List<ObjectRef> sources;

  /// Distinct objects actually present in the content.
  final int dedupedObjectCount;
  final List<LocalExportExclusion> exclusions;
  final List<String> warnings;
  final int preparationVersion;
  final String manifestDigest;
}

enum LocalExportOutcome { succeeded, cancelled, failed, interrupted, unknown }

enum LocalExportCleanup { notNeeded, cleaned, residue, unknown }

final _safeCode = RegExp(r'^[a-z0-9_]{1,64}$');

/// One stage's result. [errorCode] is a short identifier, never a path or text.
class LocalExportStage {
  LocalExportStage(
    this.outcome, {
    this.cleanup = LocalExportCleanup.notNeeded,
    this.errorCode,
  }) {
    final code = errorCode;
    if (code != null && !_safeCode.hasMatch(code)) {
      throw ArgumentError('Error codes are short identifiers');
    }
  }
  final LocalExportOutcome outcome;
  final LocalExportCleanup cleanup;
  final String? errorCode;
}

/// Generation and saving are separate stages; a cancelled save after a
/// successful generation is not a failure of the export file.
class LocalExportResult {
  LocalExportResult({required this.generate, this.save}) {
    if (save != null && generate.outcome != LocalExportOutcome.succeeded) {
      throw ArgumentError('Saving needs a generated export');
    }
  }
  final LocalExportStage generate;
  final LocalExportStage? save;
  bool get completed =>
      generate.outcome == LocalExportOutcome.succeeded &&
      save?.outcome == LocalExportOutcome.succeeded;
}
