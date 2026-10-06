import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'support/north_star_chain.dart';

/// Inquiry North Star chain on a device or desktop app:
///   flutter test integration_test/north_star_inquiry_test.dart -d DEVICE \
///     --dart-define=MUYON_EVAL_REAL=1 \
///     --dart-define=MUYON_EVAL_MODEL_ENDPOINT=... \
///     --dart-define=MUYON_EVAL_MODEL_ID=...
/// Environment variables do not reach an app on a device; use --dart-define.
/// The data directory is a fresh temporary directory removed afterwards.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('North Star inquiry chain on device', (tester) async {
    final evidence = <String, Object?>{};
    binding.reportData = {'northStar': evidence};
    Directory? sandbox;
    Object? failure;
    StackTrace? failureStack;
    try {
      // runAsync would hide the error behind takeException; keep it.
      await tester.runAsync(() async {
        try {
          final temp = await getTemporaryDirectory();
          sandbox = await temp.createTemp('muyon-north-star-');
          await NorthStarInquiryChain(
            rootPath: '${sandbox!.path}/data',
            evidence: evidence,
            binding: 'integration_test',
          ).run();
        } catch (error, stack) {
          failure = error;
          failureStack = stack;
        }
      });
      if (failure != null) {
        Error.throwWithStackTrace(failure!, failureStack!);
      }
    } finally {
      await tester.runAsync(() async {
        // Relative MUYON_EVIDENCE_OUT lands in the app's own storage (on
        // Android: the external files dir, pullable with adb).
        final base = Platform.isAndroid
            ? (await getExternalStorageDirectory())?.path
            : (await getApplicationDocumentsDirectory()).path;
        await publishNorthStarEvidence(evidence, baseDir: base);
        if (sandbox != null && await sandbox!.exists()) {
          await sandbox!.delete(recursive: true);
        }
      });
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
