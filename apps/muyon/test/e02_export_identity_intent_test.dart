import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/grants/host_effect_intent.dart';
import 'package:muyon/platform/grants/local_export_target.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

/// E02: A-stage identity cannot authorize a B-stage intent.
void main() {
  final issuer = LocalExportTargetIssuer();
  final prepDigest = 'a' * 64;
  final scope = 'b' * 64;

  test('generate call rejected for save phase', () {
    final target = issuer.issue('docs');
    expect(
      () => HostEffectIntent.localExport(
        toolId: 'research.export',
        call: LocalExportGenerateCall(exportId: 'e1', invocationId: 'i1'),
        phase: LocalExportPhase.save,
        scopeDigest: scope,
        preparationDigest: prepDigest,
        preparationVersion: 1,
        fileName: 'report-1.md',
        format: 'text/markdown',
        content: const [1],
        sourceObjects: const [],
        targetIssuer: issuer,
        target: target,
        overwrite: LocalExportOverwrite.createNew,
        policyVersion: 'p1',
      ),
      throwsArgumentError,
    );
  });

  test('save call rejected for generate phase', () {
    expect(
      () => HostEffectIntent.localExport(
        toolId: 'research.export',
        call: LocalExportSaveCall(exportId: 'e1', invocationId: 'i1'),
        phase: LocalExportPhase.generate,
        scopeDigest: scope,
        preparationDigest: prepDigest,
        preparationVersion: 1,
        fileName: 'report-1.md',
        format: 'text/markdown',
        content: const [1],
        sourceObjects: const [],
        targetIssuer: issuer,
        overwrite: LocalExportOverwrite.createNew,
        policyVersion: 'p1',
      ),
      throwsArgumentError,
    );
  });

  test('intent digest binds preparationDigest', () {
    final a = HostEffectIntent.localExport(
      toolId: 'research.export',
      call: LocalExportGenerateCall(exportId: 'e1', invocationId: 'i1'),
      phase: LocalExportPhase.generate,
      scopeDigest: scope,
      preparationDigest: 'a' * 64,
      preparationVersion: 1,
      fileName: 'report-1.md',
      format: 'text/markdown',
      content: const [1, 2, 3],
      sourceObjects: const [],
      targetIssuer: issuer,
      overwrite: LocalExportOverwrite.createNew,
      policyVersion: 'p1',
    );
    final b = HostEffectIntent.localExport(
      toolId: 'research.export',
      call: LocalExportGenerateCall(exportId: 'e1', invocationId: 'i1'),
      phase: LocalExportPhase.generate,
      scopeDigest: scope,
      preparationDigest: 'c' * 64,
      preparationVersion: 1,
      fileName: 'report-1.md',
      format: 'text/markdown',
      content: const [1, 2, 3],
      sourceObjects: const [],
      targetIssuer: issuer,
      overwrite: LocalExportOverwrite.createNew,
      policyVersion: 'p1',
    );
    expect(a.payloadDigest, b.payloadDigest);
    expect(a.digest, isNot(b.digest));
  });
}
