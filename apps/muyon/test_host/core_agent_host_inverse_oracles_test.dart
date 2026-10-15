import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:path/path.dart' as p;

import 'support/host_fixture.dart';
import 'support/offline_model.dart';

/// Independent boundary oracles: same expectations on baseline and mutant.
/// Positive projection and one-driver cases always launch real compiled Rust.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  requiredBinary();

  test('actual host projection contains only accepted reference fields', () async {
    final f = await HostFixture.open();
    addTearDown(f.dispose);
    f.transport.replies.addAll([
      (_) => toolReply(f.supplierId),
      (_) => answerReply('Metadata observed.'),
    ]);
    final task = await f.start();
    // Inspect actual bytes before task state: downstream Rust refusal cannot
    // substitute for the assertion detecting a leaked projection field.
    final results = f.frames('host.bin').where((frame) => frame['kind'] == 'tool_result').toList();
    expect(results, hasLength(1), reason: 'HOST_PROJECTION_SETUP');
    final actual = results.single['projection'] as Map;
    expect(actual, f.projection, reason: 'HOST_PROJECTION_FIELDS');
    final ref = (actual['objectRefs'] as List).single as Map;
    expect(ref.keys.toSet(), {'moduleId', 'objectType', 'objectId', 'revisionRef', 'contentDigest'},
      reason: 'HOST_PROJECTION_FIELDS');
    expect(task.state, PersonalTaskState.succeeded);
    expect(f.receiptRows, hasLength(1));
    expect(f.host.tools.receiptFor(f.receiptRows.single['invocation_id'] as String)!.succeeded, isTrue);
    f.assertReaped();
  });

  test('wrong native call identity cannot create a registry receipt', () async {
    // An artificial child is confined to this negative correlation case.
    final f = await HostFixture.open(negativeMode: 'wrong_call_id');
    addTearDown(f.dispose);
    f.transport.replies.add((_) => toolReply(f.supplierId));
    final task = await f.start();
    expect(f.receiptRows, isEmpty, reason: 'HOST_AUTHORITY_BINDING');
    f.assertRejection(task.error, 'callback_mismatch');
    expect(task.state, PersonalTaskState.failed);
    expect(f.transport.bodies, hasLength(1));
    f.assertReaped();
  });

  test('concurrent actual core starts retain exactly one process launch', () async {
    final f = await HostFixture.open();
    addTearDown(f.dispose);
    final entered = Completer<void>();
    final release = Completer<String>();
    addTearDown(() { if (!release.isCompleted) release.complete(answerReply('First settled.')); });
    f.transport.replies.add((_) { entered.complete(); return release.future; });
    f.transport.replies.add((_) => answerReply('A second process must not run.'));
    final first = f.start();
    await entered.future;
    final second = await f.start(prompt: 'Concurrent inverse boundary request.');
    release.complete(answerReply('First settled.'));
    final settledFirst = await first;
    final launches = File(p.join(f.evidence.path, 'launches.jsonl')).readAsLinesSync()
        .map((line) => jsonDecode(line) as Map).toList();
    expect(launches, hasLength(1), reason: 'HOST_ONE_DRIVER_LAUNCH_COUNT');
    expect(settledFirst.state, PersonalTaskState.succeeded);
    expect(second.state, PersonalTaskState.failed);
    expect(second.error, contains('core_busy'));
    f.assertReaped();
  });
}
