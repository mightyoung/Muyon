import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

/// E02: preparationDigest / presentationDigest freeze + A/B identity types.
void main() {
  final digest = 'a' * 64;
  final source = ObjectRef(
    moduleId: 'research',
    objectType: 'project',
    objectId: 'P',
    revisionRef: 'r1',
    contentDigest: 'c' * 64,
  );

  LocalExportPreparation prepare({
    List<int>? bytes,
    List<ObjectRef>? sources,
    List<LocalExportExclusion>? exclusions,
    List<String>? warnings,
    DateTime? generatedAt,
    String? manifestDigest,
    int dedupedObjectCount = 1,
  }) => LocalExportPreparation(
    kind: LocalExportKind.report,
    formatVersion: 'report-md-1',
    mimeType: 'text/markdown',
    generatedAt: generatedAt ?? DateTime.utc(2026, 10, 11, 12),
    bytes: bytes ?? const [1, 2, 3],
    sha256: digest,
    sources: sources ?? [source],
    dedupedObjectCount: dedupedObjectCount,
    exclusions: exclusions ?? const [],
    warnings: warnings ?? const [],
    preparationVersion: 1,
    manifestDigest: manifestDigest ?? digest,
  );

  /// Mutation probe: a broken digest that forgets exclusions. Real digest must
  /// not collide the way this one does.
  String omitExclusions(LocalExportPreparation p) {
    final payload = jsonEncode([
      p.sha256,
      p.manifestDigest,
      p.byteCount,
      p.kind.name,
      p.formatVersion,
      p.mimeType,
      p.generatedAt.toUtc().toIso8601String(),
      p.dedupedObjectCount,
      p.sources.map((s) => s.toJson()).toList(),
      // exclusions intentionally omitted
      p.warnings,
      p.preparationVersion,
    ]);
    return sha256.convert(utf8.encode(payload)).toString();
  }

  String omitWarnings(LocalExportPreparation p) {
    final payload = jsonEncode([
      p.sha256,
      p.manifestDigest,
      p.byteCount,
      p.kind.name,
      p.formatVersion,
      p.mimeType,
      p.generatedAt.toUtc().toIso8601String(),
      p.dedupedObjectCount,
      p.sources.map((s) => s.toJson()).toList(),
      p.exclusions.map((e) => {'id': e.id, 'reason': e.reason}).toList(),
      // warnings intentionally omitted
      p.preparationVersion,
    ]);
    return sha256.convert(utf8.encode(payload)).toString();
  }

  group('preparationDigest', () {
    test('exclusions change the digest even when bytes stay the same', () {
      final sameBytes = [1, 2, 3];
      final base = prepare(bytes: sameBytes);
      final changed = prepare(
        bytes: sameBytes,
        exclusions: const [LocalExportExclusion('x', 'out of scope')],
      );
      expect(base.sha256, changed.sha256);
      expect(base.byteCount, changed.byteCount);
      expect(base.preparationDigest, isNot(changed.preparationDigest));
    });

    test('warnings change the digest', () {
      final base = prepare();
      final changed = prepare(warnings: const ['truncated']);
      expect(base.preparationDigest, isNot(changed.preparationDigest));
    });

    test('counts, manifest, and generatedAt change the digest', () {
      final base = prepare();
      expect(
        prepare(dedupedObjectCount: 2).preparationDigest,
        isNot(base.preparationDigest),
      );
      expect(
        prepare(manifestDigest: 'b' * 64).preparationDigest,
        isNot(base.preparationDigest),
      );
      expect(
        prepare(generatedAt: DateTime.utc(2026, 10, 12)).preparationDigest,
        isNot(base.preparationDigest),
      );
    });

    test('mutation: omitting exclusions collides; real digest does not', () {
      final empty = prepare();
      final withEx = prepare(
        exclusions: const [LocalExportExclusion('x', 'denied')],
      );
      expect(omitExclusions(empty), omitExclusions(withEx));
      expect(empty.preparationDigest, isNot(withEx.preparationDigest));
    });

    test('mutation: omitting warnings collides; real digest does not', () {
      final empty = prepare();
      final withWarn = prepare(warnings: const ['soft']);
      expect(omitWarnings(empty), omitWarnings(withWarn));
      expect(empty.preparationDigest, isNot(withWarn.preparationDigest));
    });

    test('collections are deep-frozen', () {
      final exclusions = [const LocalExportExclusion('x', 'r')];
      final warnings = ['w'];
      final sources = [source];
      final p = prepare(
        exclusions: exclusions,
        warnings: warnings,
        sources: sources,
      );
      expect(() => p.exclusions.add(const LocalExportExclusion('y', 'r')), throwsUnsupportedError);
      expect(() => p.warnings.add('z'), throwsUnsupportedError);
      expect(() => p.sources.add(source), throwsUnsupportedError);
      expect(() => p.bytes[0] = 9, throwsUnsupportedError);
    });
  });

  group('presentationDigest', () {
    test('review outcome is outside preparation and changes presentation', () {
      final prep = prepare();
      final before = LocalExportPresentation(
        fixedCardId: 'card-export-v1',
        preparationDigest: prep.preparationDigest,
        reviewOutcome: null,
        phase: LocalExportPhase.generate,
        targetIdentity: null,
        overwrite: LocalExportOverwrite.createNew,
      );
      final after = LocalExportPresentation(
        fixedCardId: 'card-export-v1',
        preparationDigest: prep.preparationDigest,
        reviewOutcome: 'approved',
        phase: LocalExportPhase.generate,
        targetIdentity: null,
        overwrite: LocalExportOverwrite.createNew,
      );
      expect(before.presentationDigest, isNot(after.presentationDigest));
      // preparation itself does not embed review
      expect(prep.preparationDigest, isNot(before.presentationDigest));
    });

    test('phase, target, overwrite, and card change the presentation digest', () {
      final prep = prepare();
      final base = LocalExportPresentation(
        fixedCardId: 'card-export-v1',
        preparationDigest: prep.preparationDigest,
        reviewOutcome: null,
        phase: LocalExportPhase.generate,
        targetIdentity: null,
        overwrite: LocalExportOverwrite.createNew,
      );
      expect(
        LocalExportPresentation(
          fixedCardId: 'card-export-v2',
          preparationDigest: prep.preparationDigest,
          reviewOutcome: null,
          phase: LocalExportPhase.generate,
          targetIdentity: null,
          overwrite: LocalExportOverwrite.createNew,
        ).presentationDigest,
        isNot(base.presentationDigest),
      );
      expect(
        LocalExportPresentation(
          fixedCardId: 'card-export-v1',
          preparationDigest: prep.preparationDigest,
          reviewOutcome: null,
          phase: LocalExportPhase.save,
          targetIdentity: 'tgt-1',
          overwrite: LocalExportOverwrite.createNew,
        ).presentationDigest,
        isNot(base.presentationDigest),
      );
      expect(
        LocalExportPresentation(
          fixedCardId: 'card-export-v1',
          preparationDigest: prep.preparationDigest,
          reviewOutcome: null,
          phase: LocalExportPhase.save,
          targetIdentity: 'tgt-1',
          overwrite: LocalExportOverwrite.replace,
        ).presentationDigest,
        isNot(
          LocalExportPresentation(
            fixedCardId: 'card-export-v1',
            preparationDigest: prep.preparationDigest,
            reviewOutcome: null,
            phase: LocalExportPhase.save,
            targetIdentity: 'tgt-1',
            overwrite: LocalExportOverwrite.createNew,
          ).presentationDigest,
        ),
      );
    });
  });

  group('stage call identity', () {
    test('generate and save identities are distinct types', () {
      final a = LocalExportGenerateCall(
        exportId: 'export-1',
        invocationId: 'inv-a',
      );
      final b = LocalExportSaveCall(
        exportId: 'export-1',
        invocationId: 'inv-b',
      );
      expect(a, isA<LocalExportCallIdentity>());
      expect(b, isA<LocalExportCallIdentity>());
      expect(a.phase, LocalExportPhase.generate);
      expect(b.phase, LocalExportPhase.save);
      expect(a.runtimeType, isNot(b.runtimeType));
    });

    test('mutation: a shared string identity would not distinguish stages', () {
      // Broken approach: one opaque string for both stages.
      String shared(String exportId, String invocationId) =>
          '$exportId|$invocationId';
      final same = shared('e', 'i');
      expect(same, shared('e', 'i')); // would allow A string to look like B
      final gen = LocalExportGenerateCall(exportId: 'e', invocationId: 'i');
      final save = LocalExportSaveCall(exportId: 'e', invocationId: 'i');
      expect(gen.phase, isNot(save.phase));
      expect(identical(gen, save), isFalse);
    });
  });
}
