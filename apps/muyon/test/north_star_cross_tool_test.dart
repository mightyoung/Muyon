import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/north_star_chain.dart';
import '../integration_test/support/north_star_fixture_model.dart';

/// P0-3c N1: tools are judged per question. A model that answers the compare
/// question with an unrelated read tool and calls both inquiry tools for the
/// budget question used to pass the run-wide check; it must now fail.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('crossed tools across the two read questions fail the run', () async {
    HttpOverrides.global = null;
    final sandbox = Directory.systemTemp.createTempSync('muyon-north-cross-');
    final evidence = <String, Object?>{};
    final chain = NorthStarInquiryChain(
      rootPath: '${sandbox.path}/data',
      evidence: evidence,
      binding: 'flutter_test (headless)',
      fixtureTurns: {
        'assistant.read.compare_quotes': [
          FixtureModelServer.tool('knowledge.search', {'query': '电缆 报价'}),
          FixtureModelServer.answer('电缆报价见资料。'),
        ],
        'assistant.read.project_budget': [
          FixtureModelServer.tool('inquiry.compare_quotes', {}),
          FixtureModelServer.tool('inquiry.project_budget', {}),
          FixtureModelServer.answer('预算见明细。'),
        ],
      },
    );
    try {
      await expectLater(chain.run(), throwsA(isA<StateError>()));
    } finally {
      sandbox.deleteSync(recursive: true);
    }
    expect(evidence['passed'], isFalse);
    expect(
      evidence['failure'],
      allOf(
        contains('Read question compare_quotes'),
        contains('inquiry.compare_quotes'),
        contains('knowledge.search'),
      ),
    );
    final steps = (evidence['steps'] as List).cast<Map>();
    expect(
      steps.singleWhere(
        (s) => s['name'] == 'assistant.read.compare_quotes',
      )['ok'],
      isFalse,
    );
  });
}
