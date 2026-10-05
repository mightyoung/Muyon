import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/north_star_chain.dart';

/// Inquiry North Star chain, headless. Without `MUYON_EVAL_MODEL_*` a loopback
/// fixture model answers and the evidence is labelled "fixture" (not M/R
/// evidence). See docs/implementation/north-star-inquiry-runbook.md.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'host → inquiry data → assistant reads → approved write → reopen',
    () async {
      // The test binding replaces HttpClient; the model call needs a real one.
      HttpOverrides.global = null;
      final sandbox = Directory.systemTemp.createTempSync('muyon-north-star-');
      final evidence = <String, Object?>{};
      try {
        await NorthStarInquiryChain(
          rootPath: '${sandbox.path}/data',
          evidence: evidence,
          binding: 'flutter_test (headless)',
        ).run();
      } finally {
        await publishNorthStarEvidence(evidence);
        sandbox.deleteSync(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
