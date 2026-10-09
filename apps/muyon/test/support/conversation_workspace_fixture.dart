import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/screens/dynamic_workspace.dart';

/// Start an operation in the real zone while also advancing callbacks queued
/// earlier in the widget binding's fake zone. Direct runAsync-await would stop
/// those fake callbacks and can deadlock SQLite's serialized write tail.
Future<T> workspaceOperation<T>(
  WidgetTester tester,
  Future<T> Function() operation,
) async {
  var completed = false;
  late T result;
  Object? failure;
  StackTrace? failureStack;
  await tester.runAsync(() async {
    try {
      operation().then<void>((value) {
        result = value;
        completed = true;
      }, onError: (Object error, StackTrace stack) {
        failure = error;
        failureStack = stack;
        completed = true;
      });
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
      completed = true;
    }
  });
  for (var turn = 0; turn < 2000 && !completed; turn++) {
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pump();
  }
  if (!completed) fail('Workspace operation did not finish after draining real and fake event turns');
  if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  return result;
}

/// Drain real SQLite/registered plugin futures until the expected visible state.
/// No elapsed-time sleeps are used to manufacture navigation/save ordering.
Future<void> workspaceReady(WidgetTester tester) async {
  await tester.pump();
  final finder = find.byType(DynamicWorkspace);
  if (finder.evaluate().isNotEmpty) {
    final session = tester.widget<DynamicWorkspace>(finder.first).session;
    if (session != null) await workspaceOperation(tester, session.ensureLoaded);
  }
  await tester.runAsync(() => Future<void>(() {}));
  await tester.pump(const Duration(milliseconds: 16));
}

Future<void> workspaceVisible(WidgetTester tester, Finder target) async {
  for (var turn = 0; turn < 1000; turn++) {
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pump(const Duration(milliseconds: 16));
    if (target.evaluate().isNotEmpty) return;
  }
  fail('Navigation did not expose $target after draining pending event turns');
}

Future<void> workspaceGone(WidgetTester tester, Finder target) async {
  for (var turn = 0; turn < 2000; turn++) {
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pump(const Duration(milliseconds: 16));
    if (target.evaluate().isEmpty) return;
  }
  fail('Navigation did not remove $target after draining pending event turns');
}
