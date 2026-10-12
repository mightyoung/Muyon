import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'support/aiui_smoke_config.dart';
import 'support/aiui_smoke_driver.dart';
import 'support/aiui_smoke_evidence.dart';
import 'support/aiui_smoke_fixture.dart';

/// Formal device entry. Missing real configuration or production connections
/// FAIL with stable codes; no script fixture, skip or silent success fallback.
/// This deliverable provides checked preflight/support, not completed Android
/// acceptance automation. CF observation, I/O and recovery owners remain open.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('AIUI-SMOKE-ANDROID1–4/7 production readiness', (tester) async {
    AiuiSmokeFixture? fixture;
    Directory? sandbox;
    AiuiSmokeEvidence evidence = AiuiSmokeEvidence(runId: const Uuid().v4());
    SmokeFailureCode? failure;
    try {
      final configuration = AiuiSmokeConfiguration.fromDartDefines();
      evidence = AiuiSmokeEvidence(
        runId: evidence.runId,
        candidateSha: configuration.candidateSha,
      );
      await tester.runAsync(() async {
        final directory = await getApplicationSupportDirectory();
        sandbox = await directory.createTemp('aiui-smoke-');
        fixture = await AiuiSmokeFixture.open(p.join(sandbox!.path, 'data'));
      });
      if (fixture == null) {
        throw SmokeFailure(SmokeFailureCode.unexpectedFailure);
      }
      await fixture!.mount(tester);
      // An explicitly offline structural source probe, not a warmup model
      // request, normal measurement sample or ANDROID3 acceptance claim.
      await AiuiSmokeDriver(tester).submit('只读展示当前选定询价的已保存事实');
      for (
        var frame = 0;
        frame < 100 &&
            fixture!.host.foundation
                .tasks(conversationId: fixture!.conversation.id)
                .isEmpty;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      final state = await tester.runAsync(fixture!.sourceForCurrentTask);
      final preflight = inspectSmokeProduction(fixture!.host, state);
      evidence.preflight.addAll(preflight.toEvidence());
      preflight.requireReady();
      // Success requires the full scenario executor and actual observations.
      // Capability presence alone cannot supply Android/card/model evidence.
      throw SmokeFailure(SmokeFailureCode.acceptanceCoverageIncomplete);
    } on SmokeFailure catch (error) {
      failure = error.code;
    } catch (_) {
      failure = SmokeFailureCode.unexpectedFailure;
    } finally {
      evidence.failure =
          failure ?? SmokeFailureCode.acceptanceCoverageIncomplete;
      evidence.preflight.putIfAbsent('passed', () => false);
      for (final sample in evidence.probe.samples) {
        sample.missingReason = evidence.failure;
      }
      evidence.preflight.putIfAbsent(
        'failure_code',
        () => evidence.failure!.code,
      );
      for (final id in smokeCaseIds) {
        evidence.cases.add({
          'id': id,
          'status': 'not_yet',
          'stage': 'preflight',
          'failure_code': evidence.failure!.code,
          'evidence_class': 'not_executed',
        });
      }
      // Publish identical whitelist data even when a device storage method is
      // unavailable. Publishing failure remains failure, never a successful run.
      try {
        await tester.runAsync(() async {
          if (sandbox != null) {
            await writeSmokeCheckpointStatus(sandbox!.path, complete: false);
          }
          await publishAiuiSmokeEvidence(
            evidence,
            write: (json) async {
              final directory = Platform.isAndroid
                  ? await getExternalStorageDirectory()
                  : await getApplicationDocumentsDirectory();
              if (directory == null) {
                throw SmokeFailure(SmokeFailureCode.evidenceWriteFailed);
              }
              await File(p.join(directory.path, 'aiui-smoke-evidence.json'))
                  .writeAsString(json, flush: true);
            },
            report: (data) => binding.reportData = {'aiuiSmoke': data},
            emit: (chunk) => debugPrintSynchronously(chunk),
          );
        });
      } catch (_) {
        failure ??= SmokeFailureCode.evidenceWriteFailed;
        evidence.failure = failure;
        binding.reportData = {'aiuiSmoke': evidence.filtered()};
      }
      if (fixture != null) {
        await fixture!.close(tester);
      }
      // Deliberately retain isolation; handoff is explicitly incomplete until
      // the production owner can restore the same task/object/card without I/O.
    }
    throw SmokeFailure(
      failure ?? SmokeFailureCode.acceptanceCoverageIncomplete,
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
