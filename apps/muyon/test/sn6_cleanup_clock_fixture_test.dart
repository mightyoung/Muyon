import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'support/agent_loop_fixture.dart';

void main() {
  testWidgets('cleanup waits for completion across both clocks', (
    tester,
  ) async {
    final fakeGate = Future<void>(() {});
    var realTurns = 0;
    await drainLoopCleanup(() async {
      await fakeGate;
      for (var turn = 0; turn < 32; turn++) {
        await Future<void>.delayed(Duration.zero);
        realTurns++;
      }
    }, label: 'cross-clock close');
    expect(realTurns, 32);
  });

  testWidgets('cleanup preserves synchronous operation errors', (tester) async {
    final error = StateError('sync close failed');
    await expectLater(
      drainLoopCleanup(() => throw error, label: 'sync close'),
      throwsA(same(error)),
    );
  });

  testWidgets('cleanup preserves asynchronous operation errors', (
    tester,
  ) async {
    final error = StateError('async close failed');
    await expectLater(
      drainLoopCleanup(() => Future<void>.error(error), label: 'async close'),
      throwsA(same(error)),
    );
  });

  testWidgets('unfinished cleanup fails with bounded diagnostics', (
    tester,
  ) async {
    final never = Completer<void>();
    await expectLater(
      drainLoopCleanup(() => never.future, label: 'unfinished close'),
      throwsA(
        isA<TestFailure>().having(
          (error) => error.message,
          'diagnostic',
          contains('unfinished close did not complete'),
        ),
      ),
    );
  });
}
