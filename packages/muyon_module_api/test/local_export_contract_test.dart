import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

/// LE-01: the declaration contract for the host's local export facade. A
/// declaration grants nothing; it only says "use the host facade".
void main() {
  final digest = 'a' * 64;
  ExternalToolSpec tool({
    required ToolEffect effect,
    required DestinationRule destination,
  }) => ExternalToolSpec(
    name: 'export_report',
    description: 'd',
    effect: effect,
    destination: destination,
  );

  LocalExportPreparation prepare({
    List<int>? bytes,
    List<ObjectRef>? sources,
    List<LocalExportExclusion>? exclusions,
    List<String>? warnings,
  }) => LocalExportPreparation(
    kind: LocalExportKind.report,
    formatVersion: 'report-md-1',
    mimeType: 'text/markdown',
    generatedAt: DateTime.utc(2026, 10, 11),
    bytes: bytes ?? [1, 2, 3],
    sha256: digest,
    sources:
        sources ??
        [
          const ObjectRef(
            moduleId: 'research',
            objectType: 'project',
            objectId: 'P',
            revisionRef: 'r1',
          ),
        ],
    dedupedObjectCount: 1,
    exclusions: exclusions ?? const [],
    warnings: warnings ?? const [],
    preparationVersion: 1,
    manifestDigest: digest,
  );

  group('destination rule', () {
    test('localExport carries no path, host or web access', () {
      const rule = DestinationRule.localExport();
      expect(rule.localExport, isTrue);
      expect(rule.fixedHosts, isEmpty);
      expect(rule.publicWeb, isFalse);
    });

    test('network rules keep their shape and are not local exports', () {
      const rule = DestinationRule(fixedHosts: {'a.example'}, publicWeb: true);
      expect(rule.localExport, isFalse);
      expect(rule.fixedHosts, {'a.example'});
      expect(rule.publicWeb, isTrue);
      expect(const DestinationRule().localExport, isFalse);
      final spec = tool(effect: ToolEffect.network, destination: rule);
      expect(spec.destination, same(rule));
    });

    test('a local export is an export-effect declaration only', () {
      final ok = tool(
        effect: ToolEffect.export,
        destination: const DestinationRule.localExport(),
      );
      expect(ok.destination.localExport, isTrue);
      expect(
        () => tool(
          effect: ToolEffect.network,
          destination: const DestinationRule.localExport(),
        ),
        throwsArgumentError,
      );
      expect(
        () => ChannelSpec(
          name: 'c',
          description: 'd',
          effect: ToolEffect.network,
          destination: const DestinationRule.localExport(),
          parameterSchema: const {'type': 'object'},
        ),
        throwsArgumentError,
      );
    });

    test('a local export cannot be mixed with a network rule', () {
      const mixedHosts = DestinationRule(
        fixedHosts: {'a.example'},
        localExport: true,
      );
      const mixedWeb = DestinationRule(publicWeb: true, localExport: true);
      for (final rule in [mixedHosts, mixedWeb]) {
        expect(
          () => tool(effect: ToolEffect.export, destination: rule),
          throwsArgumentError,
        );
        expect(
          localExportDeclarationProblems(
            capabilityIds: const {localExportsCapabilityId},
            declarations: [
              LocalExportDeclaration('t', ToolEffect.export, rule),
            ],
          ),
          isNotEmpty,
        );
      }
    });
  });

  group('capability', () {
    test('the capability id is local_exports', () {
      expect(localExportsCapabilityId, 'local_exports');
    });

    test('a localExport target without the capability is refused', () {
      final decl = LocalExportDeclaration(
        'export_report',
        ToolEffect.export,
        const DestinationRule.localExport(),
      );
      expect(
        localExportDeclarationProblems(
          capabilityIds: const {},
          declarations: [decl],
        ),
        hasLength(1),
      );
      expect(
        localExportDeclarationProblems(
          capabilityIds: const {'knowledge'},
          declarations: [decl],
        ),
        isNotEmpty,
      );
      expect(
        localExportDeclarationProblems(
          capabilityIds: const {localExportsCapabilityId},
          declarations: [decl],
        ),
        isEmpty,
      );
    });

    test('modules that declare no local export are unaffected', () {
      final network = LocalExportDeclaration(
        'fetch',
        ToolEffect.network,
        const DestinationRule(publicWeb: true),
      );
      final read = LocalExportDeclaration(
        'r',
        ToolEffect.read,
        const DestinationRule(),
      );
      expect(
        localExportDeclarationProblems(
          capabilityIds: const {},
          declarations: [network, read],
        ),
        isEmpty,
      );
      expect(
        localExportDeclarationProblems(
          capabilityIds: const {},
          declarations: const [],
        ),
        isEmpty,
      );
    });

    test('v1 and v2 manifests do not need the capability by default', () {
      const manifest = ModuleManifest(
        id: 'm',
        apiVersion: 2,
        packageRevision: '1',
      );
      expect(
        manifest.capabilities.any((c) => c.id == localExportsCapabilityId),
        isFalse,
      );
      expect(manifest.network.fixedHosts, isEmpty);
    });
  });

  group('preparation is deeply frozen', () {
    test(
      'a later change to the caller bytes does not reach the preparation',
      () {
        final source = Uint8List.fromList([1, 2, 3]);
        final prepared = prepare(bytes: source);
        source[0] = 99;
        expect(prepared.bytes, [1, 2, 3]);
        expect(prepared.byteCount, 3);
      },
    );

    test('the exposed bytes and lists cannot be modified', () {
      final prepared = prepare(
        exclusions: [const LocalExportExclusion('n1', 'no_binding')],
        warnings: ['hash mismatch'],
      );
      expect(() => prepared.bytes[0] = 7, throwsUnsupportedError);
      expect(
        () => prepared.sources.add(prepared.sources.first),
        throwsUnsupportedError,
      );
      expect(() => prepared.exclusions.clear(), throwsUnsupportedError);
      expect(() => prepared.warnings.add('x'), throwsUnsupportedError);
    });

    test('caller lists mutated afterwards do not change the preparation', () {
      final sources = [
        const ObjectRef(
          moduleId: 'research',
          objectType: 'project',
          objectId: 'P',
        ),
      ];
      final warnings = ['w'];
      final exclusions = [const LocalExportExclusion('a', 'r')];
      final prepared = prepare(
        sources: sources,
        warnings: warnings,
        exclusions: exclusions,
      );
      sources.clear();
      warnings.add('later');
      exclusions.clear();
      expect(prepared.sources, hasLength(1));
      expect(prepared.warnings, ['w']);
      expect(prepared.exclusions, hasLength(1));
    });

    test('malformed digests, counts and versions are refused', () {
      for (final bad in ['', 'A' * 64, 'a' * 63, 'g' * 64]) {
        expect(
          () => LocalExportPreparation(
            kind: LocalExportKind.report,
            formatVersion: 'v',
            mimeType: 'text/plain',
            generatedAt: DateTime.utc(2026),
            bytes: const [1],
            sha256: bad,
            sources: const [],
            dedupedObjectCount: 0,
            exclusions: const [],
            warnings: const [],
            preparationVersion: 1,
            manifestDigest: digest,
          ),
          throwsArgumentError,
          reason: bad,
        );
      }
      expect(
        () => LocalExportPreparation(
          kind: LocalExportKind.report,
          formatVersion: 'v',
          mimeType: 'text/plain',
          generatedAt: DateTime.utc(2026),
          bytes: const [1],
          sha256: digest,
          sources: const [],
          dedupedObjectCount: -1,
          exclusions: const [],
          warnings: const [],
          preparationVersion: 1,
          manifestDigest: digest,
        ),
        throwsArgumentError,
      );
      expect(
        () => LocalExportPreparation(
          kind: LocalExportKind.report,
          formatVersion: 'v',
          mimeType: 'text/plain',
          generatedAt: DateTime.utc(2026),
          bytes: const [1],
          sha256: digest,
          sources: const [],
          dedupedObjectCount: 0,
          exclusions: const [],
          warnings: const [],
          preparationVersion: 0,
          manifestDigest: digest,
        ),
        throwsArgumentError,
      );
    });

    test('a zero-byte export is refused', () {
      expect(() => prepare(bytes: const []), throwsArgumentError);
    });
  });

  group('staged results', () {
    test('each stage has its own outcome and cleanup', () {
      const generate = LocalExportStage(LocalExportOutcome.succeeded);
      const save = LocalExportStage(
        LocalExportOutcome.cancelled,
        cleanup: LocalExportCleanup.notNeeded,
      );
      final result = LocalExportResult(generate: generate, save: save);
      expect(result.generate.outcome, LocalExportOutcome.succeeded);
      expect(result.save!.outcome, LocalExportOutcome.cancelled);
      expect(result.completed, isFalse);
    });

    test('only generate + save succeeded counts as completed', () {
      expect(
        const LocalExportResult(
          generate: LocalExportStage(LocalExportOutcome.succeeded),
          save: LocalExportStage(LocalExportOutcome.succeeded),
        ).completed,
        isTrue,
      );
      for (final outcome in LocalExportOutcome.values) {
        if (outcome == LocalExportOutcome.succeeded) continue;
        expect(
          LocalExportResult(
            generate: const LocalExportStage(LocalExportOutcome.succeeded),
            save: LocalExportStage(outcome),
          ).completed,
          isFalse,
          reason: outcome.name,
        );
        expect(
          LocalExportResult(generate: LocalExportStage(outcome)).completed,
          isFalse,
          reason: outcome.name,
        );
      }
    });

    test('a save stage cannot exist when generation did not succeed', () {
      for (final outcome in LocalExportOutcome.values) {
        if (outcome == LocalExportOutcome.succeeded) continue;
        expect(
          () => LocalExportResult(
            generate: LocalExportStage(outcome),
            save: const LocalExportStage(LocalExportOutcome.succeeded),
          ),
          throwsArgumentError,
          reason: outcome.name,
        );
      }
    });

    test('error codes are short safe identifiers, never paths or text', () {
      expect(
        const LocalExportStage(
          LocalExportOutcome.failed,
          errorCode: 'write_failed',
        ).errorCode,
        'write_failed',
      );
      for (final bad in ['/Users/a/b', 'has space', '', 'x' * 65, 'a/b']) {
        expect(
          () => LocalExportStage(LocalExportOutcome.failed, errorCode: bad),
          throwsArgumentError,
          reason: bad,
        );
      }
    });

    test('cleanup residue and unknown are distinct, reportable states', () {
      const stage = LocalExportStage(
        LocalExportOutcome.interrupted,
        cleanup: LocalExportCleanup.residue,
      );
      expect(stage.cleanup, LocalExportCleanup.residue);
      expect(
        LocalExportCleanup.values,
        containsAll([
          LocalExportCleanup.notNeeded,
          LocalExportCleanup.cleaned,
          LocalExportCleanup.residue,
          LocalExportCleanup.unknown,
        ]),
      );
    });
  });
}
